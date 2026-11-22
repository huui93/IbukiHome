import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/application/ai/ai_model_resolver.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/plugins/ibuki_hook_bus.dart';
import 'package:ibukihome/application/plugins/ibuki_prompt_pipeline.dart';
import 'package:ibukihome/application/world_roleplay/world_context_builder.dart';
import 'package:ibukihome/application/world_roleplay/world_director.dart';
import 'package:ibukihome/application/world_roleplay/world_lore_activator.dart';
import 'package:ibukihome/application/world_roleplay/world_mutation_service.dart';
import 'package:ibukihome/application/world_roleplay/world_post_processing.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_engine.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_service.dart';
import 'package:ibukihome/application/world_roleplay/world_speaker_selector.dart';
import 'package:ibukihome/core/network/ai_provider_exceptions.dart';
import 'package:ibukihome/data/ai/ai_provider_client.dart';
import 'package:ibukihome/data/memory/in_memory_character_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_world_roleplay_repository.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_engine_models.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_models.dart';

void main() {
  test('Lore activation respects mode, priority, manual pin, and budget', () {
    const activator = WorldLoreActivator();
    final entries = [
      _lore('always', LoreActivationMode.always, priority: 1, content: 'A'),
      _lore(
        'keyword',
        LoreActivationMode.keyword,
        priority: 2,
        keywords: const ['蛋糕'],
        content: 'B',
      ),
      _lore('manual', LoreActivationMode.manual, priority: 4, content: 'C'),
      _lore(
        'disabled',
        LoreActivationMode.always,
        enabled: false,
        content: 'D',
      ),
    ];
    final result = activator.activate(
      entries: entries,
      searchTexts: const ['我把蛋糕放到桌上'],
      tokenBudget: 2,
      manualEntryIds: const {'manual'},
    );
    expect(result.diagnostics.candidateLoreCount, 3);
    expect(result.diagnostics.activatedLoreCount, 3);
    expect(result.entries.map((entry) => entry.id), ['manual', 'keyword']);
    expect(result.diagnostics.selectedLoreCount, 2);
  });

  test('speaker selector supports zero, manual, natural, and sequence', () {
    const selector = WorldSpeakerSelector(maxSpeakers: 2);
    final characters = [
      _instance('a', talkativeness: 0.2),
      _instance('b', talkativeness: 0.9),
      _instance('c', talkativeness: 0.5),
    ];
    const zeroDecision = WorldDirectorDecision(
      intentSummary: 'leave quietly',
      narrationNeeded: true,
    );
    expect(
      selector
          .select(
            decision: zeroDecision,
            mode: WorldSpeakerMode.natural,
            presentCharacters: characters,
          )
          .speakerIds,
      isEmpty,
    );
    const decision = WorldDirectorDecision(
      intentSummary: 'ask',
      narrationNeeded: false,
      candidateSpeakerIds: ['a', 'b', 'c'],
      preferredSpeakerIds: ['a'],
    );
    expect(
      selector
          .select(
            decision: decision,
            mode: WorldSpeakerMode.manual,
            presentCharacters: characters,
            manualSpeakerIds: const {'c'},
          )
          .speakerIds,
      ['c'],
    );
    expect(
      selector
          .select(
            decision: decision,
            mode: WorldSpeakerMode.natural,
            presentCharacters: characters,
          )
          .speakerIds,
      ['a', 'b'],
    );
    expect(
      selector
          .select(
            decision: decision,
            mode: WorldSpeakerMode.sequence,
            presentCharacters: characters,
            recentFeed: [_feed('last', speakerId: 'a')],
          )
          .speakerIds,
      ['b', 'c'],
    );
  });

  test('context enforces player knowledge boundary per character', () async {
    final fixture = await _seedWorld();
    var snapshot = await fixture.contextBuilder.build(
      worldSessionId: fixture.sessionId,
      userAction: '你好',
    );
    expect(snapshot.context.directorPlayerContext, contains('异世界来客'));
    expect(snapshot.context.publicPlayerContext, isNot(contains('异世界来客')));
    var prompt = fixture.contextBuilder.buildCharacterSystemPrompt(
      snapshot: snapshot,
      speakerId: fixture.characterIds.first,
      userAction: '你好',
      turnLocalEntries: const [],
    );
    expect(prompt, isNot(contains('异世界来客')));

    await fixture.repository.upsertMemory(
      WorldMemoryEntry(
        entity: _meta('secret-memory'),
        worldSessionId: fixture.sessionId,
        type: 'disclosure',
        summary: '玩家曾向角色透露自己是异世界来客。',
        content: '',
        importance: 1,
        relatedCharacterIds: [fixture.characterIds.first],
      ),
    );
    snapshot = await fixture.contextBuilder.build(
      worldSessionId: fixture.sessionId,
      userAction: '继续',
    );
    prompt = fixture.contextBuilder.buildCharacterSystemPrompt(
      snapshot: snapshot,
      speakerId: fixture.characterIds.first,
      userAction: '继续',
      turnLocalEntries: const [],
    );
    expect(prompt, contains('异世界来客'));
    final otherPrompt = fixture.contextBuilder.buildCharacterSystemPrompt(
      snapshot: snapshot,
      speakerId: fixture.characterIds[1],
      userAction: '继续',
      turnLocalEntries: const [],
    );
    expect(otherPrompt, isNot(contains('异世界来客')));
  });

  test('Director retries one malformed JSON response then parses', () async {
    final fixture = await _seedWorld();
    final snapshot = await fixture.contextBuilder.build(
      worldSessionId: fixture.sessionId,
      userAction: '放下蛋糕',
    );
    final runtime = _ScriptedRuntime(
      generated: [
        'not-json',
        '''{"intentSummary":"分享蛋糕","narrationNeeded":true,"candidateSpeakerIds":[],"preferredSpeakerIds":[],"loreQueryTerms":["蛋糕"],"mutationProposal":{"operations":[],"memories":[],"timelineEvents":[]}}''',
      ],
    );
    final director = AiWorldDirector(
      runtime: runtime,
      modelResolver: _FakeResolver(),
    );
    final decision = await director.decide(
      requestId: 'director-test',
      snapshot: snapshot,
      cancellation: AiRequestCancellation(),
    );
    expect(decision.intentSummary, '分享蛋糕');
    expect(decision.loreQueryTerms, ['蛋糕']);
    expect(runtime.generateCalls, 2);
  });

  test(
    'multi-speaker turn is serialized, branch-aware, and commits safe mutations',
    () async {
      final fixture = await _seedWorld();
      final originalCard = fixture.core.character('card-a')!;
      final originalPersona = await fixture.repository.getPersona(
        fixture.personaId,
      );
      final decision = WorldDirectorDecision(
        intentSummary: '分享蛋糕',
        narrationNeeded: false,
        candidateSpeakerIds: fixture.characterIds.take(2).toList(),
        preferredSpeakerIds: fixture.characterIds.take(2).toList(),
        mutationProposal: WorldMutationProposal(
          operations: [
            const WorldMutationOperation(
              type: WorldMutationType.stateSet,
              values: {'key': 'event.cake_shared', 'value': true},
            ),
            WorldMutationOperation(
              type: WorldMutationType.playerUpdate,
              entityId: fixture.playerInstanceId,
              values: const {'currentMood': '期待'},
            ),
            WorldMutationOperation(
              type: WorldMutationType.relationshipUpsert,
              values: {
                'sourceEntityType': 'character',
                'sourceEntityId': fixture.characterIds.first,
                'targetEntityType': 'player',
                'targetEntityId': fixture.playerInstanceId,
                'relationType': 'trusted',
                'summary': '因为分享蛋糕而更亲近。',
                'state': const {'trust': 'growing'},
              },
            ),
          ],
          memories: [
            WorldMemoryCandidate(
              summary: '玩家分享了蛋糕。',
              importance: 0.8,
              relatedCharacterIds: fixture.characterIds.take(2).toList(),
            ),
          ],
          timelineEvents: [
            WorldTimelineCandidate(
              title: '食堂里的蛋糕',
              importance: 0.8,
              characterIds: fixture.characterIds.take(2).toList(),
            ),
          ],
        ),
      );
      final runtime = _ScriptedRuntime(
        streamed: ['“真的？给我的？”（眼睛亮了起来）', '“是给我们。”（淡淡看了她一眼）'],
      );
      final resolver = _FakeResolver();
      final engine = _engine(
        fixture,
        runtime: runtime,
        resolver: resolver,
        decision: decision,
      );
      final updates = await engine
          .runTurn(worldSessionId: fixture.sessionId, userAction: '我把蛋糕放到桌上。')
          .toList();
      expect(
        updates.last.type,
        WorldTurnUpdateType.completed,
        reason: '${updates.last.error} ${updates.last.error?.detail}',
      );
      expect(runtime.streamCalls, 2);
      expect(resolver.worldSessionIds, [fixture.sessionId, fixture.sessionId]);
      expect(runtime.requests[1].systemPrompt, contains('“真的？给我的？”（眼睛亮了起来）'));
      final feed = await fixture.repository.listFeedEntries(
        fixture.sessionId,
        branchId: fixture.branchId,
      );
      expect(feed.map((entry) => entry.type), [
        WorldFeedEntryType.userAction,
        WorldFeedEntryType.characterSpeech,
        WorldFeedEntryType.characterSpeech,
      ]);
      expect(feed[1].content, '“真的？给我的？”（眼睛亮了起来）');
      expect(feed[2].content, '“是给我们。”（淡淡看了她一眼）');
      final persistedTurn = (await fixture.repository.listTurns(
        fixture.sessionId,
      )).single;
      expect(persistedTurn.status, WorldTurnStatus.completed);
      expect(persistedTurn.metadata['activatedLoreEntryIds'], ['cake-lore']);
      expect(persistedTurn.metadata['manualLoreEntryIds'], isEmpty);
      expect(persistedTurn.metadata['speakerMode'], 'natural');
      final contextDiagnostics =
          persistedTurn.metadata['contextDiagnostics']! as Map<String, Object?>;
      expect(contextDiagnostics['selectedLoreCount'], 1);
      expect(contextDiagnostics['selectedCharacterCount'], 3);
      expect(contextDiagnostics['estimatedTokensBySection'], isA<Map>());
      expect(contextDiagnostics, isNot(contains('prompt')));
      expect(contextDiagnostics, isNot(contains('content')));
      expect(
        (await fixture.repository.listStateEntries(
          fixture.sessionId,
        )).single.value,
        true,
      );
      expect(
        await fixture.repository.listMemories(fixture.sessionId),
        hasLength(1),
      );
      expect(
        await fixture.repository.listTimelineEvents(fixture.sessionId),
        hasLength(1),
      );
      expect(fixture.core.character('card-a'), originalCard);
      expect(
        await fixture.repository.getPersona(fixture.personaId),
        originalPersona,
      );
    },
  );

  test('zero-speaker turn generates narration only', () async {
    final fixture = await _seedWorld();
    final engine = _engine(
      fixture,
      runtime: _ScriptedRuntime(streamed: ['走廊里只剩脚步声。']),
      resolver: _FakeResolver(),
      decision: const WorldDirectorDecision(
        intentSummary: 'quietly leave',
        narrationNeeded: true,
      ),
    );
    final updates = await engine
        .runTurn(worldSessionId: fixture.sessionId, userAction: '我悄悄离开空无一人的走廊。')
        .toList();
    expect(
      updates.last.status,
      WorldTurnStatus.completed,
      reason: '${updates.last.error} ${updates.last.error?.detail}',
    );
    final generated = (await fixture.repository.listFeedEntries(
      fixture.sessionId,
      branchId: fixture.branchId,
    )).where((entry) => entry.type != WorldFeedEntryType.userAction);
    expect(generated.single.type, WorldFeedEntryType.narration);
  });

  test(
    'normal STOP with no character text fails without saving empty feed',
    () async {
      final fixture = await _seedWorld();
      final engine = _engine(
        fixture,
        runtime: _ScriptedRuntime(streamed: ['']),
        resolver: _FakeResolver(),
        decision: WorldDirectorDecision(
          intentSummary: 'ask',
          narrationNeeded: false,
          candidateSpeakerIds: [fixture.characterIds.first],
        ),
      );
      final updates = await engine
          .runTurn(worldSessionId: fixture.sessionId, userAction: '请回应。')
          .toList();
      expect(updates.last.type, WorldTurnUpdateType.failed);
      expect(
        updates.last.error?.category,
        WorldEngineErrorCategory.characterGenerationError,
      );
      final feed = await fixture.repository.listFeedEntries(
        fixture.sessionId,
        branchId: fixture.branchId,
      );
      expect(feed.map((entry) => entry.type), [WorldFeedEntryType.userAction]);
    },
  );

  test(
    'post-processing failure keeps generated reply and completes turn',
    () async {
      final fixture = await _seedWorld();
      final engine = _engine(
        fixture,
        runtime: _ScriptedRuntime(streamed: ['回应成功。']),
        resolver: _FakeResolver(),
        decision: WorldDirectorDecision(
          intentSummary: 'important event',
          narrationNeeded: false,
          candidateSpeakerIds: [fixture.characterIds.first],
          mutationProposal: const WorldMutationProposal(
            memories: [WorldMemoryCandidate(summary: '重要记忆', importance: 0.9)],
            timelineEvents: [
              WorldTimelineCandidate(title: '重要事件', importance: 0.9),
            ],
          ),
        ),
        memoryExtractor: const _ThrowingMemoryExtractor(),
      );
      final updates = await engine
          .runTurn(worldSessionId: fixture.sessionId, userAction: '继续。')
          .toList();
      expect(updates.last.type, WorldTurnUpdateType.completed);
      final turn = (await fixture.repository.listTurns(
        fixture.sessionId,
      )).single;
      expect(turn.metadata['postProcessingFailed'], ['memory']);
      expect(await fixture.repository.listMemories(fixture.sessionId), isEmpty);
      expect(
        await fixture.repository.listTimelineEvents(fixture.sessionId),
        hasLength(1),
      );
      final feed = await fixture.repository.listFeedEntries(
        fixture.sessionId,
        branchId: fixture.branchId,
      );
      expect(
        feed.where((entry) => entry.type == WorldFeedEntryType.characterSpeech),
        hasLength(1),
      );
    },
  );

  test(
    'transport interruption before content retries original speaker once',
    () async {
      final fixture = await _seedWorld();
      final runtime = _RetryBeforeContentRuntime();
      final engine = _engine(
        fixture,
        runtime: runtime,
        resolver: _FakeResolver(),
        decision: WorldDirectorDecision(
          intentSummary: 'ask',
          narrationNeeded: false,
          candidateSpeakerIds: [fixture.characterIds.first],
        ),
      );
      final updates = await engine
          .runTurn(worldSessionId: fixture.sessionId, userAction: '请回应。')
          .toList();
      expect(updates.last.type, WorldTurnUpdateType.completed);
      expect(runtime.streamCalls, 2);
      final speeches = (await fixture.repository.listFeedEntries(
        fixture.sessionId,
        branchId: fixture.branchId,
      )).where((entry) => entry.type == WorldFeedEntryType.characterSpeech);
      expect(speeches.single.content, '重试成功。');
    },
  );

  test(
    'second speaker partial failure preserves first and skips mutation',
    () async {
      final fixture = await _seedWorld();
      final runtime = _SecondSpeakerInterruptedRuntime();
      final engine = _engine(
        fixture,
        runtime: runtime,
        resolver: _FakeResolver(),
        decision: WorldDirectorDecision(
          intentSummary: 'ask both',
          narrationNeeded: false,
          candidateSpeakerIds: fixture.characterIds.take(2).toList(),
          preferredSpeakerIds: fixture.characterIds.take(2).toList(),
          mutationProposal: const WorldMutationProposal(
            operations: [
              WorldMutationOperation(
                type: WorldMutationType.stateSet,
                values: {'key': 'must.not.commit', 'value': true},
              ),
            ],
          ),
        ),
      );
      final updates = await engine
          .runTurn(worldSessionId: fixture.sessionId, userAction: '你们都说说。')
          .toList();
      expect(updates.last.type, WorldTurnUpdateType.failed);
      expect(
        updates.last.error?.category,
        WorldEngineErrorCategory.transportInterrupted,
      );
      expect(runtime.streamCalls, 2);
      final speeches =
          (await fixture.repository.listFeedEntries(
                fixture.sessionId,
                branchId: fixture.branchId,
              ))
              .where(
                (entry) => entry.type == WorldFeedEntryType.characterSpeech,
              )
              .toList();
      expect(speeches.map((entry) => entry.content), ['第一位完成。', '第二位 partial']);
      expect(speeches.first.metadata['generationStatus'], 'completed');
      expect(speeches.last.metadata['generationStatus'], 'interrupted');
      expect(
        await fixture.repository.listStateEntries(fixture.sessionId),
        isEmpty,
      );
    },
  );

  test('busy guard and Stop cancel only the active world turn', () async {
    final fixture = await _seedWorld();
    final runtime = _BlockingRuntime();
    final engine = _engine(
      fixture,
      runtime: runtime,
      resolver: _FakeResolver(),
      decision: WorldDirectorDecision(
        intentSummary: 'ask',
        narrationNeeded: false,
        candidateSpeakerIds: [fixture.characterIds.first],
      ),
    );
    final iterator = StreamIterator(
      engine.runTurn(worldSessionId: fixture.sessionId, userAction: '请回应。'),
    );
    while (await iterator.moveNext()) {
      if (iterator.current.type == WorldTurnUpdateType.streaming) break;
    }
    await expectLater(
      engine
          .runTurn(worldSessionId: fixture.sessionId, userAction: '重复请求')
          .toList(),
      throwsA(
        isA<WorldEngineException>().having(
          (error) => error.category,
          'category',
          WorldEngineErrorCategory.busy,
        ),
      ),
    );
    expect(engine.stop(fixture.sessionId), isTrue);
    while (await iterator.moveNext()) {}
    final turn = (await fixture.repository.listTurns(fixture.sessionId)).first;
    expect(turn.status, WorldTurnStatus.cancelled);
    final partial = (await fixture.repository.listFeedEntries(
      fixture.sessionId,
      branchId: fixture.branchId,
    )).where((entry) => entry.type == WorldFeedEntryType.characterSpeech);
    expect(partial.single.content, 'partial');
    expect(partial.single.metadata['generationStatus'], 'cancelled');
  });

  test('branch feed inherits parent only through branch point', () async {
    final fixture = await _seedWorld();
    await fixture.repository.upsertFeedEntry(
      _feed(
        'parent-1',
        sessionId: fixture.sessionId,
        branchId: fixture.branchId,
        content: 'one',
      ),
    );
    await fixture.repository.upsertFeedEntry(
      _feed(
        'parent-2',
        sessionId: fixture.sessionId,
        branchId: fixture.branchId,
        content: 'two',
      ),
    );
    final branch = WorldBranch(
      entity: _meta('branch-child'),
      worldSessionId: fixture.sessionId,
      name: 'child',
      parentBranchId: fixture.branchId,
      branchPointMessageId: 'parent-1',
    );
    await fixture.repository.upsertBranch(branch);
    await fixture.repository.upsertFeedEntry(
      _feed(
        'child-1',
        sessionId: fixture.sessionId,
        branchId: branch.id,
        content: 'child',
      ),
    );
    final entries = await fixture.repository.listFeedEntries(
      fixture.sessionId,
      branchId: branch.id,
    );
    expect(entries.map((entry) => entry.id), ['parent-1', 'child-1']);
  });

  test(
    'World, Character, Persona references share one deterministic Lore pipeline',
    () async {
      final fixture = await _seedWorld();
      final session = await fixture.repository.getSession(fixture.sessionId);
      final firstCharacter = (await fixture.repository.listCharacterInstances(
        fixture.sessionId,
      )).first;
      for (final id in ['shared-a', 'shared-b', 'shared-c']) {
        await fixture.repository.upsertWorldBook(
          WorldBook(entity: _meta(id), name: id),
        );
        await fixture.repository.upsertLoreEntry(
          LoreEntry(
            entity: _meta('entry-$id'),
            worldBookId: id,
            title: id,
            content: 'Lore $id',
            activationMode: LoreActivationMode.always,
            priority: 1,
          ),
        );
      }
      await fixture.repository.upsertWorldBookReference(
        WorldWorldBookReference(
          entity: _meta('world-a'),
          worldId: session.worldId,
          worldBookId: 'shared-a',
          priority: 2,
        ),
      );
      await fixture.repository.upsertWorldBookReference(
        WorldWorldBookReference(
          entity: _meta('world-b'),
          worldId: session.worldId,
          worldBookId: 'shared-b',
          enabled: false,
        ),
      );
      await fixture.repository.upsertCharacterWorldBookReference(
        EntityWorldBookReference(
          entity: _meta('character-c'),
          entityId: firstCharacter.characterCardId,
          worldBookId: 'shared-c',
          priority: 4,
        ),
      );
      await fixture.repository.upsertPersonaWorldBookReference(
        EntityWorldBookReference(
          entity: _meta('persona-a'),
          entityId: fixture.personaId,
          worldBookId: 'shared-a',
          priority: 9,
        ),
      );
      await fixture.repository.upsertPersonaWorldBookReference(
        EntityWorldBookReference(
          entity: _meta('persona-b'),
          entityId: fixture.personaId,
          worldBookId: 'shared-b',
        ),
      );
      await fixture.repository.upsertWorldBookOverride(
        WorldSessionWorldBookOverride(
          entity: _meta('session-b'),
          worldSessionId: fixture.sessionId,
          worldBookId: 'shared-b',
          mode: WorldBookOverrideMode.enabled,
          priority: 3,
        ),
      );

      var snapshot = await fixture.contextBuilder.build(
        worldSessionId: fixture.sessionId,
        userAction: 'continue',
      );
      expect(
        snapshot.lore.entries.map((entry) => entry.id).toSet(),
        containsAll({'entry-shared-a', 'entry-shared-b', 'entry-shared-c'}),
      );
      expect(
        snapshot.lore.entries.where((entry) => entry.id == 'entry-shared-a'),
        hasLength(1),
      );
      expect(
        snapshot.lore.entries
            .firstWhere((entry) => entry.id == 'entry-shared-a')
            .priority,
        10,
      );

      await fixture.repository.upsertWorldBookOverride(
        WorldSessionWorldBookOverride(
          entity: _meta('session-b').copyWith(revision: 2),
          worldSessionId: fixture.sessionId,
          worldBookId: 'shared-b',
          mode: WorldBookOverrideMode.disabled,
        ),
      );
      snapshot = await fixture.contextBuilder.build(
        worldSessionId: fixture.sessionId,
        userAction: 'continue',
      );
      expect(
        snapshot.lore.entries.map((entry) => entry.id),
        isNot(contains('entry-shared-b')),
      );
    },
  );

  test('Lore selection never reads unreferenced library books', () async {
    final core = InMemoryIbukiStore();
    final repository = _CountingWorldRepository(core);
    final service = WorldRoleplayService(
      repository: repository,
      ids: EntityIdGenerator(),
      clock: const UtcClock(),
    );
    final created = await service.createWorld(name: 'Large lore library');
    for (var bookIndex = 0; bookIndex < 100; bookIndex += 1) {
      final bookId = 'large-book-$bookIndex';
      await repository.upsertWorldBook(
        WorldBook(entity: _meta(bookId), name: bookId),
      );
      repository.syntheticEntryCounts[bookId] = 1000;
      if (bookIndex < 10) {
        await repository.upsertWorldBookReference(
          WorldWorldBookReference(
            entity: _meta('large-reference-$bookIndex'),
            worldId: created.world.id,
            worldBookId: bookId,
          ),
        );
      }
    }
    repository.loreBookReads.clear();
    await WorldRoleplayContextBuilder(
      worlds: repository,
      characters: InMemoryCharacterRepository(core),
    ).build(worldSessionId: created.session.id, userAction: 'continue');

    expect(repository.loreBookReads, hasLength(11));
    expect(repository.loreBookReads, contains(created.worldBook.id));
    expect(
      repository.loreBookReads.where((id) => id.startsWith('large-book-')),
      hasLength(10),
    );
    expect(repository.syntheticEntriesRead, 10000);
    expect(repository.loreBookReads, isNot(contains('large-book-99')));
  });
}

