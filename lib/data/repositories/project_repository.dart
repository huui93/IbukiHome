import '../../domain/projects/project.dart';

abstract class ProjectRepository {
  Future<List<Project>> listProjects({bool includeDeleted = false});

  Future<Project> getProject(String id);

  Future<void> upsertProject(Project project);

  Future<void> softDeleteProject(String id, DateTime deletedAt);

  Future<void> restoreProject(String id, DateTime updatedAt);
}
