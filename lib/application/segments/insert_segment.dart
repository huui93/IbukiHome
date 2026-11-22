import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/segment_repository.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/segments/segment.dart';
import '../memory/novel_memory_invalidator.dart';

class InsertSegment {
  const InsertSegment(
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
    required String anchorSegmentId,
    required SegmentInsertPosition position,
    required String content,
    required String id,
    required DateTime nowUtc,
  }) async {
    final project = await _projects.getProject(projectId);
    if (project.deletedAt != null) {
      throw const DataConflictException('项目已删除，不能插入正文段落。');
    }
    final anchor = await _segments.getSegment(anchorSegmentId);
    if (anchor.projectId != projectId) {
      throw const DataConflictException('插入锚点不属于当前项目。');
    }
    if (anchor.deletedAt != null) {
      throw const DataConflictException('已删除段落不能作为插入锚点。');
    }

    final now = nowUtc.toUtc();
    final segment = Segment(
      metadata: EntityMetadata(
        id: id,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      ),
      projectId: projectId,
      orderIndex: anchor.orderIndex,
      content: content,
    );
    final inserted = await _segments.insertSegmentAt(
      segment: segment,
      anchorSegmentId: anchorSegmentId,
      position: position,
    );
    await _memoryInvalidator?.invalidateStructureFromOrder(
      projectId: projectId,
      fromOrder: inserted.orderIndex,
      nowUtc: now,
    );
    _onCommitted?.call(inserted);
    return inserted;
  }
}
