import 'package:sqflite/sqflite.dart';

import '../../core/errors/data_exceptions.dart';
import '../../domain/segments/segment.dart';
import '../../domain/segments/segment_revision.dart';
import '../repositories/segment_repository.dart';
import 'ibuki_database.dart';
import 'sqlite_repository_helpers.dart';
import 'sqlite_value_codec.dart';

class SQLiteSegmentRepository implements SegmentRepository {
  SQLiteSegmentRepository(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;

  @override
  Future<List<Segment>> listSegments(
    String projectId, {
    bool includeDeleted = false,
  }) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'segments',
      where: activeWhere('project_id = ?', includeDeleted: includeDeleted),
      whereArgs: activeWhereArgs([projectId]),
      orderBy: 'order_index ASC, created_at ASC, id ASC',
    );
    return List.unmodifiable(rows.map(segmentFromSql));
  }

  @override
  Future<Segment> getSegment(String id) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'segments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EntityNotFoundException('Segment', id);
    }
    return segmentFromSql(rows.single);
  }

  @override
  Future<void> upsertSegment(Segment segment) async {
    final database = await ibukiDatabase.database;
    await handleSqliteWrite(
      () async {
        await database.transaction((txn) async {
          await _requireWritableProject(txn, segment.projectId);
          final existing = await _getSegmentOrNull(txn, segment.id);
          if (existing != null && existing.projectId != segment.projectId) {
            throw DataConflictException(
              'Segment ${segment.id} cannot move between projects.',
            );
          }
          await txn.insert(
            'segments',
            segmentToSql(segment),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        });
      },
      entityName: 'Segment',
      entityId: segment.id,
    );
  }

  @override
  Future<void> softDeleteSegment(String id, DateTime deletedAt) async {
    final segment = await getSegment(id);
    await softDeleteAndReorder(
      projectId: segment.projectId,
      segmentId: id,
      deletedAt: deletedAt,
    );
  }

  @override
  Future<void> restoreSegment(String id, DateTime updatedAt) async {
    final segment = await getSegment(id);
    await restoreAndReorder(
      projectId: segment.projectId,
      segmentId: id,
      restoredAt: updatedAt,
    );
  }

  @override
  Future<List<SegmentRevision>> listRevisions(String segmentId) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'segment_revisions',
      where: 'segment_id = ? AND deleted_at IS NULL',
      whereArgs: [segmentId],
      orderBy: 'revision_number ASC, created_at ASC, id ASC',
    );
    return List.unmodifiable(rows.map(segmentRevisionFromSql));
  }

  @override
  Future<SegmentRevision> getRevision(String id) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'segment_revisions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EntityNotFoundException('SegmentRevision', id);
    }
    return segmentRevisionFromSql(rows.single);
  }

  @override
  Future<void> appendRevision(SegmentRevision revision) async {
    final database = await ibukiDatabase.database;
    await _validateRevision(database, revision);
    await handleSqliteWrite(
      () async {
        await database.insert(
          'segment_revisions',
          segmentRevisionToSql(revision),
        );
      },
      entityName: 'SegmentRevision',
      entityId: revision.id,
    );
  }

  @override
  Future<Segment> insertSegmentAt({
    required Segment segment,
    required String anchorSegmentId,
    required SegmentInsertPosition position,
  }) async {
    final database = await ibukiDatabase.database;
    late Segment inserted;
    await handleSqliteWrite(
      () async {
        await database.transaction((transaction) async {
          await _requireWritableProject(transaction, segment.projectId);
          if (await _getSegmentOrNull(transaction, segment.id) != null) {
            throw DuplicateEntityException('Segment', segment.id);
          }
          final anchor = await _getSegmentOrNull(transaction, anchorSegmentId);
          if (anchor == null) {
            throw EntityNotFoundException('Segment', anchorSegmentId);
          }
          if (anchor.projectId != segment.projectId) {
            throw const DataConflictException('插入锚点不属于当前项目。');
          }
          if (anchor.deletedAt != null) {
            throw const DataConflictException('已删除段落不能作为插入锚点。');
          }

          final active = await _listActiveSegments(
            transaction,
            segment.projectId,
          );
          final anchorIndex = active.indexWhere(
            (item) => item.id == anchorSegmentId,
          );
          if (anchorIndex < 0) {
            throw EntityNotFoundException('Segment', anchorSegmentId);
          }
          final insertionIndex =
              anchorIndex + (position == SegmentInsertPosition.after ? 1 : 0);
          final updatedAt = segment.updatedAt.toUtc();
          for (var index = insertionIndex; index < active.length; index += 1) {
            final current = active[index];
            await _updateSegment(
              transaction,
              current.copyWith(
                metadata: current.metadata.copyWith(
                  updatedAt: updatedAt,
                  revision: current.revision + 1,
                ),
                orderIndex: index + 1,
              ),
            );
          }
          inserted = segment.copyWith(orderIndex: insertionIndex);
          await transaction.insert('segments', segmentToSql(inserted));
        });
      },
      entityName: 'SegmentInsert',
      entityId: segment.id,
    );
    return inserted;
  }

  @override
  Future<void> reorderSegments({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  }) async {
    final database = await ibukiDatabase.database;
    await handleSqliteWrite(
      () async {
        await database.transaction((transaction) async {
          await _requireProject(transaction, projectId);
          final active = await _listActiveSegments(transaction, projectId);
          _validateOrderedIds(active, orderedIds);
          final updatedUtc = updatedAt.toUtc();
          final byId = {for (final segment in active) segment.id: segment};
          for (var index = 0; index < orderedIds.length; index += 1) {
            final current = byId[orderedIds[index]]!;
            if (current.orderIndex == index) {
              continue;
            }
            await _updateSegment(
              transaction,
              current.copyWith(
                metadata: current.metadata.copyWith(
                  updatedAt: updatedUtc,
                  revision: current.revision + 1,
                ),
                orderIndex: index,
              ),
            );
          }
        });
      },
      entityName: 'SegmentOrder',
      entityId: projectId,
    );
  }

  @override
  Future<Segment> softDeleteAndReorder({
    required String projectId,
    required String segmentId,
    required DateTime deletedAt,
  }) async {
    final database = await ibukiDatabase.database;
    late Segment deleted;
    await handleSqliteWrite(
      () async {
        await database.transaction((transaction) async {
          await _requireProject(transaction, projectId);
          final target = await _getSegmentOrNull(transaction, segmentId);
          if (target == null) {
            throw EntityNotFoundException('Segment', segmentId);
          }
          if (target.projectId != projectId) {
            throw const DataConflictException('段落不属于当前项目。');
          }
          if (target.deletedAt != null) {
            deleted = target;
            return;
          }

          final active = await _listActiveSegments(transaction, projectId);
          final deletedUtc = deletedAt.toUtc();
          deleted = target.copyWith(
            metadata: target.metadata.copyWith(
              updatedAt: deletedUtc,
              revision: target.revision + 1,
              deletedAt: deletedUtc,
            ),
          );
          await _updateSegment(transaction, deleted);
          var order = 0;
          for (final current in active) {
            if (current.id == segmentId) {
              continue;
            }
            if (current.orderIndex != order) {
              await _updateSegment(
                transaction,
                current.copyWith(
                  metadata: current.metadata.copyWith(
                    updatedAt: deletedUtc,
                    revision: current.revision + 1,
                  ),
                  orderIndex: order,
                ),
              );
            }
            order += 1;
          }
        });
      },
      entityName: 'SegmentDelete',
      entityId: segmentId,
    );
    return deleted;
  }

  @override
  Future<Segment> restoreAndReorder({
    required String projectId,
    required String segmentId,
    required DateTime restoredAt,
  }) async {
    final database = await ibukiDatabase.database;
    late Segment restored;
    await handleSqliteWrite(
      () async {
        await database.transaction((transaction) async {
          await _requireProject(transaction, projectId);
          final target = await _getSegmentOrNull(transaction, segmentId);
          if (target == null) {
            throw EntityNotFoundException('Segment', segmentId);
          }
          if (target.projectId != projectId) {
            throw const DataConflictException('段落不属于当前项目。');
          }
          if (target.deletedAt == null) {
            restored = target;
            return;
          }

          final active = await _listActiveSegments(transaction, projectId);
          final insertionIndex = target.orderIndex
              .clamp(0, active.length)
              .toInt();
          final restoredUtc = restoredAt.toUtc();
          for (var index = insertionIndex; index < active.length; index += 1) {
            final current = active[index];
            await _updateSegment(
              transaction,
              current.copyWith(
                metadata: current.metadata.copyWith(
                  updatedAt: restoredUtc,
                  revision: current.revision + 1,
                ),
                orderIndex: index + 1,
              ),
            );
          }
          restored = target.copyWith(
            metadata: target.metadata.copyWith(
              updatedAt: restoredUtc,
              revision: target.revision + 1,
              deletedAt: null,
            ),
            orderIndex: insertionIndex,
          );
          await _updateSegment(transaction, restored);
        });
      },
      entityName: 'SegmentRestore',
      entityId: segmentId,
    );
    return restored;
  }

  @override
  Future<void> saveSegmentWithRevision({
    required Segment updatedSegment,
    required SegmentRevision revision,
  }) async {
    final database = await ibukiDatabase.database;
    try {
      await database.transaction((txn) async {
        await _requireWritableProject(txn, updatedSegment.projectId);
        await _validateRevision(txn, revision);
        final current = await _getSegmentOrNull(txn, updatedSegment.id);
        if (current == null) {
          throw EntityNotFoundException('Segment', updatedSegment.id);
        }
        if (current.projectId != updatedSegment.projectId ||
            current.orderIndex != updatedSegment.orderIndex ||
            current.revision != revision.revisionNumber ||
            current.content != revision.content ||
            revision.segmentId != updatedSegment.id ||
            revision.projectId != updatedSegment.projectId) {
          throw DataConflictException(
            'Segment ${updatedSegment.id} and revision ${revision.id} do not match.',
          );
        }
        await txn.insert('segment_revisions', segmentRevisionToSql(revision));
        final changed = await txn.update(
          'segments',
          segmentToSql(updatedSegment),
          where: 'id = ? AND project_id = ?',
          whereArgs: [updatedSegment.id, updatedSegment.projectId],
        );
        if (changed != 1) {
          throw EntityNotFoundException('Segment', updatedSegment.id);
        }
      });
    } on DatabaseException catch (error) {
      throw _mapRevisionTransactionException(error, revision.id);
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

  Future<void> _requireWritableProject(
    DatabaseExecutor db,
    String projectId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT p.deleted_at, b.ended_by_plugin FROM projects p '
      'LEFT JOIN novel_story_branches b ON p.id = b.id WHERE p.id = ?',
      [projectId],
    );
    if (rows.isEmpty) throw EntityNotFoundException('Project', projectId);
    if (rows.single['deleted_at'] != null) {
      throw const DataConflictException('作品已删除，不能继续保存正文。');
    }
    if (rows.single['ended_by_plugin'] != null) {
      throw const DataConflictException('当前故事线已经结束，不能继续写入正文。');
    }
  }

  Future<Segment?> _getSegmentOrNull(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'segments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : segmentFromSql(rows.single);
  }

  Future<List<Segment>> _listActiveSegments(
    DatabaseExecutor db,
    String projectId,
  ) async {
    final rows = await db.query(
      'segments',
      where: 'project_id = ? AND deleted_at IS NULL',
      whereArgs: [projectId],
      orderBy: 'order_index ASC, created_at ASC, id ASC',
    );
    return rows.map(segmentFromSql).toList();
  }

  Future<void> _updateSegment(DatabaseExecutor db, Segment segment) async {
    final changed = await db.update(
      'segments',
      segmentToSql(segment),
      where: 'id = ? AND project_id = ?',
      whereArgs: [segment.id, segment.projectId],
    );
    if (changed != 1) {
      throw EntityNotFoundException('Segment', segment.id);
    }
  }

  void _validateOrderedIds(List<Segment> active, List<String> orderedIds) {
    final expected = active.map((item) => item.id).toSet();
    final provided = orderedIds.toSet();
    if (orderedIds.length != provided.length ||
        expected.length != provided.length ||
        !expected.containsAll(provided)) {
      throw const DataConflictException('正文排序必须包含当前项目的全部有效段落，且不能重复。');
    }
  }

  Future<void> _validateRevision(
    DatabaseExecutor db,
    SegmentRevision revision,
  ) async {
    final segment = await _getSegmentOrNull(db, revision.segmentId);
    if (segment == null) {
      throw EntityNotFoundException('Segment', revision.segmentId);
    }
    if (segment.projectId != revision.projectId) {
      throw DataConflictException(
        'SegmentRevision ${revision.id} project does not match segment.',
      );
    }
  }
}

DataException _mapRevisionTransactionException(
  DatabaseException error,
  String revisionId,
) {
  final message = error.toString().toLowerCase();
  if (message.contains('unique') || message.contains('primary key')) {
    return DuplicateEntityException('SegmentRevision', revisionId);
  }
  if (message.contains('foreign key') ||
      message.contains('check constraint') ||
      message.contains('constraint failed')) {
    return DataConflictException(
      'SegmentRevision $revisionId violates database constraints.',
    );
  }
  return DataConflictException(
    'SegmentRevision $revisionId could not be saved.',
  );
}
