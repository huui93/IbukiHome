import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:ibukihome/data/sqlite/sqlite_migrations.dart';
import 'package:ibukihome/data/sqlite/sqlite_tavern_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'package:ibukihome/domain/tavern/tavern_world_info.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';

final _now = DateTime.utc(2026, 10, 15).toIso8601String();
Future<Database> _v13(
  String path, {
  bool fail = false,
}) => databaseFactoryFfi.openDatabase(
  path,
  options: OpenDatabaseOptions(
    version: 13,
    onOpen: ensureCurrentSchema,
    onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys=ON');
    },
    onCreate: (db, _) async {
      for (final statement in SqliteSchema.createTableStatements) {
        if (!statement.contains('tavern_world_info_')) {
          await db.execute(statement);
        }
      }
      for (final statement in SqliteSchema.createIndexStatements) {
        if (!statement.contains('idx_tavern_wi_')) await db.execute(statement);
      }
      await db.insert('projects', {
        'id': 'keep-project',
        'title': 'KEEP NOVEL',
        'created_at': _now,
        'updated_at': _now,
        'revision': 1,
      });
      await db.insert('tavern_sessions', {
        'id': 's',
        'title': 'old',
        'created_at': _now,
        'updated_at': _now,
      });
      await db.insert('tavern_story_lines', {
        'id': 'main',
        'session_id': 's',
        'name': 'Main',
        'position': 0,
        'created_at': _now,
      });
      await db.update(
        'tavern_sessions',
        {'active_story_line_id': 'main'},
        where: 'id = ?',
        whereArgs: ['s'],
      );
      await db.insert('tavern_participants', {
        'id': 'speaker',
        'session_id': 's',
        'kind': 'character',
        'entity_id': 'external-card-id',
        'position': 0,
      });
      await db.insert('tavern_turns', {
        'id': 'old-turn',
        'session_id': 's',
        'story_line_id': 'main',
        'position': 0,
        'participant_id': 'speaker',
        'role': 'character',
        'created_at': _now,
        'updated_at': _now,
      });
      await db.insert('tavern_alternatives', {
        'id': 'old-alt',
        'turn_id': 'old-turn',
        'position': 0,
        'origin': 'manual',
        'created_at': _now,
      });
      await db.update(
        'tavern_turns',
        {'selected_alternative_id': 'old-alt'},
        where: 'id = ?',
        whereArgs: ['old-turn'],
      );
      if (fail) {
        await db.execute(
          'CREATE VIEW tavern_world_info_journal AS SELECT id FROM projects',
        );
      }
    },
  ),
);

