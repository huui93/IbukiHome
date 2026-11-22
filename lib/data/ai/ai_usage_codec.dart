import '../../domain/ai/ai_token_usage.dart';

int? _tokens(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toInt() : null;

AiTokenUsage? openAiUsage(Object? value) {
  if (value is! Map) return null;
  final input = _tokens(value['prompt_tokens']);
  final output = _tokens(value['completion_tokens']);
  final promptDetails = value['prompt_tokens_details'];
  final outputDetails = value['completion_tokens_details'];
  if (input == null && output == null) return null;
  return AiTokenUsage(
    inputTokens: input,
    outputTokens: output,
    totalTokens:
        _tokens(value['total_tokens']) ??
        (input != null && output != null ? input + output : null),
    cachedInputTokens: _tokens(
      promptDetails is Map
          ? promptDetails['cached_tokens']
          : value['prompt_cache_hit_tokens'],
    ),
    cacheWriteTokens: _tokens(
      promptDetails is Map ? promptDetails['cache_write_tokens'] : null,
    ),
    reasoningTokens: _tokens(
      outputDetails is Map ? outputDetails['reasoning_tokens'] : null,
    ),
    isFinal: input != null && output != null,
  );
}

AiTokenUsage? claudeUsage(Map value, {required bool isFinal}) {
  final base = _tokens(value['input_tokens']);
  final output = _tokens(value['output_tokens']);
  if (base == null && output == null) return null;
  final cached = _tokens(value['cache_read_input_tokens']);
  final written = _tokens(value['cache_creation_input_tokens']);
  final input = base == null ? null : base + (cached ?? 0) + (written ?? 0);
  return AiTokenUsage(
    inputTokens: input,
    outputTokens: output,
    totalTokens: input != null && output != null ? input + output : null,
    cachedInputTokens: cached,
    cacheWriteTokens: written,
    isFinal: isFinal,
  );
}

AiTokenUsage? geminiUsage(Object? value, {required bool isFinal}) {
  if (value is! Map) return null;
  final input = _tokens(value['promptTokenCount']);
  final visible = _tokens(value['candidatesTokenCount']);
  final thinking = _tokens(value['thoughtsTokenCount']);
  final total = _tokens(value['totalTokenCount']);
  final output = visible == null
      ? (total != null && input != null && total >= input
            ? total - input
            : null)
      : visible + (thinking ?? 0);
  if (input == null && output == null) return null;
  return AiTokenUsage(
    inputTokens: input,
    outputTokens: output,
    totalTokens: total,
    cachedInputTokens: _tokens(value['cachedContentTokenCount']),
    reasoningTokens: thinking,
    isFinal: isFinal,
  );
}
