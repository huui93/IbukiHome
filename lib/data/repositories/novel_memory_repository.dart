import '../../domain/memory/novel_summary_chunk.dart';
import '../../domain/memory/story_memory_digest.dart';

abstract class NovelMemoryRepository {
  Future<List<NovelSummaryChunk>> listChunks(String projectId);

  Future<NovelSummaryChunk?> getChunk(String id);

  Future<void> upsertChunk(NovelSummaryChunk chunk);

  Future<void> deleteChunksFromOrder(String projectId, int fromOrder);

  Future<StoryMemoryDigest?> getDigest(String projectId);

  Future<void> upsertDigest(StoryMemoryDigest digest);
}
