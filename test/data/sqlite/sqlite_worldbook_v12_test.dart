import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:ibukihome/data/sqlite/sqlite_world_roleplay_repository.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  test(
    'v11 migrates through v12 and reference state survives reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp('ibuki_v12_');
      final path = p.join(directory.path, 'ibukihome.db');
      addTearDown(() async {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 11,
          onCreate: (db, _) async {
            for (final statement in SqliteSchema.createTableStatements) {
              if (!_isV12ReferenceStatement(statement)) {
                await db.execute(statement);
              }
            }
            for (final statement in SqliteSchema.createIndexStatements) {
              if (!_isV12ReferenceStatement(statement)) {
                await db.execute(statement);
              }
            }
            const at = '2026-09-10T00:00:00.000Z';
            await db.insert('projects', {
              'id': 'project-old',
              'title': 'Preserved novel',
              'created_at': at,
              'updated_at': at,
              'revision': 1,
            });
            await db.insert('roleplay_worlds', {
              'id': 'world-old',
              'name': 'Preserved world',
              'created_at': at,
              'updated_at': at,
              'revision': 1,
            });
            await db.insert('character_cards', {
              'id': 'card-old',
              'project_id': 'project-old',
              'name': 'Preserved card',
              'sort_order': 0,
              'created_at': at,
              'updated_at': at,
              'revision': 1,
            });
            await db.insert('world_sessions', {
              'id': 'session-old',
              'world_id': 'world-old',
              'name': 'Preserved session',
              'created_at': at,
              'updated_at': at,
              'revision': 1,
            });
            await db.insert('player_personas', {
              'id': 'persona-old',
              'world_id': 'world-old',
              'name': 'Preserved persona',
              'created_at': at,
              'updated_at': at,
              'revision': 1,
            });
          },
        ),
      );
      await old.close();

      var database = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      var repository = SQLiteWorldRoleplayRepository(database);
      expect(
        (await database.open()).getVersion(),
        completion(SqliteSchema.version),
      );
      expect(
        (await database.database).query('projects'),
        completion(hasLength(1)),
      );
      final book = WorldBook(entity: _entity('book'), name: 'Shared lore');
      await repository.upsertWorldBook(book);
      final reference = WorldWorldBookReference(
        entity: _entity('world-reference'),
        worldId: 'world-old',
        worldBookId: book.id,
        enabled: false,
        priority: 7,
      );
      await repository.upsertWorldBookReference(reference);
      await repository.upsertWorldBookOverride(
        WorldSessionWorldBookOverride(
          entity: _entity('session-override'),
          worldSessionId: 'session-old',
          worldBookId: book.id,
          mode: WorldBookOverrideMode.enabled,
        ),
      );
      await repository.upsertCharacterWorldBookReference(
        EntityWorldBookReference(
          entity: _entity('card-reference'),
          entityId: 'card-old',
          worldBookId: book.id,
        ),
      );
      await repository.upsertPersonaWorldBookReference(
        EntityWorldBookReference(
          entity: _entity('persona-reference'),
          entityId: 'persona-old',
          worldBookId: book.id,
        ),
      );
      await expectLater(
        repository.deleteWorldBook(book.id),
        throwsA(isA<DataConflictException>()),
      );

      await database.close();
      database = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      repository = SQLiteWorldRoleplayRepository(database);
      final restored = (await repository.listWorldBookReferences(
        'world-old',
      )).single;
      expect(restored.worldBookId, book.id);
      expect(restored.enabled, isFalse);
      expect(restored.priority, 7);
      expect(
        await repository.listWorldBookOverrides('session-old'),
        hasLength(1),
      );
      expect(
        await repository.listCharacterWorldBookReferences('card-old'),
        hasLength(1),
      );
      expect(
        await repository.listPersonaWorldBookReferences('persona-old'),
        hasLength(1),
      );
      expect(
        (await repository.listWorldBookLibrary()).single.name,
        'Shared lore',
      );

      await repository.deleteWorld('world-old');
      expect((await repository.getWorldBook(book.id)).name, 'Shared lore');
      expect(await repository.countWorldBookReferences(book.id), 1);
      await database.close();
    },
  );
}

bool _isV12ReferenceStatement(String statement) => const [
  'world_world_book_references',
  'world_session_world_book_overrides',
  'character_world_book_references',
  'persona_world_book_references',
].any(statement.contains);

EntityMetadata _entity(String id) {
  final now = DateTime.utc(2026, 9, 10);
  return EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);
}
