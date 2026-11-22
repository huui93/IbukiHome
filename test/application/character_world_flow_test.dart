import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/characters/create_character_card.dart';
import 'package:ibukihome/application/characters/reorder_character_cards.dart';
import 'package:ibukihome/application/characters/restore_character_card.dart';
import 'package:ibukihome/application/characters/save_character_card.dart';
import 'package:ibukihome/application/characters/soft_delete_character_card.dart';
import 'package:ibukihome/application/world/create_world_card.dart';
import 'package:ibukihome/application/world/reorder_world_cards.dart';
import 'package:ibukihome/application/world/restore_world_card.dart';
import 'package:ibukihome/application/world/save_world_card.dart';
import 'package:ibukihome/application/world/soft_delete_world_card.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_character_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/data/memory/in_memory_world_repository.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';

void main() {
  late InMemoryIbukiStore store;
  late InMemoryProjectRepository projects;
  late InMemoryCharacterRepository characters;
  late InMemoryWorldRepository world;
  late CreateCharacterCard createCharacter;
  late SaveCharacterCard saveCharacter;
  late SoftDeleteCharacterCard deleteCharacter;
  late RestoreCharacterCard restoreCharacter;
  late ReorderCharacterCards reorderCharacters;
  late CreateWorldCard createWorld;
  late SaveWorldCard saveWorld;
  late SoftDeleteWorldCard deleteWorld;
  late RestoreWorldCard restoreWorld;
  late ReorderWorldCards reorderWorld;

  final t0 = DateTime.utc(2026, 7, 30, 8);
  final t1 = DateTime.utc(2026, 7, 30, 9);

  setUp(() async {
    store = InMemoryIbukiStore();
    projects = InMemoryProjectRepository(store);
    characters = InMemoryCharacterRepository(store);
    world = InMemoryWorldRepository(store);
    createCharacter = CreateCharacterCard(projects, characters);
    saveCharacter = SaveCharacterCard(characters);
    deleteCharacter = SoftDeleteCharacterCard(characters);
    restoreCharacter = RestoreCharacterCard(characters);
    reorderCharacters = ReorderCharacterCards(characters);
    createWorld = CreateWorldCard(projects, world);
    saveWorld = SaveWorldCard(world);
    deleteWorld = SoftDeleteWorldCard(world);
    restoreWorld = RestoreWorldCard(world);
    reorderWorld = ReorderWorldCards(world);
    await projects.upsertProject(_project('project-a', t0));
    await projects.upsertProject(_project('project-b', t0));
  });

  group('character application flow', () {
    test('creates a trimmed character with revision one', () async {
      final card = await _createCharacter(createCharacter, name: '  伊吹  ');
      expect(card.name, '伊吹');
      expect(card.revision, 1);
      expect(card.createdAt, t0);
      expect(card.updatedAt, t0);
      expect(card.deletedAt, isNull);
    });

    test('allows empty character content', () async {
      final card = await _createCharacter(createCharacter, content: '');
      expect(card.content, isEmpty);
    });

    test('rejects an empty character name', () async {
      expect(
        () => _createCharacter(createCharacter, name: '   '),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('rejects a missing project', () async {
      expect(
        () => _createCharacter(createCharacter, projectId: 'missing'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('rejects a deleted project', () async {
      await projects.softDeleteProject('project-a', t1);
      expect(
        () => _createCharacter(createCharacter),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('appends sort order after active characters', () async {
      final first = await _createCharacter(createCharacter, id: 'character-1');
      final second = await _createCharacter(createCharacter, id: 'character-2');
      expect([first.sortOrder, second.sortOrder], [0, 1]);
    });

    test('calculates sort order independently per project', () async {
      await _createCharacter(createCharacter, id: 'character-1');
      final other = await _createCharacter(
        createCharacter,
        id: 'character-2',
        projectId: 'project-b',
      );
      expect(other.sortOrder, 0);
    });

    test('reads a created character from its project', () async {
      await _createCharacter(createCharacter);
      expect(await characters.listCharacters('project-a'), hasLength(1));
      expect(await characters.listCharacters('project-b'), isEmpty);
    });

    test('unchanged save keeps revision and updatedAt', () async {
      final original = await _createCharacter(createCharacter);
      final saved = await saveCharacter(
        projectId: 'project-a',
        characterId: original.id,
        name: original.name,
        content: original.content,
        nowUtc: t1,
      );
      expect(saved.revision, 1);
      expect(saved.updatedAt, t0);
    });

    test('changing character name increments revision', () async {
      final original = await _createCharacter(createCharacter);
      final saved = await saveCharacter(
        projectId: 'project-a',
        characterId: original.id,
        name: '铃语',
        content: original.content,
        nowUtc: t1,
      );
      expect(saved.name, '铃语');
      expect(saved.revision, 2);
    });

    test('changing character content increments revision', () async {
      final original = await _createCharacter(createCharacter);
      final saved = await saveCharacter(
        projectId: 'project-a',
        characterId: original.id,
        name: original.name,
        content: '更新后的内容',
        nowUtc: t1,
      );
      expect(saved.content, '更新后的内容');
      expect(saved.revision, 2);
    });

    test('save preserves identity, project, order and creation time', () async {
      final original = await _createCharacter(createCharacter);
      final saved = await saveCharacter(
        projectId: 'project-a',
        characterId: original.id,
        name: '新名称',
        content: '新内容',
        nowUtc: t1,
      );
      expect(saved.id, original.id);
      expect(saved.projectId, original.projectId);
      expect(saved.sortOrder, original.sortOrder);
      expect(saved.createdAt, original.createdAt);
    });

    test('save rejects a forged project id', () async {
      final original = await _createCharacter(createCharacter);
      expect(
        () => saveCharacter(
          projectId: 'project-b',
          characterId: original.id,
          name: original.name,
          content: original.content,
          nowUtc: t1,
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('save rejects deleted characters', () async {
      final original = await _createCharacter(createCharacter);
      await deleteCharacter(
        projectId: 'project-a',
        characterId: original.id,
        nowUtc: t1,
      );
      expect(
        () => saveCharacter(
          projectId: 'project-a',
          characterId: original.id,
          name: original.name,
          content: 'cannot save',
          nowUtc: t1,
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('soft delete hides character and increments revision', () async {
      final original = await _createCharacter(createCharacter);
      final deleted = await deleteCharacter(
        projectId: 'project-a',
        characterId: original.id,
        nowUtc: t1,
      );
      expect(deleted.deletedAt, t1);
      expect(deleted.revision, 2);
      expect(await characters.listCharacters('project-a'), isEmpty);
    });

    test('includeDeleted reads a soft-deleted character', () async {
      final original = await _createCharacter(createCharacter);
      await deleteCharacter(
        projectId: 'project-a',
        characterId: original.id,
        nowUtc: t1,
      );
      expect(
        await characters.listCharacters('project-a', includeDeleted: true),
        hasLength(1),
      );
    });

    test('repeated character delete does not add a revision', () async {
      final original = await _createCharacter(createCharacter);
      final first = await deleteCharacter(
        projectId: 'project-a',
        characterId: original.id,
        nowUtc: t1,
      );
      final second = await deleteCharacter(
        projectId: 'project-a',
        characterId: original.id,
        nowUtc: t1.add(const Duration(hours: 1)),
      );
      expect(second.revision, first.revision);
      expect(second.deletedAt, first.deletedAt);
    });

    test('restores a character with its content and id', () async {
      final original = await _createCharacter(createCharacter);
      await deleteCharacter(
        projectId: 'project-a',
        characterId: original.id,
        nowUtc: t1,
      );
      final restored = await restoreCharacter(
        projectId: 'project-a',
        characterId: original.id,
        nowUtc: t1.add(const Duration(hours: 1)),
      );
      expect(restored.deletedAt, isNull);
      expect(restored.id, original.id);
      expect(restored.content, original.content);
      expect(restored.revision, 3);
    });

    test('repeated character restore does not add a revision', () async {
      final original = await _createCharacter(createCharacter);
      final restored = await restoreCharacter(
        projectId: 'project-a',
        characterId: original.id,
        nowUtc: t1,
      );
      expect(restored.revision, original.revision);
    });

    test('reorders characters and normalizes sort order', () async {
      await _createCharacter(createCharacter, id: 'character-1');
      await _createCharacter(createCharacter, id: 'character-2');
      final result = await reorderCharacters(
        projectId: 'project-a',
        orderedIds: const ['character-2', 'character-1'],
        nowUtc: t1,
      );
      expect(result.map((item) => item.id), ['character-2', 'character-1']);
      expect(result.map((item) => item.sortOrder), [0, 1]);
    });

    test('rejects missing character ordered ids without mutation', () async {
      await _createCharacter(createCharacter, id: 'character-1');
      await _createCharacter(createCharacter, id: 'character-2');
      expect(
        () => reorderCharacters(
          projectId: 'project-a',
          orderedIds: const ['character-1'],
          nowUtc: t1,
        ),
        throwsA(isA<DataConflictException>()),
      );
      expect(
        (await characters.listCharacters('project-a')).map((item) => item.id),
        ['character-1', 'character-2'],
      );
    });

    test('rejects duplicate and cross-project character ids', () async {
      await _createCharacter(createCharacter, id: 'character-1');
      await _createCharacter(
        createCharacter,
        id: 'character-2',
        projectId: 'project-b',
      );
      for (final ids in [
        ['character-1', 'character-1'],
        ['character-2'],
      ]) {
        expect(
          () => reorderCharacters(
            projectId: 'project-a',
            orderedIds: ids,
            nowUtc: t1,
          ),
          throwsA(isA<DataConflictException>()),
        );
      }
    });
  });

  group('world card application flow', () {
    test('creates a trimmed world card with revision one', () async {
      final card = await _createWorld(createWorld, title: '  城市  ');
      expect(card.title, '城市');
      expect(card.revision, 1);
      expect(card.createdAt, t0);
      expect(card.updatedAt, t0);
      expect(card.deletedAt, isNull);
    });

    test('allows empty world card content', () async {
      final card = await _createWorld(createWorld, content: '');
      expect(card.content, isEmpty);
    });

    test('rejects an empty world card title', () async {
      expect(
        () => _createWorld(createWorld, title: '  '),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('rejects a missing project for a world card', () async {
      expect(
        () => _createWorld(createWorld, projectId: 'missing'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('rejects a deleted project for a world card', () async {
      await projects.softDeleteProject('project-a', t1);
      expect(
        () => _createWorld(createWorld),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('appends world card sort order', () async {
      final first = await _createWorld(createWorld, id: 'world-1');
      final second = await _createWorld(createWorld, id: 'world-2');
      expect([first.sortOrder, second.sortOrder], [0, 1]);
    });

    test('isolates world card order per project', () async {
      await _createWorld(createWorld, id: 'world-1');
      final other = await _createWorld(
        createWorld,
        id: 'world-2',
        projectId: 'project-b',
      );
      expect(other.sortOrder, 0);
    });

    test('reads world cards only from their project', () async {
      await _createWorld(createWorld);
      expect(await world.listWorldCards('project-a'), hasLength(1));
      expect(await world.listWorldCards('project-b'), isEmpty);
    });

    test('unchanged world save keeps revision and updatedAt', () async {
      final original = await _createWorld(createWorld);
      final saved = await saveWorld(
        projectId: 'project-a',
        worldCardId: original.id,
        title: original.title,
        content: original.content,
        nowUtc: t1,
      );
      expect(saved.revision, 1);
      expect(saved.updatedAt, t0);
    });

    test('changing world title increments revision', () async {
      final original = await _createWorld(createWorld);
      final saved = await saveWorld(
        projectId: 'project-a',
        worldCardId: original.id,
        title: '组织',
        content: original.content,
        nowUtc: t1,
      );
      expect(saved.title, '组织');
      expect(saved.revision, 2);
    });

    test('changing world content increments revision', () async {
      final original = await _createWorld(createWorld);
      final saved = await saveWorld(
        projectId: 'project-a',
        worldCardId: original.id,
        title: original.title,
        content: '更新后的规则',
        nowUtc: t1,
      );
      expect(saved.content, '更新后的规则');
      expect(saved.revision, 2);
    });

    test('world save preserves identity and creation metadata', () async {
      final original = await _createWorld(createWorld);
      final saved = await saveWorld(
        projectId: 'project-a',
        worldCardId: original.id,
        title: '新标题',
        content: '新内容',
        nowUtc: t1,
      );
      expect(saved.id, original.id);
      expect(saved.projectId, original.projectId);
      expect(saved.sortOrder, original.sortOrder);
      expect(saved.createdAt, original.createdAt);
    });

    test('world save rejects forged project id', () async {
      final original = await _createWorld(createWorld);
      expect(
        () => saveWorld(
          projectId: 'project-b',
          worldCardId: original.id,
          title: original.title,
          content: original.content,
          nowUtc: t1,
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('world save rejects deleted cards', () async {
      final original = await _createWorld(createWorld);
      await deleteWorld(
        projectId: 'project-a',
        worldCardId: original.id,
        nowUtc: t1,
      );
      expect(
        () => saveWorld(
          projectId: 'project-a',
          worldCardId: original.id,
          title: original.title,
          content: 'cannot save',
          nowUtc: t1,
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('soft delete hides world card and increments revision', () async {
      final original = await _createWorld(createWorld);
      final deleted = await deleteWorld(
        projectId: 'project-a',
        worldCardId: original.id,
        nowUtc: t1,
      );
      expect(deleted.deletedAt, t1);
      expect(deleted.revision, 2);
      expect(await world.listWorldCards('project-a'), isEmpty);
    });

    test('includeDeleted reads a soft-deleted world card', () async {
      final original = await _createWorld(createWorld);
      await deleteWorld(
        projectId: 'project-a',
        worldCardId: original.id,
        nowUtc: t1,
      );
      expect(
        await world.listWorldCards('project-a', includeDeleted: true),
        hasLength(1),
      );
    });

    test('repeated world delete does not add a revision', () async {
      final original = await _createWorld(createWorld);
      final first = await deleteWorld(
        projectId: 'project-a',
        worldCardId: original.id,
        nowUtc: t1,
      );
      final second = await deleteWorld(
        projectId: 'project-a',
        worldCardId: original.id,
        nowUtc: t1.add(const Duration(hours: 1)),
      );
      expect(second.revision, first.revision);
      expect(second.deletedAt, first.deletedAt);
    });

    test('restores world card content and id', () async {
      final original = await _createWorld(createWorld);
      await deleteWorld(
        projectId: 'project-a',
        worldCardId: original.id,
        nowUtc: t1,
      );
      final restored = await restoreWorld(
        projectId: 'project-a',
        worldCardId: original.id,
        nowUtc: t1.add(const Duration(hours: 1)),
      );
      expect(restored.deletedAt, isNull);
      expect(restored.id, original.id);
      expect(restored.content, original.content);
      expect(restored.revision, 3);
    });

    test('repeated world restore does not add a revision', () async {
      final original = await _createWorld(createWorld);
      final restored = await restoreWorld(
        projectId: 'project-a',
        worldCardId: original.id,
        nowUtc: t1,
      );
      expect(restored.revision, original.revision);
    });

    test('reorders world cards and normalizes sort order', () async {
      await _createWorld(createWorld, id: 'world-1');
      await _createWorld(createWorld, id: 'world-2');
      final result = await reorderWorld(
        projectId: 'project-a',
        orderedIds: const ['world-2', 'world-1'],
        nowUtc: t1,
      );
      expect(result.map((item) => item.id), ['world-2', 'world-1']);
      expect(result.map((item) => item.sortOrder), [0, 1]);
    });

    test('rejects missing world ordered ids without mutation', () async {
      await _createWorld(createWorld, id: 'world-1');
      await _createWorld(createWorld, id: 'world-2');
      expect(
        () => reorderWorld(
          projectId: 'project-a',
          orderedIds: const ['world-1'],
          nowUtc: t1,
        ),
        throwsA(isA<DataConflictException>()),
      );
      expect((await world.listWorldCards('project-a')).map((item) => item.id), [
        'world-1',
        'world-2',
      ]);
    });

    test('rejects duplicate and cross-project world ids', () async {
      await _createWorld(createWorld, id: 'world-1');
      await _createWorld(createWorld, id: 'world-2', projectId: 'project-b');
      for (final ids in [
        ['world-1', 'world-1'],
        ['world-2'],
      ]) {
        expect(
          () =>
              reorderWorld(projectId: 'project-a', orderedIds: ids, nowUtc: t1),
          throwsA(isA<DataConflictException>()),
        );
      }
    });
  });
}

Project _project(String id, DateTime now, {DateTime? deletedAt}) {
  return Project(
    metadata: EntityMetadata(
      id: id,
      createdAt: now,
      updatedAt: now,
      revision: 1,
      deletedAt: deletedAt,
    ),
    title: id,
    description: '',
  );
}

Future<dynamic> _createCharacter(
  CreateCharacterCard useCase, {
  String projectId = 'project-a',
  String name = '伊吹',
  String content = '角色内容',
  String id = 'character-1',
}) {
  return useCase(
    projectId: projectId,
    name: name,
    content: content,
    id: id,
    nowUtc: DateTime.utc(2026, 7, 30, 8),
  );
}

Future<dynamic> _createWorld(
  CreateWorldCard useCase, {
  String projectId = 'project-a',
  String title = '城市',
  String content = '世界观内容',
  String id = 'world-1',
}) {
  return useCase(
    projectId: projectId,
    title: title,
    content: content,
    id: id,
    nowUtc: DateTime.utc(2026, 7, 30, 8),
  );
}
