import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/segment_repository.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/segments/segment.dart';
import '../../domain/segments/segment_revision.dart';
import '../memory/novel_memory_invalidator.dart';

class RestoreSegmentRevision {
  const RestoreSegmentRevision(
    this._projects,
    this._segments, [
    this._memoryInvalidator,
  ]);

  final ProjectRepository _projects;
  final SegmentRepository _segments;
  final NovelMemoryInvalidator? _memoryInvalidator;

  Future<Segment> call({
    required String projectId,
    required String segmentId,
    required String segmentRevisionId,
    required String newRevisionId,
    required DateTime nowUtc,
  }) async {
    final project = await _projects.getProject(projectId);
    if (project.deletedAt != null) {
      throw const DataConflictException('项目已删除，不能恢复正文历史。');
    }
    final current = await _segments.getSegment(segmentId);
    if (current.projectId != projectId) {
      throw const DataConflictException('段落不属于当前项目。');
    }
    if (current.deletedAt != null) {
      throw const DataConflictException('已删除段落不能恢复正文历史。');
    }
    final target = await _segments.getRevision(segmentRevisionId);
    if (target.projectId != projectId || target.segmentId != segmentId) {
      throw const DataConflictException('历史版本与当前段落不匹配。');
    }
    if (target.deletedAt != null) {
      throw const DataConflictException('历史版本已不可用。');
    }
    if (target.content == current.content) {
      return current;
    }

    final now = nowUtc.toUtc();
    final rollbackRevision = SegmentRevision(
      metadata: EntityMetadata(
        id: newRevisionId,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      ),
      projectId: projectId,
      segmentId: segmentId,
      revisionNumber: current.revision,
      content: current.content,
      note: '恢复到历史版本 ${target.revisionNumber} 前自动保存',
      userInstruction: '',
      mode: 'mobile_restore',
    );
    final restored = current.copyWith(
      metadata: current.metadata.copyWith(
        updatedAt: now,
        revision: current.revision + 1,
      ),
      content: target.content,
    );
    await _segments.saveSegmentWithRevision(
      updatedSegment: restored,
      revision: rollbackRevision,
    );
    await _memoryInvalidator?.invalidateFromOrder(
      projectId: projectId,
      fromOrder: current.orderIndex,
      nowUtc: now,
    );
    return restored;
  }
}
