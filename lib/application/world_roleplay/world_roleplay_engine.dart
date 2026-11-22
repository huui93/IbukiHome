import '../../application/ai/ai_generation_service.dart';
import '../../application/ai/ai_model_resolver.dart';
import '../../application/common/entity_id_generator.dart';
import '../../application/common/utc_clock.dart';
import '../../application/plugins/ibuki_hook_bus.dart';
import '../../application/plugins/ibuki_prompt_pipeline.dart';
import '../../core/network/ai_provider_exceptions.dart';
import '../../data/ai/ai_provider_client.dart';
import '../../data/repositories/world_roleplay_repository.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/world_roleplay/world_roleplay_engine_models.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';
import 'world_context_builder.dart';
import 'world_director.dart';
import 'world_mutation_service.dart';
import 'world_post_processing.dart';
import 'world_speaker_selector.dart';

abstract class WorldMutationPlanner {
  Future<WorldMutationProposal> propose({
    required WorldRoleplaySnapshot snapshot,
    required WorldDirectorDecision decision,
    required List<WorldFeedEntry> generatedEntries,
  });
}

class DirectorHintMutationPlanner implements WorldMutationPlanner {
  const DirectorHintMutationPlanner();

  @override
  Future<WorldMutationProposal> propose({
    required WorldRoleplaySnapshot snapshot,
    required WorldDirectorDecision decision,
    required List<WorldFeedEntry> generatedEntries,
  }) async {
    return decision.mutationProposal;
  }
}

class WorldRoleplayEngine {
  WorldRoleplayEngine({
    required this.repository,
    required this.contextBuilder,
    required this.director,
    required this.speakerSelector,
    required this.mutationService,
    required this.runtime,
    required this.modelResolver,
    required this.promptPipeline,
    required this.hooks,
    required this.ids,
    required this.clock,
    this.mutationPlanner = const DirectorHintMutationPlanner(),
    this.memoryExtractor = const WorldMemoryExtractor(),
    this.timelineExtractor = const WorldTimelineExtractor(),
  });

  final WorldRoleplayRepository repository;
  final WorldRoleplayContextBuilder contextBuilder;
  final WorldDirector director;
  final WorldSpeakerSelector speakerSelector;
  final WorldMutationService mutationService;
  final AiGenerationRuntime runtime;
  final AiModelResolver modelResolver;
  final IbukiPromptPipeline promptPipeline;
  final IbukiHookBus hooks;
  final EntityIdGenerator ids;
  final UtcClock clock;
  final WorldMutationPlanner mutationPlanner;
  final WorldMemoryExtractor memoryExtractor;
  final WorldTimelineExtractor timelineExtractor;
  final Map<String, _ActiveWorldTurn> _active = {};

  bool isRunning(String worldSessionId) => _active.containsKey(worldSessionId);
  bool get hasActiveTurns => _active.isNotEmpty;

  bool stop(String worldSessionId) {
    final active = _active[worldSessionId];
    if (active == null) return false;
    active.cancellation.cancel();
    return true;
  }

