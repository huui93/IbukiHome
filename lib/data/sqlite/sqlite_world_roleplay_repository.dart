import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/world_roleplay_repository.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';
import '../../domain/world_roleplay/world_roleplay_engine_models.dart';
import 'ibuki_database.dart';
import 'sqlite_repository_helpers.dart';

class SQLiteWorldRoleplayRepository implements WorldRoleplayRepository {
  SQLiteWorldRoleplayRepository(this.ibukiDatabase);

  final IbukiDatabase ibukiDatabase;
  static const _libraryWorldId = worldBookLibraryOwnerId;

  @override
  Future<List<RoleplayWorld>> listWorlds() async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        'roleplay_worlds',
        where: 'id != ?',
        whereArgs: [_libraryWorldId],
        orderBy: 'updated_at DESC, id ASC',
      ),
      _worldFromSql,
    );
  }

  @override
  Future<RoleplayWorld> getWorld(String id) =>
      _get('roleplay_worlds', id, 'World', _worldFromSql);

  @override
  Future<void> upsertWorld(RoleplayWorld world) => _upsert(
    'roleplay_worlds',
    _worldToSql(world),
    entityName: 'World',
    entityId: world.id,
  );

  @override
  Future<void> deleteWorld(String id) async {
    final db = await ibukiDatabase.database;
    await db.transaction((txn) async {
      await _ensureLibraryWorld(txn);
      await txn.update(
        'world_books',
        {'world_id': _libraryWorldId, 'is_primary': 0},
        where: 'world_id = ?',
        whereArgs: [id],
      );
      final count = await txn.delete(
        'roleplay_worlds',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (count == 0) throw EntityNotFoundException('World', id);
    });
  }

  @override
  Future<List<WorldSession>> listSessions(String worldId) async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        'world_sessions',
        where: 'world_id = ?',
        whereArgs: [worldId],
        orderBy: 'updated_at DESC, id ASC',
      ),
      _sessionFromSql,
    );
  }

  @override
  Future<WorldSession> getSession(String id) =>
      _get('world_sessions', id, 'WorldSession', _sessionFromSql);

  @override
  Future<void> upsertSession(WorldSession session) async {
    final playerInstanceId = session.currentPlayerInstanceId;
    if (playerInstanceId != null) {
      final instance = await getPlayerInstance(playerInstanceId);
      if (instance.worldSessionId != session.id) {
        throw const DataConflictException('当前玩家实例必须属于同一个世界存档。');
      }
    }
    await _upsert(
      'world_sessions',
      _sessionToSql(session),
      entityName: 'WorldSession',
      entityId: session.id,
    );
  }

  @override
  Future<void> deleteSession(String id) =>
      _delete('world_sessions', id, 'WorldSession');

  @override
  Future<List<WorldBook>> listWorldBooks(String worldId) async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        'world_books',
        where: 'world_id = ?',
        whereArgs: [worldId],
        orderBy: 'is_primary DESC, name ASC, id ASC',
      ),
      _bookFromSql,
    );
  }

  @override
  Future<List<WorldBook>> listWorldBookLibrary({String query = ''}) async {
    final db = await ibukiDatabase.database;
    final normalized = query.trim();
    final rows = normalized.isEmpty
        ? await db.query('world_books', orderBy: 'name ASC, id ASC')
        : await db.rawQuery('''SELECT DISTINCT b.* FROM world_books b
LEFT JOIN lore_entries l ON l.world_book_id = b.id
WHERE b.name LIKE ? OR l.title LIKE ? OR l.content LIKE ? OR l.keywords_json LIKE ?
ORDER BY b.name ASC, b.id ASC''', List.filled(4, '%$normalized%'));
    return _mapped(rows, _bookFromSql);
  }

  @override
  Future<WorldBook> getWorldBook(String id) =>
      _get('world_books', id, 'WorldBook', _bookFromSql);

  @override
  Future<void> upsertWorldBook(WorldBook book) async {
    if (book.worldId == null) {
      final db = await ibukiDatabase.database;
      await _ensureLibraryWorld(db);
    }
    await _upsert(
      'world_books',
      _bookToSql(book),
      entityName: 'WorldBook',
      entityId: book.id,
    );
  }

  @override
  Future<void> deleteWorldBook(String id) async {
    if (await countWorldBookReferences(id) > 0) {
      throw const DataConflictException('这本世界书仍被引用，请先解除引用。');
    }
    await _delete('world_books', id, 'WorldBook');
  }

  @override
  Future<List<WorldWorldBookReference>> listWorldBookReferences(
    String worldId,
  ) => _listWorldReferences('world_id = ?', [worldId]);

  @override
  Future<void> upsertWorldBookReference(WorldWorldBookReference reference) =>
      _upsert(
        'world_world_book_references',
        _worldReferenceToSql(reference),
        entityName: 'WorldBookReference',
        entityId: reference.id,
      );

  @override
  Future<void> deleteWorldBookReference(String id) =>
      _delete('world_world_book_references', id, 'WorldBookReference');

  @override
  Future<List<WorldSessionWorldBookOverride>> listWorldBookOverrides(
    String worldSessionId,
  ) async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        'world_session_world_book_overrides',
        where: 'world_session_id = ?',
        whereArgs: [worldSessionId],
        orderBy: 'priority DESC, world_book_id ASC',
      ),
      _worldBookOverrideFromSql,
    );
  }

  @override
  Future<void> upsertWorldBookOverride(
    WorldSessionWorldBookOverride override,
  ) => _upsert(
    'world_session_world_book_overrides',
    _worldBookOverrideToSql(override),
    entityName: 'WorldBookOverride',
    entityId: override.id,
  );

  @override
  Future<void> deleteWorldBookOverride(String id) =>
      _delete('world_session_world_book_overrides', id, 'WorldBookOverride');

  @override
  Future<List<EntityWorldBookReference>> listCharacterWorldBookReferences(
    String characterCardId,
  ) => _listEntityReferences(
    'character_world_book_references',
    'character_card_id',
    characterCardId,
  );

  @override
  Future<void> upsertCharacterWorldBookReference(
    EntityWorldBookReference reference,
  ) => _upsert(
    'character_world_book_references',
    _entityReferenceToSql(reference, 'character_card_id'),
    entityName: 'CharacterWorldBookReference',
    entityId: reference.id,
  );

  @override
  Future<void> deleteCharacterWorldBookReference(String id) => _delete(
    'character_world_book_references',
    id,
    'CharacterWorldBookReference',
  );

  @override
  Future<List<EntityWorldBookReference>> listPersonaWorldBookReferences(
    String playerPersonaId,
  ) => _listEntityReferences(
    'persona_world_book_references',
    'player_persona_id',
    playerPersonaId,
  );

  @override
  Future<void> upsertPersonaWorldBookReference(
    EntityWorldBookReference reference,
  ) => _upsert(
    'persona_world_book_references',
    _entityReferenceToSql(reference, 'player_persona_id'),
    entityName: 'PersonaWorldBookReference',
    entityId: reference.id,
  );

  @override
  Future<void> deletePersonaWorldBookReference(String id) =>
      _delete('persona_world_book_references', id, 'PersonaWorldBookReference');

  @override
  Future<int> countWorldBookReferences(String worldBookId) async {
    final db = await ibukiDatabase.database;
    var total = 0;
    for (final table in const [
      'world_world_book_references',
      'world_session_world_book_overrides',
      'character_world_book_references',
      'persona_world_book_references',
    ]) {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM $table WHERE world_book_id = ?',
        [worldBookId],
      );
      total += Sqflite.firstIntValue(rows) ?? 0;
    }
    return total;
  }

  Future<List<WorldWorldBookReference>> _listWorldReferences(
    String where,
    List<Object?> args,
  ) async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        'world_world_book_references',
        where: where,
        whereArgs: args,
        orderBy: 'priority DESC, world_book_id ASC',
      ),
      _worldReferenceFromSql,
    );
  }

  Future<List<EntityWorldBookReference>> _listEntityReferences(
    String table,
    String ownerColumn,
    String ownerId,
  ) async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        table,
        where: '$ownerColumn = ?',
        whereArgs: [ownerId],
        orderBy: 'priority DESC, world_book_id ASC',
      ),
      (row) => _entityReferenceFromSql(row, ownerColumn),
    );
  }

  Future<void> _ensureLibraryWorld(DatabaseExecutor db) async {
    final rows = await db.query(
      'roleplay_worlds',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [_libraryWorldId],
      limit: 1,
    );
    if (rows.isNotEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('roleplay_worlds', {
      'id': _libraryWorldId,
      'name': 'WorldBook Library',
      'description': '',
      'default_session_id': null,
      'metadata_json': '{"hidden":true}',
      'created_at': now,
      'updated_at': now,
      'revision': 1,
    });
  }

  @override
  Future<List<LoreEntry>> listLoreEntries(
    String worldBookId, {
    String query = '',
  }) async {
    final db = await ibukiDatabase.database;
    final normalized = query.trim();
    return _mapped(
      await db.query(
        'lore_entries',
        where: normalized.isEmpty
            ? 'world_book_id = ?'
            : 'world_book_id = ? AND (title LIKE ? OR content LIKE ?)',
        whereArgs: normalized.isEmpty
            ? [worldBookId]
            : [worldBookId, '%$normalized%', '%$normalized%'],
        orderBy: 'enabled DESC, priority DESC, title ASC, id ASC',
      ),
      _loreFromSql,
    );
  }

  @override
  Future<LoreEntry> getLoreEntry(String id) =>
      _get('lore_entries', id, 'LoreEntry', _loreFromSql);

  @override
  Future<void> upsertLoreEntry(LoreEntry entry) => _upsert(
    'lore_entries',
    _loreToSql(entry),
    entityName: 'LoreEntry',
    entityId: entry.id,
  );

  @override
  Future<void> deleteLoreEntry(String id) =>
      _delete('lore_entries', id, 'LoreEntry');

  @override
  Future<List<PlayerPersona>> listPersonas(String worldId) async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        'player_personas',
        where: 'world_id = ?',
        whereArgs: [worldId],
        orderBy: 'name ASC, id ASC',
      ),
      _personaFromSql,
    );
  }

  @override
  Future<PlayerPersona> getPersona(String id) =>
      _get('player_personas', id, 'PlayerPersona', _personaFromSql);

  @override
  Future<void> upsertPersona(PlayerPersona persona) => _upsert(
    'player_personas',
    _personaToSql(persona),
    entityName: 'PlayerPersona',
    entityId: persona.id,
  );

  @override
  Future<void> deletePersona(String id) =>
      _delete('player_personas', id, 'PlayerPersona');

  @override
  Future<List<WorldPlayerInstance>> listPlayerInstances(
    String worldSessionId,
  ) async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        'world_player_instances',
        where: 'world_session_id = ?',
        whereArgs: [worldSessionId],
        orderBy: 'is_active DESC, updated_at DESC, id ASC',
      ),
      _playerInstanceFromSql,
    );
  }

  @override
  Future<WorldPlayerInstance> getPlayerInstance(String id) => _get(
    'world_player_instances',
    id,
    'WorldPlayerInstance',
    _playerInstanceFromSql,
  );

  @override
  Future<void> upsertPlayerInstance(WorldPlayerInstance instance) async {
    final session = await getSession(instance.worldSessionId);
    final persona = await getPersona(instance.playerPersonaId);
    if (session.worldId != persona.worldId) {
      throw const DataConflictException('玩家身份定义与实例必须属于同一个世界。');
    }
    await _upsert(
      'world_player_instances',
      _playerInstanceToSql(instance),
      entityName: 'WorldPlayerInstance',
      entityId: instance.id,
    );
  }

  @override
  Future<void> deletePlayerInstance(String id) =>
      _delete('world_player_instances', id, 'WorldPlayerInstance');

  @override
  Future<List<WorldCharacterInstance>> listCharacterInstances(
    String worldSessionId,
  ) async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        'world_character_instances',
        where: 'world_session_id = ?',
        whereArgs: [worldSessionId],
        orderBy: 'is_active DESC, is_present DESC, updated_at DESC, id ASC',
      ),
      _characterInstanceFromSql,
    );
  }

  @override
  Future<WorldCharacterInstance> getCharacterInstance(String id) => _get(
    'world_character_instances',
    id,
    'WorldCharacterInstance',
    _characterInstanceFromSql,
  );

  @override
  Future<void> upsertCharacterInstance(WorldCharacterInstance instance) =>
      _upsert(
        'world_character_instances',
        _characterInstanceToSql(instance),
        entityName: 'WorldCharacterInstance',
        entityId: instance.id,
      );

  @override
  Future<void> deleteCharacterInstance(String id) =>
      _delete('world_character_instances', id, 'WorldCharacterInstance');

  @override
  Future<List<WorldScene>> listScenes(String worldSessionId) async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        'world_scenes',
        where: 'world_session_id = ?',
        whereArgs: [worldSessionId],
        orderBy: 'updated_at DESC, id ASC',
      ),
      _sceneFromSql,
    );
  }

  @override
  Future<WorldScene> getScene(String id) =>
      _get('world_scenes', id, 'WorldScene', _sceneFromSql);

  @override
  Future<void> upsertScene(WorldScene scene) => _upsert(
    'world_scenes',
    _sceneToSql(scene),
    entityName: 'WorldScene',
    entityId: scene.id,
  );

  @override
  Future<void> deleteScene(String id) =>
      _delete('world_scenes', id, 'WorldScene');

  @override
  Future<Set<String>> listSceneCast(String sceneId) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      'world_scene_cast',
      columns: ['character_instance_id'],
      where: 'scene_id = ?',
      whereArgs: [sceneId],
    );
    return Set.unmodifiable(
      rows.map((row) => row['character_instance_id']! as String),
    );
  }

  @override
  Future<void> setSceneCast(
    String sceneId,
    Set<String> characterInstanceIds,
  ) async {
    final db = await ibukiDatabase.database;
    await handleSqliteWrite(
      () async {
        await db.transaction((txn) async {
          final sceneRows = await txn.query(
            'world_scenes',
            columns: ['world_session_id'],
            where: 'id = ?',
            whereArgs: [sceneId],
            limit: 1,
          );
          if (sceneRows.isEmpty) {
            throw EntityNotFoundException('WorldScene', sceneId);
          }
          final sessionId = sceneRows.single['world_session_id']! as String;
          if (characterInstanceIds.isNotEmpty) {
            final placeholders = List.filled(
              characterInstanceIds.length,
              '?',
            ).join(',');
            final rows = await txn.rawQuery(
              'SELECT id FROM world_character_instances '
              'WHERE world_session_id = ? AND id IN ($placeholders)',
              [sessionId, ...characterInstanceIds],
            );
            if (rows.length != characterInstanceIds.length) {
              throw const DataConflictException('场景角色必须属于同一个世界存档。');
            }
          }
          await txn.delete(
            'world_scene_cast',
            where: 'scene_id = ?',
            whereArgs: [sceneId],
          );
          for (final id in characterInstanceIds) {
            await txn.insert('world_scene_cast', {
              'scene_id': sceneId,
              'character_instance_id': id,
            });
          }
          final now = DateTime.now().toUtc().toIso8601String();
          await txn.rawUpdate(
            'UPDATE world_character_instances SET is_present = 0, '
            'updated_at = ?, revision = revision + 1 '
            'WHERE world_session_id = ? AND is_present <> 0',
            [now, sessionId],
          );
          if (characterInstanceIds.isNotEmpty) {
            final placeholders = List.filled(
              characterInstanceIds.length,
              '?',
            ).join(',');
            await txn.rawUpdate(
              'UPDATE world_character_instances SET is_present = 1, '
              'updated_at = ?, revision = revision + 1 '
              'WHERE id IN ($placeholders) AND is_present <> 1',
              [now, ...characterInstanceIds],
            );
          }
        });
      },
      entityName: 'WorldSceneCast',
      entityId: sceneId,
    );
  }

  @override
  Future<List<WorldStateEntry>> listStateEntries(String worldSessionId) async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        'world_state_entries',
        where: 'world_session_id = ?',
        whereArgs: [worldSessionId],
        orderBy: 'state_key ASC, id ASC',
      ),
      _stateFromSql,
    );
  }

  @override
  Future<WorldStateEntry> getStateEntry(String id) =>
      _get('world_state_entries', id, 'WorldStateEntry', _stateFromSql);

  @override
  Future<void> upsertStateEntry(WorldStateEntry entry) => _upsert(
    'world_state_entries',
    _stateToSql(entry),
    entityName: 'WorldStateEntry',
    entityId: entry.id,
  );

  @override
  Future<void> deleteStateEntry(String id) =>
      _delete('world_state_entries', id, 'WorldStateEntry');

  @override
  Future<List<WorldRelationship>> listRelationships(
    String worldSessionId,
  ) async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        'world_relationships',
        where: 'world_session_id = ?',
        whereArgs: [worldSessionId],
        orderBy: 'updated_at DESC, id ASC',
      ),
      _relationshipFromSql,
    );
  }

  @override
  Future<WorldRelationship> getRelationship(String id) => _get(
    'world_relationships',
    id,
    'WorldRelationship',
    _relationshipFromSql,
  );

  @override
  Future<void> upsertRelationship(WorldRelationship relationship) => _upsert(
    'world_relationships',
    _relationshipToSql(relationship),
    entityName: 'WorldRelationship',
    entityId: relationship.id,
  );

  @override
  Future<void> deleteRelationship(String id) =>
      _delete('world_relationships', id, 'WorldRelationship');

  @override
  Future<List<WorldMemoryEntry>> listMemories(
    String worldSessionId, {
    String query = '',
  }) async {
    final db = await ibukiDatabase.database;
    final normalized = query.trim();
    return _mapped(
      await db.query(
        'world_memory_entries',
        where: normalized.isEmpty
            ? 'world_session_id = ?'
            : 'world_session_id = ? AND (summary LIKE ? OR content LIKE ?)',
        whereArgs: normalized.isEmpty
            ? [worldSessionId]
            : [worldSessionId, '%$normalized%', '%$normalized%'],
        orderBy: 'enabled DESC, importance DESC, created_at DESC, id ASC',
      ),
      _memoryFromSql,
    );
  }

  @override
  Future<WorldMemoryEntry> getMemory(String id) =>
      _get('world_memory_entries', id, 'WorldMemoryEntry', _memoryFromSql);

  @override
  Future<void> upsertMemory(WorldMemoryEntry memory) => _upsert(
    'world_memory_entries',
    _memoryToSql(memory),
    entityName: 'WorldMemoryEntry',
    entityId: memory.id,
  );

  @override
  Future<void> deleteMemory(String id) =>
      _delete('world_memory_entries', id, 'WorldMemoryEntry');

  @override
  Future<List<WorldTimelineEvent>> listTimelineEvents(
    String worldSessionId, {
    String query = '',
  }) async {
    final db = await ibukiDatabase.database;
    final normalized = query.trim();
    return _mapped(
      await db.query(
        'world_timeline_events',
        where: normalized.isEmpty
            ? 'world_session_id = ?'
            : 'world_session_id = ? AND (title LIKE ? OR description LIKE ?)',
        whereArgs: normalized.isEmpty
            ? [worldSessionId]
            : [worldSessionId, '%$normalized%', '%$normalized%'],
        orderBy: 'world_time ASC, created_at ASC, id ASC',
      ),
      _timelineFromSql,
    );
  }

  @override
  Future<WorldTimelineEvent> getTimelineEvent(String id) =>
      _get('world_timeline_events', id, 'WorldTimelineEvent', _timelineFromSql);

  @override
  Future<void> upsertTimelineEvent(WorldTimelineEvent event) => _upsert(
    'world_timeline_events',
    _timelineToSql(event),
    entityName: 'WorldTimelineEvent',
    entityId: event.id,
  );

  @override
  Future<void> deleteTimelineEvent(String id) =>
      _delete('world_timeline_events', id, 'WorldTimelineEvent');

  @override
  Future<List<WorldBranch>> listBranches(String worldSessionId) async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        'world_branches',
        where: 'world_session_id = ?',
        whereArgs: [worldSessionId],
        orderBy: 'is_current DESC, created_at ASC, id ASC',
      ),
      _branchFromSql,
    );
  }

  @override
  Future<WorldBranch> getBranch(String id) =>
      _get('world_branches', id, 'WorldBranch', _branchFromSql);

  @override
  Future<void> upsertBranch(WorldBranch branch) => _upsert(
    'world_branches',
    _branchToSql(branch),
    entityName: 'WorldBranch',
    entityId: branch.id,
  );

  @override
  Future<void> setCurrentBranch(String worldSessionId, String branchId) async {
    final db = await ibukiDatabase.database;
    await handleSqliteWrite(
      () async {
        await db.transaction((txn) async {
          final rows = await txn.query(
            'world_branches',
            columns: ['id'],
            where: 'id = ? AND world_session_id = ?',
            whereArgs: [branchId, worldSessionId],
            limit: 1,
          );
          if (rows.isEmpty) {
            throw EntityNotFoundException('WorldBranch', branchId);
          }
          final now = DateTime.now().toUtc().toIso8601String();
          await txn.rawUpdate(
            'UPDATE world_branches SET is_current = 0, updated_at = ?, '
            'revision = revision + 1 '
            'WHERE world_session_id = ? AND is_current = 1',
            [now, worldSessionId],
          );
          await txn.rawUpdate(
            'UPDATE world_branches SET is_current = 1, updated_at = ?, '
            'revision = revision + 1 WHERE id = ?',
            [now, branchId],
          );
          await txn.rawUpdate(
            'UPDATE world_sessions SET current_branch_id = ?, '
            'updated_at = ?, revision = revision + 1 WHERE id = ?',
            [branchId, now, worldSessionId],
          );
        });
      },
      entityName: 'WorldBranch',
      entityId: branchId,
    );
  }

  @override
  Future<void> deleteBranch(String id) =>
      _delete('world_branches', id, 'WorldBranch');

  @override
  Future<List<WorldFeedEntry>> listFeedEntries(
    String worldSessionId, {
    String? branchId,
    int? limit,
  }) async {
    final db = await ibukiDatabase.database;
    if (branchId != null) {
      final entries = await _listBranchFeed(
        db,
        worldSessionId,
        branchId,
        visited: <String>{},
      );
      if (limit == null || entries.length <= limit) return entries;
      return List.unmodifiable(entries.sublist(entries.length - limit));
    }
    final rows = await db.query(
      'world_feed_entries',
      where: 'world_session_id = ?',
      whereArgs: [worldSessionId],
      orderBy: limit == null
          ? 'created_at ASC, id ASC'
          : 'created_at DESC, id DESC',
      limit: limit,
    );
    final result = rows.map(_feedFromSql).toList(growable: false);
    if (limit != null) return List.unmodifiable(result.reversed);
    return List.unmodifiable(result);
  }

  @override
  Future<void> upsertFeedEntry(WorldFeedEntry entry) => _upsert(
    'world_feed_entries',
    _feedToSql(entry),
    entityName: 'WorldFeedEntry',
    entityId: entry.id,
  );

  @override
  Future<void> deleteFeedEntry(String id) =>
      _delete('world_feed_entries', id, 'WorldFeedEntry');

  @override
  Future<List<WorldTurn>> listTurns(String worldSessionId, {int? limit}) async {
    final db = await ibukiDatabase.database;
    return _mapped(
      await db.query(
        'world_turns',
        where: 'world_session_id = ?',
        whereArgs: [worldSessionId],
        orderBy: 'created_at DESC, id ASC',
        limit: limit,
      ),
      _turnFromSql,
    );
  }

  @override
  Future<WorldTurn> getTurn(String id) =>
      _get('world_turns', id, 'WorldTurn', _turnFromSql);

  @override
  Future<void> upsertTurn(WorldTurn turn) => _upsert(
    'world_turns',
    _turnToSql(turn),
    entityName: 'WorldTurn',
    entityId: turn.id,
  );

  @override
  Future<void> commitWorldMutation(WorldMutationCommit commit) async {
    final db = await ibukiDatabase.database;
    await handleSqliteWrite(
      () => db.transaction((txn) async {
        Future<void> requireSessionEntity(String table, String id) async {
          final rows = await txn.query(
            table,
            columns: const ['world_session_id'],
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
          if (rows.isEmpty ||
              rows.single['world_session_id'] != commit.worldSessionId) {
            throw const DataConflictException('世界变化不能修改其它世界存档的数据。');
          }
        }

        final session = commit.session;
        if (session != null) {
          if (session.id != commit.worldSessionId) {
            throw const DataConflictException('世界存档变更范围无效。');
          }
          await _upsertTxn(txn, 'world_sessions', _sessionToSql(session));
        }
        final scene = commit.scene;
        if (scene != null) {
          if (scene.worldSessionId != commit.worldSessionId) {
            throw const DataConflictException('场景变更范围无效。');
          }
          await _upsertTxn(txn, 'world_scenes', _sceneToSql(scene));
        }
        for (final character in commit.characterInstances) {
          if (character.worldSessionId != commit.worldSessionId) {
            throw const DataConflictException('角色实例变更范围无效。');
          }
          await _upsertTxn(
            txn,
            'world_character_instances',
            _characterInstanceToSql(character),
          );
        }
        final player = commit.playerInstance;
        if (player != null) {
          if (player.worldSessionId != commit.worldSessionId) {
            throw const DataConflictException('玩家实例变更范围无效。');
          }
          await _upsertTxn(
            txn,
            'world_player_instances',
            _playerInstanceToSql(player),
          );
        }
        for (final state in commit.stateUpserts) {
          if (state.worldSessionId != commit.worldSessionId) {
            throw const DataConflictException('世界状态变更范围无效。');
          }
          await _upsertTxn(txn, 'world_state_entries', _stateToSql(state));
        }
        for (final id in commit.stateDeleteIds) {
          await requireSessionEntity('world_state_entries', id);
          await txn.delete(
            'world_state_entries',
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        for (final relationship in commit.relationshipUpserts) {
          if (relationship.worldSessionId != commit.worldSessionId) {
            throw const DataConflictException('人物关系变更范围无效。');
          }
          await _upsertTxn(
            txn,
            'world_relationships',
            _relationshipToSql(relationship),
          );
        }
        for (final memory in commit.memories) {
          if (memory.worldSessionId != commit.worldSessionId) {
            throw const DataConflictException('世界记忆变更范围无效。');
          }
          await _upsertTxn(txn, 'world_memory_entries', _memoryToSql(memory));
        }
        for (final event in commit.timelineEvents) {
          if (event.worldSessionId != commit.worldSessionId) {
            throw const DataConflictException('时间线变更范围无效。');
          }
          await _upsertTxn(txn, 'world_timeline_events', _timelineToSql(event));
        }
        if (scene != null && commit.sceneCast != null) {
          await txn.delete(
            'world_scene_cast',
            where: 'scene_id = ?',
            whereArgs: [scene.id],
          );
          for (final characterId in commit.sceneCast!) {
            await requireSessionEntity(
              'world_character_instances',
              characterId,
            );
            await txn.insert('world_scene_cast', {
              'scene_id': scene.id,
              'character_instance_id': characterId,
            });
          }
        }
        if (commit.turn.worldSessionId != commit.worldSessionId) {
          throw const DataConflictException('世界回合变更范围无效。');
        }
        await _upsertTxn(txn, 'world_turns', _turnToSql(commit.turn));
      }),
      entityName: 'WorldTurn',
      entityId: commit.turn.id,
    );
  }

  Future<List<WorldFeedEntry>> _listBranchFeed(
    DatabaseExecutor db,
    String worldSessionId,
    String branchId, {
    required Set<String> visited,
  }) async {
    if (!visited.add(branchId)) {
      throw const DataConflictException('世界线父级关系存在循环。');
    }
    final branchRows = await db.query(
      'world_branches',
      where: 'id = ? AND world_session_id = ?',
      whereArgs: [branchId, worldSessionId],
      limit: 1,
    );
    if (branchRows.isEmpty) {
      throw EntityNotFoundException('WorldBranch', branchId);
    }
    final branch = _branchFromSql(branchRows.single);
    var inherited = <WorldFeedEntry>[];
    if (branch.parentBranchId != null &&
        branch.metadata['inheritParentFeed'] != false) {
      inherited = (await _listBranchFeed(
        db,
        worldSessionId,
        branch.parentBranchId!,
        visited: visited,
      )).toList(growable: true);
      final pointId = branch.branchPointMessageId;
      if (pointId != null) {
        final pointIndex = inherited.indexWhere((entry) => entry.id == pointId);
        if (pointIndex >= 0) {
          inherited = inherited.sublist(0, pointIndex + 1);
        }
      }
    }
    final own = _mapped(
      await db.query(
        'world_feed_entries',
        where: 'world_session_id = ? AND branch_id = ?',
        whereArgs: [worldSessionId, branchId],
        orderBy: 'created_at ASC, id ASC',
      ),
      _feedFromSql,
    );
    return List.unmodifiable([...inherited, ...own]);
  }

  @override
  Future<WorldDatabaseCounts> getDatabaseCounts(String worldSessionId) async {
    final db = await ibukiDatabase.database;
    final session = await getSession(worldSessionId);
    Future<int> count(String table, String where, List<Object?> args) async {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM $table WHERE $where',
        args,
      );
      return Sqflite.firstIntValue(rows) ?? 0;
    }

    return WorldDatabaseCounts(
      characterInstances: await count(
        'world_character_instances',
        'world_session_id = ?',
        [worldSessionId],
      ),
      loreEntries: await count(
        'lore_entries',
        'world_book_id IN (SELECT id FROM world_books WHERE world_id = ?)',
        [session.worldId],
      ),
      personas: await count('player_personas', 'world_id = ?', [
        session.worldId,
      ]),
      playerInstances: await count(
        'world_player_instances',
        'world_session_id = ?',
        [worldSessionId],
      ),
      scenes: await count('world_scenes', 'world_session_id = ?', [
        worldSessionId,
      ]),
      stateEntries: await count('world_state_entries', 'world_session_id = ?', [
        worldSessionId,
      ]),
      relationships: await count(
        'world_relationships',
        'world_session_id = ?',
        [worldSessionId],
      ),
      memories: await count('world_memory_entries', 'world_session_id = ?', [
        worldSessionId,
      ]),
      timelineEvents: await count(
        'world_timeline_events',
        'world_session_id = ?',
        [worldSessionId],
      ),
      branches: await count('world_branches', 'world_session_id = ?', [
        worldSessionId,
      ]),
      feedEntries: await count('world_feed_entries', 'world_session_id = ?', [
        worldSessionId,
      ]),
      pluginBindings: await count('plugin_storage', 'value_json LIKE ?', [
        '%"worldSession"%$worldSessionId%',
      ]),
    );
  }

  @override
  Future<List<WorldSearchResult>> searchWorldDatabase(
    String worldSessionId,
    String query,
  ) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    final db = await ibukiDatabase.database;
    final session = await getSession(worldSessionId);
    final like = '%$normalized%';
    final results = <WorldSearchResult>[];

    Future<void> collect({
      required String sql,
      required List<Object?> args,
      required String type,
      required String titleKey,
      required String previewKey,
    }) async {
      for (final row in await db.rawQuery(sql, args)) {
        results.add(
          WorldSearchResult(
            type: type,
            id: row['id']! as String,
            title: row[titleKey]! as String,
            preview: row[previewKey]! as String,
          ),
        );
      }
    }

    await collect(
      sql:
          'SELECT id, title, content FROM lore_entries WHERE '
          'world_book_id IN (SELECT id FROM world_books WHERE world_id = ?) '
          'AND (title LIKE ? OR content LIKE ?) LIMIT 30',
      args: [session.worldId, like, like],
      type: 'lore',
      titleKey: 'title',
      previewKey: 'content',
    );
    await collect(
      sql:
          'SELECT i.id, COALESCE(i.display_name_override, c.name) AS title, '
          'i.current_status AS preview FROM world_character_instances i '
          'JOIN character_cards c ON c.id = i.character_card_id '
          'WHERE i.world_session_id = ? AND '
          '(c.name LIKE ? OR i.display_name_override LIKE ? OR i.current_status LIKE ?) LIMIT 30',
      args: [worldSessionId, like, like, like],
      type: 'character',
      titleKey: 'title',
      previewKey: 'preview',
    );
    await collect(
      sql:
          'SELECT id, summary AS title, content FROM world_memory_entries '
          'WHERE world_session_id = ? AND (summary LIKE ? OR content LIKE ?) LIMIT 30',
      args: [worldSessionId, like, like],
      type: 'memory',
      titleKey: 'title',
      previewKey: 'content',
    );
    await collect(
      sql:
          'SELECT id, title, description FROM world_timeline_events '
          'WHERE world_session_id = ? AND (title LIKE ? OR description LIKE ?) LIMIT 30',
      args: [worldSessionId, like, like],
      type: 'timeline',
      titleKey: 'title',
      previewKey: 'description',
    );
    await collect(
      sql:
          'SELECT id, state_key AS title, value_json AS preview '
          'FROM world_state_entries WHERE world_session_id = ? '
          'AND state_key LIKE ? LIMIT 30',
      args: [worldSessionId, like],
      type: 'state',
      titleKey: 'title',
      previewKey: 'preview',
    );
    await collect(
      sql:
          'SELECT id, name AS title, description FROM world_scenes '
          'WHERE world_session_id = ? AND (name LIKE ? OR description LIKE ?) LIMIT 30',
      args: [worldSessionId, like, like],
      type: 'scene',
      titleKey: 'title',
      previewKey: 'description',
    );
    return List.unmodifiable(results.take(100));
  }

  Future<T> _get<T>(
    String table,
    String id,
    String entityName,
    T Function(Map<String, Object?>) mapper,
  ) async {
    final db = await ibukiDatabase.database;
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw EntityNotFoundException(entityName, id);
    return mapper(rows.single);
  }

  Future<void> _upsert(
    String table,
    Map<String, Object?> values, {
    required String entityName,
    required String entityId,
  }) async {
    final db = await ibukiDatabase.database;
    await handleSqliteWrite(
      () async {
        final existing = await db.query(
          table,
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [entityId],
          limit: 1,
        );
        if (existing.isEmpty) {
          await db.insert(table, values);
        } else {
          final update = Map<String, Object?>.from(values)..remove('id');
          await db.update(
            table,
            update,
            where: 'id = ?',
            whereArgs: [entityId],
          );
        }
      },
      entityName: entityName,
      entityId: entityId,
    );
  }

  Future<void> _delete(String table, String id, String entityName) async {
    final db = await ibukiDatabase.database;
    await handleSqliteWrite(
      () async {
        final changed = await db.delete(
          table,
          where: 'id = ?',
          whereArgs: [id],
        );
        if (changed == 0) throw EntityNotFoundException(entityName, id);
      },
      entityName: entityName,
      entityId: id,
    );
  }
}

