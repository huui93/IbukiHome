import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'real v5 disk database migrates through v6 to latest without losing data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ibuki_v5_fixture_',
      );
      final path = p.join(directory.path, 'ibukihome.db');
      try {
        final old = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 5,
            onCreate: (db, _) async {
              await _createVersionFive(db);
              await _seedVersionFive(db);
            },
          ),
        );
        await old.close();

        final database = IbukiDatabase(
          pathResolver: () async => path,
          databaseFactory: databaseFactoryFfi,
        );
        final db = await database.open();

        expect(await db.getVersion(), SqliteSchema.version);
        for (final table in const <String>[
          'projects',
          'segments',
          'segment_revisions',
          'outline_nodes',
          'character_cards',
          'world_cards',
          'novel_summary_chunks',
          'story_memory_digests',
          'reader_preferences',
          'reader_progress',
          'chat_personas',
          'chat_sessions',
          'chat_messages',
          'conversation_summaries',
        ]) {
          expect(await _count(db, table), 1, reason: table);
        }
        expect(await _count(db, 'chat_memory_entries'), 2);

        final project = (await db.query('projects')).single;
        expect(project['system_prompt'], 'third person');
        expect(project['ai_provider_config_id'], isNull);
        expect(project['ai_model'], isNull);

        final character = (await db.query('character_cards')).single;
        expect(character['content'], 'old character content');
        expect(character['mode'], isNull);
        expect(character['source_work_title'], '');
        expect(character['source_character_name'], '');
        expect(character['source_version_hint'], '');
        expect(character['fanfic_adaptation_notes'], '');
        expect(character['original_idea'], '');

        final session = (await db.query('chat_sessions')).single;
        expect(session['persona_id'], 'persona-1');
        expect(session['ai_provider_config_id'], isNull);
        expect(session['ai_model'], isNull);

        final message = (await db.query('chat_messages')).single;
        expect(message['content'], 'old message remains intact');
        expect(message['finish_reason'], isNull);

        final memories = await db.query(
          'chat_memory_entries',
          orderBy: 'id ASC',
        );
        expect(memories[0]['session_id'], isNull);
        expect(memories[0]['source_session_id'], isNull);
        expect(memories[1]['session_id'], 'session-1');
        expect(memories[1]['source_session_id'], 'session-1');

        await database.close();
      } finally {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      }
    },
  );
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
  return rows.single['count']! as int;
}

Future<void> _createVersionFive(Database db) async {
  for (var statement in SqliteSchema.createTableStatements) {
    statement = statement
        .replaceAll('  ai_provider_config_id TEXT NULL,\n', '')
        .replaceAll('  ai_model TEXT NULL,\n', '')
        .replaceAll(
          "  finish_reason TEXT NULL CHECK (finish_reason IS NULL OR finish_reason IN ('stop', 'length', 'contentFiltered', 'cancelled', 'interrupted', 'providerError', 'unknown')),\n",
          '',
        )
        .replaceAll('  session_id TEXT NULL,\n', '')
        .replaceAll(
          "  mode TEXT NULL CHECK (mode IS NULL OR mode IN ('fanfic', 'original')),\n",
          '',
        )
        .replaceAll("  source_work_title TEXT NOT NULL DEFAULT '',\n", '')
        .replaceAll("  source_character_name TEXT NOT NULL DEFAULT '',\n", '')
        .replaceAll("  source_version_hint TEXT NOT NULL DEFAULT '',\n", '')
        .replaceAll("  fanfic_adaptation_notes TEXT NOT NULL DEFAULT '',\n", '')
        .replaceAll("  original_idea TEXT NOT NULL DEFAULT '',\n", '')
        .replaceAll(
          '  FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE RESTRICT,\n',
          '',
        );
    await db.execute(statement);
  }
  for (final statement in SqliteSchema.createIndexStatements) {
    if (statement.contains('idx_chat_memory_entries_session_updated')) {
      continue;
    }
    await db.execute(statement);
  }
}

