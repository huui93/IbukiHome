import 'package:sqflite/sqflite.dart';
import '../../core/errors/data_exceptions.dart';
import '../../domain/projects/project.dart';
import '../../domain/segments/segment.dart';
import '../repositories/novel_import_repository.dart';
import 'ibuki_database.dart';
import 'sqlite_repository_helpers.dart';
import 'sqlite_value_codec.dart';

class SQLiteNovelImportRepository implements NovelImportRepository {
  const SQLiteNovelImportRepository(this.database);
  final IbukiDatabase database;

  @override
  Future<void> insertNovel(Project project, List<Segment> segments) async {
    if (segments.any((segment) => segment.projectId != project.id)) {
      throw const DataConflictException('导入正文不属于这部小说。');
    }
    final db = await database.database;
    await handleSqliteWrite(
      () => db.transaction((txn) async {
        final batch = txn.batch();
        batch.insert(
          'projects',
          projectToSql(project),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        for (final segment in segments) {
          batch.insert(
            'segments',
            segmentToSql(segment),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        await batch.commit(noResult: true);
      }),
      entityName: 'Project',
      entityId: project.id,
    );
  }
}
