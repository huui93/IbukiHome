import '../../domain/ai/ai_reasoning_level.dart';
import 'ai_reasoning_parameters.dart';

/// Provider-specific parameters shared by the application and Tavern transports.
Map<String, Object?> chatCompletionParameters({
  required String provider,
  required String model,
  double? temperature,
  int? maxTokens,
  bool structuredJson = false,
  AiReasoningLevel reasoning = AiReasoningLevel.automatic,
  bool preferCompletionTokens = false,
}) {
  final id = model.toLowerCase();
  final reasoningOpenAi =
      provider == 'openai' &&
      RegExp(r'^(o[1-9](?:-|$)|gpt-(?:[5-9]|[1-9][0-9]))').hasMatch(id);
  final fixedKimi =
      provider == 'kimi' &&
      (id.startsWith('kimi-k2.') ||
          id.startsWith('kimi-k3') ||
          id.contains('thinking'));
  return {
    if (temperature != null && !reasoningOpenAi && !fixedKimi)
      'temperature': provider == 'glm' ? temperature.clamp(0, 1) : temperature,
    (reasoningOpenAi || provider == 'grok' || preferCompletionTokens
            ? 'max_completion_tokens'
            : 'max_tokens'):
        ?maxTokens,
    // Hybrid models otherwise default to reasoning, and some reject non-streaming calls.
    if (provider == 'qwen' &&
        reasoningLevels(provider, model).contains(AiReasoningLevel.disabled))
      'enable_thinking': false,
    if (provider == 'kimi' &&
        (id.startsWith('kimi-k2.5') || id.startsWith('kimi-k2.6')))
      'thinking': const {'type': 'disabled'},
    if (provider == 'glm' &&
        reasoningLevels(provider, model).contains(AiReasoningLevel.disabled))
      'thinking': const {'type': 'disabled'},
    if (provider == 'deepseek' &&
        (id.startsWith('deepseek-v4') || id == 'deepseek-flash'))
      'thinking': const {'type': 'disabled'},
    ...reasoningParameters(
      provider: provider,
      model: model,
      level: reasoning,
      maxTokens: maxTokens,
    ),
    if (structuredJson) 'response_format': const {'type': 'json_object'},
  };
}
