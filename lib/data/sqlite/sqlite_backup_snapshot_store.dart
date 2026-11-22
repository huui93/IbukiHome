import 'novel_plugin_backup.dart';
import 'sqlite_migrations.dart';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../application/backup/backup_contracts.dart';
import '../../application/common/entity_id_generator.dart';
import '../../domain/backup/backup_models.dart';
import '../../domain/chat/chat_message_role.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';
import 'ibuki_database.dart';
import 'sqlite_tavern_repository.dart';
import 'sqlite_value_codec.dart';
import 'chat_memory_backup.dart';
import 'chat_memory_state_codec.dart';

class _CollectionSpec {
  const _CollectionSpec(
    this.name,
    this.table, {
    this.deferredColumns = const [],
  });
  final String name;
  final String table;
  final List<String> deferredColumns;
}

const _collections = <_CollectionSpec>[
  _CollectionSpec('projects', 'projects'),
  _CollectionSpec('novelOutputSettings', 'novel_output_settings'),
  _CollectionSpec('novelPromptPresets', 'novel_prompt_presets'),
  _CollectionSpec('outlineNodes', 'outline_nodes'),
  _CollectionSpec('segments', 'segments'),
  _CollectionSpec('segmentRevisions', 'segment_revisions'),
  _CollectionSpec('characterCards', 'character_cards'),
  _CollectionSpec('worldCards', 'world_cards'),
  _CollectionSpec('chatPersonas', 'chat_personas'),
  _CollectionSpec('chatSessions', 'chat_sessions'),
  _CollectionSpec('chatSessionControls', 'chat_session_controls'),
  _CollectionSpec('chatMessages', 'chat_messages'),
  _CollectionSpec(
    'novelStoryBranches',
    'novel_story_branches',
    deferredColumns: ['parent_id'],
  ),
  _CollectionSpec('novelActiveBranches', 'novel_active_branches'),
  _CollectionSpec('novelSegmentOrigins', 'novel_segment_origins'),
  _CollectionSpec(
    'novelPluginCandidates',
    'novel_plugin_candidates',
    deferredColumns: ['source_candidate_id'],
  ),
  _CollectionSpec('novelPluginSelections', 'novel_plugin_selections'),
  _CollectionSpec('novelPluginReplyViews', 'novel_plugin_reply_views'),
  _CollectionSpec('novelPluginState', 'novel_plugin_state'),
  _CollectionSpec('chatUsageRecords', 'chat_usage_records'),
  _CollectionSpec('novelSummaryChunks', 'novel_summary_chunks'),
  _CollectionSpec('storyMemoryDigests', 'story_memory_digests'),
  _CollectionSpec('readerPreferences', 'reader_preferences'),
  _CollectionSpec('readerProgress', 'reader_progress'),
  _CollectionSpec('chatMemoryEntries', 'chat_memory_entries'),
  _CollectionSpec('conversationSummaries', 'conversation_summaries'),
  _CollectionSpec('chatMemoryStates', 'chat_memory_states'),
  _CollectionSpec('chatMemoryUsage', 'chat_memory_usage'),
  _CollectionSpec('compatibilityPayloads', 'external_compatibility_payloads'),
  _CollectionSpec(
    'worlds',
    'roleplay_worlds',
    deferredColumns: ['default_session_id'],
  ),
  _CollectionSpec(
    'worldSessions',
    'world_sessions',
    deferredColumns: [
      'current_player_instance_id',
      'current_scene_id',
      'current_branch_id',
    ],
  ),
  _CollectionSpec('worldBooks', 'world_books'),
  _CollectionSpec('loreEntries', 'lore_entries'),
  _CollectionSpec('worldBookReferences', 'world_world_book_references'),
  _CollectionSpec(
    'worldSessionBookOverrides',
    'world_session_world_book_overrides',
  ),
  _CollectionSpec('characterBookReferences', 'character_world_book_references'),
  _CollectionSpec('playerPersonas', 'player_personas'),
  _CollectionSpec('personaBookReferences', 'persona_world_book_references'),
  _CollectionSpec('worldPlayerInstances', 'world_player_instances'),
  _CollectionSpec('worldCharacterInstances', 'world_character_instances'),
  _CollectionSpec('worldScenes', 'world_scenes'),
  _CollectionSpec('worldSceneCast', 'world_scene_cast'),
  _CollectionSpec('worldState', 'world_state_entries'),
  _CollectionSpec('worldRelationships', 'world_relationships'),
  _CollectionSpec('worldMemories', 'world_memory_entries'),
  _CollectionSpec('worldTimeline', 'world_timeline_events'),
  _CollectionSpec(
    'worldBranches',
    'world_branches',
    deferredColumns: ['parent_branch_id'],
  ),
  _CollectionSpec('worldFeed', 'world_feed_entries'),
  _CollectionSpec('worldTurns', 'world_turns'),
  _CollectionSpec(
    'tavernSessions',
    'tavern_sessions',
    deferredColumns: ['active_story_line_id'],
  ),
  _CollectionSpec('tavernParticipants', 'tavern_participants'),
  _CollectionSpec(
    'tavernStoryLines',
    'tavern_story_lines',
    deferredColumns: ['parent_id', 'origin_turn_id', 'origin_alternative_id'],
  ),
  _CollectionSpec(
    'tavernTurns',
    'tavern_turns',
    deferredColumns: ['selected_alternative_id'],
  ),
  _CollectionSpec('tavernAlternatives', 'tavern_alternatives'),
  _CollectionSpec('tavernLineSelections', 'tavern_line_selections'),
  _CollectionSpec('tavernGenerationAttempts', 'tavern_generation_attempts'),
  _CollectionSpec('tavernContentParts', 'tavern_content_parts'),
  _CollectionSpec('tavernWorldInfoStates', 'tavern_world_info_states'),
  _CollectionSpec('tavernWorldInfoJournal', 'tavern_world_info_journal'),
];

