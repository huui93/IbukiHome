import '../../data/repositories/segment_repository.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/segments/segment.dart';
import '../../domain/segments/segment_revision.dart';
import '../memory/novel_memory_invalidator.dart';

class SaveSegment {
  const SaveSegment(
    this._segments, [
    this._memoryInvalidator,
    this._onCommitted,
  ]);

  final SegmentRepository _segments;
  final void Function(Segment)? _onCommitted;
  final NovelMemoryInvalidator? _memoryInvalidator;

  Future<Segment> call({
    required Segment currentSegment,
    required String newContent,
    required DateTime now,
    required String revisionId,
    String note = '',
    String userInstruction = '',
    String mode = '',
    bool notify = true,
  }) async {
    final stored = await _segments.getSegment(currentSegment.id);
    if (stored.content == newContent) {
      return stored;
    }

    final updatedAt = now.toUtc();
    final revision = SegmentRevision(
      metadata: EntityMetadata(
        id: revisionId,
        createdAt: updatedAt,
        updatedAt: updatedAt,
        revision: 1,
      ),
      projectId: stored.projectId,
      segmentId: stored.id,
      revisionNumber: stored.revision,
      content: stored.content,
      note: note,
      userInstruction: userInstruction,
      mode: mode,
    );
    final updated = stored.copyWith(
      metadata: stored.metadata.copyWith(
        updatedAt: updatedAt,
        revision: stored.revision + 1,
      ),
      content: newContent,
    );

    await _segments.saveSegmentWithRevision(
      updatedSegment: updated,
      revision: revision,
    );
    await _memoryInvalidator?.invalidateFromOrder(
      projectId: stored.projectId,
      fromOrder: stored.orderIndex,
      nowUtc: updatedAt,
    );
    if (notify) _onCommitted?.call(updated);
    return updated;
  }
}
