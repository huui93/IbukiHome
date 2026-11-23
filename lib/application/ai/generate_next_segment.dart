import '../../domain/projects/novel_output_limits.dart';
import '../../data/repositories/novel_output_limits_repository.dart';
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../../core/errors/data_exceptions.dart';
import '../../core/network/ai_provider_exceptions.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/segments/segment.dart';
import '../segments/create_segment.dart';
import 'ai_draft_update.dart';
import 'ai_generation_service.dart';
import 'ai_request_coordinator.dart';
import 'novel_output_policy.dart';
import 'novel_context_loader.dart';
import 'novel_ai_response.dart';
import 'novel_prompt_builder.dart';
import '../memory/novel_memory_service.dart';
import '../plugins/ibuki_prompt_pipeline.dart';
import '../plugins/novel_plugin_host.dart';
import '../plugins/novel_reply_markup.dart';
import '../plugins/novel_prompt_compiler.dart';
import '../../domain/plugins/novel_plugin_models.dart';
import 'ai_model_resolver.dart';

class GenerateNextSegment {
  const GenerateNextSegment({
    required NovelContextLoader contextLoader,
    required NovelPromptBuilder promptBuilder,
    required AiGenerationRuntime runtime,
    required AiRequestCoordinator coordinator,
    required CreateSegment createSegment,
    NovelMemoryService? memoryService,
    AiModelResolver? modelResolver,
    IbukiPromptPipeline? promptPipeline,
    NovelOutputLimitsRepository? outputLimits,
    NovelPluginHost? novelPlugins,
  }) : _contextLoader = contextLoader,
       _promptBuilder = promptBuilder,
       _runtime = runtime,
       _coordinator = coordinator,
       _createSegment = createSegment,
       _memoryService = memoryService,
       _modelResolver = modelResolver,
       _promptPipeline = promptPipeline,
       _outputLimits = outputLimits,
       _novelPlugins = novelPlugins;

  final NovelPluginHost? _novelPlugins;

  static const channel = 'novel-generation';

  final NovelContextLoader _contextLoader;
  final NovelPromptBuilder _promptBuilder;
  final AiGenerationRuntime _runtime;
  final AiRequestCoordinator _coordinator;
  final CreateSegment _createSegment;
  final NovelMemoryService? _memoryService;
  final AiModelResolver? _modelResolver;
  final IbukiPromptPipeline? _promptPipeline;
  final NovelOutputLimitsRepository? _outputLimits;

  Stream<AiDraftUpdate> call({
    required String projectId,
    required String userInstruction,
    required Set<String> selectedCharacterIds,
    required Set<String> selectedWorldCardIds,
    required String requestId,
    required String segmentId,
    required DateTime nowUtc,
    NovelGenerationMode mode = NovelGenerationMode.normal,
    String? speakerId,
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
    var attempt = 0;
    String? pluginNotice;
    NovelOutputLimits? outputLimitsForCancellation;
    var structuredReply = false;
    try {
      final context = await _contextLoader.load(
        projectId: projectId,
        selectedCharacterIds: selectedCharacterIds,
        selectedWorldCardIds: selectedWorldCardIds,
      );
      final host = _novelPlugins;
      final binding = await host?.bindingFor(projectId);
      if (binding == null && mode != NovelGenerationMode.normal) {
        throw const NovelPluginRequestException('请先在当前作品启用小说插件。');
      }
      final prompt = _promptBuilder.buildContinue(
        project: context.project,
        segments: context.segments,
        characters: context.characters,
        worldCards: context.worldCards,
        instruction: userInstruction,
        outline: context.outline,
        memory: context.memory,
        structured: binding != null,
      );
      final settings = await _outputLimits?.get(projectId);
      final applyLength = mode != NovelGenerationMode.impersonate;
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
        temperature: 0.75,
        maxTokens: novelDefaultOutputTokens,
      );
      var request = coreRequest;
      final pipeline = _promptPipeline;
      if (pipeline != null && binding == null) {
        try {
          final result = await pipeline.apply(
            coreRequest,
            PluginPromptContext(
              operation: PluginPromptOperation.novelGenerate,
              projectId: projectId,
              safeMetadata: {
                'segmentCount': context.segments.length,
                'characterCount': context.characters.length,
                'worldCardCount': context.worldCards.length,
                'userInstructionChars': userInstruction.length,
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
              authorInput:
                  mode == NovelGenerationMode.impersonate ||
                      mode == NovelGenerationMode.empty
                  ? userInstruction.trim()
                  : prompt.userPrompt,
              instruction: userInstruction,
              mode: mode,
              speakerId: speakerId,
              now: nowUtc,
            );
      if (run != null) request = run.compiled.request;
      if (!_coordinator.isCurrent(channel, requestId)) {
        throw const AiProviderCancelledException();
      }
      while (true) {
        attempt += 1;
        draft.clear();
        run?.reasoning.clear();
        finishReason = null;
        streamEventCount = 0;
        lastYield = DateTime.fromMillisecondsSinceEpoch(0);
        try {
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
          break;
        } on AiProviderInterruptedBeforeContentException catch (error) {
          NovelAiResponse.recordTransportInterruption(
            requestId: requestId,
            stage: 'generate-next-segment',
            error: error,
            attempt: attempt,
          );
          if (attempt >= 2 ||
              !_coordinator.isCurrent(channel, requestId) ||
              cancellation.isCancelled) {
            rethrow;
          }
          yield AiDraftUpdate(
            requestId: requestId,
            draft: '',
            status: AiDraftStatus.retrying,
            pluginNotice: pluginNotice,
          );
        }
      }
      if (!_coordinator.isCurrent(channel, requestId)) {
        throw const AiProviderCancelledException();
      }
      final decoded = NovelAiResponse.finalize(
        requestId: requestId,
        stage: 'generate-next-segment',
        adapterText: run == null
            ? draft.toString()
            : NovelReplyMarkup.withoutTemplateReasoning(draft.toString()),
        finishReason: finishReason,
        streamEventCount: streamEventCount,
        provider: selected?.providerType,
        model: selected?.model,
        attempt: attempt,
      );
      final output = enforceNovelOutputLength(
        decoded,
        outputLimits,
        structured: run != null,
      );
      final content = output.text;
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
      if (mode == NovelGenerationMode.impersonate) {
        yield AiDraftUpdate(
          requestId: requestId,
          draft: content,
          status: AiDraftStatus.completed,
        );
        return;
      }
      late final Segment segment;
      try {
        segment = await _createSegment(
          projectId: projectId,
          content: content,
          id: segmentId,
          nowUtc: nowUtc,
          notify: false,
        );
      } catch (error) {
        throw AiPersistenceException(
          stage: AiPersistenceStage.segmentSave,
          causeType: error.runtimeType.toString(),
          message: '正文已经生成，但本地保存失败。',
        );
      }
      var ended = false;
      if (run != null) {
        try {
          ended = await host!.complete(
            run: run,
            segment: segment,
            raw: draft.toString(),
            finish: output.trimmed ? AiFinishReason.length : finishReason,
          );
        } catch (_) {
          pluginNotice = '正文已保存，插件展示或结束状态未能保存。';
        }
      } else {
        host?.publish(projectId, 'send', segmentId: segment.id);
      }
      final memoryService = run == null ? _memoryService : null;
      if (memoryService != null) {
        unawaited(memoryService.refresh(projectId));
      }
      yield AiDraftUpdate(
        requestId: requestId,
        draft: content,
        status: AiDraftStatus.completed,
        savedSegment: segment,
        outputNotice: output.notice,
        storyEnded: ended,
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
        stage: 'generate-next-segment',
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
