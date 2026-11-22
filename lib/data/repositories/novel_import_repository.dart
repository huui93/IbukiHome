import '../../domain/projects/project.dart';
import '../../domain/segments/segment.dart';

/// Inserts a new novel and all its text atomically, without replacing data.
abstract interface class NovelImportRepository {
  Future<void> insertNovel(Project project, List<Segment> segments);
}
