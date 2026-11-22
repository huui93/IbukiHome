import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_chat_persona_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_chat_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  group('SQLite ChatPersona repository', () {
    test('fresh schema is version 6', () {
      expect(SqliteSchema.version, 21);
    });

    test('fresh schema includes chat_personas table', () async {
      final fixture = await SqliteFixture.create();
      final db = await fixture.database.database;
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(tables.map((row) => row['name']), contains('chat_personas'));
    });

    test('fresh schema includes nullable persona_id', () async {
      final fixture = await SqliteFixture.create();
      final db = await fixture.database.database;
      final columns = await db.rawQuery('PRAGMA table_info(chat_sessions)');
      final persona = columns.singleWhere((row) => row['name'] == 'persona_id');
      expect(persona['notnull'], 0);
    });

    test('persona persists across reopen', () async {
      final fixture = await SqliteFixture.create();
      await fixture.personas.upsertPersona(chatPersona('p1'));
      final reopened = await reopenFixture(fixture);
      expect((await reopened.personas.getPersona('p1')).name, 'p1');
    });

    test('detailed fields persist across reopen', () async {
      final fixture = await SqliteFixture.create();
      await fixture.personas.upsertPersona(
        chatPersona(
          'p1',
          mode: ChatPersonaDescriptionMode.detailed,
        ).copyWith(background: '雨夜旧公寓', relationshipToUser: '旧友'),
      );
      final reopened = await reopenFixture(fixture);
      final persona = await reopened.personas.getPersona('p1');
      expect(persona.background, '雨夜旧公寓');
      expect(persona.relationshipToUser, '旧友');
    });

    test('persona binding persists across reopen', () async {
      final fixture = await SqliteFixture.create();
      await fixture.personas.upsertPersona(chatPersona('p1'));
      await fixture.chatRepository.upsertSession(
        chatSession('s1', null).copyWith(personaId: 'p1'),
      );
      final reopened = await reopenFixture(fixture);
      expect((await reopened.chatRepository.getSession('s1')).personaId, 'p1');
    });

    test('bound persona can be upgraded without replacing its row', () async {
      final fixture = await SqliteFixture.create();
      final original = chatPersona('p1');
      await fixture.personas.upsertPersona(original);
      await fixture.chatRepository.upsertSession(
        chatSession('s1', null).copyWith(personaId: 'p1'),
      );

      await fixture.personas.upsertPersona(
        original.copyWith(
          descriptionMode: ChatPersonaDescriptionMode.detailed,
          background: 'A quiet rainy evening.',
        ),
      );

      final stored = await fixture.personas.getPersona('p1');
      expect(stored.descriptionMode, ChatPersonaDescriptionMode.detailed);
      expect(stored.background, 'A quiet rainy evening.');
      expect((await fixture.chatRepository.getSession('s1')).personaId, 'p1');
    });
  });

  group('version 2 to version 6 migration', () {
    test('migrates to current schema without dropping data', () async {
      final fixture = await _VersionTwoFixture.create();
      final db = await fixture.database.database;
      expect(await db.getVersion(), SqliteSchema.version);
      for (final table in [
        'projects',
        'segments',
        'segment_revisions',
        'character_cards',
        'world_cards',
        'chat_sessions',
        'chat_messages',
      ]) {
        expect(await db.query(table), isNotEmpty, reason: table);
      }
    });

    test('creates one migrated Persona per CharacterCard', () async {
      final fixture = await _VersionTwoFixture.create();
      final personas = await fixture.personas.listPersonas(
        includeDeleted: true,
      );
      expect(personas, hasLength(1));
      expect(personas.single.name, 'Legacy Character');
    });

    test('multiple sessions reuse one migrated Persona', () async {
      final fixture = await _VersionTwoFixture.create();
      final one = await fixture.chats.getSession('session-1');
      final two = await fixture.chats.getSession('session-2');
      expect(one.personaId, two.personaId);
      expect(one.personaId, 'legacy-character:character-1');
    });

    test('migration detaches legacy character links', () async {
      final fixture = await _VersionTwoFixture.create();
      final session = await fixture.chats.getSession('session-1');
      expect(session.characterId, isNull);
    });

    test('null characterId remains an unbound old session', () async {
      final fixture = await _VersionTwoFixture.create();
      final session = await fixture.chats.getSession('legacy-unbound');
      expect(session.characterId, isNull);
      expect(session.personaId, isNull);
    });

    test(
      'missing CharacterCard leaves session unbound without failing',
      () async {
        final fixture = await _VersionTwoFixture.create(includeMissing: true);
        final session = await fixture.chats.getSession('missing-character');
        expect(session.characterId, isNull);
        expect(session.personaId, isNull);
      },
    );

    test('migration preserves legacy messages', () async {
      final fixture = await _VersionTwoFixture.create();
      expect(
        (await fixture.chats.listMessages('session-1')).single.content,
        'hello',
      );
    });

    test('migration does not infer Persona from session title', () async {
      final fixture = await _VersionTwoFixture.create();
      final session = await fixture.chats.getSession('legacy-unbound');
      expect(session.title, 'Legacy Character');
      expect(session.personaId, isNull);
    });

    test(
      'migrated Persona is a snapshot independent from CharacterCard',
      () async {
        final fixture = await _VersionTwoFixture.create();
        final db = await fixture.database.database;
        await db.update(
          'character_cards',
          {'content': 'changed later'},
          where: 'id = ?',
          whereArgs: ['character-1'],
        );
        final persona = await fixture.personas.getPersona(
          'legacy-character:character-1',
        );
        expect(persona.shortDescription, 'legacy description');
      },
    );
  });
}