List<T> _mapped<T>(
  List<Map<String, Object?>> rows,
  T Function(Map<String, Object?>) mapper,
) => List.unmodifiable(rows.map(mapper));

Map<String, Object?> _entityToSql(WorldRoleplayEntity value) => {
  'id': value.id,
  'created_at': value.createdAt.toUtc().toIso8601String(),
  'updated_at': value.updatedAt.toUtc().toIso8601String(),
  'revision': value.revision,
  'metadata_json': jsonEncode(value.metadata),
};

EntityMetadata _entityFromSql(Map<String, Object?> row, String model) {
  return EntityMetadata(
    id: _string(row, 'id', model),
    createdAt: _date(row, 'created_at', model),
    updatedAt: _date(row, 'updated_at', model),
    revision: _int(row, 'revision', model),
  );
}

Map<String, Object?> _metadata(Map<String, Object?> row, String model) {
  final decoded = jsonDecode(_string(row, 'metadata_json', model));
  if (decoded is! Map) {
    throw DataFormatException('$model.metadata_json must be an object.');
  }
  return Map.unmodifiable(Map<String, Object?>.from(decoded));
}

List<String> _stringsJson(Map<String, Object?> row, String key, String model) {
  final decoded = jsonDecode(_string(row, key, model));
  if (decoded is! List || decoded.any((item) => item is! String)) {
    throw DataFormatException('$model.$key must be a string list.');
  }
  return List.unmodifiable(decoded.cast<String>());
}