  Stream<WorldTurnUpdate> runTurn({
    required String worldSessionId,
    required String userAction,
    Set<String> manualSpeakerIds = const {},
    Set<String> manualLoreEntryIds = const {},
  }) async* {
    final normalizedAction = userAction.trim();
    if (normalizedAction.isEmpty) return;
    if (_active.containsKey(worldSessionId)) {
      throw const WorldEngineException(
        WorldEngineErrorCategory.busy,
        '这个世界正在回应上一条行动。',
      );
    }
    final session = await repository.getSession(worldSessionId);
    final branchId = session.currentBranchId;
    if (branchId == null) {
      throw const WorldEngineException(
        WorldEngineErrorCategory.mutationValidationError,
        '当前世界存档没有可用世界线。',
      );
    }
    final now = clock.now();
    final turnId = ids.nextId('world_turn');
    final requestId = ids.nextId('world_ai_request');
    final cancellation = AiRequestCancellation();
    _active[worldSessionId] = _ActiveWorldTurn(turnId, cancellation);
    final userEntry = WorldFeedEntry(
      entity: _entity(ids.nextId('world_feed'), now),
      worldSessionId: worldSessionId,
      branchId: branchId,
      type: WorldFeedEntryType.userAction,
      content: normalizedAction,
      metadata: {'turnId': turnId, 'generationStatus': 'completed'},
    );
    var turn = WorldTurn(
      entity: _entity(turnId, now),
      worldSessionId: worldSessionId,
      branchId: branchId,
      userFeedEntryId: userEntry.id,
      status: WorldTurnStatus.pending,
    );
    final generatedEntries = <WorldFeedEntry>[];
    String streamingContent = '';
    String? activeSpeakerId;
    WorldFeedEntryType? activeType;
    try {
      await repository.upsertFeedEntry(userEntry);
      await repository.upsertTurn(turn);
      yield WorldTurnUpdate(
        turnId: turnId,
        type: WorldTurnUpdateType.feedEntry,
        status: turn.status,
        feedEntry: userEntry,
      );
      await hooks.publish(IbukiHook.beforeWorldTurn, {
        'worldSessionId': worldSessionId,
        'turnId': turnId,
        'branchId': branchId,
      });
      turn = await _saveStatus(turn, WorldTurnStatus.directing);
      yield WorldTurnUpdate(
        turnId: turnId,
        type: WorldTurnUpdateType.status,
        status: turn.status,
      );
      var snapshot = await contextBuilder.build(
        worldSessionId: worldSessionId,
        userAction: normalizedAction,
        manualLoreEntryIds: manualLoreEntryIds,
      );
      final decision = await director.decide(
        requestId: requestId,
        snapshot: snapshot,
        cancellation: cancellation,
      );
      if (cancellation.isCancelled) throw const AiProviderCancelledException();
      turn = turn.copyWith(
        entity: _next(turn.entity, clock.now()),
        directorDecision: decision.toJson(),
      );
      await repository.upsertTurn(turn);
      await hooks.publish(IbukiHook.afterDirectorDecision, {
        'worldSessionId': worldSessionId,
        'turnId': turnId,
        'candidateSpeakerCount': decision.candidateSpeakerIds.length,
        'narrationNeeded': decision.narrationNeeded,
        'loreQueryTermCount': decision.loreQueryTerms.length,
      });
      snapshot = await contextBuilder.build(
        worldSessionId: worldSessionId,
        userAction: normalizedAction,
        loreQueryTerms: decision.loreQueryTerms,
        manualLoreEntryIds: manualLoreEntryIds,
      );
      turn = turn.copyWith(
        entity: _next(turn.entity, clock.now()),
        metadata: {
          ...turn.metadata,
          'activatedLoreEntryIds': snapshot.lore.entries
              .map((entry) => entry.id)
              .toList(growable: false),
          'manualLoreEntryIds': manualLoreEntryIds.toList(growable: false),
          'speakerMode': manualSpeakerIds.isEmpty
              ? snapshot.session.speakerMode.name
              : WorldSpeakerMode.manual.name,
          'contextDiagnostics': {
            'selectedCharacterCount':
                snapshot.context.diagnostics.selectedCharacterCount,
            'selectedMemoryCount':
                snapshot.context.diagnostics.selectedMemoryCount,
            'selectedTimelineCount':
                snapshot.context.diagnostics.selectedTimelineCount,
            'selectedStateCount':
                snapshot.context.diagnostics.selectedStateCount,
            'estimatedTokensBySection':
                snapshot.context.diagnostics.estimatedTokensBySection,
            'selectedLoreCount': snapshot.lore.diagnostics.selectedLoreCount,
            'estimatedLoreTokens': snapshot.lore.diagnostics.estimatedTokens,
            'instructionLayers': snapshot.context.diagnostics.promptLayer
                .toSafeJson(),
          },
        },
      );
      await repository.upsertTurn(turn);
      await hooks.publish(IbukiHook.beforeSpeakerSelection, {
        'worldSessionId': worldSessionId,
        'turnId': turnId,
        'presentCharacterCount': snapshot.presentCharacters.length,
        'mode': snapshot.session.speakerMode.name,
      });
      final selection = speakerSelector.select(
        decision: decision,
        mode: manualSpeakerIds.isEmpty
            ? snapshot.session.speakerMode
            : WorldSpeakerMode.manual,
        presentCharacters: snapshot.presentCharacters,
        recentFeed: snapshot.recentFeed,
        manualSpeakerIds: manualSpeakerIds,
      );
      turn = turn.copyWith(
        entity: _next(turn.entity, clock.now()),
        selectedSpeakerIds: selection.speakerIds,
        status: WorldTurnStatus.generating,
      );
      await repository.upsertTurn(turn);
      await hooks.publish(IbukiHook.afterSpeakerSelection, {
        'worldSessionId': worldSessionId,
        'turnId': turnId,
        'selectedSpeakerIds': selection.speakerIds,
        'mode': selection.mode.name,
      });
      yield WorldTurnUpdate(
        turnId: turnId,
        type: WorldTurnUpdateType.status,
        status: turn.status,
      );

      if (decision.narrationNeeded) {
        activeType = WorldFeedEntryType.narration;
        activeSpeakerId = null;
        streamingContent = '';
        final prompt = contextBuilder.buildNarrationSystemPrompt(
          snapshot: snapshot,
          userAction: normalizedAction,
          turnLocalEntries: generatedEntries,
        );
        await for (final text in _streamText(
          worldSessionId: worldSessionId,
          worldId: snapshot.world.id,
          requestId: '$requestId-narration',
          systemPrompt: prompt,
          operation: PluginPromptOperation.worldNarration,
          maxTokens: 900,
          cancellation: cancellation,
        )) {
          streamingContent = text;
          yield WorldTurnUpdate(
            turnId: turnId,
            type: WorldTurnUpdateType.streaming,
            status: turn.status,
            streamingContent: text,
          );
        }
        if (streamingContent.trim().isNotEmpty) {
          final entry = await _saveGeneratedEntry(
            turnId: turnId,
            sessionId: worldSessionId,
            branchId: branchId,
            type: activeType,
            content: streamingContent,
          );
          generatedEntries.add(entry);
          activeType = null;
          streamingContent = '';
          yield WorldTurnUpdate(
            turnId: turnId,
            type: WorldTurnUpdateType.feedEntry,
            status: turn.status,
            feedEntry: entry,
          );
        }
      }

      for (var index = 0; index < selection.speakerIds.length; index += 1) {
        if (cancellation.isCancelled) {
          throw const AiProviderCancelledException();
        }
        final speakerId = selection.speakerIds[index];
        activeType = WorldFeedEntryType.characterSpeech;
        activeSpeakerId = speakerId;
        streamingContent = '';
        await hooks.publish(IbukiHook.beforeWorldCharacterGeneration, {
          'worldSessionId': worldSessionId,
          'turnId': turnId,
          'speakerId': speakerId,
          'speakerIndex': index,
        });
        final prompt = contextBuilder.buildCharacterSystemPrompt(
          snapshot: snapshot,
          speakerId: speakerId,
          userAction: normalizedAction,
          turnLocalEntries: generatedEntries,
        );
        await for (final text in _streamText(
          worldSessionId: worldSessionId,
          worldId: snapshot.world.id,
          requestId: '$requestId-character-${index + 1}',
          systemPrompt: prompt,
          operation: PluginPromptOperation.worldCharacter,
          maxTokens: 1800,
          cancellation: cancellation,
        )) {
          streamingContent = text;
          yield WorldTurnUpdate(
            turnId: turnId,
            type: WorldTurnUpdateType.streaming,
            status: turn.status,
            streamingContent: text,
            activeSpeakerId: speakerId,
          );
        }
        final entry = await _saveGeneratedEntry(
          turnId: turnId,
          sessionId: worldSessionId,
          branchId: branchId,
          type: activeType,
          speakerId: speakerId,
          content: streamingContent,
        );
        generatedEntries.add(entry);
        activeType = null;
        activeSpeakerId = null;
        streamingContent = '';
        await hooks.publish(IbukiHook.afterWorldCharacterGeneration, {
          'worldSessionId': worldSessionId,
          'turnId': turnId,
          'speakerId': speakerId,
          'receivedChars': entry.content.length,
        });
        yield WorldTurnUpdate(
          turnId: turnId,
          type: WorldTurnUpdateType.feedEntry,
          status: turn.status,
          feedEntry: entry,
        );
      }

      turn = turn.copyWith(
        entity: _next(turn.entity, clock.now()),
        generatedFeedEntryIds: generatedEntries
            .map((entry) => entry.id)
            .toList(),
        status: WorldTurnStatus.committing,
      );
      await repository.upsertTurn(turn);
      yield WorldTurnUpdate(
        turnId: turnId,
        type: WorldTurnUpdateType.status,
        status: turn.status,
      );
      final rawProposal = await mutationPlanner.propose(
        snapshot: snapshot,
        decision: decision,
        generatedEntries: generatedEntries,
      );
      final postProcessingFailures = <String>[];
      var memories = const <WorldMemoryCandidate>[];
      var timelineEvents = const <WorldTimelineCandidate>[];
      try {
        memories = memoryExtractor.extract(rawProposal);
      } catch (_) {
        postProcessingFailures.add('memory');
      }
      try {
        timelineEvents = timelineExtractor.extract(rawProposal);
      } catch (_) {
        postProcessingFailures.add('timeline');
      }
      final proposal = WorldMutationProposal(
        operations: rawProposal.operations,
        memories: memories,
        timelineEvents: timelineEvents,
      );
      await hooks.publish(IbukiHook.beforeWorldMutation, {
        'worldSessionId': worldSessionId,
        'turnId': turnId,
        'mutationTypes': proposal.operations
            .map((item) => item.type.name)
            .toSet()
            .toList(),
        'entityCount': proposal.operations.length,
      });
      final completedTurn = turn.copyWith(
        entity: _next(turn.entity, clock.now()),
        mutationProposal: proposal.toJson(),
        status: WorldTurnStatus.completed,
        completedAt: clock.now(),
        metadata: {
          ...turn.metadata,
          if (postProcessingFailures.isNotEmpty)
            'postProcessingFailed': postProcessingFailures,
        },
      );
      final commit = await mutationService.prepare(
        snapshot: snapshot,
        turn: completedTurn,
        proposal: proposal,
      );
      await mutationService.commit(commit);
      turn = completedTurn;
      await hooks.publish(IbukiHook.afterWorldMutation, {
        'worldSessionId': worldSessionId,
        'turnId': turnId,
        'success': true,
        'entityCount': proposal.operations.length,
      });
      await hooks.publish(IbukiHook.afterWorldTurn, {
        'worldSessionId': worldSessionId,
        'turnId': turnId,
        'status': turn.status.name,
        'speakerCount': selection.speakerIds.length,
        'feedEntryCount': generatedEntries.length,
      });
      yield WorldTurnUpdate(
        turnId: turnId,
        type: WorldTurnUpdateType.completed,
        status: turn.status,
      );
    } catch (error) {
      final cancelled =
          cancellation.isCancelled || error is AiProviderCancelledException;
      if (streamingContent.trim().isNotEmpty && activeType != null) {
        final partial = await _saveGeneratedEntry(
          turnId: turnId,
          sessionId: worldSessionId,
          branchId: branchId,
          type: activeType,
          speakerId: activeSpeakerId,
          content: streamingContent,
          generationStatus: cancelled ? 'cancelled' : 'interrupted',
        );
        if (!generatedEntries.any((entry) => entry.id == partial.id)) {
          generatedEntries.add(partial);
          yield WorldTurnUpdate(
            turnId: turnId,
            type: WorldTurnUpdateType.feedEntry,
            status: cancelled
                ? WorldTurnStatus.cancelled
                : WorldTurnStatus.failed,
            feedEntry: partial,
          );
        }
      }
      final mapped = _mapError(error, cancelled: cancelled);
      turn = turn.copyWith(
        entity: _next(turn.entity, clock.now()),
        generatedFeedEntryIds: generatedEntries
            .map((entry) => entry.id)
            .toList(),
        status: cancelled ? WorldTurnStatus.cancelled : WorldTurnStatus.failed,
        completedAt: clock.now(),
        errorCategory: mapped.category,
        metadata: {
          ...turn.metadata,
          'errorType': error.runtimeType.toString(),
          'receivedChars': streamingContent.length,
        },
      );
      await repository.upsertTurn(turn);
      yield WorldTurnUpdate(
        turnId: turnId,
        type: cancelled
            ? WorldTurnUpdateType.cancelled
            : WorldTurnUpdateType.failed,
        status: turn.status,
        error: mapped,
      );
    } finally {
      _active.remove(worldSessionId);
    }
  }

