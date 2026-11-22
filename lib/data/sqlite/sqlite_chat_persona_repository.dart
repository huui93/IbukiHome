import '../../core/errors/data_exceptions.dart';
import '../../domain/chat/chat_persona.dart';
import '../repositories/chat_persona_repository.dart';
import 'ibuki_database.dart';
import 'sqlite_repository_helpers.dart';
import 'sqlite_value_codec.dart';

class SQLiteChatPersonaRepository implements ChatPersonaRepository {
  SQLiteChatPersonaRepository(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;

  @override
  Future<List<ChatPersona>> listPersonas({bool includeDeleted = false}) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'chat_personas',
      where: includeDeleted ? null : 'deleted_at IS NULL',
      orderBy: 'name ASC, id ASC',
    );
    return List.unmodifiable(rows.map(chatPersonaFromSql));
  }

  @override
  Future<ChatPersona> getPersona(String id) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'chat_personas',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EntityNotFoundException('ChatPersona', id);
    }
    return chatPersonaFromSql(rows.single);
  }

  @override
  Future<void> upsertPersona(ChatPersona persona) async {
    final db = await ibukiDatabase.database;
    await handleSqliteWrite(
      () async {
        final values = chatPersonaToSql(persona);
        final updatedRows = await db.update(
          'chat_personas',
          values,
          where: 'id = ?',
          whereArgs: [persona.id],
        );
        if (updatedRows == 0) {
          await db.insert('chat_personas', values);
        }
      },
      entityName: 'ChatPersona',
      entityId: persona.id,
    );
  }

  @override
  Future<void> softDeletePersona(String id, DateTime deletedAt) async {
    final persona = await getPersona(id);
    if (persona.deletedAt != null) {
      return;
    }
    final now = deletedAt.toUtc();
    await upsertPersona(
      persona.copyWith(
        metadata: persona.metadata.copyWith(
          updatedAt: now,
          revision: persona.revision + 1,
          deletedAt: now,
        ),
      ),
    );
  }

  @override
  Future<void> restorePersona(String id, DateTime updatedAt) async {
    final persona = await getPersona(id);
    if (persona.deletedAt == null) {
      return;
    }
    final now = updatedAt.toUtc();
    await upsertPersona(
      persona.copyWith(
        metadata: persona.metadata.copyWith(
          updatedAt: now,
          revision: persona.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }
}
