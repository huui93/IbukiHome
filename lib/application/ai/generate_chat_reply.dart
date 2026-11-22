// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../../core/errors/data_exceptions.dart';
import '../../core/network/ai_provider_exceptions.dart';
import '../../data/repositories/chat_persona_repository.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/chat_controls_repository.dart';
import '../../domain/ai/ai_reasoning_level.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_message_role.dart';
import '../../domain/common/entity_metadata.dart';
import '../chat/chat_usage_tracker.dart';
import '../chat/recognize_chat_image.dart';
import '../memory/chat_memory_context.dart';
import '../memory/chat_memory_service.dart';
import '../plugins/ibuki_prompt_pipeline.dart';
import 'ai_draft_update.dart';
import 'ai_generation_service.dart';
import 'ai_model_resolver.dart';
import 'ai_request_coordinator.dart';
import 'ai_stream_diagnostics.dart';
import 'chat_continuation_stitcher.dart';
import 'chat_prompt_builder.dart';

class GenerateChatReply {
  const GenerateChatReply({
    required ChatRepository chats,
    required ChatPersonaRepository personas,
    required ChatPromptBuilder promptBuilder,
    required AiGenerationRuntime runtime,
    required AiRequestCoordinator coordinator,
    ChatMemoryService? memoryService,
    AiModelResolver? modelResolver,
    IbukiPromptPipeline? promptPipeline,
    ChatControlsRepository? controls,
    ChatUsageTracker? usageTracker,
    RecognizeChatImage? imageRecognizer,
  }) : _chats = chats,
       _personas = personas,
       _promptBuilder = promptBuilder,
       _runtime = runtime,
       _coordinator = coordinator,
       _memoryService = memoryService,
       _modelResolver = modelResolver,
       _promptPipeline = promptPipeline,
       _controls = controls,
       _usageTracker = usageTracker,
       _imageRecognizer = imageRecognizer;

  static const channel = 'chat-generation';
  static const maxAutomaticRecoveryAttempts = 1;

  final ChatRepository _chats;
  final ChatPersonaRepository _personas;
  final ChatPromptBuilder _promptBuilder;
  final AiGenerationRuntime _runtime;
  final AiRequestCoordinator _coordinator;
  final ChatMemoryService? _memoryService;
  final AiModelResolver? _modelResolver;
  final IbukiPromptPipeline? _promptPipeline;
  final ChatControlsRepository? _controls;
  final ChatUsageTracker? _usageTracker;
  final RecognizeChatImage? _imageRecognizer;

