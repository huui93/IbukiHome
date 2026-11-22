import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive_io.dart';
import 'package:ibukihome/application/backup/backup_archive_codec.dart';
import 'package:ibukihome/application/backup/file_backup_asset_store.dart';
import 'package:ibukihome/application/segments/restore_segment_revision.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/data/sqlite/sqlite_project_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_segment_repository.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'v12 logical archive round-trips history, world graph, assets, and compatibility',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ibuki-backup-roundtrip-',
      );
      final support = Directory('${root.path}/support')
        ..createSync(recursive: true);
      final avatar = File('${support.path}/imports/avatar.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync([137, 80, 78, 71]);
      final source = _database('${root.path}/source.db');
      final target = _database('${root.path}/target.db');
      try {
        final db = await source.database;
        await _seed(db, avatar.path);
        final sourceStore = SQLiteBackupSnapshotStore(source);
        final codec = BackupArchiveCodec(applicationSupportDirectory: support);
        final archiveFile = File('${root.path}/full.ibukibackup');
        final preview = await codec.write(
          snapshot: await sourceStore.buildSnapshot(),
          destination: archiveFile,
          appVersion: 'test',
          schemaVersion: 12,
        );
        const artifactPath = String.fromEnvironment(
          'IBUKI_SYNTHETIC_BACKUP_OUTPUT',
        );
        if (artifactPath.isNotEmpty) {
          final artifact = File(artifactPath);
          await artifact.parent.create(recursive: true);
          await archiveFile.copy(artifact.path);
        }
        expect(preview.manifest.security['credentialsIncluded'], isFalse);
        final archiveText = await _archiveText(archiveFile);
        for (final forbidden in const [
          'sk-super-secret-123456789',
          'Bearer abcdefghijklmnop',
          'provider-secret-binding',
        ]) {
          expect(archiveText, isNot(contains(forbidden)));
        }

        final staging = Directory('${root.path}/restore');
        final decoded = await codec.read(source: archiveFile, staging: staging);
        final assets = FileBackupAssetStore(
          Directory('${root.path}/target-support'),
        );
        final restoredAssets = await assets.promoteRestoredAssets(
          staging,
          decoded.preview.manifest.assets,
        );
        await SQLiteBackupSnapshotStore(target).restore(
          decoded.snapshot,
          mode: BackupRestoreMode.fresh,
          restoredAssets: restoredAssets,
        );

        final restored = await target.database;
        expect(await _count(restored, 'projects'), 1);
        expect(await _count(restored, 'segment_revisions'), 1);
        expect(await _count(restored, 'outline_nodes'), 1);
        expect(await _count(restored, 'novel_summary_chunks'), 1);
        expect(await _count(restored, 'story_memory_digests'), 1);
        expect(await _count(restored, 'chat_messages'), 2);
        expect(await _count(restored, 'chat_memory_entries'), 1);
        expect(await _count(restored, 'conversation_summaries'), 1);
        expect(await _count(restored, 'world_feed_entries'), 3);
        expect(await _count(restored, 'world_turns'), 1);
        expect(await _count(restored, 'world_state_entries'), 1);
        expect(await _count(restored, 'world_relationships'), 1);
        expect(await _count(restored, 'world_memory_entries'), 1);
        expect(await _count(restored, 'world_timeline_events'), 1);
        expect(await _count(restored, 'world_world_book_references'), 1);
        expect(await _count(restored, 'world_session_world_book_overrides'), 1);
        expect(await _count(restored, 'character_world_book_references'), 1);
        expect(await _count(restored, 'persona_world_book_references'), 1);

        final project = (await restored.query('projects')).single;
        expect(project['system_prompt'], 'world-safe author intent');
        expect(project['ai_provider_config_id'], isNull);
        expect(project['ai_model'], isNull);
        final session = (await restored.query('world_sessions')).single;
        expect(session['current_scene_id'], 'scene-1');
        expect(session['current_branch_id'], 'branch-1');
        expect(session['current_player_instance_id'], 'player-instance-1');
        expect(session['ai_provider_config_id'], isNull);
        final currentBranch = (await restored.query(
          'world_branches',
          where: 'id = ?',
          whereArgs: ['branch-1'],
        )).single;
        expect(currentBranch['parent_branch_id'], 'branch-0');
        expect(currentBranch['branch_point_event_id'], 'timeline-1');
        final card = (await restored.query('character_cards')).single;
        final restoredAvatar = File(card['avatar_reference']! as String);
        expect(await restoredAvatar.exists(), isTrue);
        expect(await restoredAvatar.readAsBytes(), [137, 80, 78, 71]);

        final restoredRevision =
            await RestoreSegmentRevision(
              SQLiteProjectRepository(target),
              SQLiteSegmentRepository(target),
            ).call(
              projectId: 'project-1',
              segmentId: 'segment-1',
              segmentRevisionId: 'revision-1',
              newRevisionId: 'revision-after-restore',
              nowUtc: DateTime.utc(2026, 1, 2),
            );
        expect(restoredRevision.content, '旧正文');

        final payload = (await restored.query(
          'external_compatibility_payloads',
        )).single;
        final unsupported = payload['unsupported_payload_json']! as String;
        expect(unsupported, contains('rubyPanel'));
        expect(unsupported, isNot(contains('sk-super-secret')));
        expect(unsupported, isNot(contains('Authorization')));
      } finally {
        await source.close();
        await target.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'merge remaps colliding IDs without replacing existing content',
    () async {
      final root = await Directory.systemTemp.createTemp('ibuki-backup-merge-');
      final source = _database('${root.path}/source.db');
      final target = _database('${root.path}/target.db');
      try {
        final sourceDb = await source.database;
        final targetDb = await target.database;
        await _insertProject(sourceDb, title: 'Archived');
        await _insertProject(targetDb, title: 'Existing');
        final snapshot = await SQLiteBackupSnapshotStore(
          source,
        ).buildSnapshot();
        await SQLiteBackupSnapshotStore(target).restore(
          snapshot,
          mode: BackupRestoreMode.merge,
          restoredAssets: const {},
        );
        final rows = await targetDb.query('projects', orderBy: 'title');
        expect(rows.map((row) => row['title']), ['Archived', 'Existing']);
        expect(rows.map((row) => row['id']).toSet(), hasLength(2));
      } finally {
        await source.close();
        await target.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );
}

Future<String> _archiveText(File file) async {
  final input = InputFileStream(file.path);
  try {
    final archive = ZipDecoder().decodeStream(input, verify: true);
    final buffer = StringBuffer();
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final bytes = entry.readBytes();
      if (bytes != null) buffer.write(utf8.decode(bytes, allowMalformed: true));
    }
    return buffer.toString();
  } finally {
    input.closeSync();
  }
}

IbukiDatabase _database(String path) => IbukiDatabase(
  pathResolver: () async => path,
  databaseFactory: databaseFactoryFfi,
);

Future<int> _count(Database db, String table) async =>
    (await db.rawQuery('SELECT COUNT(*) AS value FROM $table')).single['value']
        as int;

Future<void> _insertProject(Database db, {required String title}) async {
  await db.insert('projects', {
    'id': 'project-1',
    'title': title,
    'description': '',
    'system_prompt': '',
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
    'revision': 1,
  });
}

Future<void> _seed(Database db, String avatar) async {
  const now = '2026-01-01T00:00:00Z';
  await _insertProject(db, title: 'Archive Novel');
  await db.update('projects', {
    'system_prompt': 'world-safe author intent',
    'ai_provider_config_id': 'provider-secret-binding',
    'ai_model': 'private-model',
  });
  await db.insert('segments', {
    'id': 'segment-1',
    'project_id': 'project-1',
    'order_index': 0,
    'content': '正文',
    'created_at': now,
    'updated_at': now,
    'revision': 2,
  });
  await db.insert('outline_nodes', {
    'id': 'outline-1',
    'project_id': 'project-1',
    'title': 'Outline',
    'summary': 'summary',
    'order_index': 0,
    'status': 'current',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('segment_revisions', {
    'id': 'revision-1',
    'project_id': 'project-1',
    'segment_id': 'segment-1',
    'revision_number': 1,
    'content': '旧正文',
    'note': 'history',
    'user_instruction': '',
    'mode': 'rewrite',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('novel_summary_chunks', {
    'id': 'summary-1',
    'project_id': 'project-1',
    'source_start_order': 0,
    'source_end_order': 0,
    'source_start_segment_id': 'segment-1',
    'source_end_segment_id': 'segment-1',
    'summary': 'novel summary',
    'source_fingerprint': 'fingerprint',
    'status': 'valid',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('story_memory_digests', {
    'id': 'digest-1',
    'project_id': 'project-1',
    'content': 'digest',
    'source_through_order': 0,
    'source_fingerprint': 'fingerprint',
    'status': 'valid',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('reader_preferences', {
    'project_id': 'project-1',
    'font_size': 17.0,
    'line_height': 1.7,
    'horizontal_margin': 20.0,
    'theme': 'warm',
    'updated_at': now,
  });
  await db.insert('reader_progress', {
    'project_id': 'project-1',
    'last_read_segment_id': 'segment-1',
    'scroll_offset': 42.0,
    'updated_at': now,
  });
  await db.insert('character_cards', {
    'id': 'character-1',
    'project_id': 'project-1',
    'name': 'Mira',
    'content': 'character',
    'avatar_reference': avatar,
    'sort_order': 0,
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('chat_personas', {
    'id': 'chat-persona-1',
    'name': 'User',
    'description_mode': 'simple',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('chat_sessions', {
    'id': 'chat-1',
    'project_id': 'project-1',
    'character_id': 'character-1',
    'persona_id': 'chat-persona-1',
    'title': 'Chat',
    'ai_provider_config_id': 'provider-secret-binding',
    'ai_model': 'private-model',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  for (final item in const [
    ('message-1', 'user', 'hello'),
    ('message-2', 'assistant', 'hi'),
  ]) {
    await db.insert('chat_messages', {
      'id': item.$1,
      'session_id': 'chat-1',
      'project_id': 'project-1',
      'role': item.$2,
      'content': item.$3,
      'created_at': now,
      'updated_at': now,
      'revision': 1,
    });
  }
  await db.insert('chat_memory_entries', {
    'id': 'chat-memory-1',
    'persona_id': 'chat-persona-1',
    'session_id': 'chat-1',
    'category': 'sharedEvent',
    'content': 'met once',
    'origin': 'manual',
    'is_pinned': 1,
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('conversation_summaries', {
    'id': 'chat-summary-1',
    'session_id': 'chat-1',
    'source_start_message_id': 'message-1',
    'source_end_message_id': 'message-2',
    'summary': 'greeting',
    'source_fingerprint': 'chat-fingerprint',
    'status': 'valid',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('roleplay_worlds', {
    'id': 'world-1',
    'name': 'Chaldea',
    'description': '',
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('world_sessions', {
    'id': 'world-session-1',
    'world_id': 'world-1',
    'name': 'Timeline A',
    'ai_provider_config_id': 'provider-secret-binding',
    'ai_model': 'private-model',
    'metadata_json': jsonEncode({'additionalInstructions': 'session intent'}),
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('world_books', {
    'id': 'book-1',
    'world_id': 'world-1',
    'name': 'Lore',
    'is_primary': 1,
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('lore_entries', {
    'id': 'lore-1',
    'world_book_id': 'book-1',
    'title': 'Cafeteria',
    'content': 'Lore content',
    'activation_mode': 'keyword',
    'keywords_json': '["食堂"]',
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('player_personas', {
    'id': 'persona-1',
    'world_id': 'world-1',
    'name': 'Master',
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('world_player_instances', {
    'id': 'player-instance-1',
    'world_session_id': 'world-session-1',
    'player_persona_id': 'persona-1',
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('world_character_instances', {
    'id': 'character-instance-1',
    'world_session_id': 'world-session-1',
    'character_card_id': 'character-1',
    'is_present': 1,
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('world_scenes', {
    'id': 'scene-1',
    'world_session_id': 'world-session-1',
    'name': 'Cafeteria',
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('world_scene_cast', {
    'scene_id': 'scene-1',
    'character_instance_id': 'character-instance-1',
  });
  await db.insert('world_state_entries', {
    'id': 'state-1',
    'world_session_id': 'world-session-1',
    'state_key': 'door.open',
    'value_json': 'true',
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('world_relationships', {
    'id': 'relationship-1',
    'world_session_id': 'world-session-1',
    'source_entity_type': 'character',
    'source_entity_id': 'character-instance-1',
    'target_entity_type': 'player',
    'target_entity_id': 'player-instance-1',
    'relation_type': 'trusted',
    'summary': 'trusted',
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('world_memory_entries', {
    'id': 'world-memory-1',
    'world_session_id': 'world-session-1',
    'memory_type': 'event',
    'summary': 'arrival',
    'content': 'arrived',
    'related_character_ids_json': '["character-instance-1"]',
    'related_scene_id': 'scene-1',
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('world_timeline_events', {
    'id': 'timeline-1',
    'world_session_id': 'world-session-1',
    'title': 'Arrival',
    'description': 'arrived',
    'scene_id': 'scene-1',
    'character_ids_json': '["character-instance-1"]',
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('world_branches', {
    'id': 'branch-0',
    'world_session_id': 'world-session-1',
    'name': 'Parent',
    'is_current': 0,
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('world_feed_entries', {
    'id': 'feed-parent',
    'world_session_id': 'world-session-1',
    'branch_id': 'branch-0',
    'entry_type': 'narration',
    'content': 'Inherited history.',
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  await db.insert('world_branches', {
    'id': 'branch-1',
    'world_session_id': 'world-session-1',
    'name': 'Main',
    'parent_branch_id': 'branch-0',
    'branch_point_event_id': 'timeline-1',
    'is_current': 1,
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  for (final item in const [
    ('feed-1', 'userAction', null, 'I enter.'),
    ('feed-2', 'characterSpeech', 'character-instance-1', '“Welcome.”'),
  ]) {
    await db.insert('world_feed_entries', {
      'id': item.$1,
      'world_session_id': 'world-session-1',
      'branch_id': 'branch-1',
      'entry_type': item.$2,
      'speaker_character_instance_id': item.$3,
      'content': item.$4,
      'metadata_json': '{}',
      'created_at': now,
      'updated_at': now,
      'revision': 1,
    });
  }
  await db.insert('world_turns', {
    'id': 'turn-1',
    'world_session_id': 'world-session-1',
    'branch_id': 'branch-1',
    'user_feed_entry_id': 'feed-1',
    'selected_speaker_ids_json': '["character-instance-1"]',
    'generated_feed_entry_ids_json': '["feed-2"]',
    'status': 'completed',
    'metadata_json': '{}',
    'created_at': now,
    'updated_at': now,
    'revision': 1,
  });
  for (final insert in [
    (
      'world_world_book_references',
      {'id': 'wr-1', 'world_id': 'world-1', 'world_book_id': 'book-1'},
    ),
    (
      'world_session_world_book_overrides',
      {
        'id': 'wo-1',
        'world_session_id': 'world-session-1',
        'world_book_id': 'book-1',
      },
    ),
    (
      'character_world_book_references',
      {
        'id': 'cr-1',
        'character_card_id': 'character-1',
        'world_book_id': 'book-1',
      },
    ),
    (
      'persona_world_book_references',
      {
        'id': 'pr-1',
        'player_persona_id': 'persona-1',
        'world_book_id': 'book-1',
      },
    ),
  ]) {
    await db.insert(insert.$1, {
      ...insert.$2,
      'metadata_json': '{}',
      'created_at': now,
      'updated_at': now,
      'revision': 1,
    });
  }
  await db.insert('external_compatibility_payloads', {
    'id': 'compat-1',
    'source_type': 'character',
    'source_format': 'sillytavern-v3',
    'source_sha256': 'source-hash',
    'linked_entity_type': 'characterCard',
    'linked_entity_id': 'character-1',
    'normalized_payload_json': '{}',
    'unsupported_payload_json': jsonEncode({
      'script': 'function rubyPanel() { return true; }',
      'api_key': 'sk-super-secret-123456789',
      'Authorization': 'Bearer abcdefghijklmnop',
    }),
    'security_flags_json': '["scriptLike"]',
    'import_warnings_json': '[]',
    'created_at': now,
    'metadata_json': '{}',
  });
  await db.update(
    'world_sessions',
    {
      'current_player_instance_id': 'player-instance-1',
      'current_scene_id': 'scene-1',
      'current_branch_id': 'branch-1',
    },
    where: 'id = ?',
    whereArgs: ['world-session-1'],
  );
  await db.update(
    'roleplay_worlds',
    {'default_session_id': 'world-session-1'},
    where: 'id = ?',
    whereArgs: ['world-1'],
  );
}
