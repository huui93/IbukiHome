import '../../core/errors/data_exceptions.dart';
import '../../domain/projects/novel_output_limits.dart';
import '../repositories/novel_output_limits_repository.dart';
import '../repositories/project_repository.dart';

class InMemoryNovelOutputLimitsRepository
    implements NovelOutputLimitsRepository {
  InMemoryNovelOutputLimitsRepository(this.projects);
  final ProjectRepository projects;
  final _values = <String, NovelOutputLimits>{};
  @override
  Future<NovelOutputLimits> get(String projectId) async {
    if ((await projects.getProject(projectId)).deletedAt != null) {
      throw const DataConflictException('作品已删除。');
    }
    return _values[projectId] ?? NovelOutputLimits(projectId: projectId);
  }

  @override
  Future<NovelOutputLimits> save(
    NovelOutputLimits value, {
    required int expectedRevision,
    required DateTime now,
  }) async {
    value.validate();
    await get(value.projectId);
    final old =
        _values[value.projectId] ??
        NovelOutputLimits(projectId: value.projectId);
    if (old.revision != expectedRevision) {
      throw const DataConflictException('设置已改变，请重新打开后修改。');
    }
    if (old.minimum == value.minimum && old.maximum == value.maximum) {
      return old;
    }
    if (value.isDefault) {
      _values.remove(value.projectId);
      return NovelOutputLimits(projectId: value.projectId);
    }
    final updated = NovelOutputLimits(
      projectId: value.projectId,
      minimum: value.minimum,
      maximum: value.maximum,
      revision: old.revision + 1,
    );
    _values[value.projectId] = updated;
    return updated;
  }
}