WorldRoleplayEngine _engine(
  _WorldFixture fixture, {
  required AiGenerationRuntime runtime,
  required _FakeResolver resolver,
  required WorldDirectorDecision decision,
  WorldMemoryExtractor memoryExtractor = const WorldMemoryExtractor(),
  WorldTimelineExtractor timelineExtractor = const WorldTimelineExtractor(),
}) {
  return WorldRoleplayEngine(
    repository: fixture.repository,
    contextBuilder: fixture.contextBuilder,
    director: _FixedDirector(decision),
    speakerSelector: const WorldSpeakerSelector(maxSpeakers: 3),
    mutationService: WorldMutationService(
      repository: fixture.repository,
      ids: EntityIdGenerator(),
      clock: const UtcClock(),
    ),
    runtime: runtime,
    modelResolver: resolver,
    promptPipeline: const CoreOnlyPromptPipeline(),
    hooks: IbukiHookBus(),
    ids: EntityIdGenerator(),
    clock: const UtcClock(),
    memoryExtractor: memoryExtractor,
    timelineExtractor: timelineExtractor,
  );
}

Future<_WorldFixture> _seedWorld() async {
  final core = InMemoryIbukiStore();
  final repository = InMemoryWorldRoleplayRepository(core);
  final service = WorldRoleplayService(
    repository: repository,
    ids: EntityIdGenerator(),
    clock: const UtcClock(),
  );
  final created = await service.createWorld(name: '测试世界 · 迦勒底');
  var persona = await service.createPersona(
    worldId: created.world.id,
    name: '御主',
    description: '公开的迦勒底御主',
    background: '异世界来客',
  );
  persona = persona.copyWith(
    entity: persona.entity.copyWith(
      revision: persona.revision + 1,
      updatedAt: DateTime.now().toUtc(),
    ),
    metadata: {
      'knowledgeVisibility': {
        'description': 'public',
        'background': 'directorOnly',
      },
    },
  );
  await repository.upsertPersona(persona);
  final player = await service.activatePlayerPersona(
    worldSessionId: created.session.id,
    playerPersonaId: persona.id,
  );
  final characterIds = <String>[];
  for (final name in ['梅柳齐娜', '摩根', '奥伯龙']) {
    final suffix = switch (name) {
      '梅柳齐娜' => 'a',
      '摩根' => 'b',
      _ => 'c',
    };
    final cardId = 'card-$suffix';
    core.putCharacter(
      CharacterCard(
        metadata: _meta(cardId),
        projectId: 'global-project',
        name: name,
        content: '$name 的稳定角色设定。',
        sortOrder: characterIds.length,
      ),
    );
    final instance = await service.addCharacterToWorld(
      worldSessionId: created.session.id,
      characterCardId: cardId,
    );
    characterIds.add(instance.id);
  }
  final scene = await service.createScene(
    worldSessionId: created.session.id,
    name: '迦勒底食堂',
    location: '食堂',
    timeText: 'Day 18 · 20:22',
    atmosphere: '轻松',
  );
  await service.setCurrentScene(
    worldSessionId: created.session.id,
    sceneId: scene.id,
    presentCharacterInstanceIds: characterIds.toSet(),
  );
  final session = await repository.getSession(created.session.id);
  await repository.upsertSession(
    session.copyWith(
      entity: session.entity.copyWith(
        revision: session.revision + 1,
        updatedAt: DateTime.now().toUtc(),
      ),
      aiProviderConfigId: 'gemini',
      aiModel: 'gemini-test',
    ),
  );
  await repository.upsertLoreEntry(
    LoreEntry(
      entity: _meta('cake-lore'),
      worldBookId: created.worldBook.id,
      title: '食堂点心',
      content: '迦勒底成员喜欢分享点心。',
      keywords: const ['蛋糕'],
      priority: 10,
    ),
  );
  return _WorldFixture(
    core: core,
    repository: repository,
    contextBuilder: WorldRoleplayContextBuilder(
      worlds: repository,
      characters: InMemoryCharacterRepository(core),
    ),
    sessionId: created.session.id,
    branchId: created.branch.id,
    personaId: persona.id,
    playerInstanceId: player.id,
    characterIds: characterIds,
  );
}

