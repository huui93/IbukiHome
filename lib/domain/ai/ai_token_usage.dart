class AiTokenUsage {
  const AiTokenUsage({
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.cachedInputTokens,
    this.cacheWriteTokens,
    this.reasoningTokens,
    this.isFinal = false,
  });
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final int? cachedInputTokens;
  final int? cacheWriteTokens;
  final int? reasoningTokens;
  final bool isFinal;
  bool get isComplete => isFinal && inputTokens != null && outputTokens != null;

  AiTokenUsage merge(AiTokenUsage newer) => AiTokenUsage(
    inputTokens: newer.inputTokens ?? inputTokens,
    outputTokens: newer.outputTokens ?? outputTokens,
    totalTokens: newer.totalTokens ?? totalTokens,
    cachedInputTokens: newer.cachedInputTokens ?? cachedInputTokens,
    cacheWriteTokens: newer.cacheWriteTokens ?? cacheWriteTokens,
    reasoningTokens: newer.reasoningTokens ?? reasoningTokens,
    isFinal: isFinal || newer.isFinal,
  );
}