class _VersionTwoFixture {
  _VersionTwoFixture(this.directory, this.database)
    : chats = SQLiteChatRepository(database),
      personas = SQLiteChatPersonaRepository(database);

  final Directory directory;
  final IbukiDatabase database;
  final SQLiteChatRepository chats;
  final SQLiteChatPersonaRepository personas;

  static Future<_VersionTwoFixture> create({
    bool includeMissing = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp('ibuki_v2_');
    final path = p.join(directory.path, 'ibukihome.db');
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) => _createVersionTwo(db),
      ),
    );
    await _seedVersionTwo(old, includeMissing: includeMissing);
    await old.close();
    final database = IbukiDatabase(
      pathResolver: () async => path,
      databaseFactory: databaseFactoryFfi,
    );
    await database.open();
    final fixture = _VersionTwoFixture(directory, database);
    addTearDown(() async {
      await database.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    return fixture;
  }
}

Future<void> _createVersionTwo(Database db) async {
  for (final statement in SqliteSchema.createTableStatements) {
    if (statement.contains('CREATE TABLE chat_personas')) continue;
    if (statement.contains('CREATE TABLE outline_nodes')) continue;
    if (statement.contains('CREATE TABLE novel_summary_chunks')) continue;
    if (statement.contains('CREATE TABLE story_memory_digests')) continue;
    if (statement.contains('CREATE TABLE reader_preferences')) continue;
    if (statement.contains('CREATE TABLE reader_progress')) continue;
    if (statement.contains('CREATE TABLE chat_memory_entries')) continue;
    if (statement.contains('CREATE TABLE conversation_summaries')) continue;
    if (statement.contains('CREATE TABLE projects')) {
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
    } else if (statement.contains('CREATE TABLE chat_sessions')) {
      await db.execute('''
CREATE TABLE chat_sessions (
  id TEXT PRIMARY KEY,
  project_id TEXT NULL,
  character_id TEXT NULL,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL,
  deleted_at TEXT NULL
)
''');
    } else {
      await db.execute(statement);
    }
  }
}

Future<void> _seedVersionTwo(
  Database db, {
  required bool includeMissing,
}) async {
  const time = '2026-08-11T08:00:00.000Z';
  await db.insert('projects', {
    'id': 'project-1',
    'title': 'Legacy Project',
    'description': 'direction',
    'created_at': time,
    'updated_at': time,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('segments', {
    'id': 'segment-1',
    'project_id': 'project-1',
    'order_index': 0,
    'content': 'segment',
    'created_at': time,
    'updated_at': time,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('segment_revisions', {
    'id': 'revision-1',
    'project_id': 'project-1',
    'segment_id': 'segment-1',
    'revision_number': 1,
    'content': 'old',
    'note': '',
    'user_instruction': '',
    'mode': 'local_edit',
    'created_at': time,
    'updated_at': time,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('character_cards', {
    'id': 'character-1',
    'project_id': 'project-1',
    'name': 'Legacy Character',
    'content': 'legacy description',
    'sort_order': 0,
    'created_at': time,
    'updated_at': time,
    'revision': 1,
    'deleted_at': null,
  });
  await db.insert('world_cards', {
    'id': 'world-1',
    'project_id': 'project-1',
    'title': 'World',
    'content': 'setting',
    'sort_order': 0,
    'created_at': time,
    'updated_at': time,
    'revision': 1,
    'deleted_at': null,
  });
  for (final entry in const [
    ('session-1', 'character-1', 'Legacy Character'),
    ('session-2', 'character-1', 'Second'),
    ('legacy-unbound', null, 'Legacy Character'),
  ]) {
    await db.insert('chat_sessions', {
      'id': entry.$1,
      'project_id': 'project-1',
      'character_id': entry.$2,
      'title': entry.$3,
      'created_at': time,
      'updated_at': time,
      'revision': 1,
      'deleted_at': null,
    });
  }
  if (includeMissing) {
    await db.insert('chat_sessions', {
      'id': 'missing-character',
      'project_id': 'project-1',
      'character_id': 'missing',
      'title': 'Missing',
      'created_at': time,
      'updated_at': time,
      'revision': 1,
      'deleted_at': null,
    });
  }
  await db.insert('chat_messages', {
    'id': 'message-1',
    'session_id': 'session-1',
    'project_id': 'project-1',
    'role': 'user',
    'content': 'hello',
    'created_at': time,
    'updated_at': time,
    'revision': 1,
    'deleted_at': null,
  });
}