Map<String, Object?> _mapJson(
  Map<String, Object?> row,
  String key,
  String model,
) {
  final decoded = jsonDecode(_string(row, key, model));
  if (decoded is! Map) {
    throw DataFormatException('$model.$key must be an object.');
  }
  return Map.unmodifiable(Map<String, Object?>.from(decoded));
}

Map<String, Object?> _worldToSql(RoleplayWorld value) => {
  ..._entityToSql(value),
  'name': value.name,
  'description': value.description,
  'default_session_id': value.defaultSessionId,
};

RoleplayWorld _worldFromSql(Map<String, Object?> row) => RoleplayWorld(
  entity: _entityFromSql(row, 'World'),
  name: _string(row, 'name', 'World'),
  description: _string(row, 'description', 'World'),
  defaultSessionId: _nullableString(row, 'default_session_id', 'World'),
  metadata: _metadata(row, 'World'),
);

Map<String, Object?> _sessionToSql(WorldSession value) => {
  ..._entityToSql(value),
  'world_id': value.worldId,
  'name': value.name,
  'current_player_instance_id': value.currentPlayerInstanceId,
  'current_scene_id': value.currentSceneId,
  'current_branch_id': value.currentBranchId,
  'world_time': value.worldTime,
  'ai_provider_config_id': value.aiProviderConfigId,
  'ai_model': value.aiModel,
  'lore_context_budget': value.loreContextBudget,
  'speaker_mode': value.speakerMode.name,
};

