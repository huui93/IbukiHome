import '../../domain/memory/novel_summary_chunk.dart';
import '../../domain/memory/story_memory_digest.dart';
import '../repositories/novel_memory_repository.dart';
import 'in_memory_ibuki_store.dart';

class InMemoryNovelMemoryRepository implements NovelMemoryRepository {
  InMemoryNovelMemoryRepository(this.store);

  final InMemoryIbukiStore store;

  @override
  Future<List<NovelSummaryChunk>> listChunks(String projectId) async {
    final items =
        store.novelSummaryChunks
            .where((item) => item.projectId == projectId)
            .toList()
          ..sort((a, b) => a.sourceStartOrder.compareTo(b.sourceStartOrder));
    return List.unmodifiable(items);
  }

  @override
  Future<NovelSummaryChunk?> getChunk(String id) async =>
      store.novelSummaryChunk(id);

  @override
  Future<void> upsertChunk(NovelSummaryChunk chunk) async {
    store.putNovelSummaryChunk(chunk);
  }

  @override
  Future<void> deleteChunksFromOrder(String projectId, int fromOrder) async {
    final ids = store.novelSummaryChunks
        .where(
          (item) =>
              item.projectId == projectId && item.sourceEndOrder >= fromOrder,
        )
        .map((item) => item.id)
        .toList(growable: false);
    for (final id in ids) {
      store.removeNovelSummaryChunk(id);
    }
  }

  @override
  Future<StoryMemoryDigest?> getDigest(String projectId) async =>
      store.storyMemoryDigest(projectId);

  @override
  Future<void> upsertDigest(StoryMemoryDigest digest) async {
    store.putStoryMemoryDigest(digest);
  }
}
