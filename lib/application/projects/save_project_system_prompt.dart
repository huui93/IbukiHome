import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/project_repository.dart';
import '../../domain/projects/project.dart';

class SaveProjectSystemPrompt {
  const SaveProjectSystemPrompt(this._projects);

  final ProjectRepository _projects;

  Future<Project> call({
    required String projectId,
    required String systemPrompt,
    required DateTime nowUtc,
  }) async {
    final project = await _projects.getProject(projectId);
    if (project.deletedAt != null) {
      throw const DataConflictException(
        'Deleted projects cannot update creation settings.',
      );
    }
    final normalized = systemPrompt.trim();
    if (project.systemPrompt == normalized) return project;
    final updated = project.copyWith(
      metadata: project.metadata.copyWith(
        updatedAt: nowUtc.toUtc(),
        revision: project.revision + 1,
      ),
      systemPrompt: normalized,
    );
    await _projects.upsertProject(updated);
    return updated;
  }
}