  Stream<String> _streamText({
    required String worldSessionId,
    required String worldId,
    required String requestId,
    required String systemPrompt,
    required PluginPromptOperation operation,
    required int maxTokens,
    required AiRequestCancellation cancellation,
  }) async* {
    final resolved = await modelResolver.resolveForWorldSession(worldSessionId);
    for (var attempt = 1; attempt <= 2; attempt += 1) {
      final coreRequest = AiGenerationRequest(
        requestId: attempt == 1 ? requestId : '$requestId-retry',
        providerConfigId: resolved.providerConfigId,
        model: resolved.model,
        systemPrompt: systemPrompt,
        messages: const [
          AiGenerationMessage(role: AiMessageRole.user, content: '请继续当前世界回合。'),
        ],
        temperature: 0.8,
        maxTokens: maxTokens,
      );
      final piped = await promptPipeline.apply(
        coreRequest,
        PluginPromptContext(
          operation: operation,
          worldId: worldId,
          worldSessionId: worldSessionId,
          safeMetadata: {'requestKind': 'worldRoleplay'},
        ),
      );
      final output = StringBuffer();
      AiFinishReason? finishReason;
      try {
        await for (final event in runtimeStreamEvents(
          runtime,
          piped.request,
          cancellation: cancellation,
        )) {
          if (cancellation.isCancelled) {
            throw const AiProviderCancelledException();
          }
          if (event.isTerminal) {
            finishReason = event.finishReason;
          } else if (event.content.isNotEmpty) {
            output.write(event.content);
            yield output.toString();
          }
        }
        if (finishReason == AiFinishReason.stop) {
          if (output.toString().trim().isNotEmpty) return;
          throw WorldEngineException(
            operation == PluginPromptOperation.worldNarration
                ? WorldEngineErrorCategory.narrationError
                : WorldEngineErrorCategory.characterGenerationError,
            operation == PluginPromptOperation.worldNarration
                ? '世界叙述没有返回正文。'
                : '角色没有返回正文。',
          );
        }
        if (finishReason == AiFinishReason.cancelled) {
          throw const AiProviderCancelledException();
        }
        if (output.isNotEmpty) {
          throw WorldEngineException(
            WorldEngineErrorCategory.transportInterrupted,
            '角色回应在生成中断开。',
            detail: 'finishReason=${finishReason?.name ?? 'missing'}',
          );
        }
        if (attempt == 1) continue;
        throw const WorldEngineException(
          WorldEngineErrorCategory.transportInterrupted,
          'AI 连接在收到正文前中断。',
        );
      } on AiProviderInterruptedBeforeContentException {
        if (attempt == 1 && !cancellation.isCancelled) continue;
        rethrow;
      } on AiProviderInterruptedException {
        rethrow;
      }
    }
  }

