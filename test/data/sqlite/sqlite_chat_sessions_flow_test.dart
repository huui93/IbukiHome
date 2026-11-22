import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/chat/send_chat_message.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';

import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  group('SQLite chat sessions and messages', () {
    test('creates and reads an unbound session', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(_session('session-1'));

      final session = await fixture.chatRepository.getSession('session-1');

      expect(session.projectId, isNull);
      expect(session.title, 'session-1');
    });

    test('rejects binding a chat to a novel project', () async {
      final fixture = await SqliteFixture.create();
      expect(
        fixture.chatRepository.upsertSession(
          _session('session-1', projectId: 'project-1'),
        ),
        throwsA(isA<DataConflictException>()),
      );
      expect(await fixture.chatRepository.listSessions(), isEmpty);
    });

    test('foreign key rejects a missing project', () async {
      final fixture = await SqliteFixture.create();

      expect(
        fixture.chatRepository.upsertSession(
          _session('session-1', projectId: 'missing'),
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('session list defaults to active sessions', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(_session('active'));
      await fixture.chatRepository.upsertSession(_session('deleted'));
      await fixture.chatRepository.softDeleteSession('deleted', _t1);

      expect(
        (await fixture.chatRepository.listSessions()).map(
          (session) => session.id,
        ),
        ['active'],
      );
    });

    test('includeDeleted can read soft-deleted sessions', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(_session('deleted'));
      await fixture.chatRepository.softDeleteSession('deleted', _t1);

      final sessions = await fixture.chatRepository.listSessions(
        includeDeleted: true,
      );

      expect(sessions.single.deletedAt, _t1);
    });

    test('restores a soft-deleted session', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(_session('session-1'));
      await fixture.chatRepository.softDeleteSession('session-1', _t1);

      await fixture.chatRepository.restoreSession(
        'session-1',
        _t1.add(const Duration(hours: 1)),
      );

      final session = await fixture.chatRepository.getSession('session-1');
      expect(session.deletedAt, isNull);
      expect(session.revision, 3);
    });

    test('session sorting matches updatedAt title and id rules', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(
        _session('session-b', title: 'B'),
      );
      await fixture.chatRepository.upsertSession(
        _session('session-a', title: 'A'),
      );
      await fixture.chatRepository.upsertSession(
        _session('session-new', title: 'C', updatedAt: _t1),
      );

      expect((await fixture.chatRepository.listSessions()).map((s) => s.id), [
        'session-new',
        'session-a',
        'session-b',
      ]);
    });

    test('session persists after closing and reopening database', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(_session('session-1'));

      final reopened = await reopenFixture(fixture);

      expect(
        (await reopened.chatRepository.getSession('session-1')).id,
        'session-1',
      );
    });

    test('sends a user message and touches the session atomically', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(_session('session-1'));
      final send = SendChatMessage(fixture.chatRepository);

      await send(
        sessionId: 'session-1',
        messageId: 'message-1',
        role: ChatMessageRole.user,
        content: ' hello ',
        nowUtc: _t1,
      );

      final session = await fixture.chatRepository.getSession('session-1');
      final messages = await fixture.chatRepository.listMessages('session-1');
      expect(messages.single.content, 'hello');
      expect(session.updatedAt, _t1);
      expect(session.revision, 2);
    });

    test('assistant and system messages can be read by role', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(_session('session-1'));
      await fixture.chatRepository.appendMessage(
        chatMessage(
          'message-assistant',
          'session-1',
          null,
          hour: 1,
          role: ChatMessageRole.assistant,
        ),
      );
      await fixture.chatRepository.appendMessage(
        chatMessage(
          'message-system',
          'session-1',
          null,
          hour: 2,
          role: ChatMessageRole.system,
        ),
      );

      expect(
        (await fixture.chatRepository.listMessages(
          'session-1',
        )).map((m) => m.role),
        [ChatMessageRole.assistant, ChatMessageRole.system],
      );
    });

    test('empty messages fail before database write', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(_session('session-1'));
      final send = SendChatMessage(fixture.chatRepository);

      expect(
        send(
          sessionId: 'session-1',
          messageId: 'message-1',
          role: ChatMessageRole.user,
          content: '  ',
          nowUtc: _t1,
        ),
        throwsA(isA<DataFormatException>()),
      );
      expect(await fixture.chatRepository.listMessages('session-1'), isEmpty);
    });

    test('deleted sessions cannot receive messages', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(_session('session-1'));
      await fixture.chatRepository.softDeleteSession('session-1', _t1);
      final send = SendChatMessage(fixture.chatRepository);

      expect(
        send(
          sessionId: 'session-1',
          messageId: 'message-1',
          role: ChatMessageRole.user,
          content: 'hello',
          nowUtc: _t1,
        ),
        throwsA(isA<DataConflictException>()),
      );
      expect(
        await fixture.chatRepository.listMessages(
          'session-1',
          includeDeleted: true,
        ),
        isEmpty,
      );
    });

    test('missing sessions cannot receive messages', () async {
      final fixture = await SqliteFixture.create();
      final send = SendChatMessage(fixture.chatRepository);

      expect(
        send(
          sessionId: 'missing',
          messageId: 'message-1',
          role: ChatMessageRole.user,
          content: 'hello',
          nowUtc: _t1,
        ),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('message sorting uses createdAt then id', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(_session('session-1'));
      await fixture.chatRepository.appendMessage(
        _message('message-b', 'session-1', createdAt: _t1),
      );
      await fixture.chatRepository.appendMessage(
        _message('message-a', 'session-1', createdAt: _t1),
      );

      expect(
        (await fixture.chatRepository.listMessages(
          'session-1',
        )).map((m) => m.id),
        ['message-a', 'message-b'],
      );
    });

    test('message id conflict rolls back the session touch', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(_session('session-1'));
      final send = SendChatMessage(fixture.chatRepository);
      await send(
        sessionId: 'session-1',
        messageId: 'message-1',
        role: ChatMessageRole.user,
        content: 'first',
        nowUtc: _t1,
      );
      final before = await fixture.chatRepository.getSession('session-1');

      expect(
        send(
          sessionId: 'session-1',
          messageId: 'message-1',
          role: ChatMessageRole.user,
          content: 'duplicate',
          nowUtc: _t1.add(const Duration(hours: 1)),
        ),
        throwsA(isA<DuplicateEntityException>()),
      );

      final after = await fixture.chatRepository.getSession('session-1');
      expect(after.revision, before.revision);
      expect(after.updatedAt, before.updatedAt);
      expect(
        await fixture.chatRepository.listMessages('session-1'),
        hasLength(1),
      );
    });

    test('project mismatch rolls back without message residue', () async {
      final fixture = await SqliteFixture.create();
      await fixture.projects.upsertProject(project('project-a'));
      await fixture.projects.upsertProject(project('project-b'));
      await fixture.chatRepository.upsertSession(_session('session-1'));

      expect(
        fixture.chatRepository.appendMessageAndTouchSession(
          _message('message-1', 'session-1', projectId: 'project-b'),
          _t1,
        ),
        throwsA(isA<DataConflictException>()),
      );
      expect(await fixture.chatRepository.listMessages('session-1'), isEmpty);
    });

    test('messages persist after reopening database', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(_session('session-1'));
      await fixture.chatRepository.appendMessage(
        _message('message-1', 'session-1'),
      );

      final reopened = await reopenFixture(fixture);

      expect(
        (await reopened.chatRepository.listMessages('session-1')).single.id,
        'message-1',
      );
    });

    test('updates a session that already has messages', () async {
      final fixture = await SqliteFixture.create();
      await fixture.chatRepository.upsertSession(_session('session-1'));
      await fixture.chatRepository.appendMessage(
        _message('message-1', 'session-1'),
      );

      await fixture.chatRepository.upsertSession(
        _session('session-1', title: 'renamed', updatedAt: _t1).copyWith(
          metadata: _session(
            'session-1',
            updatedAt: _t1,
          ).metadata.copyWith(revision: 2),
        ),
      );

      final session = await fixture.chatRepository.getSession('session-1');
      expect(session.title, 'renamed');
      expect(session.revision, 2);
      expect(
        (await fixture.chatRepository.listMessages('session-1')).single.id,
        'message-1',
      );
    });

    test(
      'soft deletes and restores a session that already has messages',
      () async {
        final fixture = await SqliteFixture.create();
        await fixture.chatRepository.upsertSession(_session('session-1'));
        await fixture.chatRepository.appendMessage(
          _message('message-1', 'session-1'),
        );

        await fixture.chatRepository.softDeleteSession('session-1', _t1);
        await fixture.chatRepository.restoreSession(
          'session-1',
          _t1.add(const Duration(hours: 1)),
        );

        final session = await fixture.chatRepository.getSession('session-1');
        expect(session.deletedAt, isNull);
        expect(session.revision, 3);
        expect(
          (await fixture.chatRepository.listMessages('session-1')).single.id,
          'message-1',
        );
      },
    );

    test(
      'independent chats retain no novel associations after reopen',
      () async {
        final fixture = await SqliteFixture.create();
        await fixture.chatRepository.upsertSession(_session('session-a'));
        final reopened = await reopenFixture(fixture);
        expect(
          (await reopened.chatRepository.getSession('session-a')).projectId,
          isNull,
        );
        expect(
          await reopened.chatRepository.listSessions(projectId: 'novel'),
          isEmpty,
        );
      },
    );
  });
}

final _t0 = DateTime.utc(2026, 8, 1, 8);
final _t1 = DateTime.utc(2026, 8, 1, 9);

ChatSession _session(
  String id, {
  String? projectId,
  String? title,
  DateTime? updatedAt,
}) {
  return ChatSession(
    metadata: EntityMetadata(
      id: id,
      createdAt: _t0,
      updatedAt: updatedAt ?? _t0,
      revision: 1,
    ),
    projectId: projectId,
    title: title ?? id,
  );
}

ChatMessage _message(
  String id,
  String sessionId, {
  String? projectId,
  DateTime? createdAt,
}) {
  final created = createdAt ?? _t0;
  return ChatMessage(
    metadata: EntityMetadata(
      id: id,
      createdAt: created,
      updatedAt: created,
      revision: 1,
    ),
    sessionId: sessionId,
    projectId: projectId,
    role: ChatMessageRole.user,
    content: id,
  );
}
