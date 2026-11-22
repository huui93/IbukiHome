import 'dart:convert';
import '../../core/network/ai_provider_exceptions.dart';
import '../../data/ai/ai_provider_client.dart';
import '../../data/repositories/chat_controls_repository.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/ai/ai_token_usage.dart';
import '../../domain/chat/chat_usage_record.dart';
import '../ai/ai_generation_service.dart';

int estimateAiTextTokens(String text) => (utf8.encode(text).length / 3).ceil();

class ChatUsageTracker {
  ChatUsageTracker(this.repository, {this.onChanged});
  final ChatControlsRepository repository;
  final void Function(String sessionId)? onChanged;
  final failedSessions = <String>{};

  Stream<AiStreamEvent> stream({
    required String sessionId,
    required String operation,
    required AiGenerationRuntime runtime,
    required AiGenerationRequest request,
    AiRequestCancellation? cancellation,
  }) async* {
    final pending = _PendingUsage(sessionId, operation, request);
    try {
      await for (final event in runtimeStreamEvents(
        runtime,
        pending.observedRequest,
        cancellation: cancellation,
      )) {
        pending.output.write(event.content);
        if (event.isTerminal) {
          pending.status = event.finishReason?.name ?? 'unknown';
        }
        yield event;
      }
    } catch (error) {
      pending.status = error is AiProviderCancelledException
          ? 'cancelled'
          : 'failed';
      rethrow;
    } finally {
      await _save(pending);
    }
  }

  Future<String> generate({
    required String sessionId,
    required String operation,
    required AiGenerationRuntime runtime,
    required AiGenerationRequest request,
  }) async {
    final pending = _PendingUsage(sessionId, operation, request);
    try {
      final output = await runtime.generate(pending.observedRequest);
      pending.output.write(output);
      pending.status = 'stop';
      return output;
    } catch (_) {
      pending.status = 'failed';
      rethrow;
    } finally {
      await _save(pending);
    }
  }

  Future<void> _save(_PendingUsage pending) async {
    if (!pending.started && pending.output.isEmpty && pending.usage == null) {
      return;
    }
    final request = pending.request;
    final inputEstimate =
        estimateAiTextTokens(request.systemPrompt) +
        4 +
        request.messages.fold<int>(
          0,
          (sum, m) => sum + estimateAiTextTokens(m.content) + 4,
        );
    try {
      await repository.recordUsage(
        ChatUsageRecord(
          id: request.requestId,
          sessionId: pending.sessionId,
          operation: pending.operation,
          providerId: pending.providerId,
          model: pending.model,
          status: pending.status,
          startedAt: pending.startedAt,
          endedAt: DateTime.now().toUtc(),
          estimatedInputTokens: inputEstimate,
          estimatedOutputTokens: estimateAiTextTokens(
            pending.output.toString(),
          ),
          usage: pending.usage,
        ),
      );
    } catch (_) {
      failedSessions.add(pending.sessionId);
    }
    onChanged?.call(pending.sessionId);
  }
}

class _PendingUsage {
  _PendingUsage(this.sessionId, this.operation, this.request)
    : providerId = request.providerConfigId ?? '',
      model = request.model ?? '';
  final String sessionId;
  final String operation;
  final AiGenerationRequest request;
  final startedAt = DateTime.now().toUtc();
  final output = StringBuffer();
  String providerId;
  String model;
  String status = 'unknown';
  bool started = false;
  AiTokenUsage? usage;
  AiGenerationRequest get observedRequest => request.copyWith(
    onUsage: (value) {
      usage = usage?.merge(value) ?? value;
      request.reportUsage(value);
    },
    onTransportStarted: (provider, selectedModel) {
      started = true;
      providerId = provider;
      model = selectedModel;
      request.reportTransportStarted(provider, selectedModel);
    },
  );
}