WorldSession _sessionFromSql(Map<String, Object?> row) => WorldSession(
  entity: _entityFromSql(row, 'WorldSession'),
  worldId: _string(row, 'world_id', 'WorldSession'),
  name: _string(row, 'name', 'WorldSession'),
  currentPlayerInstanceId: _nullableString(
    row,
    'current_player_instance_id',
    'WorldSession',
  ),
  currentSceneId: _nullableString(row, 'current_scene_id', 'WorldSession'),
  currentBranchId: _nullableString(row, 'current_branch_id', 'WorldSession'),
  worldTime: _string(row, 'world_time', 'WorldSession'),
  aiProviderConfigId: _nullableString(
    row,
    'ai_provider_config_id',
    'WorldSession',
  ),
  aiModel: _nullableString(row, 'ai_model', 'WorldSession'),
  loreContextBudget: _int(row, 'lore_context_budget', 'WorldSession'),
  speakerMode: WorldSpeakerMode.values.firstWhere(
    (value) => value.name == _string(row, 'speaker_mode', 'WorldSession'),
  ),
  metadata: _metadata(row, 'WorldSession'),
);

Map<String, Object?> _bookToSql(WorldBook value) => {
  ..._entityToSql(value),
  'world_id': value.worldId ?? SQLiteWorldRoleplayRepository._libraryWorldId,
  'name': value.name,
  'is_primary': value.isPrimary ? 1 : 0,
};