  Stream<AiDraftUpdate> call({
    required String sessionId,
    required String userMessageId,
    required String requestId,
    required String assistantMessageId,
    required DateTime nowUtc,
    String? continueMessageId,
    String? regenerateMessageId,
  }) async* {
    final cancellation = _coordinator.begin(channel, requestId);
    try {
      final session = await _chats.getSession(sessionId);
      if (session.deletedAt != null) {
        throw const DataConflictException('已删除会话不能生成回复。');
      }
      final personaId = session.personaId;
      if (personaId == null) {
        throw const DataConflictException('旧会话尚未关联聊天角色，不能生成角色回复。');
      }
      final persona = await _personas.getPersona(personaId);
      if (persona.deletedAt != null) {
        throw const DataConflictException('已删除聊天角色不能生成回复。');
      }
      var initialMessages = await _chats.listMessages(sessionId);
      _requireUserMessage(initialMessages, userMessageId);
      final userIndex = initialMessages.indexWhere(
        (m) => m.id == userMessageId,
      );
      var initialUser = initialMessages[userIndex];
      if (continueMessageId != null && regenerateMessageId != null) {
        throw const DataConflictException('不能同时续写和重新生成。');
      }
      final regenerationTarget = _latestAssistantTarget(
        initialMessages,
        regenerateMessageId,
        userMessageId,
      );
      if (continueMessageId == null &&
          regenerationTarget == null &&
          initialMessages.last.id != userMessageId) {
        throw const DataConflictException('这条消息已有后续内容，请对最后一条回复操作。');
      }
      if (initialUser.image?.needsRecognition == true) {
        final recognizer = _imageRecognizer;
        if (recognizer == null) {
          throw const AiProviderValidationException('图片识别尚未配置。');
        }
        initialUser = await recognizer(
          message: initialUser,
          personaId: personaId,
          requestId: requestId,
          cancellation: cancellation,
        );
        initialMessages = await _chats.listMessages(sessionId);
      }
      final alreadyAnswered = initialMessages
          .skip(userIndex + 1)
          .any(
            (m) => m.role == ChatMessageRole.assistant && m.deletedAt == null,
          );
      final memoryInstruction = alreadyAnswered
          ? null
          : await _memoryService?.applyUserInstruction(
              sessionId,
              initialUser.image?.userText ?? initialUser.content,
            );
      var targetMessage = _latestAssistantTarget(
        initialMessages,
        continueMessageId,
        userMessageId,
      );
      var automaticRecoveryAttempts = 0;
      var beforeContentRetryAttempts = 0;
      var requestAttempt = 0;
      var attemptRequestType = targetMessage == null
          ? regenerationTarget == null
                ? 'chat-reply'
                : 'chat-regenerate'
          : 'manual-continue';
      String? pluginNotice;
      final reasoning =
          await _controls?.getReasoning(sessionId) ??
          AiReasoningLevel.automatic;

      while (true) {
        requestAttempt += 1;
        final selected = await _modelResolver?.resolveForChatSession(sessionId);
        final attemptRequestId = requestAttempt == 1
            ? requestId
            : '$requestId-attempt-$requestAttempt';
        final activeMessages = await _chats.listMessages(sessionId);
        final messages = regenerationTarget != null && targetMessage == null
            ? activeMessages
                  .where((m) => m.id != regenerationTarget.id)
                  .toList()
            : activeMessages;
        _requireUserMessage(messages, userMessageId);
        final memoryContext =
            await _memoryService?.loadContext(
              personaId: personaId,
              sessionId: sessionId,
              query: messages.where((m) => m.id == userMessageId).first.content,
              excludedMessageIds:
                  regenerationTarget != null && targetMessage == null
                  ? {regenerationTarget.id}
                  : const {},
            ) ??
            const ChatMemoryContext();
        var request = _promptBuilder.build(
          requestId: attemptRequestId,
          persona: persona,
          messages: messages,
          memory: memoryContext,
        );
        if (memoryInstruction != null) {
          request = request.copyWith(
            systemPrompt:
                '${request.systemPrompt}\n【本次本地记忆操作结果】\n$memoryInstruction',
          );
        }
        if (targetMessage != null) {
          request = request.copyWith(
            messages: [
              ...request.messages,
              const AiGenerationMessage(
                role: AiMessageRole.user,
                content:
                    '请从上一条角色回复的末尾自然续写，只输出新增内容，不重复已有文字，'
                    '不要重新回答或总结，也不要解释续写操作。',
              ),
            ],
          );
        }
        final pipeline = _promptPipeline;
        if (pipeline != null) {
          try {
            final result = await pipeline.apply(
              request,
              PluginPromptContext(
                operation: targetMessage == null
                    ? PluginPromptOperation.chatReply
                    : PluginPromptOperation.chatContinue,
                chatSessionId: sessionId,
                safeMetadata: {
                  'messageCount': messages.length,
                  'isContinuation': targetMessage != null,
                  'personaId': personaId,
                },
              ),
            );
            request = result.request;
            pluginNotice = result.userNotice;
          } catch (_) {
            pluginNotice = '插件运行异常，本次已使用默认创作流程。';
          }
        }
        request = request.copyWith(
          providerConfigId: selected?.providerConfigId,
          model: selected?.model,
          reasoning: reasoning,
        );
        final diagnostics = AiStreamDiagnostics(
          generationTraceId: attemptRequestId,
          sessionId: sessionId,
          requestType: attemptRequestType,
          provider: selected?.providerConfigId ?? 'default',
          model: selected?.model ?? 'default',
          requestedOutputLimit: request.maxTokens,
          effectiveOutputLimit: request.maxTokens,
          autoRecoveryAttemptCount: automaticRecoveryAttempts,
        );
        if (targetMessage != null) {
          diagnostics.recordContinueContext(
            previousAssistantCharacterCount: targetMessage.content.length,
            previousAssistantStatus:
                targetMessage.finishReason?.name ?? 'unknown',
          );
        }

        final draft = StringBuffer();
        var finishReason = AiFinishReason.unknown;
        var lastYield = DateTime.fromMillisecondsSinceEpoch(0);
        try {
          final events =
              _usageTracker?.stream(
                sessionId: sessionId,
                operation: attemptRequestType,
                runtime: _runtime,
                request: request,
                cancellation: cancellation,
              ) ??
              runtimeStreamEvents(
                _runtime,
                request,
                cancellation: cancellation,
              );
          await for (final event in events) {
            diagnostics.record(event);
            if (!_coordinator.isCurrent(channel, requestId)) {
              throw const AiProviderCancelledException();
            }
            if (event.isTerminal) {
              finishReason = event.finishReason ?? AiFinishReason.unknown;
              continue;
            }
            draft.write(event.content);
            final now = DateTime.now();
            if (now.difference(lastYield) >= const Duration(milliseconds: 32)) {
              lastYield = now;
              final visibleDraft = targetMessage == null
                  ? draft.toString()
                  : stitchChatContinuation(
                      targetMessage.content,
                      draft.toString(),
                      separateWords:
                          continueMessageId != null &&
                          automaticRecoveryAttempts == 0,
                    );
              yield AiDraftUpdate(
                requestId: requestId,
                draft: visibleDraft,
                status: automaticRecoveryAttempts == 0
                    ? AiDraftStatus.streaming
                    : AiDraftStatus.autoRecovering,
                pluginNotice: pluginNotice,
              );
            }
          }
          if (!_coordinator.isCurrent(channel, requestId)) {
            throw const AiProviderCancelledException();
          }
          if (finishReason == AiFinishReason.interrupted) {
            throw const AiProviderInterruptedException();
          }
          if (regenerationTarget != null &&
              finishReason != AiFinishReason.stop &&
              finishReason != AiFinishReason.length) {
            throw const AiProviderInterruptedException();
          }
          final generated = draft.toString();
          if (generated.trim().isEmpty) {
            throw AiProviderInvalidResponseException.empty(
              emptyKind: generated.isEmpty
                  ? finishReason == AiFinishReason.contentFiltered
                        ? AiEmptyResponseKind.filteredEmpty
                        : AiEmptyResponseKind.providerEmpty
                  : AiEmptyResponseKind.whitespaceOnly,
              responseDiagnostics: AiProviderResponseDiagnostics(
                normalizedFinishReason: finishReason.name,
                rawReceivedChars: generated.length,
                normalizedChars: generated.length,
                finalResultChars: 0,
                streamEventCount: diagnostics.streamEventCount,
                streamClosedNormally: finishReason != AiFinishReason.unknown,
                abnormalEof: finishReason == AiFinishReason.unknown,
              ),
            );
          }
          await _validateSession(sessionId, personaId, userMessageId);
          final content = targetMessage == null
              ? generated
              : stitchChatContinuation(
                  targetMessage.content,
                  generated,
                  separateWords:
                      continueMessageId != null &&
                      automaticRecoveryAttempts == 0,
                );
          final assistant = await _saveAssistant(
            target: targetMessage ?? regenerationTarget,
            expectedLatest: targetMessage ?? regenerationTarget ?? initialUser,
            personaId: personaId,
            sessionId: sessionId,
            assistantMessageId: assistantMessageId,
            content: content,
            finishReason: finishReason,
            nowUtc: nowUtc,
          );
          final persisted = await _chats.getMessage(assistant.id);
          final readback = await _chats.getMessage(assistant.id);
          diagnostics.complete(
            adapterOutput: generated,
            authoritativeBuffer: content,
            messageContent: assistant.content,
            persistedContent: persisted.content,
            readbackContent: readback.content,
            finishReason: finishReason,
            generationStatus: _generationStatus(finishReason),
            streamEndType: 'terminal-signal',
          );
          final memoryService = _memoryService;
          if (memoryService != null) {
            try {
              await memoryService.recordUsage(
                sessionId,
                assistant.id,
                memoryContext,
              );
            } catch (_) {
              // Recording provenance must not turn a saved reply into a failure.
            }
            unawaited(memoryService.organize(sessionId));
          }
          yield AiDraftUpdate(
            requestId: requestId,
            draft: content,
            status: _draftStatus(finishReason),
            savedMessage: assistant,
            finishReason: finishReason,
            pluginNotice: pluginNotice,
          );
          return;
        } on AiProviderInterruptedBeforeContentException catch (error) {
          diagnostics.complete(
            adapterOutput: '',
            authoritativeBuffer: targetMessage?.content ?? '',
            messageContent: targetMessage?.content ?? '',
            persistedContent: targetMessage?.content ?? '',
            readbackContent: targetMessage?.content ?? '',
            finishReason: AiFinishReason.interrupted,
            generationStatus: 'transportInterruptedBeforeContent',
            streamEndType: error.causeType,
            timeoutType: error.timeoutType,
            exceptionType: error.causeType,
          );
          if (beforeContentRetryAttempts < 1 &&
              _coordinator.isCurrent(channel, requestId)) {
            beforeContentRetryAttempts += 1;
            attemptRequestType = targetMessage == null
                ? 'chat-reply-retry'
                : 'continue-retry';
            yield AiDraftUpdate(
              requestId: requestId,
              draft: targetMessage?.content ?? '',
              status: AiDraftStatus.autoRecovering,
              savedMessage: targetMessage,
              finishReason: AiFinishReason.interrupted,
            );
            continue;
          }
          if (targetMessage != null && automaticRecoveryAttempts > 0) {
            yield AiDraftUpdate(
              requestId: requestId,
              draft: targetMessage.content,
              status: AiDraftStatus.interrupted,
              savedMessage: targetMessage,
              finishReason: AiFinishReason.interrupted,
            );
            return;
          }
          rethrow;
        } on AiProviderInterruptedException catch (error) {
          if (regenerationTarget != null && targetMessage == null) {
            yield AiDraftUpdate(
              requestId: requestId,
              draft: '',
              status: AiDraftStatus.interrupted,
              finishReason: AiFinishReason.interrupted,
            );
            return;
          }
          final partial = draft.toString();
          if (partial.isEmpty || !_coordinator.isCurrent(channel, requestId)) {
            rethrow;
          }
          final content = targetMessage == null
              ? partial
              : stitchChatContinuation(
                  targetMessage.content,
                  partial,
                  separateWords:
                      continueMessageId != null &&
                      automaticRecoveryAttempts == 0,
                );
          final saved = await _saveAssistant(
            target: targetMessage,
            expectedLatest: targetMessage ?? initialUser,
            personaId: personaId,
            sessionId: sessionId,
            assistantMessageId: assistantMessageId,
            content: content,
            finishReason: AiFinishReason.interrupted,
            nowUtc: nowUtc,
          );
          final persisted = await _chats.getMessage(saved.id);
          final readback = await _chats.getMessage(saved.id);
          diagnostics.complete(
            adapterOutput: partial,
            authoritativeBuffer: content,
            messageContent: saved.content,
            persistedContent: persisted.content,
            readbackContent: readback.content,
            finishReason: AiFinishReason.interrupted,
            generationStatus: 'interrupted',
            streamEndType: error.causeType == 'abnormal-eof'
                ? 'abnormal-eof'
                : 'transport-interrupted',
            timeoutType: error.timeoutType,
            exceptionType: error.causeType,
          );
          if (automaticRecoveryAttempts < maxAutomaticRecoveryAttempts) {
            automaticRecoveryAttempts += 1;
            targetMessage = saved;
            attemptRequestType = 'automatic-continue';
            yield AiDraftUpdate(
              requestId: requestId,
              draft: saved.content,
              status: AiDraftStatus.autoRecovering,
              savedMessage: saved,
              finishReason: AiFinishReason.interrupted,
            );
            continue;
          }
          yield AiDraftUpdate(
            requestId: requestId,
            draft: saved.content,
            status: AiDraftStatus.interrupted,
            savedMessage: saved,
            finishReason: AiFinishReason.interrupted,
          );
          return;
        } on AiProviderCancelledException {
          final retained = automaticRecoveryAttempts > 0 ? targetMessage : null;
          final persisted = retained == null
              ? null
              : await _chats.getMessage(retained.id);
          final readback = retained == null
              ? null
              : await _chats.getMessage(retained.id);
          diagnostics.complete(
            adapterOutput: draft.toString(),
            authoritativeBuffer: retained?.content ?? draft.toString(),
            messageContent: retained?.content ?? '',
            persistedContent: persisted?.content ?? '',
            readbackContent: readback?.content ?? '',
            finishReason: AiFinishReason.cancelled,
            generationStatus: 'cancelled',
            streamEndType: 'cancelled',
            cancelReason: 'user-or-lifecycle',
          );
          yield AiDraftUpdate(
            requestId: requestId,
            draft: retained?.content ?? draft.toString(),
            status: AiDraftStatus.cancelled,
            savedMessage: retained,
            finishReason: AiFinishReason.cancelled,
          );
          return;
        } on AiProviderException catch (error) {
          if (targetMessage == null || automaticRecoveryAttempts == 0) {
            rethrow;
          }
          final persisted = await _chats.getMessage(targetMessage.id);
          final readback = await _chats.getMessage(targetMessage.id);
          diagnostics.complete(
            adapterOutput: draft.toString(),
            authoritativeBuffer: targetMessage.content,
            messageContent: targetMessage.content,
            persistedContent: persisted.content,
            readbackContent: readback.content,
            finishReason: AiFinishReason.interrupted,
            generationStatus: 'interrupted',
            streamEndType: 'provider-error-during-auto-recovery',
            exceptionType: error.runtimeType.toString(),
          );
          yield AiDraftUpdate(
            requestId: requestId,
            draft: targetMessage.content,
            status: AiDraftStatus.interrupted,
            savedMessage: targetMessage,
            finishReason: AiFinishReason.interrupted,
          );
          return;
        }
      }
    } finally {
      _coordinator.finish(channel, requestId);
    }
  }

