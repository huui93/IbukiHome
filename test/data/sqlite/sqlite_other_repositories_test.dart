import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  group('other SQLite repositories', () {
    test('character cards support basic CRUD and sorting', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));
      await fixture.characters.upsertCharacter(
        characterCard('character-2', 'project-1', 2),
      );
      await fixture.characters.upsertCharacter(
        characterCard('character-1', 'project-1', 1),
      );

      expect(
        (await fixture.characters.listCharacters(
          'project-1',
        )).map((item) => item.id),
        ['character-1', 'character-2'],
      );

      await fixture.characters.softDeleteCharacter(
        'character-1',
        DateTime.utc(2026, 1, 2),
      );
      expect(
        (await fixture.characters.listCharacters(
          'project-1',
        )).map((item) => item.id),
        ['character-2'],
      );

      await fixture.characters.restoreCharacter(
        'character-1',
        DateTime.utc(2026, 1, 3),
      );
      expect(
        await fixture.characters.listCharacters('project-1'),
        hasLength(2),
      );
    });

    test('world cards support basic CRUD and sorting', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));
      await fixture.world.upsertWorldCard(worldCard('world-2', 'project-1', 2));
      await fixture.world.upsertWorldCard(worldCard('world-1', 'project-1', 1));

      expect(
        (await fixture.world.listWorldCards(
          'project-1',
        )).map((item) => item.id),
        ['world-1', 'world-2'],
      );

      await fixture.world.softDeleteWorldCard(
        'world-1',
        DateTime.utc(2026, 1, 2),
      );
      expect(
        (await fixture.world.listWorldCards(
          'project-1',
        )).map((item) => item.id),
        ['world-2'],
      );

      await fixture.world.restoreWorldCard('world-1', DateTime.utc(2026, 1, 3));
      expect(await fixture.world.listWorldCards('project-1'), hasLength(2));
    });

    test('chat sessions and messages support basic CRUD and sorting', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-1'));
      await fixture.chatRepository.upsertSession(
        chatSession('session-1', null),
      );
      await fixture.chatRepository.appendMessage(
        chatMessage('message-2', 'session-1', null, hour: 2),
      );
      await fixture.chatRepository.appendMessage(
        chatMessage('message-1', 'session-1', null, hour: 1),
      );

      final messages = await fixture.chatRepository.listMessages('session-1');

      expect(messages.map((message) => message.id), ['message-1', 'message-2']);

      await fixture.chatRepository.softDeleteMessage(
        'message-1',
        DateTime.utc(2026, 1, 3),
      );
      expect(
        (await fixture.chatRepository.listMessages(
          'session-1',
        )).map((message) => message.id),
        ['message-2'],
      );
    });

    test('chat sessions never filter into novel projects', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(
        chatSession('session-free', null),
      );
      expect(
        await fixture.chatRepository.listSessions(projectId: 'project-a'),
        isEmpty,
      );
    });

    test('chat messages reject novel project bindings', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-a'));
      await fixture.projects.upsertProject(project('project-b'));
      await fixture.chatRepository.upsertSession(
        chatSession('session-a', null),
      );

      expect(
        fixture.chatRepository.appendMessage(
          chatMessage('message-1', 'session-a', 'project-b', hour: 1),
        ),
        throwsA(isA<DataConflictException>()),
      );
    });
  });
}