WorldBook _bookFromSql(Map<String, Object?> row) => WorldBook(
  entity: _entityFromSql(row, 'WorldBook'),
  worldId:
      _string(row, 'world_id', 'WorldBook') ==
          SQLiteWorldRoleplayRepository._libraryWorldId
      ? null
      : _string(row, 'world_id', 'WorldBook'),
  name: _string(row, 'name', 'WorldBook'),
  isPrimary: _bool(row, 'is_primary', 'WorldBook'),
  metadata: _metadata(row, 'WorldBook'),
);

Map<String, Object?> _worldReferenceToSql(WorldWorldBookReference value) => {
  ..._entityToSql(value),
  'world_id': value.worldId,
  'world_book_id': value.worldBookId,
  'enabled': value.enabled ? 1 : 0,
  'priority': value.priority,
};

WorldWorldBookReference _worldReferenceFromSql(Map<String, Object?> row) =>
    WorldWorldBookReference(
      entity: _entityFromSql(row, 'WorldBookReference'),
      worldId: _string(row, 'world_id', 'WorldBookReference'),
      worldBookId: _string(row, 'world_book_id', 'WorldBookReference'),
      enabled: _bool(row, 'enabled', 'WorldBookReference'),
      priority: _int(row, 'priority', 'WorldBookReference'),
      metadata: _metadata(row, 'WorldBookReference'),
    );

