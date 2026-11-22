import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/segment_repository.dart';
import '../../domain/segments/segment.dart';
import '../memory/novel_memory_invalidator.dart';

class ReorderSegments {
  const ReorderSegments(
    this._projects,
    this._segments, [
    this._memoryInvalidator,
  ]);

  final ProjectRepository _projects;
  final SegmentRepository _segments;
  final NovelMemoryInvalidator? _memoryInvalidator;

  Future<List<Segment>> call({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  }) async {
    final project = await _projects.getProject(projectId);
    if (project.deletedAt != null) {
      throw const DataConflictException('项目已删除，不能调整正文顺序。');
    }
    final before = await _segments.listSegments(projectId);
    await _segments.reorderSegments(
      projectId: projectId,
      orderedIds: orderedIds,
      updatedAt: updatedAt,
    );
    var changedFrom = orderedIds.length;
    for (var index = 0; index < orderedIds.length; index += 1) {
      if (index >= before.length || before[index].id != orderedIds[index]) {
        changedFrom = index;
        break;
      }
    }
    if (changedFrom < orderedIds.length) {
      await _memoryInvalidator?.invalidateStructureFromOrder(
        projectId: projectId,
        fromOrder: changedFrom,
        nowUtc: updatedAt,
      );
    }
    return _segments.listSegments(projectId);
  }
}
