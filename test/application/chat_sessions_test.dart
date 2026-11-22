import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/chat/create_chat_session.dart';
import 'package:ibukihome/application/chat/list_chat_messages.dart';
import 'package:ibukihome/application/chat/list_chat_sessions.dart';
import 'package:ibukihome/application/chat/rename_chat_session.dart';
import 'package:ibukihome/application/chat/restore_chat_session.dart';
import 'package:ibukihome/application/chat/send_chat_message.dart';
import 'package:ibukihome/application/chat/soft_delete_chat_session.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_chat_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';

void main() {
  group('chat session application flow', () {
    test('creates an unbound chat session', () async {
      final fixture = _Fixture();

      final session = await fixture.createSession(
        id: 'session-1',
        title: '  灵感会话  ',
        projectId: null,
        nowUtc: _t0,
      );

      expect(session.id, 'session-1');
      expect(session.projectId, isNull);
      expect(session.title, '灵感会话');
      expect(session.revision, 1);
      expect(session.createdAt, _t0);
      expect(session.updatedAt, _t0);
      expect(session.deletedAt, isNull);
    });

    test('rejects binding a chat to an existing novel project', () async {
      final fixture = _Fixture();
      await fixture.addProject('project-1');
      expect(
        fixture.createSession(
          id: 'session-1',
          title: '会话',
          projectId: 'project-1',
          nowUtc: _t0,
        ),
        throwsA(isA<DataConflictException>()),
      );
      expect(await fixture.chats.listSessions(), isEmpty);
    });

    test('empty title fails', () async {
      final fixture = _Fixture();

      expect(
        fixture.createSession(
          id: 'session-1',
          title: '   ',
          projectId: null,
          nowUtc: _t0,
        ),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('even missing novel bindings are rejected without lookup', () async {
      final fixture = _Fixture();

      expect(
        fixture.createSession(
          id: 'session-1',
          title: '项目会话',
          projectId: 'missing',
          nowUtc: _t0,
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('deleted project fails', () async {
      final fixture = _Fixture();
      await fixture.addProject('project-1');
      await fixture.projects.softDeleteProject('project-1', _t1);

      expect(
        fixture.createSession(
          id: 'session-1',
          title: '项目会话',
          projectId: 'project-1',
          nowUtc: _t1,
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('created session can be listed and read', () async {
      final fixture = _Fixture();
      await fixture.createSession(
        id: 'session-1',
        title: '会话',
        projectId: null,
        nowUtc: _t0,
      );

      expect((await fixture.listSessions()).single.id, 'session-1');
      expect((await fixture.chats.getSession('session-1')).title, '会话');
    });

    test('renames a chat session', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-1');

      final renamed = await fixture.renameSession(
        sessionId: 'session-1',
        title: '  新标题  ',
        nowUtc: _t1,
      );

      expect(renamed.title, '新标题');
      expect(renamed.revision, 2);
      expect(renamed.updatedAt, _t1);
    });

    test('unchanged rename does not increment revision', () async {
      final fixture = _Fixture();
      final original = await fixture.addSession('session-1', title: '会话');

      final renamed = await fixture.renameSession(
        sessionId: 'session-1',
        title: '会话',
        nowUtc: _t1,
      );

      expect(renamed.revision, original.revision);
      expect(renamed.updatedAt, original.updatedAt);
    });

    test('soft delete hides a chat session', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-1');

      await fixture.deleteSession(sessionId: 'session-1', nowUtc: _t1);

      expect(await fixture.listSessions(), isEmpty);
      final deleted = await fixture.chats.getSession('session-1');
      expect(deleted.deletedAt, _t1);
      expect(deleted.revision, 2);
    });

    test('includeDeleted and onlyDeleted read soft-deleted sessions', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-1');
      await fixture.deleteSession(sessionId: 'session-1', nowUtc: _t1);

      expect(await fixture.listSessions(includeDeleted: true), hasLength(1));
      expect(
        (await fixture.listSessions(onlyDeleted: true)).single.id,
        'session-1',
      );
    });

    test('repeated delete does not increment revision', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-1');

      await fixture.deleteSession(sessionId: 'session-1', nowUtc: _t1);
      final first = await fixture.chats.getSession('session-1');
      await fixture.deleteSession(
        sessionId: 'session-1',
        nowUtc: _t1.add(const Duration(hours: 1)),
      );
      final second = await fixture.chats.getSession('session-1');

      expect(second.revision, first.revision);
      expect(second.deletedAt, first.deletedAt);
    });

    test('restores a deleted chat session', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-1');
      await fixture.deleteSession(sessionId: 'session-1', nowUtc: _t1);

      await fixture.restoreSession(
        sessionId: 'session-1',
        nowUtc: _t1.add(const Duration(hours: 1)),
      );

      final restored = await fixture.chats.getSession('session-1');
      expect(restored.deletedAt, isNull);
      expect(restored.revision, 3);
      expect((await fixture.listSessions()).single.id, 'session-1');
    });

    test('repeated restore does not increment revision', () async {
      final fixture = _Fixture();
      final original = await fixture.addSession('session-1');

      await fixture.restoreSession(sessionId: 'session-1', nowUtc: _t1);

      expect(
        (await fixture.chats.getSession('session-1')).revision,
        original.revision,
      );
    });

    test('deleting a session does not clear messages', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-1');
      await fixture.sendMessage(
        sessionId: 'session-1',
        messageId: 'message-1',
        role: ChatMessageRole.user,
        content: 'hello',
        nowUtc: _t1,
      );

      await fixture.deleteSession(
        sessionId: 'session-1',
        nowUtc: _t1.add(const Duration(hours: 1)),
      );

      expect(await fixture.listMessages('session-1'), hasLength(1));
    });

    test('session sorting is stable', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-b', title: 'B', nowUtc: _t0);
      await fixture.addSession('session-a', title: 'A', nowUtc: _t0);
      await fixture.addSession('session-new', title: 'C', nowUtc: _t1);

      expect((await fixture.listSessions()).map((session) => session.id), [
        'session-new',
        'session-a',
        'session-b',
      ]);
    });

    test('deleted sessions sort by deletedAt descending then id', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-a');
      await fixture.addSession('session-b');
      await fixture.deleteSession(sessionId: 'session-a', nowUtc: _t1);
      await fixture.deleteSession(
        sessionId: 'session-b',
        nowUtc: _t1.add(const Duration(hours: 1)),
      );

      expect(
        (await fixture.listSessions(
          onlyDeleted: true,
        )).map((session) => session.id),
        ['session-b', 'session-a'],
      );
    });

    test('sends and trims a user message', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-1');

      final message = await fixture.sendMessage(
        sessionId: 'session-1',
        messageId: 'message-1',
        role: ChatMessageRole.user,
        content: '  第一条消息  ',
        nowUtc: _t1,
      );

      expect(message.content, '第一条消息');
      expect((await fixture.listMessages('session-1')).single.id, 'message-1');
    });

    test('empty and trim-empty messages fail', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-1');

      for (final content in ['', '   ']) {
        expect(
          fixture.sendMessage(
            sessionId: 'session-1',
            messageId: 'message-$content',
            role: ChatMessageRole.user,
            content: content,
            nowUtc: _t1,
          ),
          throwsA(isA<DataFormatException>()),
        );
      }
    });

    test('deleted session cannot receive messages', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-1');
      await fixture.deleteSession(sessionId: 'session-1', nowUtc: _t1);

      expect(
        fixture.sendMessage(
          sessionId: 'session-1',
          messageId: 'message-1',
          role: ChatMessageRole.user,
          content: 'hello',
          nowUtc: _t1,
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('missing session cannot receive messages', () async {
      final fixture = _Fixture();

      expect(
        fixture.sendMessage(
          sessionId: 'missing',
          messageId: 'message-1',
          role: ChatMessageRole.user,
          content: 'hello',
          nowUtc: _t1,
        ),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('messages sort by createdAt then id', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-1');
      await fixture.sendMessage(
        sessionId: 'session-1',
        messageId: 'message-b',
        role: ChatMessageRole.user,
        content: 'B',
        nowUtc: _t1,
      );
      await fixture.sendMessage(
        sessionId: 'session-1',
        messageId: 'message-a',
        role: ChatMessageRole.user,
        content: 'A',
        nowUtc: _t1,
      );

      expect(
        (await fixture.listMessages('session-1')).map((message) => message.id),
        ['message-a', 'message-b'],
      );
    });

    test('assistant and system messages can be saved and read', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-1');

      await fixture.sendMessage(
        sessionId: 'session-1',
        messageId: 'message-assistant',
        role: ChatMessageRole.assistant,
        content: '助手消息',
        nowUtc: _t1,
      );
      await fixture.sendMessage(
        sessionId: 'session-1',
        messageId: 'message-system',
        role: ChatMessageRole.system,
        content: '系统消息',
        nowUtc: _t1.add(const Duration(minutes: 1)),
      );

      expect(
        (await fixture.listMessages(
          'session-1',
        )).map((message) => message.role),
        [ChatMessageRole.assistant, ChatMessageRole.system],
      );
    });

    test('sending updates session updatedAt and revision', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-1', nowUtc: _t0);

      await fixture.sendMessage(
        sessionId: 'session-1',
        messageId: 'message-1',
        role: ChatMessageRole.user,
        content: 'hello',
        nowUtc: _t1,
      );

      final session = await fixture.chats.getSession('session-1');
      expect(session.updatedAt, _t1);
      expect(session.revision, 2);
    });

    test('message id conflict rolls back session touch', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-1', nowUtc: _t0);
      await fixture.sendMessage(
        sessionId: 'session-1',
        messageId: 'message-1',
        role: ChatMessageRole.user,
        content: 'first',
        nowUtc: _t1,
      );
      final before = await fixture.chats.getSession('session-1');

      expect(
        fixture.sendMessage(
          sessionId: 'session-1',
          messageId: 'message-1',
          role: ChatMessageRole.user,
          content: 'duplicate',
          nowUtc: _t1.add(const Duration(hours: 1)),
        ),
        throwsA(isA<DuplicateEntityException>()),
      );
      final after = await fixture.chats.getSession('session-1');

      expect(after.updatedAt, before.updatedAt);
      expect(after.revision, before.revision);
      expect(await fixture.listMessages('session-1'), hasLength(1));
    });

    test('novel project filters never return independent chats', () async {
      final fixture = _Fixture();
      await fixture.addSession('session-a');
      expect(await fixture.listSessions(projectId: 'project-a'), isEmpty);
    });
  });
}

final _t0 = DateTime.utc(2026, 8, 1, 8);
final _t1 = DateTime.utc(2026, 8, 1, 9);

class _Fixture {
  final InMemoryIbukiStore store = InMemoryIbukiStore();
  late final InMemoryProjectRepository projects = InMemoryProjectRepository(
    store,
  );
  late final InMemoryChatRepository chats = InMemoryChatRepository(store);
  late final CreateChatSession createSession = CreateChatSession(chats);
  late final RenameChatSession renameSession = RenameChatSession(chats);
  late final SoftDeleteChatSession deleteSession = SoftDeleteChatSession(chats);
  late final RestoreChatSession restoreSession = RestoreChatSession(chats);
  late final SendChatMessage sendMessage = SendChatMessage(chats);
  late final ListChatSessions listSessions = ListChatSessions(chats);
  late final ListChatMessages listMessages = ListChatMessages(chats);

  Future<void> addProject(String id) {
    return projects.upsertProject(
      Project(
        metadata: EntityMetadata(
          id: id,
          createdAt: _t0,
          updatedAt: _t0,
          revision: 1,
        ),
        title: id,
        description: '',
      ),
    );
  }

  Future<dynamic> addSession(
    String id, {
    String title = '会话',
    String? projectId,
    DateTime? nowUtc,
  }) {
    return createSession(
      id: id,
      title: title,
      projectId: projectId,
      nowUtc: nowUtc ?? _t0,
    );
  }
}
