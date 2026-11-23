import 'package:sqflite/sqflite.dart';

import '../../core/errors/data_exceptions.dart';
import '../../domain/chat/chat_image.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_session.dart';
import '../repositories/chat_repository.dart';
import '../repositories/latest_chat_mutation.dart';
import 'ibuki_database.dart';
import 'sqlite_repository_helpers.dart';
import 'sqlite_value_codec.dart';

class SQLiteChatRepository implements ChatRepository {
  SQLiteChatRepository(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;

  @override
  Future<List<ChatSession>> listSessions({
    String? projectId,
    String? characterId,
    String? personaId,
    bool includeDeleted = false,
  }) async {
    final database = await ibukiDatabase.database;
    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    if (projectId != null) {
      whereParts.add('project_id = ?');
      whereArgs.add(projectId);
    }
    if (characterId != null) {
      whereParts.add('character_id = ?');
      whereArgs.add(characterId);
    }
    if (personaId != null) {
      whereParts.add('persona_id = ?');
      whereArgs.add(personaId);
    }
    if (!includeDeleted) {
      whereParts.add('deleted_at IS NULL');
    }
    final rows = await database.query(
      'chat_sessions',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'updated_at DESC, title ASC, id ASC',
    );
    return List.unmodifiable(rows.map(chatSessionFromSql));
  }

  @override
  Future<ChatSession> getSession(String id) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'chat_sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EntityNotFoundException('ChatSession', id);
    }
    return chatSessionFromSql(rows.single);
  }

  @override
  Future<void> upsertSession(ChatSession session) async {
    final database = await ibukiDatabase.database;
    if (session.projectId != null || session.characterId != null) {
      throw const DataConflictException('聊天会话不能关联小说资料。');
    }
    if (session.personaId != null) {
      await _requirePersona(database, session.personaId!);
    }
    final existing = await _getSessionOrNull(database, session.id);
    if (existing != null && existing.projectId != session.projectId) {
      throw DataConflictException(
        'ChatSession ${session.id} cannot move between projects.',
      );
    }
    if (existing != null && existing.characterId != session.characterId) {
      throw DataConflictException(
        'ChatSession ${session.id} cannot change its character binding.',
      );
    }
    if (existing != null && existing.personaId != session.personaId) {
      throw DataConflictException(
        'ChatSession ${session.id} cannot change its persona binding.',
      );
    }
    await handleSqliteWrite(
      () async {
        if (existing == null) {
          await database.insert('chat_sessions', chatSessionToSql(session));
          return;
        }

        final updatedRows = await database.update(
          'chat_sessions',
          chatSessionToSql(session),
          where: 'id = ?',
          whereArgs: [session.id],
        );
        if (updatedRows != 1) {
          throw EntityNotFoundException('ChatSession', session.id);
        }
      },
      entityName: 'ChatSession',
      entityId: session.id,
    );
  }

  @override
  Future<void> softDeleteSession(String id, DateTime deletedAt) async {
    final session = await getSession(id);
    if (session.deletedAt != null) {
      return;
    }
    final deletedUtc = deletedAt.toUtc();
    await upsertSession(
      session.copyWith(
        metadata: session.metadata.copyWith(
          updatedAt: deletedUtc,
          revision: session.revision + 1,
          deletedAt: deletedUtc,
        ),
      ),
    );
  }

  @override
  Future<void> restoreSession(String id, DateTime updatedAt) async {
    final session = await getSession(id);
    if (session.deletedAt == null) {
      return;
    }
    final updatedUtc = updatedAt.toUtc();
    await upsertSession(
      session.copyWith(
        metadata: session.metadata.copyWith(
          updatedAt: updatedUtc,
          revision: session.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  @override
  Future<List<ChatMessage>> listMessages(
    String sessionId, {
    bool includeDeleted = false,
    bool includeImageData = true,
  }) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'chat_messages',
      columns: includeImageData
          ? null
          : const [
              'id',
              'created_at',
              'updated_at',
              'revision',
              'deleted_at',
              'session_id',
              'project_id',
              'role',
              'content',
              'finish_reason',
              'image_json IS NOT NULL AS has_image',
            ],
      where: activeWhere('session_id = ?', includeDeleted: includeDeleted),
      whereArgs: [sessionId],
      orderBy: 'created_at ASC, id ASC',
    );
    return List.unmodifiable(
      rows.map((row) => chatMessageFromSql(row, deferImageDecoding: true)),
    );
  }

  @override
  Future<ChatMessage> getMessage(String id) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'chat_messages',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw EntityNotFoundException('ChatMessage', id);
    return chatMessageFromSql(rows.single);
  }

  @override
  Future<ChatImage?> getMessageImage(String id) async =>
      (await getMessage(id)).image;

  @override
  Future<void> appendMessage(ChatMessage message) async {
    final database = await ibukiDatabase.database;
    final session = await _getSessionOrNull(database, message.sessionId);
    if (session == null) {
      throw EntityNotFoundException('ChatSession', message.sessionId);
    }
    if (session.deletedAt != null) {
      throw DataConflictException(
        'ChatSession ${session.id} is deleted and cannot receive messages.',
      );
    }
    if (message.projectId != null) {
      throw const DataConflictException('聊天消息不能关联小说资料。');
    }
    if (session.projectId != null && session.projectId != message.projectId) {
      throw DataConflictException(
        'ChatMessage ${message.id} project does not match session.',
      );
    }
    await handleSqliteWrite(
      () async {
        await database.insert('chat_messages', chatMessageToSql(message));
      },
      entityName: 'ChatMessage',
      entityId: message.id,
    );
  }

  @override
  Future<void> upsertMessage(ChatMessage message) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'chat_messages',
      where: 'id = ?',
      whereArgs: [message.id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EntityNotFoundException('ChatMessage', message.id);
    }
    if (message.projectId != null) {
      throw const DataConflictException('聊天消息不能关联小说资料。');
    }
    final current = chatMessageFromSql(rows.single);
    if (current.sessionId != message.sessionId) {
      throw DataConflictException(
        'ChatMessage ${message.id} cannot move sessions.',
      );
    }
    await handleSqliteWrite(
      () => database.update(
        'chat_messages',
        chatMessageToSql(message),
        where: 'id = ?',
        whereArgs: [message.id],
      ),
      entityName: 'ChatMessage',
      entityId: message.id,
    );
  }

  @override
  Future<ChatSession> appendMessageAndTouchSession(
    ChatMessage message,
    DateTime updatedAt,
  ) async {
    final database = await ibukiDatabase.database;
    try {
      return await database.transaction((txn) async {
        final session = await _getSessionOrNull(txn, message.sessionId);
        if (session == null) {
          throw EntityNotFoundException('ChatSession', message.sessionId);
        }
        if (session.deletedAt != null) {
          throw DataConflictException(
            'ChatSession ${session.id} is deleted and cannot receive messages.',
          );
        }
        if (message.projectId != null) {
          throw const DataConflictException('聊天消息不能关联小说资料。');
        }
        if (session.projectId != message.projectId) {
          throw DataConflictException(
            'ChatMessage ${message.id} project does not match session.',
          );
        }

        final updatedUtc = updatedAt.toUtc();
        final touched = session.copyWith(
          metadata: session.metadata.copyWith(
            updatedAt: updatedUtc,
            revision: session.revision + 1,
          ),
        );
        await txn.insert('chat_messages', chatMessageToSql(message));
        final touchedRows = await txn.update(
          'chat_sessions',
          chatSessionToSql(touched),
          where: 'id = ?',
          whereArgs: [touched.id],
        );
        if (touchedRows != 1) {
          throw EntityNotFoundException('ChatSession', touched.id);
        }
        return touched;
      });
    } on DatabaseException catch (error) {
      throw _mapChatDatabaseException(error, message.id);
    }
  }

  @override
  Future<void> softDeleteMessage(String id, DateTime deletedAt) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'chat_messages',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EntityNotFoundException('ChatMessage', id);
    }
    final message = chatMessageFromSql(rows.single);
    final deletedUtc = deletedAt.toUtc();
    await handleSqliteWrite(
      () async {
        await database.insert(
          'chat_messages',
          chatMessageToSql(
            message.copyWith(
              metadata: message.metadata.copyWith(
                updatedAt: deletedUtc,
                revision: message.revision + 1,
                deletedAt: deletedUtc,
              ),
            ),
          ),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      },
      entityName: 'ChatMessage',
      entityId: id,
    );
  }

  @override
  Future<ChatMessage> mutateLatestMessage({
    required ChatMessage expected,
    required DateTime nowUtc,
    ChatMessage? replacement,
    bool append = false,
    String? expectedPersonaId,
  }) async {
    final db = await ibukiDatabase.database;
    return db.transaction((txn) async {
      final session = await _getSessionOrNull(txn, expected.sessionId);
      if (session == null ||
          session.deletedAt != null ||
          (expectedPersonaId != null &&
              session.personaId != expectedPersonaId)) {
        throw const DataConflictException('会话不存在、已删除或人格已经变化。');
      }
      if (expectedPersonaId != null) {
        await _requirePersona(txn, expectedPersonaId);
      }
      final rows = await txn.query(
        'chat_messages',
        where: 'session_id = ? AND deleted_at IS NULL',
        whereArgs: [expected.sessionId],
        orderBy: 'created_at DESC, id DESC',
        limit: 1,
      );
      if (rows.isEmpty) throw const DataConflictException('会话已经没有消息。');
      final updated = prepareLatestChatMutation(
        expected: expected,
        latest: chatMessageFromSql(rows.single),
        nowUtc: nowUtc,
        replacement: replacement,
        append: append,
      );
      if (append) {
        await txn.insert(
          'chat_messages',
          chatMessageToSql(updated),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        final count = await txn.update(
          'chat_messages',
          chatMessageToSql(updated),
          where: 'id = ? AND revision = ? AND deleted_at IS NULL',
          whereArgs: [expected.id, expected.revision],
        );
        if (count != 1) throw const DataConflictException('最后一条消息已经变化。');
      }
      final touched = session.copyWith(
        metadata: session.metadata.copyWith(
          updatedAt: updated.updatedAt,
          revision: session.revision + 1,
        ),
      );
      await txn.update(
        'chat_sessions',
        chatSessionToSql(touched),
        where: 'id = ?',
        whereArgs: [session.id],
      );
      return updated;
    });
  }

  Future<void> _requirePersona(DatabaseExecutor db, String personaId) async {
    final rows = await db.query(
      'chat_personas',
      columns: ['id', 'deleted_at'],
      where: 'id = ?',
      whereArgs: [personaId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EntityNotFoundException('ChatPersona', personaId);
    }
    if (rows.single['deleted_at'] != null) {
      throw DataConflictException('ChatPersona $personaId is deleted.');
    }
  }

  Future<ChatSession?> _getSessionOrNull(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'chat_sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : chatSessionFromSql(rows.single);
  }

  DataException _mapChatDatabaseException(
    DatabaseException error,
    String messageId,
  ) {
    final message = error.toString().toLowerCase();
    if (message.contains('unique') || message.contains('primary key')) {
      return DuplicateEntityException('ChatMessage', messageId);
    }
    if (message.contains('foreign key') ||
        message.contains('check constraint') ||
        message.contains('constraint failed')) {
      return DataConflictException(
        'ChatMessage $messageId violates database constraints.',
      );
    }
    return DataConflictException('ChatMessage $messageId could not be saved.');
  }
}
