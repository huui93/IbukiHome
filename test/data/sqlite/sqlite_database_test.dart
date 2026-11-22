import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_migrations.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  group('SQLite database', () {
    test('creates version 1 database', () async {
      final fixture = await SqliteFixture.create();

      final db = await fixture.database.database;
      final version = await db.getVersion();

      expect(version, SqliteSchema.version);
    });

    test('creates all required tables', () async {
      final fixture = await SqliteFixture.create();
      final db = await fixture.database.database;

      final tables = await _sqliteNames(db, 'table');

      expect(
        tables,
        containsAll([
          'projects',
          'segments',
          'segment_revisions',
          'character_cards',
          'world_cards',
          'chat_personas',
          'chat_sessions',
          'chat_messages',
        ]),
      );
    });

    test('creates all required indexes', () async {
      final fixture = await SqliteFixture.create();
      final db = await fixture.database.database;

      final indexes = await _sqliteNames(db, 'index');

      expect(
        indexes,
        containsAll([
          'idx_projects_updated_at',
          'idx_segments_project_id',
          'idx_segments_project_order',
          'idx_segment_revisions_project_id',
          'idx_segment_revisions_segment_revision',
          'idx_character_cards_project_sort',
          'idx_world_cards_project_sort',
          'idx_chat_sessions_project_created',
          'idx_chat_personas_name',
          'idx_chat_sessions_persona_updated',
          'idx_chat_messages_session_created',
          'idx_chat_messages_project_id',
        ]),
      );
    });

    test('enables foreign_keys pragma', () async {
      final fixture = await SqliteFixture.create();
      final db = await fixture.database.database;

      final result = await db.rawQuery('PRAGMA foreign_keys');

      expect(result.single.values.single, 1);
    });

    test('stores user_version as schema version', () async {
      final fixture = await SqliteFixture.create();
      final db = await fixture.database.database;

      final result = await db.rawQuery('PRAGMA user_version');

      expect(result.single.values.single, SqliteSchema.version);
    });

    test('repeated open reuses the existing database', () async {
      final fixture = await SqliteFixture.create();

      await fixture.database.open();
      await fixture.database.open();

      expect(fixture.database.openCount, 1);
    });

    test('rejects a database version higher than the app supports', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ibukihome_high_version_',
      );
      addTearDown(() {
        if (directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      });
      final databasePath = p.join(directory.path, 'ibukihome.db');
      final highVersionDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
      );
      await highVersionDatabase.setVersion(SqliteSchema.version + 1);
      await highVersionDatabase.close();

      final database = IbukiDatabase(
        pathResolver: () async => databasePath,
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);

      expect(
        database.open(),
        throwsA(isA<UnsupportedDatabaseVersionException>()),
      );
    });

    test('closed database operations fail clearly', () async {
      final fixture = await SqliteFixture.create();
      await fixture.database.close();

      expect(
        fixture.projects.listProjects(),
        throwsA(isA<DatabaseClosedException>()),
      );
    });
  });
}

Future<Set<String>> _sqliteNames(dynamic db, String type) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = ?",
    [type],
  );
  return rows.map<String>((row) => row['name'] as String).toSet();
}
