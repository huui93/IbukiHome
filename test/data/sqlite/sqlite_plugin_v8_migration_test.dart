import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_plugin_registry.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:ibukihome/domain/plugins/ibuki_plugin_manifest.dart';
import 'package:ibukihome/domain/plugins/installed_plugin.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('real v7 disk database migrates non-destructively to v8', () async {
    final directory = await Directory.systemTemp.createTemp('ibuki_v7_plugin_');
    final path = p.join(directory.path, 'ibukihome.db');
    final databases = <IbukiDatabase>[];
    try {
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (db, _) async {
            for (final statement in SqliteSchema.createTableStatements) {
              if (statement.contains('CREATE TABLE installed_plugins') ||
                  statement.contains('CREATE TABLE plugin_storage')) {
                continue;
              }
              await db.execute(statement);
            }
            for (final statement in SqliteSchema.createIndexStatements) {
              if (statement.contains('idx_installed_plugins') ||
                  statement.contains('idx_plugin_storage')) {
                continue;
              }
              await db.execute(statement);
            }
            await _seedV7(db);
          },
        ),
      );
      await old.close();

      final database = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      databases.add(database);
      final db = await database.open();
      expect(await db.getVersion(), SqliteSchema.version);
      await _expectBusinessDataPreserved(db);
      expect(await _count(db, 'installed_plugins'), 0);
      expect(await _count(db, 'plugin_storage'), 0);

      final registry = SQLitePluginRegistry(database);
      final installed = InstalledPlugin(
        manifest: const IbukiPluginManifest(
          manifestVersion: 1,
          id: 'dev.ibuki.persisted',
          name: 'Persisted Plugin',
          version: '1.0.0',
          capabilities: ['future.capability'],
        ),
        installedPath: p.join(
          directory.path,
          'plugins',
          'installed',
          'dev.ibuki.persisted',
        ),
        dataPath: p.join(directory.path, 'plugin_data', 'dev.ibuki.persisted'),
        enabled: false,
        installedAt: DateTime.utc(2026, 8, 26),
        updatedAt: DateTime.utc(2026, 8, 26),
        packageSize: 100,
        extractedSize: 200,
      );
      await registry.upsertPlugin(installed);
      await database.close();

      final reopened = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      databases.add(reopened);
      final persisted = await SQLitePluginRegistry(
        reopened,
      ).getPlugin(installed.id);
      expect(persisted?.manifest.name, 'Persisted Plugin');
      expect(persisted?.manifest.capabilities, ['future.capability']);
      expect(persisted?.enabled, false);
      final reopenedDb = await reopened.database;
      await reopenedDb.update(
        'installed_plugins',
        {'manifest_json': '{broken'},
        where: 'id = ?',
        whereArgs: [installed.id],
      );
      final isolated = await SQLitePluginRegistry(reopened).listPlugins();
      expect(isolated.single.status, InstalledPluginStatus.broken);
      expect(isolated.single.errorCategory, 'registryManifestInvalid');
      await reopened.close();
    } finally {
      await _disposeDatabases(databases, directory);
    }
  });

  test('early v8 plugin table is repaired without a version bump', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ibuki_early_v8_plugin_',
    );
    final path = p.join(directory.path, 'ibukihome.db');
    final databases = <IbukiDatabase>[];
    try {
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 8,
          onCreate: (db, _) async {
            for (final statement in SqliteSchema.createTableStatements) {
              if (statement.contains('CREATE TABLE installed_plugins') ||
                  statement.contains('CREATE TABLE plugin_storage')) {
                continue;
              }
              await db.execute(statement);
            }
            for (final statement in SqliteSchema.createIndexStatements) {
              if (statement.contains('idx_installed_plugins') ||
                  statement.contains('idx_plugin_storage')) {
                continue;
              }
              await db.execute(statement);
            }
            await db.execute('''
CREATE TABLE installed_plugins (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  version TEXT NOT NULL,
  author TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  manifest_version INTEGER NOT NULL,
  manifest_json TEXT NOT NULL,
  installed_path TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'installed',
  error_category TEXT NULL,
  package_size INTEGER NOT NULL DEFAULT 0,
  extracted_size INTEGER NOT NULL DEFAULT 0,
  installed_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');
            await _seedV7(db);
          },
        ),
      );
      await old.close();

      final database = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      databases.add(database);
      final db = await database.open();

      expect(await db.getVersion(), SqliteSchema.version);
      await _expectBusinessDataPreserved(db);
      final columns = await db.rawQuery('PRAGMA table_info(installed_plugins)');
      expect(columns.map((row) => row['name']), contains('data_path'));
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'plugin_storage'",
        ),
        isNotEmpty,
      );

      final registry = SQLitePluginRegistry(database);
      final installed = InstalledPlugin(
        manifest: const IbukiPluginManifest(
          manifestVersion: 1,
          id: 'dev.ibuki.repaired',
          name: 'Repaired Plugin',
          version: '1.0.0',
        ),
        installedPath: p.join(directory.path, 'installed'),
        dataPath: p.join(directory.path, 'data'),
        enabled: true,
        installedAt: DateTime.utc(2026, 8, 27),
        updatedAt: DateTime.utc(2026, 8, 27),
      );
      await registry.upsertPlugin(installed);
      expect(
        (await registry.getPlugin(installed.id))?.dataPath,
        installed.dataPath,
      );
      await database.close();
    } finally {
      await _disposeDatabases(databases, directory);
    }
  });

  test('complete v8 reopens idempotently and preserves business data', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ibuki_complete_v8_plugin_',
    );
    final path = p.join(directory.path, 'ibukihome.db');
    final databases = <IbukiDatabase>[];
    try {
      final initial = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      databases.add(initial);
      final initialDb = await initial.open();
      await _seedV7(initialDb);
      await initial.close();

      for (var reopen = 0; reopen < 2; reopen += 1) {
        final database = IbukiDatabase(
          pathResolver: () async => path,
          databaseFactory: databaseFactoryFfi,
        );
        databases.add(database);
        final db = await database.open();
        expect(await db.getVersion(), SqliteSchema.version);
        await _expectBusinessDataPreserved(db);
        final columns = await db.rawQuery(
          'PRAGMA table_info(installed_plugins)',
        );
        expect(
          columns.where((row) => row['name'] == 'data_path'),
          hasLength(1),
        );
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'plugin_storage'",
          ),
          hasLength(1),
        );
        await database.close();
      }
    } finally {
      await _disposeDatabases(databases, directory);
    }
  });
}

Future<void> _disposeDatabases(
  Iterable<IbukiDatabase> databases,
  Directory directory,
) async {
  for (final database in databases) {
    await database.close();
  }
  if (directory.existsSync()) directory.deleteSync(recursive: true);
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
  return rows.single['count']! as int;
}

Future<void> _seedV7(Database db) async {
  const at = '2026-08-26T00:00:00.000Z';
  const metadata = {
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  };
  await db.insert('projects', {
    'id': 'project-v7',
    'title': '旧项目',
    'description': '保留',
    'system_prompt': '旧系统提示词',
    'ai_provider_config_id': 'gemini',
    'ai_model': 'gemini-test',
    ...metadata,
  });
  await db.insert('outline_nodes', {
    'id': 'outline-v7',
    'project_id': 'project-v7',
    'title': '旧大纲',
    'summary': '保留',
    'order_index': 0,
    'status': 'current',
    ...metadata,
  });
  await db.insert('segments', {
    'id': 'segment-v7',
    'project_id': 'project-v7',
    'order_index': 0,
    'content': '旧正文',
    ...metadata,
  });
  await db.insert('segment_revisions', {
    'id': 'revision-v7',
    'project_id': 'project-v7',
    'segment_id': 'segment-v7',
    'revision_number': 1,
    'content': '旧修订',
    'note': '',
    'user_instruction': '',
    'mode': 'edit',
    ...metadata,
  });
  await db.insert('character_cards', {
    'id': 'character-v7',
    'project_id': 'project-v7',
    'name': '旧角色',
    'content': '角色内容',
    'mode': 'original',
    'source_work_title': '',
    'source_character_name': '',
    'source_version_hint': '',
    'fanfic_adaptation_notes': '',
    'original_idea': '原创',
    'sort_order': 0,
    ...metadata,
  });
  await db.insert('world_cards', {
    'id': 'world-v7',
    'project_id': 'project-v7',
    'title': '旧世界观',
    'content': '世界内容',
    'sort_order': 0,
    ...metadata,
  });
  await db.insert('chat_personas', {
    'id': 'persona-v7',
    'name': '旧角色人格',
    'avatar_reference': null,
    'description_mode': 'simple',
    'short_description': '',
    'speaking_style': '',
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
    'id': 'session-v7',
    'project_id': null,
    'character_id': null,
    'persona_id': 'persona-v7',
    'ai_provider_config_id': 'deepseek',
    'ai_model': 'deepseek-test',
    'title': '旧聊天',
    ...metadata,
  });
  await db.insert('chat_messages', {
    'id': 'message-v7',
    'session_id': 'session-v7',
    'project_id': null,
    'role': 'user',
    'content': '旧消息',
    'finish_reason': null,
    ...metadata,
  });
  await db.insert('novel_summary_chunks', {
    'id': 'summary-chunk-v7',
    'project_id': 'project-v7',
    'source_start_order': 0,
    'source_end_order': 0,
    'source_start_segment_id': 'segment-v7',
    'source_end_segment_id': 'segment-v7',
    'summary': '旧小说摘要',
    'source_fingerprint': 'summary-fingerprint-v7',
    'status': 'valid',
    'provider': 'gemini',
    'model': 'gemini-test',
    ...metadata,
  });
  await db.insert('story_memory_digests', {
    'id': 'story-digest-v7',
    'project_id': 'project-v7',
    'content': '旧故事记忆',
    'source_through_order': 0,
    'source_fingerprint': 'digest-fingerprint-v7',
    'status': 'valid',
    'is_user_edited': 1,
    'is_pinned': 1,
    'provider': 'gemini',
    'model': 'gemini-test',
    ...metadata,
  });
  await db.insert('chat_memory_entries', {
    'id': 'chat-memory-v7',
    'persona_id': 'persona-v7',
    'session_id': 'session-v7',
    'category': 'preference',
    'content': '旧聊天记忆',
    'origin': 'manual',
    'is_pinned': 1,
    'is_user_edited': 1,
    'source_session_id': 'session-v7',
    'source_start_message_id': 'message-v7',
    'source_end_message_id': 'message-v7',
    ...metadata,
  });
  await db.insert('conversation_summaries', {
    'id': 'conversation-summary-v7',
    'session_id': 'session-v7',
    'source_start_message_id': 'message-v7',
    'source_end_message_id': 'message-v7',
    'summary': '旧会话摘要',
    'source_fingerprint': 'conversation-fingerprint-v7',
    'status': 'valid',
    ...metadata,
  });
}

Future<void> _expectBusinessDataPreserved(Database db) async {
  const expectations = <String, (String, Object?)>{
    'projects': ('title', '旧项目'),
    'segments': ('content', '旧正文'),
    'segment_revisions': ('content', '旧修订'),
    'outline_nodes': ('title', '旧大纲'),
    'character_cards': ('content', '角色内容'),
    'world_cards': ('content', '世界内容'),
    'chat_personas': ('name', '旧角色人格'),
    'chat_sessions': ('ai_model', 'deepseek-test'),
    'chat_messages': ('content', '旧消息'),
    'novel_summary_chunks': ('summary', '旧小说摘要'),
    'story_memory_digests': ('content', '旧故事记忆'),
    'chat_memory_entries': ('content', '旧聊天记忆'),
    'conversation_summaries': ('summary', '旧会话摘要'),
  };
  for (final MapEntry(key: table, value: expectation) in expectations.entries) {
    final rows = await db.query(table);
    expect(rows, hasLength(1), reason: table);
    expect(rows.single[expectation.$1], expectation.$2, reason: table);
  }
}
