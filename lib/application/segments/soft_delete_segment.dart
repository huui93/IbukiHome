import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/segment_repository.dart';
import '../../domain/segments/segment.dart';
import '../memory/novel_memory_invalidator.dart';

class SoftDeleteSegment {
  const SoftDeleteSegment(
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
    required DateTime deletedAt,
  }) async {
    final project = await _projects.getProject(projectId);
    if (project.deletedAt != null) {
      throw const DataConflictException('项目已删除，不能删除正文段落。');
    }
    final current = await _segments.getSegment(segmentId);
    final deleted = await _segments.softDeleteAndReorder(
      projectId: projectId,
      segmentId: segmentId,
      deletedAt: deletedAt,
    );
    await _memoryInvalidator?.invalidateStructureFromOrder(
      projectId: projectId,
      fromOrder: current.orderIndex,
      nowUtc: deletedAt,
    );
    _onCommitted?.call(deleted);
    return deleted;
  }
}
