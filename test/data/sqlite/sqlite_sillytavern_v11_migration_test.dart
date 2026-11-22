import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/import/sillytavern_import_plan.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_compatibility_import_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/import/external_compatibility_payload.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_models.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  test(
    'clean v10 migrates to v11 and preserves existing product data',
    () async {
      final fixture = await _V10Fixture.create(version: 10);
      addTearDown(fixture.dispose);

      final database = fixture.database();
      final db = await database.open();
      expect(await db.getVersion(), SqliteSchema.version);
      expect(
        (await db.rawQuery(
          'PRAGMA table_info(character_cards)',
        )).map((row) => row['name']),
        containsAll([
          'avatar_reference',
          'source_format',
          'compatibility_payload_id',
        ]),
      );
      expect(await _count(db, 'external_compatibility_payloads'), 0);
      for (final table in const [
        'projects',
        'segments',
        'character_cards',
        'world_cards',
        'chat_personas',
        'chat_sessions',
        'chat_messages',
        'installed_plugins',
        'roleplay_worlds',
        'world_sessions',
        'world_feed_entries',
      ]) {
        expect(await _count(db, table), 1, reason: '$table must be preserved');
      }
      final world = (await db.query('roleplay_worlds')).single;
      final session = (await db.query('world_sessions')).single;
      expect(world['metadata_json'], contains('worldSystemPrompt'));
      expect(
        session['metadata_json'],
        contains('sessionAdditionalInstructions'),
      );
      final repository = SQLiteCompatibilityImportRepository(database);
      await repository.commitImport(
        SillyTavernImportWrite(payload: _payload('payload-v11')),
      );
      expect(
        (await repository.getPayload(
          'payload-v11',
        )).unsupportedPayload['extensions'],
        {'future_ibuki_test': true},
      );

      await database.close();
      final reopened = fixture.database();
      final reopenedDb = await reopened.open();
      expect(await reopenedDb.getVersion(), SqliteSchema.version);
      expect(await _count(reopenedDb, 'projects'), 1);
      expect(await _count(reopenedDb, 'world_feed_entries'), 1);
      final reopenedPayload = await SQLiteCompatibilityImportRepository(
        reopened,
      ).getPayload('payload-v11');
      expect(reopenedPayload.sourceSha256, 'synthetic-sha-256');
      expect(reopenedPayload.securityFlags, ['scriptLike']);
      await reopened.close();
    },
  );

  test(
    'incomplete v11 self-repairs compatibility schema idempotently',
    () async {
      final fixture = await _V10Fixture.create(version: 11);
      addTearDown(fixture.dispose);

      final database = fixture.database();
      final db = await database.open();
      expect(await db.getVersion(), SqliteSchema.version);
      expect(await _count(db, 'external_compatibility_payloads'), 0);
      expect(
        (await db.rawQuery(
          'PRAGMA table_info(character_cards)',
        )).map((row) => row['name']),
        containsAll([
          'avatar_reference',
          'source_format',
          'compatibility_payload_id',
        ]),
      );
      expect(await _count(db, 'character_cards'), 1);
      await database.close();

      final reopened = fixture.database();
      final reopenedDb = await reopened.open();
      expect(await _count(reopenedDb, 'character_cards'), 1);
      expect(await _count(reopenedDb, 'external_compatibility_payloads'), 0);
      await reopened.close();
    },
  );

  test('failed v11 import transaction leaves no partial records', () async {
    final fixture = await _V10Fixture.create(version: 10);
    addTearDown(fixture.dispose);
    final database = fixture.database();
    final db = await database.open();
    final repository = SQLiteCompatibilityImportRepository(database);

    expect(
      () => repository.commitImport(
        SillyTavernImportWrite(
          payload: _payload('rollback-payload'),
          worldBook: WorldBook(
            entity: _entity('rollback-book'),
            worldId: 'missing-world',
            name: 'Must roll back',
          ),
        ),
      ),
      throwsA(anything),
    );
    expect(await _count(db, 'external_compatibility_payloads'), 0);
    expect(
      await db.query(
        'world_books',
        where: 'id = ?',
        whereArgs: ['rollback-book'],
      ),
      isEmpty,
    );
    await database.close();
  });
  test(
    'v11 rollback includes a first collection and its native character',
    () async {
      final fixture = await _V10Fixture.create(version: 10);
      addTearDown(fixture.dispose);
      final database = fixture.database();
      addTearDown(database.close);
      final db = await database.open();
      final repository = SQLiteCompatibilityImportRepository(database);
      await repository.commitImport(
        SillyTavernImportWrite(payload: _payload('duplicate')),
      );
      await expectLater(
        repository.commitImport(
          SillyTavernImportWrite(
            payload: _payload('duplicate'),
            project: Project(
              metadata: _entity('new-collection'),
              title: 'Transient',
              description: '',
            ),
            character: CharacterCard(
              metadata: _entity('new-card'),
              projectId: 'new-collection',
              name: 'Transient',
              content: '',
              sortOrder: 0,
            ),
          ),
        ),
        throwsA(anything),
      );
      expect(
        await db.query(
          'projects',
          where: 'id = ?',
          whereArgs: ['new-collection'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'character_cards',
          where: 'id = ?',
          whereArgs: ['new-card'],
        ),
        isEmpty,
      );
      expect(await _count(db, 'external_compatibility_payloads'), 1);
    },
  );

  test(
    'summary and runtime queries do not decode large unsupported payloads',
    () async {
      final fixture = await _V10Fixture.create(version: 10);
      addTearDown(fixture.dispose);
      final database = fixture.database();
      final repository = SQLiteCompatibilityImportRepository(database);
      await repository.commitImport(
        SillyTavernImportWrite(
          payload: _payload('lazy').copyWith(
            unsupportedPayload: {'future': List.filled(200000, 'x').join()},
          ),
        ),
      );
      await database.close();
      final reopened = fixture.database();
      addTearDown(reopened.close);
      final reader = SQLiteCompatibilityImportRepository(reopened);
      expect((await reader.listPayloads()).single.unsupportedPayload, isEmpty);
      expect(
        (await reader.findBySourceSha256(
          'synthetic-sha-256',
        )).single.normalizedPayload,
        isEmpty,
      );
      expect(
        (await reader.listForEntity(
          'characterCard',
          'character-v10',
        )).single.unsupportedPayload,
        isEmpty,
      );
      expect(
        (await reader.listForEntity(
          'characterCard',
          'character-v10',
        )).single.normalizedPayload['name'],
        'Synthetic',
      );
      expect(
        ((await reader.getPayload('lazy')).unsupportedPayload['future']!
                as String)
            .length,
        200000,
      );
    },
  );

  test(
    'stale preset plan cannot overwrite newer world settings or persist payload',
    () async {
      final fixture = await _V10Fixture.create(version: 10);
      addTearDown(fixture.dispose);
      final database = fixture.database();
      addTearDown(database.close);
      final db = await database.open();
      await db.update(
        'roleplay_worlds',
        {'revision': 3, 'name': 'Newer world'},
        where: 'id = ?',
        whereArgs: ['world-v10'],
      );
      await expectLater(
        SQLiteCompatibilityImportRepository(database).commitImport(
          SillyTavernImportWrite(
            payload: _payload('stale'),
            updatedWorld: RoleplayWorld(
              entity: _entity('world-v10').copyWith(revision: 2),
              name: 'Stale',
              metadata: const {'bad': true},
            ),
          ),
        ),
        throwsA(anything),
      );
      expect((await db.query('roleplay_worlds')).single['name'], 'Newer world');
      expect(await _count(db, 'external_compatibility_payloads'), 0);
    },
  );
}

