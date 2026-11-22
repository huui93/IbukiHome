import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ibukihome/data/sqlite/sqlite_chat_controls_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/domain/ai/ai_reasoning_level.dart';
import 'package:ibukihome/domain/ai/ai_token_usage.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'package:ibukihome/domain/chat/chat_usage_record.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);
  Future<SqliteFixture> fixture() async {
    final f = await SqliteFixture.create();
    for (final id in ['a', 'b']) {
      await f.chatRepository.upsertSession(
        ChatSession(
          metadata: metadata(id),
          projectId: null,
          characterId: null,
          title: id,
        ),
      );
    }
    return f;
  }

  test(
    'v17 migration preserves messages and defaults controls independently',
    () async {
      final f = await fixture();
      await f.chatRepository.appendMessage(
        message('u', 'a', ChatMessageRole.user, 0),
      );
      final db = await f.database.database;
      await db.execute('DROP TABLE chat_session_controls');
      await db.execute('DROP TABLE chat_usage_records');
      await db.setVersion(17);
      await f.database.close();
      final reopened = await reopenFixture(f);
      final repo = SQLiteChatControlsRepository(reopened.database);
      expect(await (await reopened.database.database).getVersion(), 21);
      expect(
        (await reopened.chatRepository.listMessages('a')).single.content,
        'u',
      );
      expect(await repo.getReasoning('a'), AiReasoningLevel.automatic);
      await repo.setReasoning(
        'a',
        AiReasoningLevel.high,
        DateTime.now().toUtc(),
      );
      expect(await repo.getReasoning('a'), AiReasoningLevel.high);
      expect(await repo.getReasoning('b'), AiReasoningLevel.automatic);
      await reopened.database.close();
      final again = await reopenFixture(reopened);
      expect(
        await SQLiteChatControlsRepository(again.database).getReasoning('a'),
        AiReasoningLevel.high,
      );
    },
  );
  test(
    'usage is immutable idempotent and session isolated, backup merge remaps both tables',
    () async {
      final f = await fixture();
      final repo = SQLiteChatControlsRepository(f.database);
      await repo.setReasoning(
        'a',
        AiReasoningLevel.low,
        DateTime.now().toUtc(),
      );
      final record = usage('request', 'a');
      await repo.recordUsage(record);
      await repo.recordUsage(record);
      expect(await repo.listUsage('a'), hasLength(1));
      expect((await repo.listUsage('a')).single.usage!.isComplete, isTrue);
      expect(await repo.listUsage('b'), isEmpty);
      await expectLater(
        repo.recordUsage(usage('request', 'b')),
        throwsException,
      );
      final store = SQLiteBackupSnapshotStore(f.database);
      final snapshot = await store.buildSnapshot();
      await store.restore(
        snapshot,
        mode: BackupRestoreMode.merge,
        restoredAssets: {},
      );
      final sessions = await f.chatRepository.listSessions();
      expect(sessions, hasLength(4));
      final copy = sessions.where((s) => s.title == 'a' && s.id != 'a').single;
      expect(await repo.getReasoning(copy.id), AiReasoningLevel.low);
      expect((await repo.listUsage(copy.id)).single.id, isNot('request'));
      expect((await repo.listUsage('a')).single.id, 'request');
      expect(
        await (await f.database.database).rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
    },
  );
  test(
    'latest-only mutation deletes assistant then user, rejects stale and cross-session changes atomically',
    () async {
      final f = await fixture();
      final user = message('u', 'a', ChatMessageRole.user, 0);
      final ai = message('ai', 'a', ChatMessageRole.assistant, 1);
      await f.chatRepository.appendMessage(user);
      await f.chatRepository.appendMessage(ai);
      await expectLater(
        f.chatRepository.mutateLatestMessage(
          expected: user,
          nowUtc: DateTime.now().toUtc(),
        ),
        throwsException,
      );
      await expectLater(
        f.chatRepository.mutateLatestMessage(
          expected: ai,
          replacement: message('ai', 'b', ChatMessageRole.assistant, 1),
          nowUtc: DateTime.now().toUtc(),
        ),
        throwsException,
      );
      final replaced = await f.chatRepository.mutateLatestMessage(
        expected: ai,
        replacement: ai.copyWith(content: 'new'),
        nowUtc: DateTime.now().toUtc(),
      );
      expect(replaced.revision, ai.revision + 1);
      await expectLater(
        f.chatRepository.mutateLatestMessage(
          expected: ai,
          nowUtc: DateTime.now().toUtc(),
        ),
        throwsException,
      );
      await f.chatRepository.mutateLatestMessage(
        expected: replaced,
        nowUtc: DateTime.now().toUtc(),
      );
      expect((await f.chatRepository.listMessages('a')).single.id, 'u');
      await f.chatRepository.mutateLatestMessage(
        expected: user,
        nowUtc: DateTime.now().toUtc(),
      );
      expect(await f.chatRepository.listMessages('a'), isEmpty);
    },
  );
  test(
    'append enforces the last user snapshot and strict ordering for equal timestamps',
    () async {
      final f = await fixture();
      final user = message('z-user', 'a', ChatMessageRole.user, 0);
      await f.chatRepository.appendMessage(user);
      final reply = message('a-assistant', 'a', ChatMessageRole.assistant, 0);
      await f.chatRepository.mutateLatestMessage(
        expected: user,
        replacement: reply,
        append: true,
        nowUtc: DateTime.now().toUtc(),
      );
      expect((await f.chatRepository.listMessages('a')).last.id, reply.id);
      await expectLater(
        f.chatRepository.mutateLatestMessage(
          expected: user,
          replacement: reply.copyWith(metadata: metadata('another')),
          append: true,
          nowUtc: DateTime.now().toUtc(),
        ),
        throwsException,
      );
      expect(await f.chatRepository.listMessages('a'), hasLength(2));
    },
  );
}

ChatMessage message(
  String id,
  String session,
  ChatMessageRole role,
  int seconds,
) => ChatMessage(
  metadata: metadata(
    id,
    createdAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: seconds)),
  ),
  sessionId: session,
  projectId: null,
  role: role,
  content: id,
);
ChatUsageRecord usage(String id, String session) => ChatUsageRecord(
  id: id,
  sessionId: session,
  operation: 'chat-reply',
  providerId: 'test',
  model: 'test',
  status: 'stop',
  startedAt: DateTime.utc(2026),
  endedAt: DateTime.utc(2026),
  estimatedInputTokens: 10,
  estimatedOutputTokens: 2,
  usage: const AiTokenUsage(inputTokens: 20, outputTokens: 5, isFinal: true),
);
