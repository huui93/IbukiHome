import 'package:sqflite/sqflite.dart';
import '../../core/errors/data_exceptions.dart';
import '../../domain/ai/ai_reasoning_level.dart';
import '../../domain/chat/chat_usage_record.dart';
import '../repositories/chat_controls_repository.dart';
import 'ibuki_database.dart';

class SQLiteChatControlsRepository implements ChatControlsRepository {
  const SQLiteChatControlsRepository(this.database);
  final IbukiDatabase database;
  Future<void> _requireSession(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'chat_sessions',
      columns: ['id'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (rows.isEmpty) throw const DataConflictException('会话不存在或已删除。');
  }

  @override
  Future<AiReasoningLevel> getReasoning(String sessionId) async {
    final db = await database.database;
    await _requireSession(db, sessionId);
    final rows = await db.query(
      'chat_session_controls',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    return AiReasoningLevel.parse(
      rows.firstOrNull?['reasoning_level'] as String?,
    );
  }

  @override
  Future<void> setReasoning(
    String sessionId,
    AiReasoningLevel level,
    DateTime now,
  ) async {
    final db = await database.database;
    await db.transaction((txn) async {
      await _requireSession(txn, sessionId);
      final values = {
        'reasoning_level': level.name,
        'updated_at': now.toUtc().toIso8601String(),
      };
      final updated = await txn.update(
        'chat_session_controls',
        values,
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      if (updated == 0) {
        await txn.insert('chat_session_controls', {
          'id': 'controls:$sessionId',
          'session_id': sessionId,
          ...values,
        });
      }
    });
  }

  @override
  Future<List<ChatUsageRecord>> listUsage(String sessionId) async {
    final db = await database.database;
    return List.unmodifiable(
      (await db.query(
        'chat_usage_records',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'started_at DESC, id DESC',
      )).map(ChatUsageRecord.fromJson),
    );
  }

  @override
  Future<void> recordUsage(ChatUsageRecord record) async {
    final db = await database.database;
    await db.transaction((txn) async {
      await _requireSession(txn, record.sessionId);
      final previous = await txn.query(
        'chat_usage_records',
        columns: ['session_id'],
        where: 'id = ?',
        whereArgs: [record.id],
        limit: 1,
      );
      if (previous.isNotEmpty) {
        if (previous.single['session_id'] != record.sessionId) {
          throw const DataConflictException('用量记录不属于这个会话。');
        }
        return;
      }
      await txn.insert(
        'chat_usage_records',
        record.toJson(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }
}