  ChatMessage? _latestAssistantTarget(
    List<ChatMessage> messages,
    String? continueMessageId,
    String userMessageId,
  ) {
    if (continueMessageId == null) return null;
    final message = messages
        .where(
          (item) =>
              item.id == continueMessageId &&
              item.role == ChatMessageRole.assistant,
        )
        .firstOrNull;
    if (message == null) {
      throw const DataConflictException('需要继续的回复不存在。');
    }
    final index = messages.indexWhere((m) => m.id == message.id);
    final user = messages
        .take(index)
        .where((m) => m.role == ChatMessageRole.user)
        .lastOrNull;
    if (messages.last.id != message.id || user?.id != userMessageId) {
      throw const DataConflictException('只能对最后一条 AI 回复操作。');
    }
    return message;
  }

  void _requireUserMessage(List<ChatMessage> messages, String id) {
    if (!messages.any(
      (item) => item.id == id && item.role == ChatMessageRole.user,
    )) {
      throw const DataConflictException('用户消息不存在。');
    }
  }

  Future<void> _validateSession(
    String sessionId,
    String personaId,
    String userMessageId,
  ) async {
    final current = await _chats.getSession(sessionId);
    if (current.deletedAt != null || current.personaId != personaId) {
      throw const DataConflictException('会话角色已经变化，旧回复已丢弃。');
    }
    _requireUserMessage(await _chats.listMessages(sessionId), userMessageId);
  }

