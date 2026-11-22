import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/segment_repository.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/segments/segment.dart';

class CreateSegment {
  const CreateSegment(this._projects, this._segments, [this._onCommitted]);

  final ProjectRepository _projects;
  final SegmentRepository _segments;
  final void Function(Segment)? _onCommitted;

  Future<Segment> call({
    required String projectId,
    required String content,
    required String id,
    required DateTime nowUtc,
    bool notify = true,
  }) async {
    final project = await _projects.getProject(projectId);
    if (project.deletedAt != null) {
      throw DataConflictException('项目已删除，不能继续新增正文段落。');
    }

    final existing = await _segments.listSegments(projectId);
    final nextOrderIndex = existing.length;
    final now = nowUtc.toUtc();
    final segment = Segment(
      metadata: EntityMetadata(
        id: id,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      ),
      projectId: projectId,
      orderIndex: nextOrderIndex,
      content: content,
    );

    await _segments.upsertSegment(segment);
    if (notify) _onCommitted?.call(segment);
    return segment;
  }
}