Map<String, Object?> _worldBookOverrideToSql(
  WorldSessionWorldBookOverride value,
) => {
  ..._entityToSql(value),
  'world_session_id': value.worldSessionId,
  'world_book_id': value.worldBookId,
  'override_mode': value.mode.name,
  'priority': value.priority,
};

WorldSessionWorldBookOverride _worldBookOverrideFromSql(
  Map<String, Object?> row,
) => WorldSessionWorldBookOverride(
  entity: _entityFromSql(row, 'WorldBookOverride'),
  worldSessionId: _string(row, 'world_session_id', 'WorldBookOverride'),
  worldBookId: _string(row, 'world_book_id', 'WorldBookOverride'),
  mode: WorldBookOverrideMode.values.firstWhere(
    (value) => value.name == _string(row, 'override_mode', 'WorldBookOverride'),
  ),
  priority: _int(row, 'priority', 'WorldBookOverride'),
  metadata: _metadata(row, 'WorldBookOverride'),
);

Map<String, Object?> _entityReferenceToSql(
  EntityWorldBookReference value,
  String ownerColumn,
) => {
  ..._entityToSql(value),
  ownerColumn: value.entityId,
  'world_book_id': value.worldBookId,
  'enabled': value.enabled ? 1 : 0,
  'priority': value.priority,
};

EntityWorldBookReference _entityReferenceFromSql(
  Map<String, Object?> row,
  String ownerColumn,
) => EntityWorldBookReference(
  entity: _entityFromSql(row, 'EntityWorldBookReference'),
  entityId: _string(row, ownerColumn, 'EntityWorldBookReference'),
  worldBookId: _string(row, 'world_book_id', 'EntityWorldBookReference'),
  enabled: _bool(row, 'enabled', 'EntityWorldBookReference'),
  priority: _int(row, 'priority', 'EntityWorldBookReference'),
  metadata: _metadata(row, 'EntityWorldBookReference'),
);

Map<String, Object?> _loreToSql(LoreEntry value) => {
  ..._entityToSql(value),
  'world_book_id': value.worldBookId,
  'title': value.title,
  'content': value.content,
  'keywords_json': jsonEncode(value.keywords),
  'secondary_keywords_json': jsonEncode(value.secondaryKeywords),
  'enabled': value.enabled ? 1 : 0,
  'priority': value.priority,
  'activation_mode': value.activationMode.name,
  'insertion_position': value.insertionPosition,
  'probability': value.probability,
  'scope': value.scope,
  'token_budget_hint': value.tokenBudgetHint,
  'source_world_card_id': value.sourceWorldCardId,
};

LoreEntry _loreFromSql(Map<String, Object?> row) => LoreEntry(
  entity: _entityFromSql(row, 'LoreEntry'),
  worldBookId: _string(row, 'world_book_id', 'LoreEntry'),
  title: _string(row, 'title', 'LoreEntry'),
  content: _string(row, 'content', 'LoreEntry'),
  keywords: _stringsJson(row, 'keywords_json', 'LoreEntry'),
  secondaryKeywords: _stringsJson(row, 'secondary_keywords_json', 'LoreEntry'),
  enabled: _bool(row, 'enabled', 'LoreEntry'),
  priority: _int(row, 'priority', 'LoreEntry'),
  activationMode: LoreActivationMode.values.firstWhere(
    (item) => item.name == _string(row, 'activation_mode', 'LoreEntry'),
  ),
  insertionPosition: _string(row, 'insertion_position', 'LoreEntry'),
  probability: _double(row, 'probability', 'LoreEntry'),
  scope: _string(row, 'scope', 'LoreEntry'),
  tokenBudgetHint: _nullableInt(row, 'token_budget_hint', 'LoreEntry'),
  sourceWorldCardId: _nullableString(row, 'source_world_card_id', 'LoreEntry'),
  metadata: _metadata(row, 'LoreEntry'),
);

Map<String, Object?> _personaToSql(PlayerPersona value) => {
  ..._entityToSql(value),
  'world_id': value.worldId,
  'name': value.name,
  'description': value.description,
  'appearance': value.appearance,
  'background': value.background,
  'notes': value.notes,
  'avatar_reference': value.avatarReference,
};

PlayerPersona _personaFromSql(Map<String, Object?> row) => PlayerPersona(
  entity: _entityFromSql(row, 'PlayerPersona'),
  worldId: _string(row, 'world_id', 'PlayerPersona'),
  name: _string(row, 'name', 'PlayerPersona'),
  description: _string(row, 'description', 'PlayerPersona'),
  appearance: _string(row, 'appearance', 'PlayerPersona'),
  background: _string(row, 'background', 'PlayerPersona'),
  notes: _string(row, 'notes', 'PlayerPersona'),
  avatarReference: _nullableString(row, 'avatar_reference', 'PlayerPersona'),
  metadata: _metadata(row, 'PlayerPersona'),
);

Map<String, Object?> _playerInstanceToSql(WorldPlayerInstance value) => {
  ..._entityToSql(value),
  'world_session_id': value.worldSessionId,
  'player_persona_id': value.playerPersonaId,
  'display_name_override': value.displayNameOverride,
  'current_location': value.currentLocation,
  'current_status': value.currentStatus,
  'current_mood': value.currentMood,
  'current_goal': value.currentGoal,
  'is_active': value.isActive ? 1 : 0,
  'last_active_at': value.lastActiveAt?.toUtc().toIso8601String(),
};

