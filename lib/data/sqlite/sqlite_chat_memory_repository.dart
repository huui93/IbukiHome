import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../../domain/chat/chat_memory_state.dart';
import 'chat_memory_state_codec.dart';

import '../../core/errors/data_exceptions.dart';
import '../../domain/chat/chat_memory_entry.dart';
import '../../domain/chat/conversation_summary.dart';
import '../repositories/chat_memory_repository.dart';
import 'ibuki_database.dart';
import 'sqlite_repository_helpers.dart';
import 'sqlite_value_codec.dart';

class SQLiteChatMemoryRepository implements ChatMemoryRepository {
  SQLiteChatMemoryRepository(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;

  @override
  Future<ChatMemoryState?> getState(String sessionId) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'chat_memory_states',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    return rows.isEmpty ? null : chatMemoryStateFromSql(rows.single);
  }

  @override
  Future<bool> commitSessionMemory(
    ChatMemoryState state, {
    required int expectedRevision,
    List<ChatMemoryEntry> entries = const [],
    List<ConversationSummary> summaries = const [],
  }) async {
    final db = await ibukiDatabase.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'chat_memory_states',
        where: 'session_id = ?',
        whereArgs: [state.sessionId],
      );
      final old = rows.isEmpty ? null : chatMemoryStateFromSql(rows.single);
      if ((old?.metadata.revision ?? 0) != expectedRevision) return false;
      if (state.metadata.revision != expectedRevision + 1 ||
          (old != null && old.metadata.id != state.metadata.id)) {
        throw const DataConflictException('记忆设置版本无效。');
      }
      final sessions = await txn.query(
        'chat_sessions',
        where: 'id = ?',
        whereArgs: [state.sessionId],
      );
      if (sessions.isEmpty || sessions.single['deleted_at'] != null) {
        return false;
      }
      for (final entry in entries) {
        if (entry.sessionId != state.sessionId ||
            entry.personaId != sessions.single['persona_id'] ||
            (entry.sourceSessionId != null &&
                entry.sourceSessionId != state.sessionId)) {
          throw const DataConflictException('记忆只能属于当前会话。');
        }
        final previous = await txn.query(
          'chat_memory_entries',
          columns: ['session_id', 'revision'],
          where: 'id = ?',
          whereArgs: [entry.id],
        );
        if (previous.isNotEmpty &&
            previous.single['session_id'] != state.sessionId) {
          throw const DataConflictException('不能移动其他会话的记忆。');
        }
        if (previous.isNotEmpty &&
            entry.revision != (previous.single['revision']! as int) + 1) {
          throw const DataConflictException('这条记忆刚刚发生更改，请重新读取。');
        }
        await _validateSource(
          txn,
          state.sessionId,
          entry.sourceStartMessageId,
          entry.sourceEndMessageId,
        );
        await txn.insert(
          'chat_memory_entries',
          chatMemoryEntryToSql(entry),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final summary in summaries) {
        if (summary.sessionId != state.sessionId) {
          throw const DataConflictException('摘要会话不匹配。');
        }
        await _validateSource(
          txn,
          state.sessionId,
          summary.sourceStartMessageId,
          summary.sourceEndMessageId,
        );
        await txn.insert(
          'conversation_summaries',
          conversationSummaryToSql(summary),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (old == null) {
        await txn.insert('chat_memory_states', chatMemoryStateToSql(state));
      } else {
        await txn.update(
          'chat_memory_states',
          chatMemoryStateToSql(state),
          where: 'id = ?',
          whereArgs: [state.metadata.id],
        );
      }
      return true;
    });
  }

  Future<void> _validateSource(
    DatabaseExecutor db,
    String sessionId,
    String? first,
    String? last,
  ) async {
    for (final id in {?first, ?last}) {
      final messages = await db.query(
        'chat_messages',
        columns: ['session_id'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (messages.isEmpty || messages.single['session_id'] != sessionId) {
        throw const DataConflictException('记忆来源必须属于当前会话。');
      }
    }
  }

  @override
  Future<void> saveUsage(ChatMemoryUsage usage) async {
    final db = await ibukiDatabase.database;
    await db.transaction((txn) async {
      final messages = await txn.query(
        'chat_messages',
        columns: ['session_id'],
        where: 'id = ?',
        whereArgs: [usage.messageId],
      );
      if (messages.isEmpty ||
          messages.single['session_id'] != usage.sessionId) {
        throw const DataConflictException('记忆来源会话不匹配。');
      }
      await txn.delete(
        'chat_memory_usage',
        where: 'message_id = ?',
        whereArgs: [usage.messageId],
      );
      await txn.insert('chat_memory_usage', {
        'id': usage.id,
        'session_id': usage.sessionId,
        'message_id': usage.messageId,
        'source_keys_json': jsonEncode(usage.sourceKeys),
      });
    });
  }

  @override
  Future<ChatMemoryUsage?> getUsage(String sessionId, String messageId) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'chat_memory_usage',
      where: 'session_id = ? AND message_id = ?',
      whereArgs: [sessionId, messageId],
    );
    return rows.isEmpty ? null : chatMemoryUsageFromSql(rows.single);
  }

  @override
  Future<List<ChatMemoryEntry>> listEntries(
    String personaId, {
    bool includeDeleted = false,
  }) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'chat_memory_entries',
      where: activeWhere('persona_id = ?', includeDeleted: includeDeleted),
      whereArgs: [personaId],
      orderBy: 'is_pinned DESC, updated_at DESC, id ASC',
    );
    return List.unmodifiable(rows.map(chatMemoryEntryFromSql));
  }

  @override
  Future<ChatMemoryEntry> getEntry(String id) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'chat_memory_entries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw EntityNotFoundException('ChatMemoryEntry', id);
    return chatMemoryEntryFromSql(rows.single);
  }

  @override
  Future<List<ChatMemoryEntry>> listEntriesForSession(
    String sessionId, {
    bool includeDeleted = false,
  }) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'chat_memory_entries',
      where: activeWhere('session_id = ?', includeDeleted: includeDeleted),
      whereArgs: [sessionId],
      orderBy: 'is_pinned DESC, updated_at DESC, id ASC',
    );
    return List.unmodifiable(rows.map(chatMemoryEntryFromSql));
  }

  @override
  Future<void> upsertEntry(ChatMemoryEntry entry) async {
    final db = await ibukiDatabase.database;
    await db.insert(
      'chat_memory_entries',
      chatMemoryEntryToSql(entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> softDeleteEntry(String id, DateTime deletedAt) async {
    final current = await getEntry(id);
    if (current.deletedAt != null) return;
    final at = deletedAt.toUtc();
    await upsertEntry(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: at,
          revision: current.revision + 1,
          deletedAt: at,
        ),
      ),
    );
  }

  @override
  Future<void> restoreEntry(String id, DateTime updatedAt) async {
    final current = await getEntry(id);
    if (current.deletedAt == null) return;
    final at = updatedAt.toUtc();
    await upsertEntry(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: at,
          revision: current.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  @override
  Future<List<ConversationSummary>> listSummaries(String sessionId) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'conversation_summaries',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC, id ASC',
    );
    return List.unmodifiable(rows.map(conversationSummaryFromSql));
  }

  @override
  Future<void> upsertSummary(ConversationSummary summary) async {
    final db = await ibukiDatabase.database;
    await db.insert(
      'conversation_summaries',
      conversationSummaryToSql(summary),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
