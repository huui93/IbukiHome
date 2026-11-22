import 'package:sqflite/sqflite.dart';

import '../../core/errors/data_exceptions.dart';
import '../../domain/characters/character_card.dart';
import '../repositories/character_repository.dart';
import 'ibuki_database.dart';
import 'sqlite_repository_helpers.dart';
import 'sqlite_value_codec.dart';

class SQLiteCharacterRepository implements CharacterRepository {
  SQLiteCharacterRepository(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;

  @override
  Future<List<CharacterCard>> listCharacters(
    String projectId, {
    bool includeDeleted = false,
  }) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'character_cards',
      where: activeWhere('project_id = ?', includeDeleted: includeDeleted),
      whereArgs: [projectId],
      orderBy: 'sort_order ASC, updated_at ASC, id ASC',
    );
    return List.unmodifiable(rows.map(characterCardFromSql));
  }

  @override
  Future<CharacterCard> getCharacter(String id) async {
    final database = await ibukiDatabase.database;
    final rows = await database.query(
      'character_cards',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw EntityNotFoundException('CharacterCard', id);
    }
    return characterCardFromSql(rows.single);
  }

  @override
  Future<void> upsertCharacter(CharacterCard character) async {
    final database = await ibukiDatabase.database;
    await _requireProject(database, character.projectId);
    final existing = await _getCharacterOrNull(database, character.id);
    if (existing != null && existing.projectId != character.projectId) {
      throw DataConflictException(
        'CharacterCard ${character.id} cannot move between projects.',
      );
    }
    await handleSqliteWrite(
      () async {
        if (existing == null) {
          await database.insert(
            'character_cards',
            characterCardToSql(character),
          );
          return;
        }
        final updatedRows = await database.update(
          'character_cards',
          characterCardToSql(character),
          where: 'id = ?',
          whereArgs: [character.id],
        );
        if (updatedRows != 1) {
          throw EntityNotFoundException('CharacterCard', character.id);
        }
      },
      entityName: 'CharacterCard',
      entityId: character.id,
    );
  }

  @override
  Future<void> softDeleteCharacter(String id, DateTime deletedAt) async {
    final character = await getCharacter(id);
    final deletedUtc = deletedAt.toUtc();
    await upsertCharacter(
      character.copyWith(
        metadata: character.metadata.copyWith(
          updatedAt: deletedUtc,
          revision: character.revision + 1,
          deletedAt: deletedUtc,
        ),
      ),
    );
  }

  @override
  Future<void> restoreCharacter(String id, DateTime updatedAt) async {
    final character = await getCharacter(id);
    final updatedUtc = updatedAt.toUtc();
    await upsertCharacter(
      character.copyWith(
        metadata: character.metadata.copyWith(
          updatedAt: updatedUtc,
          revision: character.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  @override
  Future<void> reorderCharacters({
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
            'character_cards',
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
UPDATE character_cards
SET sort_order = ?, updated_at = ?, revision = revision + 1
WHERE id = ? AND project_id = ? AND deleted_at IS NULL AND sort_order <> ?
''',
              [index, updated, orderedIds[index], projectId, index],
            );
          }
        });
      },
      entityName: 'CharacterCardOrder',
      entityId: projectId,
    );
  }

  void _validateOrderedIds(List<String> activeIds, List<String> orderedIds) {
    final expected = activeIds.toSet();
    final provided = orderedIds.toSet();
    if (orderedIds.length != provided.length ||
        expected.length != provided.length ||
        !expected.containsAll(provided)) {
      throw const DataConflictException('角色排序必须包含当前项目的全部有效角色，且不能重复。');
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

  Future<CharacterCard?> _getCharacterOrNull(
    DatabaseExecutor db,
    String id,
  ) async {
    final rows = await db.query(
      'character_cards',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : characterCardFromSql(rows.single);
  }
}