class _WorldFixture {
  const _WorldFixture({
    required this.core,
    required this.repository,
    required this.contextBuilder,
    required this.sessionId,
    required this.branchId,
    required this.personaId,
    required this.playerInstanceId,
    required this.characterIds,
  });

  final InMemoryIbukiStore core;
  final InMemoryWorldRoleplayRepository repository;
  final WorldRoleplayContextBuilder contextBuilder;
  final String sessionId;
  final String branchId;
  final String personaId;
  final String playerInstanceId;
  final List<String> characterIds;
}

class _CountingWorldRepository extends InMemoryWorldRoleplayRepository {
  _CountingWorldRepository(super.coreStore);

  final loreBookReads = <String>[];
  final syntheticEntryCounts = <String, int>{};
  var syntheticEntriesRead = 0;

  @override
  Future<List<LoreEntry>> listLoreEntries(
    String worldBookId, {
    String query = '',
  }) async {
    loreBookReads.add(worldBookId);
    final count = syntheticEntryCounts[worldBookId];
    if (count != null) {
      syntheticEntriesRead += count;
      return List.generate(
        count,
        (index) => LoreEntry(
          entity: _meta('$worldBookId-entry-$index'),
          worldBookId: worldBookId,
          title: 'Synthetic entry $index',
          content: 'Synthetic content $index',
          activationMode: LoreActivationMode.keyword,
          keywords: const ['never-matches-current-action'],
        ),
        growable: false,
      );
    }
    return super.listLoreEntries(worldBookId, query: query);
  }
}

