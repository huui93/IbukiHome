import 'package:sqflite/sqflite.dart';

import '../../core/errors/data_exceptions.dart';
import '../../domain/world/world_card.dart';
import '../repositories/world_repository.dart';
import 'ibuki_database.dart';
import 'sqlite_repository_helpers.dart';
import 'sqlite_value_codec.dart';

class SQLiteWorldRepository implements WorldRepository {
  SQLiteWorldRepository(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;

  @override
  Future<List<WorldCard>> listWorldCards(
    String projectId, {
    bool includeDeleted = false,
  }) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'world_cards',
      where: activeWhere('project_id = ?', includeDeleted: includeDeleted),
      whereArgs: [projectId],
      orderBy: 'sort_order ASC, updated_at ASC, id ASC',
    );
    return List.unmodifiable(rows.map(worldCardFromSql));
  }

  @override
  Future<WorldCard> getWorldCard(String id) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'world_cards',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EntityNotFoundException('WorldCard', id);
    }
    return worldCardFromSql(rows.single);
  }

  @override
  Future<void> upsertWorldCard(WorldCard card) async {
    final database = await ibukiDatabase.database;
    await _requireProject(database, card.projectId);
    final existing = await _getWorldCardOrNull(database, card.id);
    if (existing != null && existing.projectId != card.projectId) {
      throw DataConflictException(
        'WorldCard ${card.id} cannot move between projects.',
      );
    }
    await handleSqliteWrite(
      () async {
        await database.insert(
          'world_cards',
          worldCardToSql(card),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      },
      entityName: 'WorldCard',
      entityId: card.id,
    );
  }

  @override
  Future<void> softDeleteWorldCard(String id, DateTime deletedAt) async {
    final card = await getWorldCard(id);
    final deletedUtc = deletedAt.toUtc();
    await upsertWorldCard(
      card.copyWith(
        metadata: card.metadata.copyWith(
          updatedAt: deletedUtc,
          revision: card.revision + 1,
          deletedAt: deletedUtc,
        ),
      ),
    );
  }

  @override
  Future<void> restoreWorldCard(String id, DateTime updatedAt) async {
    final card = await getWorldCard(id);
    final updatedUtc = updatedAt.toUtc();
    await upsertWorldCard(
      card.copyWith(
        metadata: card.metadata.copyWith(
          updatedAt: updatedUtc,
          revision: card.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  @override
  Future<void> reorderWorldCards({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  }) async {
    final database = await ibukiDatabase.database;
    await _requireProject(database, projectId);
    await handleSqliteWrite(
      () async {
        await database.transaction((transaction) async {
          final rows = await transaction.query(
            'world_cards',
            columns: ['id'],
            where: 'project_id = ? AND deleted_at IS NULL',
            whereArgs: [projectId],
          );
          _validateOrderedIds(
            rows.map((row) => row['id']! as String).toList(),
            orderedIds,
          );
          final updated = updatedAt.toUtc().toIso8601String();
          for (var index = 0; index < orderedIds.length; index += 1) {
            await transaction.rawUpdate(
              '''
UPDATE world_cards
SET sort_order = ?, updated_at = ?, revision = revision + 1
WHERE id = ? AND project_id = ? AND deleted_at IS NULL AND sort_order <> ?
''',
              [index, updated, orderedIds[index], projectId, index],
            );
          }
        });
      },
      entityName: 'WorldCardOrder',
      entityId: projectId,
    );
  }

  void _validateOrderedIds(List<String> activeIds, List<String> orderedIds) {
    final expected = activeIds.toSet();
    final provided = orderedIds.toSet();
    if (orderedIds.length != provided.length ||
        expected.length != provided.length ||
        !expected.containsAll(provided)) {
      throw const DataConflictException('世界观排序必须包含当前项目的全部有效卡片，且不能重复。');
    }
  }

  Future<void> _requireProject(DatabaseExecutor db, String projectId) async {
    final rows = await db.query(
      'projects',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [projectId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EntityNotFoundException('Project', projectId);
    }
  }

  Future<WorldCard?> _getWorldCardOrNull(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'world_cards',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : worldCardFromSql(rows.single);
  }
}
