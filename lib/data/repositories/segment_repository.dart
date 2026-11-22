import '../../domain/segments/segment.dart';
import '../../domain/segments/segment_revision.dart';

enum SegmentInsertPosition { before, after }

abstract class SegmentRepository {
  Future<List<Segment>> listSegments(
    String projectId, {
    bool includeDeleted = false,
  });

  Future<Segment> getSegment(String id);

  Future<void> upsertSegment(Segment segment);

  Future<void> softDeleteSegment(String id, DateTime deletedAt);

  Future<void> restoreSegment(String id, DateTime updatedAt);

  Future<List<SegmentRevision>> listRevisions(String segmentId);

  Future<SegmentRevision> getRevision(String id);

  Future<void> appendRevision(SegmentRevision revision);

  /// Inserts [segment] next to an active anchor and normalizes active ordering.
  Future<Segment> insertSegmentAt({
    required Segment segment,
    required String anchorSegmentId,
    required SegmentInsertPosition position,
  });

  /// Reorders every active segment in a project as one atomic operation.
  Future<void> reorderSegments({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  });

  /// Soft-deletes one segment and normalizes remaining active ordering.
  Future<Segment> softDeleteAndReorder({
    required String projectId,
    required String segmentId,
    required DateTime deletedAt,
  });

  /// Restores one segment at its clamped former order and shifts active peers.
  Future<Segment> restoreAndReorder({
    required String projectId,
    required String segmentId,
    required DateTime restoredAt,
  });

  /// Saves a segment content change and its historical snapshot atomically.
  Future<void> saveSegmentWithRevision({
    required Segment updatedSegment,
    required SegmentRevision revision,
  });
}
