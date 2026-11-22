import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/memory/source_fingerprint.dart';
import 'package:ibukihome/data/sqlite/sqlite_chat_memory_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/data/sqlite/sqlite_migrations.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'package:ibukihome/domain/chat/chat_memory_entry.dart';
import 'package:ibukihome/domain/chat/chat_memory_state.dart';
import 'package:ibukihome/domain/chat/conversation_summary.dart';
import 'package:ibukihome/domain/memory/memory_generation_status.dart';
import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);
  test(
    'v15 upgrade retains personas, messages and legacy unassigned memories',
    () async {
      final f = await SqliteFixture.create();
      await seed(f);
      final repo = SQLiteChatMemoryRepository(f.database);
      await repo.upsertEntry(entry().copyWith(sessionId: null));
      final db = await f.database.database;
      await db.execute('DROP TABLE chat_memory_usage');
      await db.execute('DROP TABLE chat_memory_states');
      await db.execute('ALTER TABLE chat_memory_entries DROP COLUMN topic');
      await db.execute(
        'ALTER TABLE chat_memory_entries DROP COLUMN source_fingerprint',
      );
      await db.execute('PRAGMA user_version = 15');
      await f.database.close();
      final reopened = await reopenFixture(f);
      final sql = await reopened.database.database;
      expect(await sql.getVersion(), SqliteSchema.version);
      final current = SQLiteChatMemoryRepository(reopened.database);
      expect((await current.getEntry('note')).sessionId, isNull);
      expect((await current.getEntry('note')).content, '用户喜欢乌龙茶');
      expect(await current.listEntriesForSession('s'), isEmpty);
      expect(
        (await reopened.chatRepository.listMessages('s')).single.content,
        '用户喜欢乌龙茶',
      );
      expect(await current.getState('s'), isNull);
      await ensureCurrentSchema(sql);
      expect(await sql.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test('state, notes and reply sources survive reopen', () async {
    final f = await SqliteFixture.create();
    await seed(f);
    final repo = SQLiteChatMemoryRepository(f.database);
    final messages = await f.chatRepository.listMessages('s');
    final state = ChatMemoryState(
      metadata: metadata('state'),
      sessionId: 's',
      paused: true,
      overview: '只属于这个会话',
      overviewEdited: true,
      cursor: 'message',
      processedFingerprint: fingerprintMessages(messages),
    );
    expect(
      await repo.commitSessionMemory(
        state,
        expectedRevision: 0,
        entries: [entry()],
      ),
      isTrue,
    );
    await repo.saveUsage(
      const ChatMemoryUsage(
        id: 'usage',
        sessionId: 's',
        messageId: 'message',
        sourceKeys: ['saved:note|version'],
      ),
    );
    await f.database.close();
    final reopened = await reopenFixture(f);
    final current = SQLiteChatMemoryRepository(reopened.database);
    expect((await current.getState('s'))!.paused, isTrue);
    expect((await current.getState('s'))!.overviewEdited, isTrue);
    expect((await current.getEntry('note')).topic, '饮品');
    expect((await current.getUsage('s', 'message'))!.sourceKeys, [
      'saved:note|version',
    ]);
    expect(await current.getUsage('other', 'message'), isNull);
  });
  test('stale compare-and-swap commits no derived rows', () async {
    final f = await SqliteFixture.create();
    await seed(f);
    final repo = SQLiteChatMemoryRepository(f.database);
    final state = ChatMemoryState(metadata: metadata('state'), sessionId: 's');
    await repo.commitSessionMemory(state, expectedRevision: 0);
    await repo.commitSessionMemory(
      state.copyWith(
        metadata: state.metadata.copyWith(revision: 2),
        savedEnabled: false,
      ),
      expectedRevision: 1,
    );
    expect(
      await repo.commitSessionMemory(
        state.copyWith(metadata: state.metadata.copyWith(revision: 2)),
        expectedRevision: 1,
        entries: [entry()],
      ),
      isFalse,
    );
    expect(await repo.listEntriesForSession('s'), isEmpty);
    expect((await repo.getState('s'))!.savedEnabled, isFalse);
  });
  test(
    'cross-session commit and source association roll back atomically',
    () async {
      final f = await SqliteFixture.create();
      await seed(f);
      await f.chatRepository.upsertSession(
        chatSession('other', null).copyWith(personaId: 'p'),
      );
      final repo = SQLiteChatMemoryRepository(f.database);
      final state = ChatMemoryState(
        metadata: metadata('state'),
        sessionId: 's',
      );
      await expectLater(
        repo.commitSessionMemory(
          state,
          expectedRevision: 0,
          entries: [entry().copyWith(sessionId: 'other')],
        ),
        throwsException,
      );
      expect(await repo.getState('s'), isNull);
      expect(await repo.listEntriesForSession('s'), isEmpty);
      await expectLater(
        repo.saveUsage(
          const ChatMemoryUsage(
            id: 'usage',
            sessionId: 'other',
            messageId: 'message',
            sourceKeys: [],
          ),
        ),
        throwsException,
      );
      expect(await repo.getUsage('other', 'message'), isNull);
    },
  );
  test(
    'backup empty restore and collision merge rewrite all memory references',
    () async {
      final f = await SqliteFixture.create();
      await seed(f);
      final repo = SQLiteChatMemoryRepository(f.database);
      final messages = await f.chatRepository.listMessages('s');
      final state = ChatMemoryState(
        metadata: metadata('state'),
        sessionId: 's',
        cursor: 'message',
        processedFingerprint: fingerprintMessages(messages),
        overview: '概览',
        overviewEdited: true,
        excludedSources: [
          'message:message',
          'summary:summary',
          'overview:state',
        ],
      );
      await repo.commitSessionMemory(
        state,
        expectedRevision: 0,
        entries: [
          entry().copyWith(sourceFingerprint: fingerprintMessages(messages)),
        ],
        summaries: [
          ConversationSummary(
            metadata: metadata('summary'),
            sessionId: 's',
            sourceStartMessageId: 'message',
            sourceEndMessageId: 'message',
            summary: '摘要',
            sourceFingerprint: fingerprintMessages(messages),
            status: MemoryGenerationStatus.valid,
          ),
        ],
      );
      await repo.saveUsage(
        const ChatMemoryUsage(
          id: 'usage',
          sessionId: 's',
          messageId: 'message',
          sourceKeys: [
            'saved:note|v1',
            'summary:summary|v2',
            'message:message|v3',
            'overview:state|v4',
          ],
        ),
      );
      final snapshot = await SQLiteBackupSnapshotStore(
        f.database,
      ).buildSnapshot();
      final target = await SqliteFixture.create();
      final restore = SQLiteBackupSnapshotStore(target.database);
      await restore.restore(
        snapshot,
        mode: BackupRestoreMode.fresh,
        restoredAssets: const {},
      );
      await restore.restore(
        snapshot,
        mode: BackupRestoreMode.merge,
        restoredAssets: const {},
      );
      final sessions = await target.chatRepository.listSessions();
      expect(sessions, hasLength(2));
      final restored = SQLiteChatMemoryRepository(target.database);
      for (final session in sessions) {
        final current = (await restored.getState(session.id))!;
        final notes = await restored.listEntriesForSession(session.id);
        final summaries = await restored.listSummaries(session.id);
        final raw = await target.chatRepository.listMessages(session.id);
        final usage = (await restored.getUsage(session.id, raw.single.id))!;
        expect(notes.single.personaId, session.personaId);
        expect(notes.single.sourceStartMessageId, raw.single.id);
        expect(notes.single.sourceFingerprint, fingerprintMessages(raw));
        expect(summaries.single.sourceFingerprint, fingerprintMessages(raw));
        expect(current.processedFingerprint, fingerprintMessages(raw));
        expect(current.cursor, raw.single.id);
        expect(current.excludedSources, [
          'message:${raw.single.id}',
          'summary:${summaries.single.id}',
          'overview:${current.metadata.id}',
        ]);
        expect(usage.sourceKeys, [
          'saved:${notes.single.id}|v1',
          'summary:${summaries.single.id}|v2',
          'message:${raw.single.id}|v3',
          'overview:${current.metadata.id}|v4',
        ]);
      }
      expect(
        await (await target.database.database).rawQuery(
          'PRAGMA foreign_key_check',
        ),
        isEmpty,
      );
    },
  );
  test('malformed state backup is rejected and leaves target empty', () async {
    final f = await SqliteFixture.create();
    await seed(f);
    final repo = SQLiteChatMemoryRepository(f.database);
    await repo.commitSessionMemory(
      ChatMemoryState(metadata: metadata('state'), sessionId: 's'),
      expectedRevision: 0,
    );
    final snapshot = await SQLiteBackupSnapshotStore(
      f.database,
    ).buildSnapshot();
    final collections = {...snapshot.collections};
    collections['chatMemoryStates'] = [
      {
        ...collections['chatMemoryStates']!.single,
        'data_json': jsonEncode({
          'blockedPhrases': [42],
        }),
      },
    ];
    final target = await SqliteFixture.create();
    await expectLater(
      SQLiteBackupSnapshotStore(target.database).restore(
        BackupSnapshot(collections: collections),
        mode: BackupRestoreMode.fresh,
        restoredAssets: const {},
      ),
      throwsException,
    );
    expect(await target.chatRepository.listSessions(), isEmpty);
  });
}

Future<void> seed(SqliteFixture f) async {
  await f.personas.upsertPersona(chatPersona('p'));
  await f.chatRepository.upsertSession(
    chatSession('s', null).copyWith(personaId: 'p'),
  );
  await f.chatRepository.appendMessage(
    chatMessage('message', 's', null, hour: 1, content: '用户喜欢乌龙茶'),
  );
}

ChatMemoryEntry entry() => ChatMemoryEntry(
  metadata: metadata('note'),
  personaId: 'p',
  sessionId: 's',
  category: ChatMemoryCategory.preference,
  content: '用户喜欢乌龙茶',
  origin: ChatMemoryOrigin.auto,
  topic: '饮品',
  sourceSessionId: 's',
  sourceStartMessageId: 'message',
  sourceEndMessageId: 'message',
);