WorldPlayerInstance _playerInstanceFromSql(Map<String, Object?> row) =>
    WorldPlayerInstance(
      entity: _entityFromSql(row, 'WorldPlayerInstance'),
      worldSessionId: _string(row, 'world_session_id', 'WorldPlayerInstance'),
      playerPersonaId: _string(row, 'player_persona_id', 'WorldPlayerInstance'),
      displayNameOverride: _nullableString(
        row,
        'display_name_override',
        'WorldPlayerInstance',
      ),
      currentLocation: _string(row, 'current_location', 'WorldPlayerInstance'),
      currentStatus: _string(row, 'current_status', 'WorldPlayerInstance'),
      currentMood: _string(row, 'current_mood', 'WorldPlayerInstance'),
      currentGoal: _string(row, 'current_goal', 'WorldPlayerInstance'),
      isActive: _bool(row, 'is_active', 'WorldPlayerInstance'),
      lastActiveAt: _nullableDate(row, 'last_active_at', 'WorldPlayerInstance'),
      metadata: _metadata(row, 'WorldPlayerInstance'),
    );

Map<String, Object?> _characterInstanceToSql(WorldCharacterInstance value) => {
  ..._entityToSql(value),
  'world_session_id': value.worldSessionId,
  'character_card_id': value.characterCardId,
  'display_name_override': value.displayNameOverride,
  'current_location': value.currentLocation,
  'current_status': value.currentStatus,
  'current_mood': value.currentMood,
  'current_goal': value.currentGoal,
  'is_present': value.isPresent ? 1 : 0,
  'is_active': value.isActive ? 1 : 0,
  'last_active_at': value.lastActiveAt?.toUtc().toIso8601String(),
};

WorldCharacterInstance _characterInstanceFromSql(
  Map<String, Object?> row,
) => WorldCharacterInstance(
  entity: _entityFromSql(row, 'WorldCharacterInstance'),
  worldSessionId: _string(row, 'world_session_id', 'WorldCharacterInstance'),
  characterCardId: _string(row, 'character_card_id', 'WorldCharacterInstance'),
  displayNameOverride: _nullableString(
    row,
    'display_name_override',
    'WorldCharacterInstance',
  ),
  currentLocation: _string(row, 'current_location', 'WorldCharacterInstance'),
  currentStatus: _string(row, 'current_status', 'WorldCharacterInstance'),
  currentMood: _string(row, 'current_mood', 'WorldCharacterInstance'),
  currentGoal: _string(row, 'current_goal', 'WorldCharacterInstance'),
  isPresent: _bool(row, 'is_present', 'WorldCharacterInstance'),
  isActive: _bool(row, 'is_active', 'WorldCharacterInstance'),
  lastActiveAt: _nullableDate(row, 'last_active_at', 'WorldCharacterInstance'),
  metadata: _metadata(row, 'WorldCharacterInstance'),
);

Map<String, Object?> _sceneToSql(WorldScene value) => {
  ..._entityToSql(value),
  'world_session_id': value.worldSessionId,
  'name': value.name,
  'description': value.description,
  'location': value.location,
  'time_text': value.timeText,
  'weather': value.weather,
  'atmosphere': value.atmosphere,
  'current_event': value.currentEvent,
  'notes': value.notes,
};

WorldScene _sceneFromSql(Map<String, Object?> row) => WorldScene(
  entity: _entityFromSql(row, 'WorldScene'),
  worldSessionId: _string(row, 'world_session_id', 'WorldScene'),
  name: _string(row, 'name', 'WorldScene'),
  description: _string(row, 'description', 'WorldScene'),
  location: _string(row, 'location', 'WorldScene'),
  timeText: _string(row, 'time_text', 'WorldScene'),
  weather: _string(row, 'weather', 'WorldScene'),
  atmosphere: _string(row, 'atmosphere', 'WorldScene'),
  currentEvent: _string(row, 'current_event', 'WorldScene'),
  notes: _string(row, 'notes', 'WorldScene'),
  metadata: _metadata(row, 'WorldScene'),
);

Map<String, Object?> _stateToSql(WorldStateEntry value) => {
  ..._entityToSql(value),
  'world_session_id': value.worldSessionId,
  'state_key': value.key,
  'value_json': jsonEncode(value.value),
  'category': value.category,
  'source': value.source,
};

WorldStateEntry _stateFromSql(Map<String, Object?> row) => WorldStateEntry(
  entity: _entityFromSql(row, 'WorldStateEntry'),
  worldSessionId: _string(row, 'world_session_id', 'WorldStateEntry'),
  key: _string(row, 'state_key', 'WorldStateEntry'),
  value: jsonDecode(_string(row, 'value_json', 'WorldStateEntry')),
  category: _string(row, 'category', 'WorldStateEntry'),
  source: _string(row, 'source', 'WorldStateEntry'),
  metadata: _metadata(row, 'WorldStateEntry'),
);

Map<String, Object?> _relationshipToSql(WorldRelationship value) => {
  ..._entityToSql(value),
  'world_session_id': value.worldSessionId,
  'source_entity_type': value.sourceEntityType,
  'source_entity_id': value.sourceEntityId,
  'target_entity_type': value.targetEntityType,
  'target_entity_id': value.targetEntityId,
  'relation_type': value.relationType,
  'summary': value.summary,
  'state_json': jsonEncode(value.state),
};

WorldRelationship _relationshipFromSql(Map<String, Object?> row) =>
    WorldRelationship(
      entity: _entityFromSql(row, 'WorldRelationship'),
      worldSessionId: _string(row, 'world_session_id', 'WorldRelationship'),
      sourceEntityType: _string(row, 'source_entity_type', 'WorldRelationship'),
      sourceEntityId: _string(row, 'source_entity_id', 'WorldRelationship'),
      targetEntityType: _string(row, 'target_entity_type', 'WorldRelationship'),
      targetEntityId: _string(row, 'target_entity_id', 'WorldRelationship'),
      relationType: _string(row, 'relation_type', 'WorldRelationship'),
      summary: _string(row, 'summary', 'WorldRelationship'),
      state: _mapJson(row, 'state_json', 'WorldRelationship'),
      metadata: _metadata(row, 'WorldRelationship'),
    );

Map<String, Object?> _memoryToSql(WorldMemoryEntry value) => {
  ..._entityToSql(value),
  'world_session_id': value.worldSessionId,
  'memory_type': value.type,
  'summary': value.summary,
  'content': value.content,
  'importance': value.importance,
  'related_character_ids_json': jsonEncode(value.relatedCharacterIds),
  'related_scene_id': value.relatedSceneId,
  'last_referenced_at': value.lastReferencedAt?.toUtc().toIso8601String(),
  'enabled': value.enabled ? 1 : 0,
};

WorldMemoryEntry _memoryFromSql(Map<String, Object?> row) => WorldMemoryEntry(
  entity: _entityFromSql(row, 'WorldMemoryEntry'),
  worldSessionId: _string(row, 'world_session_id', 'WorldMemoryEntry'),
  type: _string(row, 'memory_type', 'WorldMemoryEntry'),
  summary: _string(row, 'summary', 'WorldMemoryEntry'),
  content: _string(row, 'content', 'WorldMemoryEntry'),
  importance: _double(row, 'importance', 'WorldMemoryEntry'),
  relatedCharacterIds: _stringsJson(
    row,
    'related_character_ids_json',
    'WorldMemoryEntry',
  ),
  relatedSceneId: _nullableString(row, 'related_scene_id', 'WorldMemoryEntry'),
  lastReferencedAt: _nullableDate(
    row,
    'last_referenced_at',
    'WorldMemoryEntry',
  ),
  enabled: _bool(row, 'enabled', 'WorldMemoryEntry'),
  metadata: _metadata(row, 'WorldMemoryEntry'),
);