void main() {
  setUpAll(sqfliteFfiInit);
  test(
    'real v12 to v13 to v14 chain preserves legacy values and existing Tavern, then archives',
    () async {
      final dir = await Directory.systemTemp.createTemp('wi_acceptance_chain_');
      final path = p.join(dir.path, 'chain.db');
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 12,
          onOpen: ensureCurrentSchema,
          onConfigure: (db) async => db.execute('PRAGMA foreign_keys=ON'),
          onCreate: (db, _) async {
            for (final sql in SqliteSchema.createTableStatements) {
              if (!sql.contains('tavern_')) await db.execute(sql);
            }
            for (final sql in SqliteSchema.createIndexStatements) {
              if (!sql.contains('tavern_')) await db.execute(sql);
            }
            final timestamps = {
              'created_at': _now,
              'updated_at': _now,
              'revision': 1,
            };
            final rows = <String, Map<String, Object?>>{
              'projects': {
                'id': 'legacy-project',
                'title': 'Legacy novel',
                ...timestamps,
              },
              'segments': {
                'id': 'legacy-segment',
                'project_id': 'legacy-project',
                'order_index': 0,
                'content': 'Synthetic saved novel text',
                ...timestamps,
              },
              'character_cards': {
                'id': 'legacy-card',
                'project_id': 'legacy-project',
                'name': 'Legacy character',
                'content': 'Synthetic personality',
                'sort_order': 0,
                ...timestamps,
              },
              'world_cards': {
                'id': 'legacy-world-card',
                'project_id': 'legacy-project',
                'title': 'Legacy setting',
                'content': 'Synthetic lore',
                'sort_order': 0,
                ...timestamps,
              },
              'chat_sessions': {
                'id': 'legacy-chat',
                'title': 'Legacy chat',
                'character_id': 'legacy-card',
                ...timestamps,
              },
              'chat_messages': {
                'id': 'legacy-message',
                'session_id': 'legacy-chat',
                'role': 'assistant',
                'content': 'Synthetic saved reply',
                'finish_reason': 'stop',
                ...timestamps,
              },
              'roleplay_worlds': {
                'id': 'legacy-world',
                'name': 'Legacy World',
                'metadata_json': '{"worldSystemPrompt":"Synthetic tone"}',
                ...timestamps,
              },
              'world_sessions': {
                'id': 'legacy-world-session',
                'world_id': 'legacy-world',
                'name': 'Legacy story',
                'world_time': 'Day 12',
                'metadata_json':
                    '{"sessionAdditionalInstructions":"Synthetic instruction"}',
                ...timestamps,
              },
              'installed_plugins': {
                'id': 'legacy-plugin',
                'name': 'Synthetic plugin',
                'version': '1.0.0',
                'manifest_version': 1,
                'manifest_json': '{}',
                'installed_path': '',
                'installed_at': _now,
                'updated_at': _now,
              },
              'plugin_storage': {
                'plugin_id': 'legacy-plugin',
                'storage_key': 'synthetic',
                'value_json': '{"enabled":true}',
                'updated_at': _now,
              },
            };
            for (final entry in rows.entries) {
              await db.insert(entry.key, entry.value);
            }
          },
        ),
      );
      final legacyTables = (await old.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      )).map((r) => r['name'] as String).toList();
      final legacyRows = {
        for (final table in legacyTables) table: await old.query(table),
      };
      expect(await old.getVersion(), 12);
      await old.close();
      final intermediate = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 13,
          onUpgrade: runMigrations,
          onOpen: ensureCurrentSchema,
          onConfigure: (db) async => db.execute('PRAGMA foreign_keys=ON'),
        ),
      );
      expect(await intermediate.getVersion(), 13);
      expect(
        await intermediate.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'tavern_%'",
        ),
        hasLength(8),
      );
      for (final entry in legacyRows.entries) {
        expect(
          jsonEncode(await intermediate.query(entry.key)),
          jsonEncode(entry.value),
          reason: entry.key,
        );
      }
      await intermediate.insert('tavern_sessions', {
        'id': 'old-tavern',
        'title': 'Existing Tavern',
        'created_at': _now,
        'updated_at': _now,
      });
      await intermediate.insert('tavern_story_lines', {
        'id': 'old-main',
        'session_id': 'old-tavern',
        'name': 'Main',
        'position': 0,
        'created_at': _now,
      });
      await intermediate.update(
        'tavern_sessions',
        {'active_story_line_id': 'old-main'},
        where: 'id = ?',
        whereArgs: ['old-tavern'],
      );
      final tables = (await intermediate.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      )).map((r) => r['name'] as String).toList();
      final before = {
        for (final table in tables) table: await intermediate.query(table),
      };
      await intermediate.close();
      final upgraded = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      final target = IbukiDatabase(
        pathResolver: () async => p.join(dir.path, 'restored.db'),
        databaseFactory: databaseFactoryFfi,
      );
      IbukiDatabase? reopened;
      try {
        final sql = await upgraded.database;
        expect(await sql.getVersion(), SqliteSchema.version);
        for (final entry in before.entries) {
          if (entry.key == 'chat_sessions') {
            final row = (await sql.query(entry.key)).single;
            expect(row['character_id'], isNull);
            expect(row['project_id'], isNull);
            expect(row['title'], entry.value.single['title']);
            expect(row['persona_id'], isNotNull);
          } else if (entry.key == 'chat_personas') {
            for (final row in entry.value) {
              final restored = (await sql.query(
                entry.key,
                where: 'id = ?',
                whereArgs: [row['id']],
              )).single;
              for (final column in row.keys) {
                expect(restored[column], row[column]);
              }
            }
          } else {
            expect(
              jsonEncode(await sql.query(entry.key)),
              jsonEncode(entry.value),
              reason: entry.key,
            );
          }
        }
        final state = await SQLiteTavernRepository(
          upgraded,
        ).loadWorldInfoState('old-tavern', 'old-main');
        expect(state.provenance, TavernWorldInfoProvenance.legacyUnavailable);
        expect(state.version, 0);
        final snapshot = await SQLiteBackupSnapshotStore(
          upgraded,
        ).buildSnapshot();
        await SQLiteBackupSnapshotStore(target).restore(
          snapshot,
          mode: BackupRestoreMode.fresh,
          restoredAssets: const {},
        );
        final restored = await target.database;
        for (final table in [
          'projects',
          'segments',
          'chat_messages',
          'world_sessions',
          'tavern_sessions',
        ]) {
          expect(
            jsonEncode(await restored.query(table)),
            jsonEncode(await sql.query(table)),
            reason: table,
          );
        }
        expect(
          (await SQLiteTavernRepository(
            target,
          ).loadWorldInfoState('old-tavern', 'old-main')).provenance,
          state.provenance,
        );
        await upgraded.close();
        reopened = IbukiDatabase(
          pathResolver: () async => path,
          databaseFactory: databaseFactoryFfi,
        );
        expect(
          await (await reopened.database).getVersion(),
          SqliteSchema.version,
        );
        expect(
          await (await reopened.database).query('tavern_world_info_states'),
          hasLength(1),
        );
        expect(
          await (await reopened.database).rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
      } finally {
        await upgraded.close();
        await reopened?.close();
        await target.close();
        if (p.isWithin(Directory.systemTemp.absolute.path, dir.absolute.path) &&
            await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    },
  );

  test(
    'fresh v14 owns exactly two additional constrained/indexed Tavern tables',
    () async {
      final dir = await Directory.systemTemp.createTemp('wi_v14_fresh_');
      final db = IbukiDatabase(
        pathResolver: () async => p.join(dir.path, 'fresh.db'),
        databaseFactory: databaseFactoryFfi,
      );
      try {
        final sql = await db.database;
        expect(await sql.getVersion(), SqliteSchema.version);
        final names = (await sql.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'tavern_%'",
        )).map((r) => r['name']).toSet();
        expect(names, hasLength(10));
        expect(
          names,
          containsAll([
            'tavern_world_info_states',
            'tavern_world_info_journal',
          ]),
        );
        expect(
          await sql.rawQuery(
            'PRAGMA foreign_key_list(tavern_world_info_journal)',
          ),
          hasLength(5),
        );
        expect(
          await sql.rawQuery('PRAGMA index_list(tavern_world_info_journal)'),
          isNotEmpty,
        );
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'real v13 fixture upgrades to v14 preserving every existing table and seeds explicit unavailable state',
    () async {
      final dir = await Directory.systemTemp.createTemp('wi_v13_upgrade_');
      final path = p.join(dir.path, 'old.db');
      final old = await _v13(path);
      final tables = (await old.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      )).map((r) => r['name'] as String).toList();
      final before = {
        for (final table in tables) table: await old.query(table),
      };
      await old.close();
      final upgraded = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      try {
        final sql = await upgraded.database;
        expect(await sql.getVersion(), SqliteSchema.version);
        for (final table in tables) {
          expect(
            jsonEncode(await sql.query(table)),
            jsonEncode(before[table]),
            reason: table,
          );
        }
        final state = await SQLiteTavernRepository(
          upgraded,
        ).loadWorldInfoState('s', 'main');
        expect(state.provenance, TavernWorldInfoProvenance.legacyUnavailable);
        expect(state.version, 0);
        expect(state.data.timers, isEmpty);
        await upgraded.close();
        final reopened = IbukiDatabase(
          pathResolver: () async => path,
          databaseFactory: databaseFactoryFfi,
        );
        try {
          expect(
            (await SQLiteTavernRepository(
              reopened,
            ).loadWorldInfoState('s', 'main')).provenance,
            TavernWorldInfoProvenance.legacyUnavailable,
          );
          expect(
            await (await reopened.database).query('tavern_world_info_states'),
            hasLength(1),
          );
          final repository = SQLiteTavernRepository(reopened);
          await repository.createStoryLine(
            TavernStoryLine(
              id: 'legacy-fork',
              sessionId: 's',
              name: 'Legacy fork',
              position: 1,
              parentId: 'main',
              originTurnId: 'old-turn',
              originAlternativeId: 'old-alt',
              createdAt: DateTime.utc(2026, 10, 15),
            ),
          );
          final fork = await repository.loadWorldInfoState('s', 'legacy-fork');
          expect(
            fork.provenance,
            TavernWorldInfoProvenance.historicalUnavailable,
          );
          expect(fork.data.timers, isEmpty);
          expect(fork.initialAttemptId, isNull);
        } finally {
          await reopened.close();
        }
      } finally {
        await upgraded.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'failed v13 to v14 upgrade rolls back new state table and retains old version/data',
    () async {
      final dir = await Directory.systemTemp.createTemp('wi_v14_rollback_');
      final path = p.join(dir.path, 'old.db');
      final old = await _v13(path, fail: true);
      await old.close();
      final failing = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      await expectLater(failing.open(), throwsA(anything));
      await failing.close();
      final inspected = await databaseFactoryFfi.openDatabase(path);
      try {
        expect(await inspected.getVersion(), 13);
        expect(
          (await inspected.query('projects')).single['title'],
          'KEEP NOVEL',
        );
        expect(
          (await inspected.query(
            'tavern_turns',
          )).single['selected_alternative_id'],
          'old-alt',
        );
        expect(
          await inspected.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='tavern_world_info_states'",
          ),
          isEmpty,
        );
      } finally {
        await inspected.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'missing v14 state is not silently re-seeded as empty on reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('wi_v14_missing_');
      final path = p.join(dir.path, 'old.db');
      final old = await _v13(path);
      await old.close();
      final first = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      await (await first.database).delete('tavern_world_info_states');
      await first.close();
      final reopened = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      try {
        await expectLater(
          SQLiteTavernRepository(reopened).loadWorldInfoState('s', 'main'),
          throwsA(isA<TavernReconciliationConflict>()),
        );
        expect(
          await (await reopened.database).query('tavern_world_info_states'),
          isEmpty,
        );
      } finally {
        await reopened.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
