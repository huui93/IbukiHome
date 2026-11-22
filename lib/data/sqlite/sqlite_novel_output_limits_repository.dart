import '../../core/errors/data_exceptions.dart';
import '../../domain/projects/novel_output_limits.dart';
import '../repositories/novel_output_limits_repository.dart';
import 'ibuki_database.dart';
import 'package:sqflite/sqflite.dart';

class SQLiteNovelOutputLimitsRepository implements NovelOutputLimitsRepository {
  const SQLiteNovelOutputLimitsRepository(this.database);
  final IbukiDatabase database;
  Future<void> _requireProject(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'projects',
      columns: ['id'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (rows.isEmpty) throw const DataConflictException('作品不存在或已删除。');
  }

  NovelOutputLimits _decode(String id, List<Map<String, Object?>> rows) =>
      rows.isEmpty
      ? NovelOutputLimits(projectId: id)
      : NovelOutputLimits(
          projectId: id,
          minimum: rows.single['minimum_characters'] as int?,
          maximum: rows.single['maximum_characters'] as int?,
          revision: rows.single['revision']! as int,
        );
  @override
  Future<NovelOutputLimits> get(String projectId) async {
    final db = await database.database;
    await _requireProject(db, projectId);
    return _decode(
      projectId,
      await db.query(
        'novel_output_settings',
        where: 'project_id = ?',
        whereArgs: [projectId],
      ),
    );
  }

  @override
  Future<NovelOutputLimits> save(
    NovelOutputLimits value, {
    required int expectedRevision,
    required DateTime now,
  }) async {
    value.validate();
    final db = await database.database;
    return db.transaction((txn) async {
      await _requireProject(txn, value.projectId);
      final rows = await txn.query(
        'novel_output_settings',
        where: 'project_id = ?',
        whereArgs: [value.projectId],
      );
      final old = _decode(value.projectId, rows);
      if (old.revision != expectedRevision) {
        throw const DataConflictException('设置已改变，请重新打开后修改。');
      }
      if (old.minimum == value.minimum && old.maximum == value.maximum) {
        return old;
      }
      if (value.isDefault) {
        await txn.delete(
          'novel_output_settings',
          where: 'project_id = ?',
          whereArgs: [value.projectId],
        );
        return NovelOutputLimits(projectId: value.projectId);
      }
      final revision = old.revision + 1;
      final data = {
        'minimum_characters': value.minimum,
        'maximum_characters': value.maximum,
        'revision': revision,
        'updated_at': now.toUtc().toIso8601String(),
      };
      if (rows.isEmpty) {
        await txn.insert('novel_output_settings', {
          'id': 'novel-output:${value.projectId}',
          'project_id': value.projectId,
          ...data,
        });
      } else {
        await txn.update(
          'novel_output_settings',
          data,
          where: 'project_id = ?',
          whereArgs: [value.projectId],
        );
      }
      return NovelOutputLimits(
        projectId: value.projectId,
        minimum: value.minimum,
        maximum: value.maximum,
        revision: revision,
      );
    });
  }
}
