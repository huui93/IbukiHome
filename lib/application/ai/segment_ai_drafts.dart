import '../../domain/projects/novel_output_limits.dart';
import '../../data/repositories/novel_output_limits_repository.dart';
// ignore_for_file: prefer_initializing_formals

import '../../core/errors/data_exceptions.dart';
import '../../core/network/ai_provider_exceptions.dart';
import '../../data/repositories/segment_repository.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/segments/segment.dart';
import '../segments/save_segment.dart';
import '../plugins/ibuki_prompt_pipeline.dart';
import '../plugins/novel_plugin_host.dart';
import '../plugins/novel_reply_markup.dart';
import '../../domain/plugins/novel_plugin_models.dart';
import 'ai_draft_update.dart';
import 'ai_generation_service.dart';
import 'ai_request_coordinator.dart';
import 'clean_ai_text.dart';
import 'novel_output_policy.dart';
import 'novel_context_loader.dart';
import 'novel_ai_response.dart';
import 'novel_prompt_builder.dart';
import 'ai_model_resolver.dart';

class RewriteSegment {
  const RewriteSegment(this._runner, this._segments, this._saveSegment);

  final SegmentAiDraftRunner _runner;
  final SegmentRepository _segments;
  final SaveSegment _saveSegment;

  Stream<AiDraftUpdate> call({
    required String projectId,
    required String segmentId,
    required String instruction,
    required Set<String> selectedCharacterIds,
    required Set<String> selectedWorldCardIds,
    required String requestId,
  }) {
    return _runner.stream(
      operation: NovelAiOperation.rewrite,
      projectId: projectId,
      segmentId: segmentId,
      instruction: instruction,
      selectedCharacterIds: selectedCharacterIds,
      selectedWorldCardIds: selectedWorldCardIds,
      requestId: requestId,
    );
  }

  Future<Segment> apply({
    required String segmentId,
    required String originalContent,
    required String draft,
    required String instruction,
    required DateTime nowUtc,
    required String revisionId,
    String? requestId,
  }) async {
    final current = await _segments.getSegment(segmentId);
    _ensureUnchanged(current, originalContent);
    final staged = await _runner._takeDraft(
      current,
      requestId,
      cleanAiText(draft),
    );
    try {
      final updatedSegment = await _saveSegment(
        currentSegment: current,
        newContent: cleanAiText(draft),
        now: nowUtc,
        revisionId: revisionId,
        note: 'AI 重写前自动归档',
        userInstruction: instruction,
        mode: 'ai_rewrite',
        notify: staged == null,
      );
      if (staged != null) await _runner._completeDraft(staged, updatedSegment);
      return updatedSegment;
    } catch (error) {
      throw AiPersistenceException(
        stage: AiPersistenceStage.revisionSave,
        causeType: error.runtimeType.toString(),
        message: '修改结果已经生成，但版本保存失败。',
      );
    }
  }
}

class ModifySegmentWithInstruction {
  const ModifySegmentWithInstruction(
    this._runner,
    this._segments,
    this._saveSegment,
  );

  final SegmentAiDraftRunner _runner;
  final SegmentRepository _segments;
  final SaveSegment _saveSegment;

  Stream<AiDraftUpdate> call({
    required String projectId,
    required String segmentId,
    required String instruction,
    required Set<String> selectedCharacterIds,
    required Set<String> selectedWorldCardIds,
    required String requestId,
  }) {
    if (instruction.trim().isEmpty) {
      throw const DataFormatException('修改要求不能为空。');
    }
    return _runner.stream(
      operation: NovelAiOperation.modify,
      projectId: projectId,
      segmentId: segmentId,
      instruction: instruction,
      selectedCharacterIds: selectedCharacterIds,
      selectedWorldCardIds: selectedWorldCardIds,
      requestId: requestId,
    );
  }

  Future<Segment> apply({
    required String segmentId,
    required String originalContent,
    required String draft,
    required String instruction,
    required DateTime nowUtc,
    required String revisionId,
    String? requestId,
  }) async {
    final current = await _segments.getSegment(segmentId);
    _ensureUnchanged(current, originalContent);
    final staged = await _runner._takeDraft(
      current,
      requestId,
      cleanAiText(draft),
    );
    try {
      final updatedSegment = await _saveSegment(
        currentSegment: current,
        newContent: cleanAiText(draft),
        now: nowUtc,
        revisionId: revisionId,
        note: 'AI 按要求修改前自动归档',
        userInstruction: instruction,
        mode: 'ai_modify',
        notify: staged == null,
      );
      if (staged != null) await _runner._completeDraft(staged, updatedSegment);
      return updatedSegment;
    } catch (error) {
      throw AiPersistenceException(
        stage: AiPersistenceStage.revisionSave,
        causeType: error.runtimeType.toString(),
        message: '修改结果已经生成，但版本保存失败。',
      );
    }
  }
}

