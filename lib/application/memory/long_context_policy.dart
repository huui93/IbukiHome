class NovelMemoryPolicy {
  const NovelMemoryPolicy._();

  static const chunkSegmentCount = 20;
  static const recentRawSegmentCount = 10;
  static const recentSummaryChunkCount = 3;
  static const maxRawSegmentCount =
      chunkSegmentCount + recentRawSegmentCount - 1;
}

class ChatMemoryPolicy {
  const ChatMemoryPolicy._();

  static const extractionMessageThreshold = 20;
  static const recentRawMessageCount = 30;
  static const ordinaryMemoryLimit = 8;
}