Future<void> _seedVersionFive(Database db) async {
  const at = '2026-08-01T00:00:00.000Z';
  const metadata = <String, Object?>{
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  };
  await db.insert('projects', {
    'id': 'project-1',
    'title': 'old project',
    'description': 'old description',
    'system_prompt': 'third person',
    ...metadata,
  });
  await db.insert('segments', {
    'id': 'segment-1',
    'project_id': 'project-1',
    'order_index': 0,
    'content': 'old segment',
    ...metadata,
  });
  await db.insert('segment_revisions', {
    'id': 'revision-1',
    'project_id': 'project-1',
    'segment_id': 'segment-1',
    'revision_number': 1,
    'content': 'old revision',
    'note': '',
    'user_instruction': '',
    'mode': 'local_edit',
    ...metadata,
  });
  await db.insert('outline_nodes', {
    'id': 'outline-1',
    'project_id': 'project-1',
    'title': 'old outline',
    'summary': 'old outline summary',
    'order_index': 0,
    'status': 'current',
    ...metadata,
  });
  await db.insert('character_cards', {
    'id': 'character-1',
    'project_id': 'project-1',
    'name': 'old character',
    'content': 'old character content',
    'sort_order': 0,
    ...metadata,
  });
  await db.insert('world_cards', {
    'id': 'world-1',
    'project_id': 'project-1',
    'title': 'old world',
    'content': 'old world content',
    'sort_order': 0,
    ...metadata,
  });
  await db.insert('chat_personas', {
    'id': 'persona-1',
    'name': 'old persona',
    'avatar_reference': null,
    'description_mode': 'simple',
    'short_description': 'old persona description',
    'speaking_style': 'short sentences',
    'core_identity': '',
    'personality': '',
    'background': '',
    'relationship_to_user': '',
    'behavior_habits': '',
    'preferences': '',
    'scenario': '',
    'notes': '',
    'auto_memory_enabled': 1,
    'use_long_term_memory': 1,
    ...metadata,
  });
  await db.insert('chat_sessions', {
    'id': 'session-1',
    'project_id': null,
    'character_id': null,
    'persona_id': 'persona-1',
    'title': 'old chat',
    ...metadata,
  });
  await db.insert('chat_messages', {
    'id': 'message-1',
    'session_id': 'session-1',
    'project_id': null,
    'role': 'user',
    'content': 'old message remains intact',
    ...metadata,
  });
  await db.insert('novel_summary_chunks', {
    'id': 'chunk-1',
    'project_id': 'project-1',
    'source_start_order': 0,
    'source_end_order': 0,
    'source_start_segment_id': 'segment-1',
    'source_end_segment_id': 'segment-1',
    'summary': 'old chunk',
    'source_fingerprint': 'fingerprint',
    'status': 'valid',
    'provider': null,
    'model': null,
    ...metadata,
  });
  await db.insert('story_memory_digests', {
    'id': 'digest-1',
    'project_id': 'project-1',
    'content': 'old digest',
    'source_through_order': 0,
    'source_fingerprint': 'fingerprint',
    'status': 'valid',
    'is_user_edited': 0,
    'is_pinned': 0,
    'provider': null,
    'model': null,
    ...metadata,
  });
  await db.insert('reader_preferences', {
    'project_id': 'project-1',
    'font_size': 18.0,
    'line_height': 1.7,
    'horizontal_margin': 24.0,
    'theme': 'warm',
    'updated_at': at,
  });
  await db.insert('reader_progress', {
    'project_id': 'project-1',
    'last_read_segment_id': 'segment-1',
    'scroll_offset': 12.0,
    'updated_at': at,
  });
  for (final memory in <Map<String, Object?>>[
    {
      'id': 'memory-legacy',
      'source_session_id': null,
      'content': 'legacy unassigned memory',
    },
    {
      'id': 'memory-session',
      'source_session_id': 'session-1',
      'content': 'session memory',
    },
  ]) {
    await db.insert('chat_memory_entries', {
      'id': memory['id'],
      'persona_id': 'persona-1',
      'category': 'other',
      'content': memory['content'],
      'origin': 'auto',
      'is_pinned': 0,
      'is_user_edited': 0,
      'source_session_id': memory['source_session_id'],
      'source_start_message_id': 'message-1',
      'source_end_message_id': 'message-1',
      ...metadata,
    });
  }
  await db.insert('conversation_summaries', {
    'id': 'summary-1',
    'session_id': 'session-1',
    'source_start_message_id': 'message-1',
    'source_end_message_id': 'message-1',
    'summary': 'old conversation summary',
    'source_fingerprint': 'fingerprint',
    'status': 'valid',
    ...metadata,
  });
}