  Future<WorldTurn> _saveStatus(WorldTurn turn, WorldTurnStatus status) async {
    final updated = turn.copyWith(
      entity: _next(turn.entity, clock.now()),
      status: status,
    );
    await repository.upsertTurn(updated);
    return updated;
  }

  Future<WorldFeedEntry> _saveGeneratedEntry({
    required String turnId,
    required String sessionId,
    required String branchId,
    required WorldFeedEntryType type,
    required String content,
    String? speakerId,
    String generationStatus = 'completed',
  }) async {
    final now = clock.now();
    final entry = WorldFeedEntry(
      entity: _entity(ids.nextId('world_feed'), now),
      worldSessionId: sessionId,
      branchId: branchId,
      type: type,
      speakerCharacterInstanceId: speakerId,
      content: content.trim(),
      metadata: {'turnId': turnId, 'generationStatus': generationStatus},
    );
    await repository.upsertFeedEntry(entry);
    return entry;
  }

  WorldEngineException _mapError(Object error, {required bool cancelled}) {
    if (cancelled) {
      return const WorldEngineException(
        WorldEngineErrorCategory.cancelled,
        '世界回应已停止。',
      );
    }
    if (error is WorldEngineException) return error;
    if (error is AiProviderInterruptedException) {
      return const WorldEngineException(
        WorldEngineErrorCategory.transportInterrupted,
        'AI 连接中断，请重试。',
      );
    }
    if (error is AiProviderException) {
      return WorldEngineException(
        WorldEngineErrorCategory.providerError,
        error.message,
        detail: error.runtimeType.toString(),
      );
    }
    return WorldEngineException(
      WorldEngineErrorCategory.providerError,
      '世界回应失败，请重试。',
      detail: error.runtimeType.toString(),
    );
  }
}

class _ActiveWorldTurn {
  const _ActiveWorldTurn(this.turnId, this.cancellation);

  final String turnId;
  final AiRequestCancellation cancellation;
}

EntityMetadata _entity(String id, DateTime now) =>
    EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);

EntityMetadata _next(EntityMetadata entity, DateTime now) =>
    entity.copyWith(updatedAt: now, revision: entity.revision + 1);