ExternalCompatibilityPayload _payload(String id) =>
    ExternalCompatibilityPayload(
      id: id,
      sourceType: ExternalCompatibilitySourceType.sillyTavern,
      sourceFormat: 'chara_card_v3',
      sourceVersion: '3.0',
      sourceSha256: 'synthetic-sha-256',
      linkedEntityType: 'characterCard',
      linkedEntityId: 'character-v10',
      normalizedPayload: const {'name': 'Synthetic'},
      unsupportedPayload: const {
        'extensions': {'future_ibuki_test': true},
      },
      securityFlags: const ['scriptLike'],
      importWarnings: const ['Synthetic warning'],
      createdAt: DateTime.utc(2026, 9, 1),
    );

EntityMetadata _entity(String id) => EntityMetadata(
  id: id,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  revision: 1,
);

class _V10Fixture {
  const _V10Fixture(this.directory, this.path);

  final Directory directory;
  final String path;

  static Future<_V10Fixture> create({required int version}) async {
    final directory = await Directory.systemTemp.createTemp('ibuki_st_v11_');
    final path = p.join(directory.path, 'ibukihome.db');
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (var statement in SqliteSchema.createTableStatements) {
            if (statement.contains(
              'CREATE TABLE external_compatibility_payloads',
            )) {
              continue;
            }
            if (statement.contains('CREATE TABLE character_cards')) {
              statement = statement
                  .replaceFirst('  avatar_reference TEXT NULL,\n', '')
                  .replaceFirst(
                    "  source_format TEXT NOT NULL DEFAULT '',\n",
                    '',
                  )
                  .replaceFirst('  compatibility_payload_id TEXT NULL,\n', '');
            }
            await db.execute(statement);
          }
          for (final statement in SqliteSchema.createIndexStatements) {
            if (!statement.contains('idx_compatibility_payloads_')) {
              await db.execute(statement);
            }
          }
          await _seed(db);
        },
      ),
    );
    await db.close();
    return _V10Fixture(directory, path);
  }

  IbukiDatabase database() => IbukiDatabase(
    pathResolver: () async => path,
    databaseFactory: databaseFactoryFfi,
  );

  Future<void> dispose() async {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

Future<void> _seed(Database db) async {
  const at = '2026-09-01T00:00:00.000Z';
  const entity = {'created_at': at, 'updated_at': at, 'revision': 1};
  await db.insert('projects', {
    'id': 'project-v10',
    'title': 'Novel',
    ...entity,
  });
  await db.insert('segments', {
    'id': 'segment-v10',
    'project_id': 'project-v10',
    'order_index': 0,
    'content': '正文',
    ...entity,
  });
  await db.insert('character_cards', {
    'id': 'character-v10',
    'project_id': 'project-v10',
    'name': '角色',
    'sort_order': 0,
    ...entity,
  });
  await db.insert('world_cards', {
    'id': 'world-card-v10',
    'project_id': 'project-v10',
    'title': '旧世界观',
    'sort_order': 0,
    ...entity,
  });
  await db.insert('chat_personas', {
    'id': 'chat-persona-v10',
    'name': 'Chat Character',
    'description_mode': 'simple',
    ...entity,
  });
  await db.insert('chat_sessions', {
    'id': 'chat-session-v10',
    'title': 'Chat',
    'persona_id': 'chat-persona-v10',
    ...entity,
  });
  await db.insert('chat_messages', {
    'id': 'chat-message-v10',
    'session_id': 'chat-session-v10',
    'role': 'user',
    'content': '你好',
    ...entity,
  });
  await db.insert('installed_plugins', {
    'id': 'dev.ibuki.v10',
    'name': 'Plugin',
    'version': '1.0.0',
    'manifest_version': 1,
    'manifest_json': '{}',
    'installed_path': 'installed/plugin',
    'data_path': 'data/plugin',
    'installed_at': at,
    'updated_at': at,
  });
  await db.insert('roleplay_worlds', {
    'id': 'world-v10',
    'name': 'World',
    'metadata_json':
        '{"worldPromptLayerV1":{"worldSystemPrompt":"world-style"}}',
    ...entity,
  });
  await db.insert('world_sessions', {
    'id': 'session-v10',
    'world_id': 'world-v10',
    'name': 'Story',
    'metadata_json':
        '{"worldPromptLayerV1":{"sessionAdditionalInstructions":"session-style"}}',
    ...entity,
  });
  await db.insert('world_branches', {
    'id': 'branch-v10',
    'world_session_id': 'session-v10',
    'name': 'Main',
    'is_current': 1,
    ...entity,
  });
  await db.insert('world_feed_entries', {
    'id': 'feed-v10',
    'world_session_id': 'session-v10',
    'branch_id': 'branch-v10',
    'entry_type': 'userAction',
    'content': 'action',
    ...entity,
  });
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $table');
  return rows.single['total']! as int;
}
