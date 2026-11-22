import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/segment_repository.dart';
import '../../domain/segments/segment.dart';
import '../memory/novel_memory_invalidator.dart';

class RestoreSegment {
  const RestoreSegment(
    this._projects,
    this._segments, [
    this._memoryInvalidator,
    this._onCommitted,
  ]);

  final ProjectRepository _projects;
  final SegmentRepository _segments;
  final void Function(Segment)? _onCommitted;
  final NovelMemoryInvalidator? _memoryInvalidator;

  Future<Segment> call({
    required String projectId,
    required String segmentId,
    required DateTime restoredAt,
  }) async {
    final project = await _projects.getProject(projectId);
    if (project.deletedAt != null) {
      throw const DataConflictException('项目已删除，不能恢复正文段落。');
    }
    final restored = await _segments.restoreAndReorder(
      projectId: projectId,
      segmentId: segmentId,
      restoredAt: restoredAt,
    );
    await _memoryInvalidator?.invalidateStructureFromOrder(
      projectId: projectId,
      fromOrder: restored.orderIndex,
      nowUtc: restoredAt,
    );
    _onCommitted?.call(restored);
    return restored;
  }
}