class SelectionModifySegment {
  const SelectionModifySegment(this._runner, this._segments, this._saveSegment);

  final SegmentAiDraftRunner _runner;
  final SegmentRepository _segments;
  final SaveSegment _saveSegment;

  Stream<AiDraftUpdate> call({
    required String projectId,
    required String segmentId,
    required int selectionStart,
    required int selectionEnd,
    required String instruction,
    required Set<String> selectedCharacterIds,
    required Set<String> selectedWorldCardIds,
    required String requestId,
  }) {
    if (selectionEnd <= selectionStart) {
      throw const DataFormatException('请选择需要修改的文字。');
    }
    return _runner.stream(
      operation: NovelAiOperation.selectionModify,
      projectId: projectId,
      segmentId: segmentId,
      selectionStart: selectionStart,
      selectionEnd: selectionEnd,
      instruction: instruction,
      selectedCharacterIds: selectedCharacterIds,
      selectedWorldCardIds: selectedWorldCardIds,
      requestId: requestId,
    );
  }

  Future<Segment> apply({
    required String segmentId,
    required String originalContent,
    required int selectionStart,
    required int selectionEnd,
    required String replacementDraft,
    required String instruction,
    required DateTime nowUtc,
    required String revisionId,
    String? requestId,
  }) async {
    final current = await _segments.getSegment(segmentId);
    _ensureUnchanged(current, originalContent);
    final start = selectionStart.clamp(0, originalContent.length);
    final end = selectionEnd.clamp(start, originalContent.length);
    if (end <= start) {
      throw const DataConflictException('原选区已经失效。');
    }
    final replacement = cleanAiText(replacementDraft);
    if (replacement.isEmpty) {
      throw const DataFormatException('模型没有返回可用的替换内容。');
    }
    final updated =
        originalContent.substring(0, start) +
        replacement +
        originalContent.substring(end);
    try {
      final updatedSegment = await _saveSegment(
        currentSegment: current,
        newContent: updated,
        now: nowUtc,
        revisionId: revisionId,
        note: 'AI 选择性修改前自动归档',
        userInstruction: instruction,
        mode: 'ai_selection_modify',
      );
      return updatedSegment;
    } catch (error) {
      throw AiPersistenceException(
        stage: AiPersistenceStage.revisionSave,
        causeType: error.runtimeType.toString(),
        message: '修改结果已经生成，但版本保存失败。',
      );
    }
  }
}

class SegmentAiDraftRunner {
  SegmentAiDraftRunner({
    required NovelContextLoader contextLoader,
    required NovelPromptBuilder promptBuilder,
    required AiGenerationRuntime runtime,
    required AiRequestCoordinator coordinator,
    AiModelResolver? modelResolver,
    IbukiPromptPipeline? promptPipeline,
    NovelOutputLimitsRepository? outputLimits,
    NovelPluginHost? novelPlugins,
  }) : _contextLoader = contextLoader,
       _promptBuilder = promptBuilder,
       _runtime = runtime,
       _coordinator = coordinator,
       _modelResolver = modelResolver,
       _promptPipeline = promptPipeline,
       _outputLimits = outputLimits,
       _novelPlugins = novelPlugins;

  final NovelPluginHost? _novelPlugins;
  final _drafts = <String, _NovelStagedDraft>{};

  Future<_NovelStagedDraft?> _takeDraft(
    Segment segment,
    String? requestId,
    String text,
  ) async {
    if (requestId == null) return null;
    final staged = _drafts.remove(requestId);
    if (staged == null) return null;
    if (staged.targetId != segment.id ||
        staged.targetRevision != segment.revision ||
        staged.content != text) {
      throw const DataConflictException('原段落已变化，请重新生成草稿。');
    }
    await _novelPlugins!.checkCurrent(segment.projectId, staged.run);
    return staged;
  }

  Future<void> _completeDraft(_NovelStagedDraft staged, Segment segment) async {
    final host = _novelPlugins!;
    if (segment.revision == staged.targetRevision) return;
    try {
      await host.complete(
        run: staged.run,
        segment: segment,
        raw: staged.raw,
        finish: staged.finish,
      );
    } catch (_) {
      host.finalized(segment, 'regenerate');
    }
  }

  static const channel = 'novel-generation';

  final NovelContextLoader _contextLoader;
  final NovelPromptBuilder _promptBuilder;
  final AiGenerationRuntime _runtime;
  final AiRequestCoordinator _coordinator;
  final AiModelResolver? _modelResolver;
  final IbukiPromptPipeline? _promptPipeline;
  final NovelOutputLimitsRepository? _outputLimits;

