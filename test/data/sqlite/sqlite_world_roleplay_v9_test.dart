import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_service.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_character_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:ibukihome/data/sqlite/sqlite_world_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_world_roleplay_repository.dart';
import 'package:ibukihome/data/sqlite/world_roleplay_schema.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_models.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_engine_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  test(
    'v9 migrates to v10 with world binding defaults and durable turns',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ibuki_world_v9_to_v10_',
      );
      final path = p.join(directory.path, 'ibukihome.db');
      addTearDown(() async {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 9,
          onCreate: (db, _) async {
            for (final statement in SqliteSchema.createTableStatements) {
              if (!WorldRoleplaySchema.createTableStatements.contains(
                statement,
              )) {
                await db.execute(statement);
              }
            }
            for (final statement in WorldRoleplaySchema.createTableStatements) {
              if (statement.contains(
                'CREATE TABLE IF NOT EXISTS world_sessions',
              )) {
                await db.execute(_worldSessionsV9);
              } else if (!statement.contains(
                'CREATE TABLE IF NOT EXISTS world_turns',
              )) {
                await db.execute(statement);
              }
            }
            for (final statement in WorldRoleplaySchema.createIndexStatements) {
              if (!statement.contains('idx_world_turns_')) {
                await db.execute(statement);
              }
            }
            const at = '2026-08-28T00:00:00.000Z';
            await db.insert('projects', {
              'id': 'project-before-v10',
              'title': 'Existing Novel',
              'created_at': at,
              'updated_at': at,
              'revision': 1,
            });
            await db.insert('roleplay_worlds', {
              'id': 'world-before-v10',
              'name': 'Existing World',
              'created_at': at,
              'updated_at': at,
              'revision': 1,
            });
            await db.insert('world_sessions', {
              'id': 'session-before-v10',
              'world_id': 'world-before-v10',
              'name': 'Existing Session',
              'created_at': at,
              'updated_at': at,
              'revision': 1,
            });
          },
        ),
      );
      await old.close();

      final database = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      final db = await database.open();
      expect(await db.getVersion(), SqliteSchema.version);
      expect(await _count(db, 'projects'), 1);
      expect(await _count(db, 'roleplay_worlds'), 1);
      final columns = await db.rawQuery('PRAGMA table_info(world_sessions)');
      expect(
        columns.map((row) => row['name']),
        containsAll([
          'ai_provider_config_id',
          'ai_model',
          'lore_context_budget',
          'speaker_mode',
        ]),
      );
      final repository = SQLiteWorldRoleplayRepository(database);
      final session = await repository.getSession('session-before-v10');
      expect(session.aiProviderConfigId, isNull);
      expect(session.aiModel, isNull);
      expect(session.loreContextBudget, 1800);
      expect(session.speakerMode, WorldSpeakerMode.natural);
      final branch = WorldBranch(
        entity: metadata('branch-v10'),
        worldSessionId: session.id,
        name: 'main',
        isCurrent: true,
      );
      await repository.upsertBranch(branch);
      final readySession = session.copyWith(
        entity: session.entity.copyWith(revision: 2),
        currentBranchId: branch.id,
        aiProviderConfigId: 'gemini',
        aiModel: 'gemini-test',
      );
      await repository.upsertSession(readySession);
      final feed = WorldFeedEntry(
        entity: metadata('feed-v10'),
        worldSessionId: session.id,
        branchId: branch.id,
        type: WorldFeedEntryType.userAction,
        content: 'hello',
      );
      await repository.upsertFeedEntry(feed);
      await repository.upsertTurn(
        WorldTurn(
          entity: metadata('turn-v10'),
          worldSessionId: session.id,
          branchId: branch.id,
          userFeedEntryId: feed.id,
          status: WorldTurnStatus.completed,
        ),
      );
      expect(
        (await repository.getTurn('turn-v10')).status,
        WorldTurnStatus.completed,
      );
      expect((await repository.getSession(session.id)).aiModel, 'gemini-test');

      final beforeRollback = await repository.getSession(session.id);
      await expectLater(
        repository.commitWorldMutation(
          WorldMutationCommit(
            worldSessionId: session.id,
            turn: await repository.getTurn('turn-v10'),
            session: beforeRollback.copyWith(
              entity: beforeRollback.entity.copyWith(revision: 3),
              worldTime: 'must-roll-back',
            ),
            characterInstances: [
              WorldCharacterInstance(
                entity: metadata('foreign-character'),
                worldSessionId: 'another-session',
                characterCardId: 'foreign-card',
              ),
            ],
          ),
        ),
        throwsA(anything),
      );
      expect(
        (await repository.getSession(session.id)).worldTime,
        beforeRollback.worldTime,
      );

      await database.close();
      final reopenedDatabase = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(reopenedDatabase.close);
      final reopenedRepository = SQLiteWorldRoleplayRepository(
        reopenedDatabase,
      );
      expect(
        (await reopenedDatabase.open()).getVersion(),
        completion(SqliteSchema.version),
      );
      expect(
        (await reopenedRepository.getSession(session.id)).aiModel,
        'gemini-test',
      );
      expect(
        (await reopenedRepository.getTurn('turn-v10')).status,
        WorldTurnStatus.completed,
      );
    },
  );

  test('incomplete v10 self-repairs missing world engine schema', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ibuki_world_incomplete_v10_',
    );
    final path = p.join(directory.path, 'ibukihome.db');
    addTearDown(() async {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final incomplete = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 10,
        onCreate: (db, _) async {
          for (final statement in SqliteSchema.createTableStatements) {
            if (!WorldRoleplaySchema.createTableStatements.contains(
              statement,
            )) {
              await db.execute(statement);
            }
          }
          for (final statement in WorldRoleplaySchema.createTableStatements) {
            if (statement.contains(
              'CREATE TABLE IF NOT EXISTS world_sessions',
            )) {
              await db.execute(_worldSessionsV9);
            } else if (!statement.contains(
              'CREATE TABLE IF NOT EXISTS world_turns',
            )) {
              await db.execute(statement);
            }
          }
          const at = '2026-08-28T00:00:00.000Z';
          await db.insert('roleplay_worlds', {
            'id': 'world-incomplete-v10',
            'name': 'Preserved World',
            'created_at': at,
            'updated_at': at,
            'revision': 1,
          });
          await db.insert('world_sessions', {
            'id': 'session-incomplete-v10',
            'world_id': 'world-incomplete-v10',
            'name': 'Preserved Session',
            'created_at': at,
            'updated_at': at,
            'revision': 1,
          });
        },
      ),
    );
    await incomplete.close();

    final database = IbukiDatabase(
      pathResolver: () async => path,
      databaseFactory: databaseFactoryFfi,
    );
    addTearDown(database.close);
    final db = await database.open();
    final columns = await db.rawQuery('PRAGMA table_info(world_sessions)');
    expect(
      columns.map((row) => row['name']),
      containsAll([
        'ai_provider_config_id',
        'ai_model',
        'lore_context_budget',
        'speaker_mode',
      ]),
    );
    expect(
      await _count(db, 'world_turns'),
      0,
      reason: 'onOpen must create the missing durable turn table',
    );
    final repository = SQLiteWorldRoleplayRepository(database);
    expect(
      (await repository.getWorld('world-incomplete-v10')).name,
      'Preserved World',
    );
    expect(
      (await repository.getSession('session-incomplete-v10')).speakerMode,
      WorldSpeakerMode.natural,
    );
  });

  test(
    'clean v8 migrates through v9 to v10 and preserves existing product data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ibuki_world_v8_',
      );
      final path = p.join(directory.path, 'ibukihome.db');
      addTearDown(() async {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 8,
          onCreate: (db, _) async {
            for (final statement in SqliteSchema.createTableStatements) {
              if (!WorldRoleplaySchema.createTableStatements.contains(
                statement,
              )) {
                await db.execute(statement);
              }
            }
            for (final statement in SqliteSchema.createIndexStatements) {
              if (!WorldRoleplaySchema.createIndexStatements.contains(
                statement,
              )) {
                await db.execute(statement);
              }
            }
            await _seedV8BusinessData(db);
          },
        ),
      );
      await old.close();

      final database = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      final db = await database.open();

      expect(await db.getVersion(), SqliteSchema.version);
      for (final table in _worldTables) {
        expect(await _count(db, table), 0, reason: table);
      }
      for (final table in <String>[
        'projects',
        'segments',
        'character_cards',
        'world_cards',
        'chat_personas',
        'chat_sessions',
        'chat_messages',
        'story_memory_digests',
        'chat_memory_entries',
        'installed_plugins',
        'plugin_storage',
      ]) {
        expect(await _count(db, table), 1, reason: table);
      }

      await database.close();
      final reopened = IbukiDatabase(
        pathResolver: () async => path,
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(reopened.close);
      final reopenedDb = await reopened.open();
      expect(await reopenedDb.getVersion(), SqliteSchema.version);
      expect(await _count(reopenedDb, 'projects'), 1);
      expect(await _count(reopenedDb, 'installed_plugins'), 1);
    },
  );

  test(
    'world roleplay entities persist, isolate sessions, search, and cascade',
    () async {
      final fixture = await SqliteFixture.create();
      final repository = SQLiteWorldRoleplayRepository(fixture.database);
      final service = WorldRoleplayService(
        repository: repository,
        ids: EntityIdGenerator(),
        clock: const UtcClock(),
      );
      await fixture.projects.upsertProject(project('project-world'));
      await fixture.characters.upsertCharacter(
        characterCard('character-shared', 'project-world', 0),
      );
      await fixture.world.upsertWorldCard(
        worldCard('legacy-world-card', 'project-world', 0),
      );

      final created = await service.createWorld(
        name: '测试世界 · 迦勒底',
        importWorldCard: worldCard('legacy-world-card', 'project-world', 0),
      );
      final sessionA = created.session;
      final sessionB = await service.createWorldSession(
        worldId: created.world.id,
        name: '第二条世界线',
      );
      final persona = await service.createPersona(
        worldId: created.world.id,
        name: '御主',
        description: '测试身份',
      );
      final playerA = await service.activatePlayerPersona(
        worldSessionId: sessionA.id,
        playerPersonaId: persona.id,
      );
      final playerB = await service.activatePlayerPersona(
        worldSessionId: sessionB.id,
        playerPersonaId: persona.id,
      );
      await repository.upsertPlayerInstance(
        playerA.copyWith(
          currentLocation: '食堂',
          currentMood: '安心',
          currentGoal: '和大家共进晚餐',
        ),
      );
      await repository.upsertPlayerInstance(
        playerB.copyWith(
          currentLocation: '管制室',
          currentMood: '紧张',
          currentGoal: '准备灵子转移',
        ),
      );
      final characterA = await service.addCharacterToWorld(
        worldSessionId: sessionA.id,
        characterCardId: 'character-shared',
      );
      final characterB = await service.addCharacterToWorld(
        worldSessionId: sessionB.id,
        characterCardId: 'character-shared',
      );
      await repository.upsertCharacterInstance(
        characterA.copyWith(
          currentLocation: '食堂',
          currentMood: '亲近',
          currentGoal: '陪御主吃晚餐',
        ),
      );
      await repository.upsertCharacterInstance(
        characterB.copyWith(
          currentLocation: '训练场',
          currentMood: '敌对',
          currentGoal: '赢下模拟战',
        ),
      );
      final scene = await service.createScene(
        worldSessionId: sessionA.id,
        name: '迦勒底食堂',
        location: '食堂',
        timeText: 'Day 18 · 20:22',
        weather: '晴',
        atmosphere: '轻松',
        currentEvent: '晚餐',
      );
      await service.setCurrentScene(
        worldSessionId: sessionA.id,
        sceneId: scene.id,
        presentCharacterInstanceIds: {characterA.id},
      );
      final secondScene = await service.createScene(
        worldSessionId: sessionA.id,
        name: '迦勒底走廊',
        location: '走廊',
        timeText: 'Day 18 · 20:30',
      );
      await service.setCurrentScene(
        worldSessionId: sessionA.id,
        sceneId: secondScene.id,
        presentCharacterInstanceIds: const {},
      );
      expect(
        (await repository.getCharacterInstance(characterA.id)).currentGoal,
        '陪御主吃晚餐',
      );
      await service.setCurrentScene(
        worldSessionId: sessionA.id,
        sceneId: secondScene.id,
        presentCharacterInstanceIds: {characterA.id},
      );
      await service.saveWorldState(
        worldSessionId: sessionA.id,
        key: 'door.training_room.broken',
        value: true,
        category: 'event',
      );
      await repository.upsertRelationship(
        WorldRelationship(
          entity: metadata('relationship-1'),
          worldSessionId: sessionA.id,
          sourceEntityType: 'character',
          sourceEntityId: characterA.id,
          targetEntityType: 'playerInstance',
          targetEntityId: playerA.id,
          relationType: '亲近',
          summary: '非常信任御主',
          state: const {'trust': 88, 'debt': false},
        ),
      );
      await repository.upsertRelationship(
        WorldRelationship(
          entity: metadata('relationship-2'),
          worldSessionId: sessionB.id,
          sourceEntityType: 'character',
          sourceEntityId: characterB.id,
          targetEntityType: 'playerInstance',
          targetEntityId: playerB.id,
          relationType: '敌对',
          summary: '把玩家视为竞争对手',
          state: const {'trust': 5, 'hostility': 80},
        ),
      );
      final memory = await service.addWorldMemory(
        worldSessionId: sessionA.id,
        summary: '食堂的约定',
        content: '约定明天见面',
        importance: 0.8,
        relatedCharacterIds: [characterA.id],
        relatedSceneId: scene.id,
      );
      final memoryB = await service.addWorldMemory(
        worldSessionId: sessionB.id,
        summary: '训练场的冲突',
        content: '角色向玩家发起挑战',
        importance: 0.7,
        relatedCharacterIds: [characterB.id],
      );
      final event = await service.addTimelineEvent(
        worldSessionId: sessionA.id,
        title: '晚餐结束',
        description: '大家离开食堂',
        worldTime: 'Day 18 · 21:00',
        sceneId: scene.id,
        characterIds: [characterA.id],
      );
      final branch = await service.createWorldBranch(
        worldSessionId: sessionA.id,
        name: '食堂之后',
        parentBranchId: created.branch.id,
        branchPointEventId: event.id,
        makeCurrent: true,
      );
      await service.addFeedEntry(
        worldSessionId: sessionA.id,
        branchId: branch.id,
        type: WorldFeedEntryType.characterSpeech,
        speakerCharacterInstanceId: characterA.id,
        content: '明天见。',
      );

      final lore = (await repository.listLoreEntries(
        created.worldBook.id,
      )).single;
      expect(lore.sourceWorldCardId, 'legacy-world-card');
      await repository.upsertLoreEntry(
        LoreEntry(
          entity: metadata('lore-keyword'),
          worldBookId: created.worldBook.id,
          title: '灵子转移',
          content: '迦勒底的核心技术。',
          keywords: const ['灵子', '转移'],
          secondaryKeywords: const ['筐体'],
          priority: 42,
          activationMode: LoreActivationMode.keyword,
          insertionPosition: 'afterContext',
          probability: 0.75,
          tokenBudgetHint: 256,
          metadata: const {'futureGroup': 'technology'},
        ),
      );

      final counts = await repository.getDatabaseCounts(sessionA.id);
      expect(counts.characterInstances, 1);
      expect(counts.loreEntries, 2);
      expect(counts.personas, 1);
      expect(counts.playerInstances, 1);
      expect(counts.scenes, 2);
      expect(counts.stateEntries, 1);
      expect(counts.relationships, 1);
      expect(counts.memories, 1);
      expect(counts.timelineEvents, 1);
      expect(counts.branches, 2);
      expect(counts.feedEntries, 1);
      expect((await repository.listSceneCast(scene.id)), {characterA.id});
      expect(
        (await repository.getCharacterInstance(characterA.id)).isPresent,
        true,
      );
      expect(
        (await repository.getCharacterInstance(characterB.id)).isPresent,
        false,
      );
      expect(
        (await repository.getCharacterInstance(characterB.id)).currentMood,
        '敌对',
      );
      expect(
        (await repository.getCharacterInstance(characterB.id)).currentGoal,
        '赢下模拟战',
      );
      expect(
        (await repository.getPlayerInstance(playerA.id)).currentMood,
        '安心',
      );
      expect(
        (await repository.getPlayerInstance(playerB.id)).currentMood,
        '紧张',
      );
      expect(
        (await repository.getSession(sessionA.id)).currentPlayerInstanceId,
        playerA.id,
      );
      expect(
        (await repository.getSession(sessionB.id)).currentPlayerInstanceId,
        playerB.id,
      );
      expect((await repository.getMemory(memory.id)).relatedCharacterIds, [
        characterA.id,
      ]);
      expect((await repository.getMemory(memoryB.id)).relatedCharacterIds, [
        characterB.id,
      ]);
      expect((await repository.getPersona(persona.id)).description, '测试身份');
      expect(
        (await repository.searchWorldDatabase(
          sessionA.id,
          '食堂',
        )).map((item) => item.type),
        containsAll(<String>['memory', 'timeline', 'scene']),
      );

      await fixture.database.close();
      final reopenedDatabase = IbukiDatabase(
        pathResolver: () async => fixture.databasePath,
        databaseFactory: databaseFactoryFfi,
      );
      addTearDown(reopenedDatabase.close);
      final reopened = SQLiteWorldRoleplayRepository(reopenedDatabase);
      final reopenedCharacters = SQLiteCharacterRepository(reopenedDatabase);
      final reopenedWorldCards = SQLiteWorldRepository(reopenedDatabase);
      final reopenedWorld = await reopened.getWorld(created.world.id);
      final reopenedSession = await reopened.getSession(sessionA.id);
      expect(reopenedWorld.name, '测试世界 · 迦勒底');
      expect(reopenedWorld.defaultSessionId, sessionA.id);
      expect(reopenedSession.currentSceneId, secondScene.id);
      expect(reopenedSession.currentBranchId, branch.id);
      expect(reopenedSession.currentPlayerInstanceId, playerA.id);
      expect(await reopened.listSceneCast(secondScene.id), {characterA.id});
      expect(
        (await reopened.listFeedEntries(sessionA.id)).single.content,
        '明天见。',
      );
      expect(
        (await reopened.getStateEntry(
          (await reopened.listStateEntries(sessionA.id)).single.id,
        )).value,
        true,
      );
      expect(
        (await reopened.getPlayerInstance(playerA.id)).currentGoal,
        '和大家共进晚餐',
      );
      expect(
        (await reopened.getCharacterInstance(characterA.id)).currentGoal,
        '陪御主吃晚餐',
      );
      expect(
        (await reopened.listRelationships(sessionA.id)).single.summary,
        '非常信任御主',
      );
      expect(
        (await reopened.listRelationships(sessionB.id)).single.summary,
        '把玩家视为竞争对手',
      );

      await reopened.deleteSession(sessionA.id);
      expect(await reopened.listCharacterInstances(sessionA.id), isEmpty);
      expect(await reopened.listPlayerInstances(sessionA.id), isEmpty);
      expect(
        (await reopened.listPlayerInstances(sessionB.id)).single.currentGoal,
        '准备灵子转移',
      );
      expect(
        (await reopened.listCharacterInstances(sessionB.id)).single.currentMood,
        '敌对',
      );
      expect(
        (await reopened.listRelationships(sessionB.id)).single.summary,
        '把玩家视为竞争对手',
      );
      expect(
        (await reopened.listMemories(sessionB.id)).single.summary,
        '训练场的冲突',
      );
      expect((await reopened.getPersona(persona.id)).description, '测试身份');
      expect(
        (await reopenedCharacters.getCharacter('character-shared')).name,
        'character-shared',
      );
      await reopened.deleteWorld(created.world.id);
      expect(await reopened.listWorlds(), isEmpty);
      expect(
        (await reopenedCharacters.getCharacter('character-shared')).name,
        'character-shared',
      );
      expect(
        (await reopenedWorldCards.getWorldCard('legacy-world-card')).title,
        'legacy-world-card',
      );
    },
  );
}

