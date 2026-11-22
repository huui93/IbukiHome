import '../../data/repositories/novel_memory_repository.dart';
import '../../domain/memory/memory_generation_status.dart';
import 'long_context_policy.dart';

class NovelMemoryInvalidator {
  const NovelMemoryInvalidator(this._repository);

  final NovelMemoryRepository _repository;

  Future<void> invalidateFromOrder({
    required String projectId,
    required int fromOrder,
    required DateTime nowUtc,
  }) async {
    final at = nowUtc.toUtc();
    final chunks = await _repository.listChunks(projectId);
    for (final chunk in chunks.where(
      (item) => item.sourceEndOrder >= fromOrder,
    )) {
      if (chunk.status == MemoryGenerationStatus.stale) continue;
      await _repository.upsertChunk(
        chunk.copyWith(
          metadata: chunk.metadata.copyWith(
            updatedAt: at,
            revision: chunk.revision + 1,
          ),
          status: MemoryGenerationStatus.stale,
        ),
      );
    }
    await _markDigestStale(projectId, at);
  }

  Future<void> invalidateStructureFromOrder({
    required String projectId,
    required int fromOrder,
    required DateTime nowUtc,
  }) async {
    final chunkStart =
        (fromOrder.clamp(0, 1 << 30) ~/ NovelMemoryPolicy.chunkSegmentCount) *
        NovelMemoryPolicy.chunkSegmentCount;
    await _repository.deleteChunksFromOrder(projectId, chunkStart);
    await _markDigestStale(projectId, nowUtc.toUtc());
  }

  Future<void> _markDigestStale(String projectId, DateTime at) async {
    final digest = await _repository.getDigest(projectId);
    if (digest == null || digest.status == MemoryGenerationStatus.stale) return;
    await _repository.upsertDigest(
      digest.copyWith(
        metadata: digest.metadata.copyWith(
          updatedAt: at,
          revision: digest.revision + 1,
        ),
        status: MemoryGenerationStatus.stale,
      ),
    );
  }
}