  Future<ChatMessage> _saveAssistant({
    required ChatMessage? target,
    required ChatMessage expectedLatest,
    required String personaId,
    required String sessionId,
    required String assistantMessageId,
    required String content,
    required AiFinishReason finishReason,
    required DateTime nowUtc,
  }) async {
    final replacement = target == null
        ? ChatMessage(
            metadata: EntityMetadata(
              id: assistantMessageId,
              createdAt: nowUtc.toUtc(),
              updatedAt: nowUtc.toUtc(),
              revision: 1,
            ),
            sessionId: sessionId,
            projectId: null,
            role: ChatMessageRole.assistant,
            content: content,
            finishReason: finishReason,
          )
        : target.copyWith(content: content, finishReason: finishReason);
    return _chats.mutateLatestMessage(
      expected: expectedLatest,
      replacement: replacement,
      append: target == null,
      expectedPersonaId: personaId,
      nowUtc: DateTime.now().toUtc(),
    );
  }

  AiDraftStatus _draftStatus(AiFinishReason reason) => switch (reason) {
    AiFinishReason.stop => AiDraftStatus.completed,
    AiFinishReason.length => AiDraftStatus.limited,
    AiFinishReason.interrupted => AiDraftStatus.interrupted,
    AiFinishReason.cancelled => AiDraftStatus.cancelled,
    AiFinishReason.contentFiltered => AiDraftStatus.contentFiltered,
    AiFinishReason.providerError ||
    AiFinishReason.unknown => AiDraftStatus.providerError,
  };

  String _generationStatus(AiFinishReason reason) => switch (reason) {
    AiFinishReason.stop => 'completed',
    AiFinishReason.length => 'lengthLimited',
    AiFinishReason.interrupted => 'interrupted',
    AiFinishReason.cancelled => 'cancelled',
    AiFinishReason.contentFiltered => 'contentFiltered',
    AiFinishReason.providerError || AiFinishReason.unknown => 'providerError',
  };

  bool cancel(String requestId) {
    return _coordinator.cancel(channel, requestId: requestId);
  }
}