Map<String, Object?> _timelineToSql(WorldTimelineEvent value) => {
  ..._entityToSql(value),
  'world_session_id': value.worldSessionId,
  'title': value.title,
  'description': value.description,
  'world_time': value.worldTime,
  'scene_id': value.sceneId,
  'character_ids_json': jsonEncode(value.characterIds),
  'event_type': value.eventType,
  'importance': value.importance,
};

WorldTimelineEvent _timelineFromSql(Map<String, Object?> row) =>
    WorldTimelineEvent(
      entity: _entityFromSql(row, 'WorldTimelineEvent'),
      worldSessionId: _string(row, 'world_session_id', 'WorldTimelineEvent'),
      title: _string(row, 'title', 'WorldTimelineEvent'),
      description: _string(row, 'description', 'WorldTimelineEvent'),
      worldTime: _string(row, 'world_time', 'WorldTimelineEvent'),
      sceneId: _nullableString(row, 'scene_id', 'WorldTimelineEvent'),
      characterIds: _stringsJson(
        row,
        'character_ids_json',
        'WorldTimelineEvent',
      ),
      eventType: _string(row, 'event_type', 'WorldTimelineEvent'),
      importance: _double(row, 'importance', 'WorldTimelineEvent'),
      metadata: _metadata(row, 'WorldTimelineEvent'),
    );

Map<String, Object?> _branchToSql(WorldBranch value) => {
  ..._entityToSql(value),
  'world_session_id': value.worldSessionId,
  'name': value.name,
  'parent_branch_id': value.parentBranchId,
  'branch_point_message_id': value.branchPointMessageId,
  'branch_point_event_id': value.branchPointEventId,
  'is_current': value.isCurrent ? 1 : 0,
};

WorldBranch _branchFromSql(Map<String, Object?> row) => WorldBranch(
  entity: _entityFromSql(row, 'WorldBranch'),
  worldSessionId: _string(row, 'world_session_id', 'WorldBranch'),
  name: _string(row, 'name', 'WorldBranch'),
  parentBranchId: _nullableString(row, 'parent_branch_id', 'WorldBranch'),
  branchPointMessageId: _nullableString(
    row,
    'branch_point_message_id',
    'WorldBranch',
  ),
  branchPointEventId: _nullableString(
    row,
    'branch_point_event_id',
    'WorldBranch',
  ),
  isCurrent: _bool(row, 'is_current', 'WorldBranch'),
  metadata: _metadata(row, 'WorldBranch'),
);

Map<String, Object?> _feedToSql(WorldFeedEntry value) => {
  ..._entityToSql(value),
  'world_session_id': value.worldSessionId,
  'branch_id': value.branchId,
  'entry_type': value.type.name,
  'speaker_character_instance_id': value.speakerCharacterInstanceId,
  'content': value.content,
};

WorldFeedEntry _feedFromSql(Map<String, Object?> row) => WorldFeedEntry(
  entity: _entityFromSql(row, 'WorldFeedEntry'),
  worldSessionId: _string(row, 'world_session_id', 'WorldFeedEntry'),
  branchId: _string(row, 'branch_id', 'WorldFeedEntry'),
  type: WorldFeedEntryType.fromJson(
    _string(row, 'entry_type', 'WorldFeedEntry'),
  ),
  speakerCharacterInstanceId: _nullableString(
    row,
    'speaker_character_instance_id',
    'WorldFeedEntry',
  ),
  content: _string(row, 'content', 'WorldFeedEntry'),
  metadata: _metadata(row, 'WorldFeedEntry'),
);

Map<String, Object?> _turnToSql(WorldTurn value) => {
  ..._entityToSql(value),
  'world_session_id': value.worldSessionId,
  'branch_id': value.branchId,
  'user_feed_entry_id': value.userFeedEntryId,
  'director_decision_json': jsonEncode(value.directorDecision),
  'selected_speaker_ids_json': jsonEncode(value.selectedSpeakerIds),
  'generated_feed_entry_ids_json': jsonEncode(value.generatedFeedEntryIds),
  'mutation_proposal_json': jsonEncode(value.mutationProposal),
  'status': value.status.name,
  'completed_at': value.completedAt?.toUtc().toIso8601String(),
  'error_category': value.errorCategory?.name,
};

WorldTurn _turnFromSql(Map<String, Object?> row) => WorldTurn(
  entity: _entityFromSql(row, 'WorldTurn'),
  worldSessionId: _string(row, 'world_session_id', 'WorldTurn'),
  branchId: _string(row, 'branch_id', 'WorldTurn'),
  userFeedEntryId: _string(row, 'user_feed_entry_id', 'WorldTurn'),
  directorDecision: _mapJson(row, 'director_decision_json', 'WorldTurn'),
  selectedSpeakerIds: _stringsJson(
    row,
    'selected_speaker_ids_json',
    'WorldTurn',
  ),
  generatedFeedEntryIds: _stringsJson(
    row,
    'generated_feed_entry_ids_json',
    'WorldTurn',
  ),
  mutationProposal: _mapJson(row, 'mutation_proposal_json', 'WorldTurn'),
  status: WorldTurnStatus.values.firstWhere(
    (value) => value.name == _string(row, 'status', 'WorldTurn'),
  ),
  completedAt: _nullableDate(row, 'completed_at', 'WorldTurn'),
  errorCategory: _worldEngineErrorFromSql(row),
  metadata: _metadata(row, 'WorldTurn'),
);

Future<void> _upsertTxn(
  DatabaseExecutor db,
  String table,
  Map<String, Object?> values,
) async {
  final id = values['id']! as String;
  final existing = await db.query(
    table,
    columns: const ['id'],
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  if (existing.isEmpty) {
    await db.insert(table, values);
  } else {
    final update = Map<String, Object?>.from(values)..remove('id');
    await db.update(table, update, where: 'id = ?', whereArgs: [id]);
  }
}

WorldEngineErrorCategory? _worldEngineErrorFromSql(Map<String, Object?> row) {
  final value = _nullableString(row, 'error_category', 'WorldTurn');
  if (value == null) return null;
  return WorldEngineErrorCategory.values.firstWhere(
    (item) => item.name == value,
  );
}

String _string(Map<String, Object?> row, String key, String model) {
  final value = row[key];
  if (value is String) return value;
  throw DataFormatException('$model.$key must be a string.');
}

String? _nullableString(Map<String, Object?> row, String key, String model) {
  final value = row[key];
  if (value == null || value is String) return value as String?;
  throw DataFormatException('$model.$key must be a string when present.');
}

int _int(Map<String, Object?> row, String key, String model) {
  final value = row[key];
  if (value is int) return value;
  throw DataFormatException('$model.$key must be an integer.');
}

int? _nullableInt(Map<String, Object?> row, String key, String model) {
  final value = row[key];
  if (value == null || value is int) return value as int?;
  throw DataFormatException('$model.$key must be an integer when present.');
}

double _double(Map<String, Object?> row, String key, String model) {
  final value = row[key];
  if (value is num) return value.toDouble();
  throw DataFormatException('$model.$key must be numeric.');
}

bool _bool(Map<String, Object?> row, String key, String model) {
  final value = row[key];
  if (value is int && (value == 0 || value == 1)) return value == 1;
  throw DataFormatException('$model.$key must be a SQLite boolean.');
}

DateTime _date(Map<String, Object?> row, String key, String model) {
  final value = _string(row, key, model);
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw DataFormatException('$model.$key must be an ISO date.');
  }
}

DateTime? _nullableDate(Map<String, Object?> row, String key, String model) {
  final value = _nullableString(row, key, model);
  if (value == null) return null;
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw DataFormatException('$model.$key must be an ISO date.');
  }
}
