import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_chat_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  group('chat character schema compatibility', () {
    test('declares schema version 6', () {
      expect(SqliteSchema.version, 22);
    });

    test('fresh database includes nullable character_id', () async {
      final fixture = await SqliteFixture.create();
      final db = await fixture.database.database;

      final columns = await db.rawQuery('PRAGMA table_info(chat_sessions)');

      expect(columns.map((column) => column['name']), contains('character_id'));
      expect(
        columns.singleWhere(
          (column) => column['name'] == 'character_id',
        )['notnull'],
        0,
      );
    });

    test('fresh database includes character lookup index', () async {
      final fixture = await SqliteFixture.create();
      final db = await fixture.database.database;

      final indexes = await db.rawQuery('PRAGMA index_list(chat_sessions)');

      expect(
        indexes.map((index) => index['name']),
        contains('idx_chat_sessions_character_updated'),
      );
    });

    test('version 1 database migrates to current version', () async {
      final fixture = await _LegacyFixture.create();

      final db = await fixture.database.database;
      final version =
          (await db.rawQuery('PRAGMA user_version')).single.values.first as int;

      expect(version, SqliteSchema.version);
    });

    test('migration preserves the legacy session', () async {
      final fixture = await _LegacyFixture.create();

      final session = await fixture.chats.getSession('legacy-session');

      expect(session.title, 'Ibuki');
      expect(session.projectId, isNull);
    });

    test('migration keeps legacy characterId null', () async {
      final fixture = await _LegacyFixture.create();

      final session = await fixture.chats.getSession('legacy-session');

      expect(session.characterId, isNull);
    });

    test(
      'migration does not guess a character from the session title',
      () async {
        final fixture = await _LegacyFixture.create();

        final session = await fixture.chats.getSession('legacy-session');

        expect(session.title, 'Ibuki');
        expect(session.characterId, isNull);
      },
    );

    test('migration preserves legacy messages', () async {
      final fixture = await _LegacyFixture.create();

      final messages = await fixture.chats.listMessages('legacy-session');

      expect(messages.single.content, 'legacy message');
    });

    test('migration preserves the legacy project', () async {
      final fixture = await _LegacyFixture.create();
      final db = await fixture.database.database;

      final rows = await db.query(
        'projects',
        where: 'id = ?',
        whereArgs: ['project-1'],
      );

      expect(rows, hasLength(1));
    });
  });

  test('SQLite rejects new novel character bindings', () async {
    final fixture = await SqliteFixture.create();
    expect(
      fixture.chatRepository.upsertSession(
        chatSession('s1', null).copyWith(characterId: 'novel-card'),
      ),
      throwsA(isA<DataConflictException>()),
    );
    expect(await fixture.chatRepository.listSessions(), isEmpty);
  });
}

class _LegacyFixture {
  _LegacyFixture({required this.directory, required this.database})
    : chats = SQLiteChatRepository(database);

  final Directory directory;
  final IbukiDatabase database;
  final SQLiteChatRepository chats;

  static Future<_LegacyFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'ibukihome_chat_v1_',
    );
    final databasePath = p.join(directory.path, 'ibukihome.db');
    final legacy = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createVersionOneSchema(db);
        },
      ),
    );
    await _insertVersionOneData(legacy);
    await legacy.close();

    final database = IbukiDatabase(
      pathResolver: () async => databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    await database.open();
    final fixture = _LegacyFixture(directory: directory, database: database);
    addTearDown(() async {
      await database.close();
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    return fixture;
  }
}

Future<void> _createVersionOneSchema(Database db) async {
  await db.execute('''
CREATE TABLE projects (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL,
  deleted_at TEXT NULL
)
''');
  await db.execute('''
CREATE TABLE character_cards (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  name TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL,
  deleted_at TEXT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''');
  await db.execute('''
CREATE TABLE chat_sessions (
  id TEXT PRIMARY KEY,
  project_id TEXT NULL,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL,
  deleted_at TEXT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''');
  await db.execute('''
CREATE TABLE chat_messages (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  project_id TEXT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL,
  deleted_at TEXT NULL,
  FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE RESTRICT,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE RESTRICT
)
''');
}

Future<void> _insertVersionOneData(Database db) async {
  const time = '2026-08-10T08:00:00.000Z';
  await db.insert('projects', {
    'id': 'project-1',
    'title': 'Legacy project',
    'description': '',
    'created_at': time,
    'updated_at': time,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('character_cards', {
    'id': 'character-1',
    'project_id': 'project-1',
    'name': 'Ibuki',
    'content': '',
    'sort_order': 0,
    'created_at': time,
    'updated_at': time,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('chat_sessions', {
    'id': 'legacy-session',
    'project_id': 'project-1',
    'title': 'Ibuki',
    'created_at': time,
    'updated_at': time,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('chat_messages', {
    'id': 'legacy-message',
    'session_id': 'legacy-session',
    'project_id': 'project-1',
    'role': 'user',
    'content': 'legacy message',
    'created_at': time,
    'updated_at': time,
    'revision': 1,
    'deleted_at': null,
  });
}
