import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/project_repository.dart';
import '../../domain/projects/project.dart';
import 'in_memory_ibuki_store.dart';

class InMemoryProjectRepository implements ProjectRepository {
  InMemoryProjectRepository(this.store);

  final InMemoryIbukiStore store;

  @override
  Future<List<Project>> listProjects({bool includeDeleted = false}) async {
    final items =
        store.projects
            .where((project) => includeDeleted || project.deletedAt == null)
            .toList()
          ..sort((left, right) {
            final time = right.updatedAt.compareTo(left.updatedAt);
            if (time != 0) {
              return time;
            }
            final title = left.title.compareTo(right.title);
            return title != 0 ? title : left.id.compareTo(right.id);
          });
    return List.unmodifiable(items);
  }

  @override
  Future<Project> getProject(String id) async {
    final project = store.project(id);
    if (project == null) {
      throw EntityNotFoundException('Project', id);
    }
    return project;
  }

  @override
  Future<void> upsertProject(Project project) async {
    store.putProject(project);
  }

  @override
  Future<void> softDeleteProject(String id, DateTime deletedAt) async {
    final project = await getProject(id);
    final deletedUtc = deletedAt.toUtc();
    store.putProject(
      project.copyWith(
        metadata: project.metadata.copyWith(
          updatedAt: deletedUtc,
          revision: project.revision + 1,
          deletedAt: deletedUtc,
        ),
      ),
    );
  }

  @override
  Future<void> restoreProject(String id, DateTime updatedAt) async {
    final project = await getProject(id);
    final updatedUtc = updatedAt.toUtc();
    store.putProject(
      project.copyWith(
        metadata: project.metadata.copyWith(
          updatedAt: updatedUtc,
          revision: project.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }
}