const _worldTables = <String>[
  'roleplay_worlds',
  'world_sessions',
  'world_books',
  'lore_entries',
  'player_personas',
  'world_player_instances',
  'world_character_instances',
  'world_scenes',
  'world_scene_cast',
  'world_state_entries',
  'world_relationships',
  'world_memory_entries',
  'world_timeline_events',
  'world_branches',
  'world_feed_entries',
  'world_turns',
];

const _worldSessionsV9 = '''
CREATE TABLE IF NOT EXISTS world_sessions (
  id TEXT PRIMARY KEY,
  world_id TEXT NOT NULL,
  name TEXT NOT NULL,
  current_player_instance_id TEXT NULL,
  current_scene_id TEXT NULL,
  current_branch_id TEXT NULL,
  world_time TEXT NOT NULL DEFAULT '',
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 1),
  FOREIGN KEY (world_id) REFERENCES roleplay_worlds(id) ON DELETE CASCADE,
  FOREIGN KEY (current_player_instance_id) REFERENCES world_player_instances(id) ON DELETE SET NULL,
  FOREIGN KEY (current_scene_id) REFERENCES world_scenes(id) ON DELETE SET NULL,
  FOREIGN KEY (current_branch_id) REFERENCES world_branches(id) ON DELETE SET NULL
)
''';

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
  return rows.single['count']! as int;
}

