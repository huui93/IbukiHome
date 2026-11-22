import 'package:sqflite/sqflite.dart';

import '../../core/errors/data_exceptions.dart';
import '../../domain/projects/project.dart';
import '../repositories/project_repository.dart';
import 'ibuki_database.dart';
import 'sqlite_repository_helpers.dart';
import 'sqlite_value_codec.dart';

class SQLiteProjectRepository implements ProjectRepository {
  SQLiteProjectRepository(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;

  @override
  Future<List<Project>> listProjects({bool includeDeleted = false}) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'projects',
      where: includeDeleted ? null : 'deleted_at IS NULL',
      orderBy: 'updated_at DESC, title ASC, id ASC',
    );
    return List.unmodifiable(rows.map(projectFromSql));
  }

  @override
  Future<Project> getProject(String id) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'projects',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EntityNotFoundException('Project', id);
    }
    return projectFromSql(rows.single);
  }

  @override
  Future<void> upsertProject(Project project) async {
    final database = await ibukiDatabase.database;
    await handleSqliteWrite(
      () async {
        final values = projectToSql(project);
        await database.transaction((transaction) async {
          final updated = await transaction.update(
            'projects',
            values,
            where: 'id = ?',
            whereArgs: [project.id],
          );
          if (updated == 0) {
            await transaction.insert(
              'projects',
              values,
              conflictAlgorithm: ConflictAlgorithm.abort,
            );
          }
        });
      },
      entityName: 'Project',
      entityId: project.id,
    );
  }

  @override
  Future<void> softDeleteProject(String id, DateTime deletedAt) async {
    await _updateProjectMetadata(
      id,
      deletedAt.toUtc(),
      deletedAt: deletedAt.toUtc(),
    );
  }

  @override
  Future<void> restoreProject(String id, DateTime updatedAt) async {
    await _updateProjectMetadata(id, updatedAt.toUtc(), deletedAt: null);
  }

  Future<void> _updateProjectMetadata(
    String id,
    DateTime updatedAt, {
    required DateTime? deletedAt,
  }) async {
    final project = await getProject(id);
    final updated = project.copyWith(
      metadata: project.metadata.copyWith(
        updatedAt: updatedAt,
        revision: project.revision + 1,
        deletedAt: deletedAt,
      ),
    );
    await upsertProject(updated);
  }
}