class SQLiteBackupSnapshotStore implements BackupSnapshotStore {
  SQLiteBackupSnapshotStore(this.database, {EntityIdGenerator? ids})
    : _ids = ids ?? EntityIdGenerator();

  final IbukiDatabase database;
  final EntityIdGenerator _ids;

  @override
  Future<BackupSnapshot> buildSnapshot() async {
    final db = await database.database;
    return db.transaction((txn) async {
      final result = <String, List<Map<String, Object?>>>{};
      for (final spec in _collections) {
        final rows = await txn.query(spec.table);
        result[spec.name] = rows
            .map(Map<String, Object?>.from)
            .toList(growable: false);
      }
      return BackupSnapshot(collections: result);
    }, exclusive: true);
  }

  @override
  Future<bool> hasUserData() async {
    final db = await database.database;
    for (final spec in _collections) {
      final where = spec.table == 'roleplay_worlds' ? 'id <> ?' : null;
      final args = spec.table == 'roleplay_worlds'
          ? [worldBookLibraryOwnerId]
          : null;
      final value = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM ${spec.table}${where == null ? '' : ' WHERE $where'}',
          args,
        ),
      );
      if ((value ?? 0) > 0) return true;
    }
    return false;
  }

  @override
  Future<void> restore(
    BackupSnapshot snapshot, {
    required BackupRestoreMode mode,
    required Map<String, String> restoredAssets,
    BackupCancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final db = await database.database;
    if (mode == BackupRestoreMode.fresh && await hasUserData()) {
      throw const BackupException('not_empty', '当前伊吹之家已有内容，请使用合并恢复。');
    }
    await db.transaction((txn) async {
      final specByName = {for (final spec in _collections) spec.name: spec};
      final collectionByTable = {
        for (final spec in _collections) spec.table: spec.name,
      };
      final mappings = <String, Map<String, String>>{};
      for (final row
          in snapshot.collections['chatMessages'] ??
              const <Map<String, Object?>>[]) {
        if (row['image_json'] == null) continue;
        try {
          final message = chatMessageFromSql(row);
          if (message.role != ChatMessageRole.user) {
            throw const FormatException();
          }
        } catch (_) {
          throw const BackupException('invalid_chat_image', '备份中的聊天图片记录无效。');
        }
      }

      for (final entry in snapshot.collections.entries) {
        cancellation?.throwIfCancelled();
        final spec = specByName[entry.key];
        if (spec == null) continue;
        final info = await txn.rawQuery('PRAGMA table_info(${spec.table})');
        final idColumns = info
            .where((column) => (column['pk'] as int? ?? 0) > 0)
            .map((column) => column['name'] as String)
            .toList();
        if (idColumns.length != 1 || idColumns.single != 'id') continue;
        final map = <String, String>{};
        for (final row in entry.value) {
          cancellation?.throwIfCancelled();
          final original = row['id'];
          if (original is! String || original.isEmpty) continue;
          if (spec.table == 'roleplay_worlds' &&
              original == worldBookLibraryOwnerId) {
            map[original] = original;
            continue;
          }
          final existing = await txn.query(
            spec.table,
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [original],
            limit: 1,
          );
          map[original] = existing.isEmpty ? original : _ids.nextId('restore');
        }
        mappings[entry.key] = map;
      }
      // Durable row IDs are canonical line/Attempt IDs, not independent assets.
      mappings['tavernWorldInfoStates'] = mappings['tavernStoryLines'] ?? {};
      mappings['novelStoryBranches'] = mappings['projects'] ?? {};
      mappings['novelActiveBranches'] = mappings['projects'] ?? {};
      mappings['novelSegmentOrigins'] = mappings['segments'] ?? {};
      mappings['novelPluginSelections'] = mappings['segments'] ?? {};
      mappings['novelPluginReplyViews'] = mappings['segments'] ?? {};
      mappings['tavernWorldInfoJournal'] =
          mappings['tavernGenerationAttempts'] ?? {};
      final prepared = rewriteChatMemoryBackup(
        TavernWorldInfoBackup.rewrite(snapshot.collections, mappings),
        mappings,
      );

      final deferred =
          <({String table, String id, Map<String, Object?> values})>[];
      for (final spec in _collections) {
        cancellation?.throwIfCancelled();
        final rows = prepared[spec.name] ?? const [];
        final foreignKeys = await txn.rawQuery(
          'PRAGMA foreign_key_list(${spec.table})',
        );
        for (final source in rows) {
          cancellation?.throwIfCancelled();
          final row = Map<String, Object?>.from(source);
          if (spec.name == 'novelPluginState') {
            rewriteNovelPluginState(row, mappings);
          }
          final ownId = row['id'];
          if (ownId is String) row['id'] = mappings[spec.name]?[ownId] ?? ownId;
          for (final foreignKey in foreignKeys) {
            final column = foreignKey['from'] as String?;
            final targetTable = foreignKey['table'] as String?;
            if (column == null || targetTable == null) continue;
            final old = row[column];
            final targetCollection = collectionByTable[targetTable];
            if (old is String && targetCollection != null) {
              row[column] = mappings[targetCollection]?[old] ?? old;
            }
          }
          _rewriteLogicalReferences(row, mappings);
          _rewriteTavernAssetReferences(row, spec.name, mappings);
          _rewriteAssets(row, restoredAssets);
          if (spec.name == 'novelPluginState' && row['project_id'] == null) {
            final existing = await txn.query(
              'novel_plugin_state',
              where: 'plugin_id=? AND storage_key=?',
              whereArgs: [row['plugin_id'], row['storage_key']],
            );
            if (existing.isNotEmpty) {
              final merged = Map<String, Object?>.from(
                jsonDecode(existing.single['value_json'] as String) as Map,
              );
              for (final entry
                  in (jsonDecode(row['value_json'] as String) as Map).entries) {
                var name = entry.key as String;
                var counter = 1;
                while (merged.containsKey(name)) {
                  name = '${entry.key}（导入 ${counter++}）';
                }
                merged[name] = entry.value;
              }
              await txn.update(
                'novel_plugin_state',
                {'value_json': jsonEncode(merged)},
                where: 'id=?',
                whereArgs: [existing.single['id']],
              );
              continue;
            }
          }

          if (spec.name == 'compatibilityPayloads') {
            _rewriteCompatibilityLink(row, mappings);
          }
          final later = <String, Object?>{};
          for (final column in spec.deferredColumns) {
            if (row[column] != null) later[column] = row[column];
            row[column] = null;
          }
          if (spec.table == 'roleplay_worlds' &&
              row['id'] == worldBookLibraryOwnerId) {
            final exists = await txn.query(
              spec.table,
              columns: ['id'],
              where: 'id = ?',
              whereArgs: [worldBookLibraryOwnerId],
              limit: 1,
            );
            if (exists.isNotEmpty) continue;
          }
          await txn.insert(
            spec.table,
            row,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          if (later.isNotEmpty && row['id'] is String) {
            deferred.add((
              table: spec.table,
              id: row['id']! as String,
              values: later,
            ));
          }
        }
      }
      for (final update in deferred) {
        cancellation?.throwIfCancelled();
        await txn.update(
          update.table,
          update.values,
          where: 'id = ?',
          whereArgs: [update.id],
        );
      }
      if (!snapshot.collections.containsKey('tavernWorldInfoStates')) {
        for (final line
            in snapshot.collections['tavernStoryLines'] ??
                <Map<String, Object?>>[]) {
          final id = mappings['tavernStoryLines']?[line['id']] ?? line['id'];
          final session =
              mappings['tavernSessions']?[line['session_id']] ??
              line['session_id'];
          await txn.insert('tavern_world_info_states', {
            'id': id,
            'session_id': session,
            'story_line_id': id,
            'version': 0,
            'provenance': 'legacyUnavailable',
            'data_json': '{"messageCount":0,"historyMarker":"","timers":[]}',
            'initial_data_json':
                '{"messageCount":0,"historyMarker":"","timers":[]}',
          });
        }
      }
      await validateNovelPluginGraph(txn);
      await detachLegacyChatLinks(txn);
      for (final row in await txn.query('chat_personas')) {
        chatPersonaFromSql(row);
      }
      for (final row in await txn.query('chat_memory_states')) {
        chatMemoryStateFromSql(row);
      }
      for (final row in await txn.query('chat_memory_usage')) {
        chatMemoryUsageFromSql(row);
      }
      final invalid = await txn.rawQuery(
        '''SELECT m.id FROM chat_memory_entries m
        JOIN chat_sessions s ON s.id = m.session_id
        WHERE m.persona_id != s.persona_id OR (m.source_session_id IS NOT NULL AND m.source_session_id != m.session_id)
        UNION ALL SELECT u.id FROM chat_memory_usage u JOIN chat_messages m ON m.id = u.message_id WHERE u.session_id != m.session_id''',
      );
      if (invalid.isNotEmpty) {
        throw const BackupException('invalid_memory_scope', '备份中的聊天记忆会话不匹配。');
      }
      await TavernWorldInfoBackup.validate(txn);
    }, exclusive: true);
  }

  void _rewriteAssets(Map<String, Object?> row, Map<String, String> assets) {
    for (final key in const [
      'avatar_reference',
      'image_reference',
      'background_reference',
    ]) {
      final value = row[key];
      if (value is String && value.startsWith('ibuki-asset://')) {
        row[key] = assets[value.substring('ibuki-asset://'.length)];
      }
    }
  }

  void _rewriteTavernAssetReferences(
    Map<String, Object?> row,
    String collection,
    Map<String, Map<String, String>> mappings,
  ) {
    if (collection == 'tavernSessions') {
      final worldType = row['world_asset_type'];
      final worldId = row['world_asset_id'];
      if (worldType == 'worldCard' && worldId is String) {
        row['world_asset_id'] = mappings['worldCards']?[worldId] ?? worldId;
      }
      if (worldType == 'roleplayWorld' && worldId is String) {
        row['world_asset_id'] = mappings['worlds']?[worldId] ?? worldId;
      }
      final metadata = row['metadata_json'];
      if (metadata is String) {
        final data = Map<String, dynamic>.from(jsonDecode(metadata) as Map);
        final overrides = data['worldInfoBookOverridesV1'];
        if (overrides is Map) {
          data['worldInfoBookOverridesV1'] = {
            for (final key in overrides.keys)
              (mappings['worldBooks']?[key] ?? key): overrides[key],
          };
          row['metadata_json'] = jsonEncode(data);
        }
        final references = data['tavernBookReferencesV1'];
        if (references is Map) {
          data['tavernBookReferencesV1'] = {
            for (final key in references.keys)
              (mappings['worldBooks']?[key] ?? key): references[key],
          };
          row['metadata_json'] = jsonEncode(data);
        }
      }
      final personaType = row['persona_type'];
      final personaId = row['persona_id'];
      if (personaType == 'playerPersona' && personaId is String) {
        row['persona_id'] = mappings['playerPersonas']?[personaId] ?? personaId;
      }
    }
    if (collection == 'tavernParticipants') {
      final type = row['kind'];
      final id = row['entity_id'];
      final target = switch (type) {
        'character' => 'characterCards',
        'persona' => 'playerPersonas',
        _ => null,
      };
      if (target != null && id is String) {
        row['entity_id'] = mappings[target]?[id] ?? id;
      }
    }
  }

  void _rewriteCompatibilityLink(
    Map<String, Object?> row,
    Map<String, Map<String, String>> mappings,
  ) {
    final id = row['linked_entity_id'];
    final type = row['linked_entity_type'];
    if (id is! String || type is! String) return;
    final collection = switch (type) {
      'characterCard' => 'characterCards',
      'playerPersona' => 'playerPersonas',
      'worldBook' => 'worldBooks',
      _ => null,
    };
    if (collection != null) {
      row['linked_entity_id'] = mappings[collection]?[id] ?? id;
    }
  }

  void _rewriteLogicalReferences(
    Map<String, Object?> row,
    Map<String, Map<String, String>> mappings,
  ) {
    final jsonColumns = <String, String>{
      'related_character_ids_json': 'worldCharacterInstances',
      'character_ids_json': 'worldCharacterInstances',
      'selected_speaker_ids_json': 'worldCharacterInstances',
      'generated_feed_entry_ids_json': 'worldFeed',
    };
    for (final entry in jsonColumns.entries) {
      final raw = row[entry.key];
      if (raw is! String) continue;
      try {
        final values = jsonDecode(raw);
        if (values is List) {
          row[entry.key] = jsonEncode(
            values.map((value) {
              if (value is! String) return value;
              return mappings[entry.value]?[value] ?? value;
            }).toList(),
          );
        }
      } catch (_) {
        // Preserve malformed legacy metadata; domain validation owns its meaning.
      }
    }
  }
}