Future<void> _seedV8BusinessData(Database db) async {
  const at = '2026-08-28T00:00:00.000Z';
  const entity = {
    'created_at': at,
    'updated_at': at,
    'revision': 1,
    'deleted_at': null,
  };
  await db.insert('projects', {
    'id': 'project-v8',
    'title': '旧作品',
    'description': 'preserve',
    'system_prompt': 'third person',
    ...entity,
  });
  await db.insert('segments', {
    'id': 'segment-v8',
    'project_id': 'project-v8',
    'order_index': 0,
    'content': 'existing segment',
    ...entity,
  });
  await db.insert('character_cards', {
    'id': 'character-v8',
    'project_id': 'project-v8',
    'name': 'Existing Character',
    'content': 'definition',
    'sort_order': 0,
    ...entity,
  });
  await db.insert('world_cards', {
    'id': 'world-card-v8',
    'project_id': 'project-v8',
    'title': 'Existing WorldCard',
    'content': 'lore',
    'sort_order': 0,
    ...entity,
  });
  await db.insert('chat_personas', {
    'id': 'persona-v8',
    'name': 'Existing Persona',
    'description_mode': 'simple',
    ...entity,
  });
  await db.insert('chat_sessions', {
    'id': 'chat-v8',
    'persona_id': 'persona-v8',
    'title': 'Existing Chat',
    ...entity,
  });
  await db.insert('chat_messages', {
    'id': 'message-v8',
    'session_id': 'chat-v8',
    'role': 'user',
    'content': 'existing message',
    ...entity,
  });
  await db.insert('story_memory_digests', {
    'id': 'digest-v8',
    'project_id': 'project-v8',
    'content': 'existing digest',
    'status': 'valid',
    ...entity,
  });
  await db.insert('chat_memory_entries', {
    'id': 'memory-v8',
    'persona_id': 'persona-v8',
    'session_id': 'chat-v8',
    'category': 'sharedEvent',
    'content': 'existing memory',
    'origin': 'manual',
    ...entity,
  });
  await db.insert('installed_plugins', {
    'id': 'dev.ibuki.existing',
    'name': 'Existing Plugin',
    'version': '1.0.0',
    'manifest_version': 1,
    'manifest_json':
        '{"manifestVersion":1,"id":"dev.ibuki.existing","name":"Existing Plugin","version":"1.0.0"}',
    'installed_path': 'installed/dev.ibuki.existing',
    'data_path': 'data/dev.ibuki.existing',
    'installed_at': at,
    'updated_at': at,
  });
  await db.insert('plugin_storage', {
    'plugin_id': 'dev.ibuki.existing',
    'storage_key': 'setting',
    'value_json': 'true',
    'updated_at': at,
  });
}