class _FixedDirector implements WorldDirector {
  const _FixedDirector(this.decision);

  final WorldDirectorDecision decision;

  @override
  Future<WorldDirectorDecision> decide({
    required String requestId,
    required WorldRoleplaySnapshot snapshot,
    required AiRequestCancellation cancellation,
  }) async => decision;
}

class _FakeResolver implements AiModelResolver {
  final List<String> worldSessionIds = [];

  @override
  Future<ResolvedAiModel> resolveForWorldSession(String sessionId) async {
    worldSessionIds.add(sessionId);
    return const ResolvedAiModel(
      providerConfigId: 'gemini',
      providerType: 'gemini',
      model: 'gemini-test',
      displayLabel: 'Gemini · gemini-test',
      source: AiModelSelectionSource.worldSessionOverride,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptedRuntime implements AiGenerationRuntime {
  _ScriptedRuntime({this.streamed = const [], this.generated = const []});

  final List<String> streamed;
  final List<String> generated;
  final List<AiGenerationRequest> requests = [];
  int streamCalls = 0;
  int generateCalls = 0;

  @override
  Future<AiResolvedProvider> resolveDefault() => throw UnimplementedError();

  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    requests.add(request);
    final value = streamed[streamCalls++];
    final split = value.length ~/ 2;
    yield value.substring(0, split);
    yield value.substring(split);
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async {
    requests.add(request);
    return generated[generateCalls++];
  }
}

class _BlockingRuntime implements AiGenerationRuntime {
  final Completer<void> _cancelled = Completer<void>();

  @override
  Future<AiResolvedProvider> resolveDefault() => throw UnimplementedError();

  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    cancellation?.attach(() {
      if (!_cancelled.isCompleted) _cancelled.complete();
    });
    yield 'partial';
    await _cancelled.future;
    throw const AiProviderCancelledException();
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) => throw UnimplementedError();
}

class _RetryBeforeContentRuntime implements AiGenerationRuntime {
  int streamCalls = 0;

  @override
  Future<AiResolvedProvider> resolveDefault() => throw UnimplementedError();

  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    streamCalls += 1;
    if (streamCalls == 1) {
      throw const AiProviderInterruptedBeforeContentException();
    }
    yield '重试成功。';
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) => throw UnimplementedError();
}

class _SecondSpeakerInterruptedRuntime implements AiGenerationRuntime {
  int streamCalls = 0;