  Stream<AiDraftUpdate> stream({
    required NovelAiOperation operation,
    required String projectId,
    required String segmentId,
    required String instruction,
    required Set<String> selectedCharacterIds,
    required Set<String> selectedWorldCardIds,
    required String requestId,
    int? selectionStart,
    int? selectionEnd,
  }) async* {
    final cancellation = _coordinator.begin(
      channel,
      requestId,
      scopeId: projectId,
    );
    final draft = StringBuffer();
    var lastYield = DateTime.fromMillisecondsSinceEpoch(0);
    ResolvedAiModel? selected;
    AiFinishReason? finishReason;
    var streamEventCount = 0;
    String? pluginNotice;
    NovelOutputLimits? outputLimitsForCancellation;
    var structuredReply = false;
    try {
      final context = await _contextLoader.load(
        projectId: projectId,
        selectedCharacterIds: selectedCharacterIds,
        selectedWorldCardIds: selectedWorldCardIds,
      );
      final target = context.segments
          .where((item) => item.id == segmentId)
          .firstOrNull;
      if (target == null) {
        throw const DataConflictException('目标段落不存在或已经删除。');
      }
      final host = _novelPlugins;
      final binding = await host?.bindingFor(projectId);
      final prompt = switch (operation) {
        NovelAiOperation.rewrite => _promptBuilder.buildRewrite(
          project: context.project,
          segments: context.segments,
          target: target,
          characters: context.characters,
          worldCards: context.worldCards,
          instruction: instruction,
          outline: context.outline,
          memory: context.memory,
          structured: binding != null,
        ),
        NovelAiOperation.modify => _promptBuilder.buildModify(
          project: context.project,
          segments: context.segments,
          target: target,
          characters: context.characters,
          worldCards: context.worldCards,
          instruction: instruction,
          outline: context.outline,
          memory: context.memory,
          structured: binding != null,
        ),
        NovelAiOperation.selectionModify => _promptBuilder.buildSelectionModify(
          project: context.project,
          segments: context.segments,
          target: target,
          selectionStart: selectionStart ?? -1,
          selectionEnd: selectionEnd ?? -1,
          characters: context.characters,
          worldCards: context.worldCards,
          instruction: instruction,
          outline: context.outline,
          memory: context.memory,
          structured: binding != null,
        ),
        _ => throw const DataConflictException('不支持这个段落 AI 操作。'),
      };
      final settings = await _outputLimits?.get(projectId);
      final applyLength = operation != NovelAiOperation.selectionModify;
      final outputLimits = applyLength ? settings : null;
      outputLimitsForCancellation = outputLimits;
      structuredReply = binding != null;
      final system = binding == null
          ? prompt.systemPrompt
          : _promptBuilder.structuredSystem(
              project: context.project,
              outline: context.outline,
            );
      final coreRequest = AiGenerationRequest(
        requestId: requestId,
        systemPrompt: system,
        messages: [
          AiGenerationMessage(
            role: AiMessageRole.user,
            content: prompt.userPrompt,
          ),
        ],
        temperature: 0.7,
        maxTokens: novelDefaultOutputTokens,
      );
      var request = coreRequest;
      final pipeline = _promptPipeline;
      if (pipeline != null && binding == null) {
        try {
          final promptOperation = switch (operation) {
            NovelAiOperation.rewrite => PluginPromptOperation.novelRewrite,
            NovelAiOperation.modify => PluginPromptOperation.novelModify,
            NovelAiOperation.selectionModify =>
              PluginPromptOperation.novelSelectionModify,
            _ => PluginPromptOperation.novelGenerate,
          };
          final result = await pipeline.apply(
            coreRequest,
            PluginPromptContext(
              operation: promptOperation,
              projectId: projectId,
              safeMetadata: {
                'segmentCount': context.segments.length,
                'characterCount': context.characters.length,
                'worldCardCount': context.worldCards.length,
                'userInstructionChars': instruction.length,
              },
            ),
          );
          request = result.request;
          pluginNotice = result.userNotice;
        } catch (_) {
          pluginNotice = '插件运行异常，本次已使用默认创作流程。';
        }
      }
      selected = await _modelResolver?.resolveForProject(projectId);
      request = request.copyWith(
        providerConfigId: selected?.providerConfigId,
        model: selected?.model,
      );
      final limits = binding == null && selected != null
          ? await host?.modelLimits?.call(selected)
          : null;
      request = applyNovelOutputSettings(
        request: request,
        settings: settings,
        model: selected,
        applyLength: applyLength,
        structured: binding != null,
        modelOutputLimit: limits?.output,
      );
      final run = binding == null
          ? null
          : await host!.prepare(
              binding: binding,
              context: context,
              core: request,
              model: selected,
              projectTemperature: settings?.temperature,
              projectOutputTokenLimit: novelOutputTokenCeiling(outputLimits),
              authorInput: prompt.userPrompt,
              instruction: instruction,
              mode: NovelGenerationMode.regenerate,
              targetSegmentId: target.id,
              targetRevision: target.revision,
              now: DateTime.now(),
            );
      if (run != null) request = run.compiled.request;
      if (!_coordinator.isCurrent(channel, requestId)) {
        throw const AiProviderCancelledException();
      }
      await for (final event in runtimeStreamEvents(
        _runtime,
        request,
        cancellation: cancellation,
      )) {
        if (!_coordinator.isCurrent(channel, requestId)) {
          throw const AiProviderCancelledException();
        }
        streamEventCount += 1;
        if (event.isTerminal) {
          finishReason = event.finishReason;
          continue;
        }
        draft.write(event.content);
        final now = DateTime.now();
        if (now.difference(lastYield) >= const Duration(milliseconds: 32)) {
          lastYield = now;
          yield AiDraftUpdate(
            requestId: requestId,
            draft: run == null
                ? enforceNovelOutputLength(
                    NovelAiResponse.clean(draft.toString()),
                    outputLimits,
                    structured: false,
                  ).text
                : draft.toString(),
            status: AiDraftStatus.streaming,
            pluginNotice: pluginNotice,
          );
        }
      }
      if (!_coordinator.isCurrent(channel, requestId)) {
        throw const AiProviderCancelledException();
      }
      if (run != null) {
        if (finishReason == AiFinishReason.cancelled) {
          throw const AiProviderCancelledException();
        }
        if (finishReason != AiFinishReason.stop &&
            finishReason != AiFinishReason.length) {
          throw const AiProviderInterruptedException();
        }
        await host!.checkCurrent(projectId, run);
        if (!_coordinator.isCurrent(channel, requestId)) {
          throw const AiProviderCancelledException();
        }
      }
      final decoded = NovelAiResponse.finalize(
        requestId: requestId,
        stage: operation.name,
        adapterText: run == null
            ? draft.toString()
            : NovelReplyMarkup.withoutTemplateReasoning(draft.toString()),
        finishReason: finishReason,
        streamEventCount: streamEventCount,
        provider: selected?.providerType,
        model: selected?.model,
      );
      final output = enforceNovelOutputLength(
        decoded,
        outputLimits,
        structured: run != null,
      );
      final content = output.text;
      if (run != null && operation != NovelAiOperation.selectionModify) {
        _drafts[requestId] = _NovelStagedDraft(
          run,
          target.id,
          target.revision,
          draft.toString(),
          content,
          output.trimmed ? AiFinishReason.length : finishReason,
        );
        if (_drafts.length > 8) _drafts.remove(_drafts.keys.first);
      }
      yield AiDraftUpdate(
        requestId: requestId,
        draft: content,
        status: AiDraftStatus.completed,
        outputNotice: output.notice,
        pluginNotice: pluginNotice,
      );
    } on AiProviderInvalidResponseException catch (error) {
      final enriched = NovelAiResponse.enrich(
        error: error,
        adapterText: draft.toString(),
        finishReason: finishReason,
        streamEventCount: streamEventCount,
        provider: selected?.providerType,
        model: selected?.model,
      );
      NovelAiResponse.recordFailure(
        requestId: requestId,
        stage: operation.name,
        error: enriched,
      );
      throw enriched;
    } on AiProviderCancelledException {
      yield AiDraftUpdate(
        requestId: requestId,
        draft: enforceNovelOutputLength(
          NovelAiResponse.clean(draft.toString()),
          outputLimitsForCancellation,
          structured: structuredReply,
        ).text,
        status: AiDraftStatus.cancelled,
        pluginNotice: pluginNotice,
      );
    } finally {
      _coordinator.finish(channel, requestId);
    }
  }

  bool cancel(String requestId) {
    return _coordinator.cancel(channel, requestId: requestId);
  }
}

void _ensureUnchanged(Segment current, String originalContent) {
  if (current.deletedAt != null || current.content != originalContent) {
    throw const DataConflictException('生成期间正文已经变化，AI 草稿未写入。');
  }
}

class _NovelStagedDraft {
  const _NovelStagedDraft(
    this.run,
    this.targetId,
    this.targetRevision,
    this.raw,
    this.content,
    this.finish,
  );
  final NovelPluginRun run;
  final String targetId;
  final int targetRevision;
  final String raw;
  final String content;
  final AiFinishReason? finish;
}
