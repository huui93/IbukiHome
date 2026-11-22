import 'package:sqflite/sqflite.dart';

import '../../core/errors/data_exceptions.dart';
import '../../domain/outline/outline_node.dart';
import '../repositories/outline_repository.dart';
import 'ibuki_database.dart';
import 'sqlite_repository_helpers.dart';
import 'sqlite_value_codec.dart';

class SQLiteOutlineRepository implements OutlineRepository {
  SQLiteOutlineRepository(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;

  @override
  Future<List<OutlineNode>> listOutlineNodes(
    String projectId, {
    bool includeDeleted = false,
  }) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'outline_nodes',
      where: activeWhere('project_id = ?', includeDeleted: includeDeleted),
      whereArgs: [projectId],
      orderBy: 'order_index ASC, id ASC',
    );
    return List.unmodifiable(rows.map(outlineNodeFromSql));
  }

  @override
  Future<OutlineNode> getOutlineNode(String id) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'outline_nodes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw EntityNotFoundException('OutlineNode', id);
    return outlineNodeFromSql(rows.single);
  }

  @override
  Future<void> upsertOutlineNode(OutlineNode node) async {
    final database = await ibukiDatabase.database;
    await _requireProject(database, node.projectId);
    final existing = await _getOrNull(database, node.id);
    if (existing != null && existing.projectId != node.projectId) {
      throw const DataConflictException(
        'Outline nodes cannot move between projects.',
      );
    }
    await handleSqliteWrite(
      () => database.insert(
        'outline_nodes',
        outlineNodeToSql(node),
        conflictAlgorithm: ConflictAlgorithm.replace,
      ),
      entityName: 'OutlineNode',
      entityId: node.id,
    );
  }

  @override
  Future<void> softDeleteOutlineNode(String id, DateTime deletedAt) async {
    final node = await getOutlineNode(id);
    if (node.deletedAt != null) return;
    final at = deletedAt.toUtc();
    await upsertOutlineNode(
      node.copyWith(
        metadata: node.metadata.copyWith(
          updatedAt: at,
          revision: node.revision + 1,
          deletedAt: at,
        ),
      ),
    );
  }

  @override
  Future<void> reorderOutlineNodes({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  }) async {
    final database = await ibukiDatabase.database;
    await handleSqliteWrite(
      () => database.transaction((transaction) async {
        await _requireProject(transaction, projectId);
        final rows = await transaction.query(
          'outline_nodes',
          columns: ['id'],
          where: 'project_id = ? AND deleted_at IS NULL',
          whereArgs: [projectId],
        );
        _validateOrderedIds(
          rows.map((row) => row['id']! as String).toList(),
          orderedIds,
        );
        final at = updatedAt.toUtc().toIso8601String();
        for (var index = 0; index < orderedIds.length; index += 1) {
          await transaction.rawUpdate(
            '''
UPDATE outline_nodes
SET order_index = ?, updated_at = ?, revision = revision + 1
WHERE id = ? AND project_id = ? AND deleted_at IS NULL AND order_index <> ?
''',
            [index, at, orderedIds[index], projectId, index],
          );
        }
      }),
      entityName: 'OutlineOrder',
      entityId: projectId,
    );
  }

  @override
  Future<void> setOutlineNodeStatus({
    required String id,
    required OutlineNodeStatus status,
    required DateTime updatedAt,
  }) async {
    final database = await ibukiDatabase.database;
    await handleSqliteWrite(
      () => database.transaction((transaction) async {
        final rows = await transaction.query(
          'outline_nodes',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) throw EntityNotFoundException('OutlineNode', id);
        final target = outlineNodeFromSql(rows.single);
        if (target.deletedAt != null || target.status == status) return;
        final at = updatedAt.toUtc().toIso8601String();
        if (status == OutlineNodeStatus.current) {
          await transaction.rawUpdate(
            '''
UPDATE outline_nodes
SET status = 'planned', updated_at = ?, revision = revision + 1
WHERE project_id = ? AND id <> ? AND status = 'current' AND deleted_at IS NULL
''',
            [at, target.projectId, target.id],
          );
        }
        await transaction.rawUpdate(
          '''
UPDATE outline_nodes
SET status = ?, updated_at = ?, revision = revision + 1
WHERE id = ? AND deleted_at IS NULL
''',
          [status.jsonValue, at, id],
        );
      }),
      entityName: 'OutlineNodeStatus',
      entityId: id,
    );
  }

  Future<void> _requireProject(DatabaseExecutor db, String projectId) async {
    final rows = await db.query(
      'projects',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [projectId],
      limit: 1,
    );
    if (rows.isEmpty) throw EntityNotFoundException('Project', projectId);
  }

  Future<OutlineNode?> _getOrNull(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'outline_nodes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : outlineNodeFromSql(rows.single);
  }
}

void _validateOrderedIds(List<String> activeIds, List<String> orderedIds) {
  final expected = activeIds.toSet();
  final provided = orderedIds.toSet();
  if (orderedIds.length != provided.length ||
      expected.length != provided.length ||
      !expected.containsAll(provided)) {
    throw const DataConflictException(
      'Outline ordering must include every active node exactly once.',
    );
  }
}
