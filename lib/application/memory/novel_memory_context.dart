import 'dart:math' as math;

import '../../domain/memory/novel_summary_chunk.dart';
import '../../domain/memory/story_memory_digest.dart';
import 'long_context_policy.dart';

class NovelMemoryContext {
  const NovelMemoryContext({
    this.digest,
    this.recentChunks = const [],
    this.rawSegmentStartOrder,
  });

  final StoryMemoryDigest? digest;
  final List<NovelSummaryChunk> recentChunks;
  final int? rawSegmentStartOrder;

  bool get isEmpty =>
      digest?.content.trim().isNotEmpty != true && recentChunks.isEmpty;
}

int calculateNovelRawStartOrder({
  required int segmentCount,
  required Iterable<NovelSummaryChunk> summarizedChunks,
}) {
  final ordered =
      summarizedChunks
          .where((chunk) => chunk.summary.trim().isNotEmpty)
          .toList(growable: false)
        ..sort(
          (left, right) =>
              left.sourceStartOrder.compareTo(right.sourceStartOrder),
        );
  var coveredEnd = -1;
  for (final chunk in ordered) {
    if (chunk.sourceStartOrder > coveredEnd + 1) break;
    coveredEnd = math.max(coveredEnd, chunk.sourceEndOrder);
  }
  final pendingStart = coveredEnd + 1;
  final boundedStart = math.max(
    0,
    segmentCount - NovelMemoryPolicy.maxRawSegmentCount,
  );
  return math.max(pendingStart, boundedStart).clamp(0, segmentCount);
}
