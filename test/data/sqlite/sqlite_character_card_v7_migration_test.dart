import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'real v6 disk database migrates to latest without guessing card mode',
    () async {
      final directory = await Directory.systemTemp.createTemp('ibuki_v6_card_');
      final path = p.join(directory.path, 'ibukihome.db');
      try {
        final old = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 6,
            onCreate: (db, _) async {
              for (var statement in SqliteSchema.createTableStatements) {
                statement = statement
                    .replaceAll(
                      "  mode TEXT NULL CHECK (mode IS NULL OR mode IN ('fanfic', 'original')),\n",
                      '',
                    )
                    .replaceAll(
                      "  source_work_title TEXT NOT NULL DEFAULT '',\n",
                      '',
                    )
                    .replaceAll(
                      "  source_character_name TEXT NOT NULL DEFAULT '',\n",
                      '',
                    )
                    .replaceAll(
                      "  source_version_hint TEXT NOT NULL DEFAULT '',\n",
                      '',
                    )
                    .replaceAll(
                      "  fanfic_adaptation_notes TEXT NOT NULL DEFAULT '',\n",
                      '',
                    )
                    .replaceAll(
                      "  original_idea TEXT NOT NULL DEFAULT '',\n",
                      '',
                    );
                await db.execute(statement);
              }
              for (final statement in SqliteSchema.createIndexStatements) {
                await db.execute(statement);
              }
              await _seed(db);
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
        final character = (await db.query('character_cards')).single;
        expect(character['name'], '旧角色');
        expect(character['content'], '用户原有设定必须保留');
        expect(character['mode'], isNull);
        expect(character['source_work_title'], '');
        expect(character['source_character_name'], '');
        expect(character['source_version_hint'], '');
        expect(character['fanfic_adaptation_notes'], '');
        expect(character['original_idea'], '');
        expect(await _count(db, 'projects'), 1);
        expect(await _count(db, 'chat_sessions'), 1);
        expect(await _count(db, 'chat_messages'), 1);
        expect(
          (await db.query('chat_messages')).single['content'],
          '旧聊天消息必须保留',
        );

        await db.update(
          'character_cards',
          {
            'mode': 'fanfic',
            'source_work_title': '测试作品',
            'source_character_name': '测试角色',
            'source_version_hint': '通常形态',
            'fanfic_adaptation_notes': '本作穿白色大衣',
          },
          where: 'id = ?',
          whereArgs: ['character-1'],
        );
        await database.close();

        final reopened = IbukiDatabase(
          pathResolver: () async => path,
          databaseFactory: databaseFactoryFfi,
        );
        final reopenedDb = await reopened.open();
        final persisted = (await reopenedDb.query('character_cards')).single;
        expect(persisted['mode'], 'fanfic');
        expect(persisted['fanfic_adaptation_notes'], '本作穿白色大衣');
        await reopened.close();
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

Future<void> _seed(Database db) async {
  const at = '2026-08-13T00:00:00.000Z';
  const metadata = {
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  };
  await db.insert('projects', {
    'id': 'project-1',
    'title': '旧作品',
    'description': '',
    'system_prompt': '',
    'ai_provider_config_id': null,
    'ai_model': null,
    ...metadata,
  });
  await db.insert('character_cards', {
    'id': 'character-1',
    'project_id': 'project-1',
    'name': '旧角色',
    'content': '用户原有设定必须保留',
    'sort_order': 0,
    ...metadata,
  });
  await db.insert('chat_sessions', {
    'id': 'session-1',
    'project_id': null,
    'character_id': null,
    'persona_id': null,
    'title': '旧会话',
    'ai_provider_config_id': null,
    'ai_model': null,
    ...metadata,
  });
  await db.insert('chat_messages', {
    'id': 'message-1',
    'session_id': 'session-1',
    'project_id': null,
    'role': 'user',
    'content': '旧聊天消息必须保留',
    'finish_reason': null,
    ...metadata,
  });
}
