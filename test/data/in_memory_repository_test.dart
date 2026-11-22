import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_character_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/data/memory/in_memory_segment_repository.dart';
import 'package:ibukihome/data/memory/in_memory_world_repository.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/chat/chat_message.dart' as domain;
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/segments/segment.dart';
import 'package:ibukihome/domain/world/world_card.dart';

void main() {
  group('in-memory repositories', () {
    test('creates and reads projects', () async {
      final repos = _Repositories();

      await repos.projects.upsertProject(_project('project-1'));

      expect(
        await repos.projects.getProject('project-1'),
        _project('project-1'),
      );
    });

    test('updates projects', () async {
      final repos = _Repositories();
      await repos.projects.upsertProject(_project('project-1'));

      await repos.projects.upsertProject(
        _project('project-1').copyWith(title: '新标题'),
      );

      expect((await repos.projects.getProject('project-1')).title, '新标题');
    });

    test('soft-deleted projects are hidden by default', () async {
      final repos = _Repositories();
      await repos.projects.upsertProject(_project('project-1'));

      await repos.projects.softDeleteProject(
        'project-1',
        DateTime.utc(2026, 1, 3),
      );

      expect(await repos.projects.listProjects(), isEmpty);
      expect(
        await repos.projects.listProjects(includeDeleted: true),
        hasLength(1),
      );
    });

    test('restores projects', () async {
      final repos = _Repositories();
      await repos.projects.upsertProject(_project('project-1'));
      await repos.projects.softDeleteProject(
        'project-1',
        DateTime.utc(2026, 1, 3),
      );

      await repos.projects.restoreProject(
        'project-1',
        DateTime.utc(2026, 1, 4),
      );

      final restored = await repos.projects.getProject('project-1');
      expect(restored.deletedAt, isNull);
      expect(await repos.projects.listProjects(), hasLength(1));
    });

    test('segments are isolated by projectId', () async {
      final repos = _Repositories();
      await repos.addProject('project-a');
      await repos.addProject('project-b');
      await repos.segments.upsertSegment(_segment('segment-a', 'project-a', 0));
      await repos.segments.upsertSegment(_segment('segment-b', 'project-b', 0));

      final aSegments = await repos.segments.listSegments('project-a');

      expect(aSegments.map((segment) => segment.id), ['segment-a']);
    });

    test('segments sort stably by orderIndex', () async {
      final repos = _Repositories();
      await repos.addProject('project-1');
      await repos.segments.upsertSegment(_segment('segment-2', 'project-1', 2));
      await repos.segments.upsertSegment(_segment('segment-1', 'project-1', 1));

      final segments = await repos.segments.listSegments('project-1');

      expect(segments.map((segment) => segment.id), ['segment-1', 'segment-2']);
    });

    test('character cards sort by sortOrder', () async {
      final repos = _Repositories();
      await repos.addProject('project-1');
      await repos.characters.upsertCharacter(
        _character('character-2', 'project-1', 2),
      );
      await repos.characters.upsertCharacter(
        _character('character-1', 'project-1', 1),
      );

      final characters = await repos.characters.listCharacters('project-1');

      expect(characters.map((character) => character.id), [
        'character-1',
        'character-2',
      ]);
    });

    test('world cards sort by sortOrder', () async {
      final repos = _Repositories();
      await repos.addProject('project-1');
      await repos.world.upsertWorldCard(_world('world-2', 'project-1', 2));
      await repos.world.upsertWorldCard(_world('world-1', 'project-1', 1));

      final cards = await repos.world.listWorldCards('project-1');

      expect(cards.map((card) => card.id), ['world-1', 'world-2']);
    });

    test('chat sessions reject novel project associations', () async {
      final repos = _Repositories();
      expect(
        repos.chat.upsertSession(_session('session-1', 'project-1')),
        throwsA(isA<DataConflictException>()),
      );
      await repos.chat.upsertSession(_session('session-free', null));
      expect(await repos.chat.listSessions(projectId: 'project-1'), isEmpty);
    });

    test('messages sort by createdAt', () async {
      final repos = _Repositories();
      await repos.chat.upsertSession(_session('session-1', null));
      await repos.chat.appendMessage(
        _message('message-2', 'session-1', null, hour: 2),
      );
      await repos.chat.appendMessage(
        _message('message-1', 'session-1', null, hour: 1),
      );

      final messages = await repos.chat.listMessages('session-1');

      expect(messages.map((message) => message.id), ['message-1', 'message-2']);
    });

    test('repositories sharing one store see the same data', () async {
      final store = InMemoryIbukiStore();
      final first = InMemoryProjectRepository(store);
      final second = InMemoryProjectRepository(store);

      await first.upsertProject(_project('project-1'));

      expect(await second.getProject('project-1'), _project('project-1'));
    });

    test('returned lists cannot mutate the internal store', () async {
      final repos = _Repositories();
      await repos.projects.upsertProject(_project('project-1'));

      final projects = await repos.projects.listProjects();

      expect(
        () => projects.add(_project('project-2')),
        throwsA(isA<UnsupportedError>()),
      );
      expect(await repos.projects.listProjects(), hasLength(1));
    });

    test('missing entities throw explicit exceptions', () async {
      final repos = _Repositories();

      expect(
        repos.projects.getProject('missing'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });
}

class _Repositories {
  final InMemoryIbukiStore store = InMemoryIbukiStore();
  late final InMemoryProjectRepository projects = InMemoryProjectRepository(
    store,
  );
  late final InMemorySegmentRepository segments = InMemorySegmentRepository(
    store,
  );
  late final InMemoryCharacterRepository characters =
      InMemoryCharacterRepository(store);
  late final InMemoryWorldRepository world = InMemoryWorldRepository(store);
  late final InMemoryChatRepository chat = InMemoryChatRepository(store);

  Future<void> addProject(String id) => projects.upsertProject(_project(id));
}

Project _project(String id) {
  return Project(
    metadata: _metadata(id),
    title: id,
    description: 'description',
  );
}

Segment _segment(String id, String projectId, int orderIndex) {
  return Segment(
    metadata: _metadata(id),
    projectId: projectId,
    orderIndex: orderIndex,
    content: id,
  );
}

CharacterCard _character(String id, String projectId, int sortOrder) {
  return CharacterCard(
    metadata: _metadata(id),
    projectId: projectId,
    name: id,
    content: 'content',
    sortOrder: sortOrder,
  );
}

WorldCard _world(String id, String projectId, int sortOrder) {
  return WorldCard(
    metadata: _metadata(id),
    projectId: projectId,
    title: id,
    content: 'content',
    sortOrder: sortOrder,
  );
}

ChatSession _session(String id, String? projectId) {
  return ChatSession(metadata: _metadata(id), projectId: projectId, title: id);
}

domain.ChatMessage _message(
  String id,
  String sessionId,
  String? projectId, {
  required int hour,
}) {
  return domain.ChatMessage(
    metadata: _metadata(id, createdAt: DateTime.utc(2026, 1, 1, hour)),
    sessionId: sessionId,
    projectId: projectId,
    role: ChatMessageRole.user,
    content: id,
  );
}

EntityMetadata _metadata(String id, {DateTime? createdAt, int revision = 1}) {
  final created = createdAt ?? DateTime.utc(2026, 1, 1);
  return EntityMetadata(
    id: id,
    createdAt: created,
    updatedAt: created,
    revision: revision,
  );
}
