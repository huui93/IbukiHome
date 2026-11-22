import '../../core/errors/data_exceptions.dart';
import '../../domain/projects/project.dart';
import '../../domain/segments/segment.dart';
import '../repositories/novel_import_repository.dart';
import 'in_memory_ibuki_store.dart';

class InMemoryNovelImportRepository implements NovelImportRepository {
  const InMemoryNovelImportRepository(this.store);
  final InMemoryIbukiStore store;

  @override
  Future<void> insertNovel(Project project, List<Segment> segments) async {
    if (store.hasProject(project.id)) {
      throw DuplicateEntityException('Project', project.id);
    }
    final ids = <String>{};
    for (final segment in segments) {
      if (segment.projectId != project.id ||
          !ids.add(segment.id) ||
          store.hasSegment(segment.id)) {
        throw const DataConflictException('小说导入数据冲突，未写入任何内容。');
      }
    }
    // Validate everything before the synchronous mutation; no partial import.
    store.putProject(project);
    for (final segment in segments) {
      store.putSegment(segment);
    }
  }
}