  @override
  Future<AiResolvedProvider> resolveDefault() => throw UnimplementedError();

  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    streamCalls += 1;
    if (streamCalls == 1) {
      yield '第一位完成。';
      return;
    }
    yield '第二位 partial';
    throw const AiProviderInterruptedException();
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) => throw UnimplementedError();
}

class _ThrowingMemoryExtractor extends WorldMemoryExtractor {
  const _ThrowingMemoryExtractor();

  @override
  List<WorldMemoryCandidate> extract(WorldMutationProposal proposal) {
    throw StateError('synthetic memory failure');
  }
}

LoreEntry _lore(
  String id,
  LoreActivationMode mode, {
  int priority = 0,
  bool enabled = true,
  List<String> keywords = const [],
  String content = '',
}) {
  return LoreEntry(
    entity: _meta(id),
    worldBookId: 'book',
    title: id,
    content: content,
    activationMode: mode,
    priority: priority,
    enabled: enabled,
    keywords: keywords,
  );
}

WorldCharacterInstance _instance(String id, {double talkativeness = 0.5}) {
  return WorldCharacterInstance(
    entity: _meta(id),
    worldSessionId: 'session',
    characterCardId: 'card-$id',
    isPresent: true,
    metadata: {'talkativeness': talkativeness},
  );
}

WorldFeedEntry _feed(
  String id, {
  String sessionId = 'session',
  String branchId = 'branch',
  String? speakerId,
  String content = 'message',
}) {
  return WorldFeedEntry(
    entity: _meta(id),
    worldSessionId: sessionId,
    branchId: branchId,
    type: speakerId == null
        ? WorldFeedEntryType.narration
        : WorldFeedEntryType.characterSpeech,
    speakerCharacterInstanceId: speakerId,
    content: content,
  );
}

EntityMetadata _meta(String id) {
  final now = DateTime.utc(2026, 1, 1);
  return EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);
}
