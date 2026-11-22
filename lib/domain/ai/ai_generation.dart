import 'ai_token_usage.dart';
import 'ai_reasoning_level.dart';

enum AiMessageRole { user, assistant, system }

enum AiFinishReason {
  stop,
  length,
  contentFiltered,
  cancelled,
  interrupted,
  providerError,
  unknown;

  bool get isComplete => this == stop;
}

class AiStreamEvent {
  const AiStreamEvent.content(this.content)
    : finishReason = null,
      isTerminal = false;

  const AiStreamEvent.finished(this.finishReason)
    : content = '',
      isTerminal = true;

  final String content;
  final AiFinishReason? finishReason;
  final bool isTerminal;
}

class AiPrompt {
  const AiPrompt({
    required this.systemPrompt,
    required this.userPrompt,
    this.historyChunks = const [],
  });

  final String systemPrompt;
  final String userPrompt;
  final List<String> historyChunks;
  String get withoutHistory {
    var result = userPrompt;
    for (final chunk in historyChunks.toSet()) {
      if (chunk.isNotEmpty) result = result.replaceAll(chunk, '（正文通过结构化历史提供）');
    }
    return result;
  }
}

class AiImageInput {
  const AiImageInput({required this.mimeType, required this.base64Data});
  final String mimeType;
  final String base64Data;
}

class AiGenerationMessage {
  const AiGenerationMessage({
    required this.role,
    required this.content,
    this.images = const [],
  });

  final AiMessageRole role;
  final String content;
  final List<AiImageInput> images;
}

class AiGenerationRequest {
  const AiGenerationRequest({
    required this.requestId,
    required this.systemPrompt,
    required this.messages,
    this.providerConfigId,
    this.model,
    this.temperature,
    this.maxTokens,
    this.structuredJson = false,
    this.reasoning = AiReasoningLevel.automatic,
    this.onUsage,
    this.onTransportStarted,
    this.streamOutput,
    this.sampling = const {},
    this.assistantPrefill,
    this.onAppliedParameters,
    this.onNativeReasoning,
  });

  final String requestId;
  final String systemPrompt;
  final List<AiGenerationMessage> messages;
  final String? providerConfigId;
  final String? model;
  final double? temperature;
  final int? maxTokens;
  final bool structuredJson;
  final AiReasoningLevel reasoning;
  final bool? streamOutput;
  final Map<String, num> sampling;
  final String? assistantPrefill;
  final void Function(Map<String, Object?> values)? onAppliedParameters;
  final void Function(String text)? onNativeReasoning;
  final void Function(AiTokenUsage usage)? onUsage;
  final void Function(String providerId, String model)? onTransportStarted;

  void reportAppliedParameters(Map<String, Object?> values) {
    try {
      onAppliedParameters?.call(Map.unmodifiable(values));
    } catch (_) {
      /* Diagnostics only. */
    }
  }

  void reportNativeReasoning(String text) {
    try {
      onNativeReasoning?.call(text);
    } catch (_) {
      /* Presentation only. */
    }
  }

  void reportUsage(AiTokenUsage usage) {
    try {
      onUsage?.call(usage);
    } catch (_) {
      /* Optional accounting cannot break a reply. */
    }
  }

  void reportTransportStarted(String providerId, String model) {
    try {
      onTransportStarted?.call(providerId, model);
    } catch (_) {
      /* Accounting only. */
    }
  }

  AiGenerationRequest copyWith({
    String? requestId,
    String? systemPrompt,
    String? providerConfigId,
    String? model,
    List<AiGenerationMessage>? messages,
    int? maxTokens,
    AiReasoningLevel? reasoning,
    double? temperature,
    bool? streamOutput,
    Map<String, num>? sampling,
    String? assistantPrefill,
    void Function(Map<String, Object?> values)? onAppliedParameters,
    void Function(String text)? onNativeReasoning,
    void Function(AiTokenUsage usage)? onUsage,
    void Function(String providerId, String model)? onTransportStarted,
  }) {
    return AiGenerationRequest(
      requestId: requestId ?? this.requestId,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      messages: messages ?? this.messages,
      providerConfigId: providerConfigId ?? this.providerConfigId,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      structuredJson: structuredJson,
      reasoning: reasoning ?? this.reasoning,
      streamOutput: streamOutput ?? this.streamOutput,
      sampling: sampling ?? this.sampling,
      assistantPrefill: assistantPrefill ?? this.assistantPrefill,
      onAppliedParameters: onAppliedParameters ?? this.onAppliedParameters,
      onNativeReasoning: onNativeReasoning ?? this.onNativeReasoning,
      onUsage: onUsage ?? this.onUsage,
      onTransportStarted: onTransportStarted ?? this.onTransportStarted,
    );
  }
}
