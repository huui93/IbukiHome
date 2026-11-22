import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/project_repository.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/projects/project.dart';

class CreateProject {
  const CreateProject(this._projects);

  final ProjectRepository _projects;

  Future<Project> call({
    required String title,
    String description = '',
    required String id,
    required DateTime nowUtc,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw const DataFormatException('项目名称不能为空。');
    }

    final now = nowUtc.toUtc();
    final project = Project(
      metadata: EntityMetadata(
        id: id,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      ),
      title: trimmedTitle,
      description: description.trim(),
    );

    await _projects.upsertProject(project);
    return project;
  }
}
