import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/chat/send_chat_message.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import '../../helpers/chat_image_fixture.dart';
import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);
  Future<SqliteFixture> fixture() async {
    final f = await SqliteFixture.create();
    await f.personas.upsertPersona(
      ChatPersona(
        metadata: metadata('p'),
        name: '人格',
        descriptionMode: ChatPersonaDescriptionMode.simple,
        shortDescription: '',
        speakingStyle: '',
      ),
    );
    for (final id in ['a', 'b']) {
      await f.chatRepository.upsertSession(
        ChatSession(
          metadata: metadata(id),
          projectId: null,
          personaId: 'p',
          title: id,
        ),
      );
    }
    return f;
  }

  Future<ChatMessage> send(SqliteFixture f) =>
      SendChatMessage(f.chatRepository)(
        sessionId: 'a',
        messageId: 'u',
        role: ChatMessageRole.user,
        content: '看看标签',
        image: imageFixture(),
        nowUtc: DateTime.utc(2026),
      );

  test(
    'v19 migration retains text history and v20 image recognition survives reopening',
    () async {
      final f = await fixture();
      await SendChatMessage(f.chatRepository)(
        sessionId: 'a',
        messageId: 'old',
        role: ChatMessageRole.user,
        content: '原有文字',
        nowUtc: DateTime.utc(2025),
      );
      final db = await f.database.database;
      await db.execute('ALTER TABLE chat_messages DROP COLUMN image_json');
      await db.setVersion(19);
      await f.database.close();
      final migrated = await reopenFixture(f);
      expect(await (await migrated.database.database).getVersion(), 21);
      expect((await migrated.chatRepository.getMessage('old')).content, '原有文字');
      expect((await migrated.chatRepository.getMessage('old')).image, isNull);
      final image = await send(migrated);
      final saved = await migrated.chatRepository.mutateLatestMessage(
        expected: image,
        nowUtc: DateTime.utc(2026, 2),
        expectedPersonaId: 'p',
        replacement: image.copyWith(
          image: image.image!.recognized('蓝色杯子，标签 ORBIT-73'),
        ),
      );
      expect(saved.revision, 2);
      await migrated.database.close();
      final again = await reopenFixture(migrated);
      final actual = await again.chatRepository.getMessage('u');
      expect(actual.image, saved.image);
      expect(actual.content, contains('ORBIT-73'));
      expect(actual.image!.userText, '看看标签');
      expect(await again.chatRepository.listMessages('b'), isEmpty);
    },
  );
  test(
    'image and description travel in fresh backups and merge with remapped sessions',
    () async {
      final f = await fixture();
      final pending = await send(f);
      await f.chatRepository.mutateLatestMessage(
        expected: pending,
        nowUtc: DateTime.utc(2026, 2),
        replacement: pending.copyWith(image: pending.image!.recognized('蓝色杯子')),
      );
      final store = SQLiteBackupSnapshotStore(f.database);
      final snapshot = await store.buildSnapshot();
      final imageJson =
          snapshot.collections['chatMessages']!.single['image_json'] as String;
      expect(jsonDecode(imageJson)['description'], '蓝色杯子');
      final empty = await SqliteFixture.create();
      await SQLiteBackupSnapshotStore(
        empty.database,
      ).restore(snapshot, mode: BackupRestoreMode.fresh, restoredAssets: {});
      expect(
        (await empty.chatRepository.getMessage('u')).image!.base64Data,
        imageFixtureBase64,
      );
      await store.restore(
        snapshot,
        mode: BackupRestoreMode.merge,
        restoredAssets: {},
      );
      final clone = (await f.chatRepository.listSessions()).singleWhere(
        (s) => s.title == 'a' && s.id != 'a',
      );
      final copied = (await f.chatRepository.listMessages(clone.id)).single;
      expect(copied.id, isNot('u'));
      expect(copied.image!.description, '蓝色杯子');
      expect(
        await (await f.database.database).rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
    },
  );
  test(
    'invalid image imports roll back without touching original conversations',
    () async {
      final f = await fixture();
      await send(f);
      final store = SQLiteBackupSnapshotStore(f.database);
      final snapshot = await store.buildSnapshot();
      for (final bad in [
        'not json',
        jsonEncode({'data': 'invalid', 'mime': 'image/png', 'userText': ''}),
      ]) {
        final rows = {
          ...snapshot.collections,
          'chatMessages': [
            {
              ...snapshot.collections['chatMessages']!.single,
              'image_json': bad,
            },
          ],
        };
        await expectLater(
          store.restore(
            BackupSnapshot(collections: rows),
            mode: BackupRestoreMode.merge,
            restoredAssets: {},
          ),
          throwsA(isA<BackupException>()),
        );
        expect((await f.chatRepository.listSessions()).length, 2);
        expect(
          (await f.chatRepository.getMessage('u')).image!.base64Data,
          imageFixtureBase64,
        );
      }
    },
  );
  test(
    'recognition cannot replace source bytes or overwrite a completed result',
    () async {
      final f = await fixture();
      final original = await send(f);
      await expectLater(
        f.chatRepository.mutateLatestMessage(
          expected: original,
          nowUtc: DateTime.utc(2026, 2),
          replacement: original.copyWith(
            image: imageFixture(text: '别的文字', description: '描述'),
          ),
        ),
        throwsException,
      );
      final recognized = await f.chatRepository.mutateLatestMessage(
        expected: original,
        nowUtc: DateTime.utc(2026, 2),
        replacement: original.copyWith(image: original.image!.recognized('描述')),
      );
      await expectLater(
        f.chatRepository.mutateLatestMessage(
          expected: original,
          nowUtc: DateTime.utc(2026, 3),
          replacement: original.copyWith(
            image: original.image!.recognized('旧请求'),
          ),
        ),
        throwsException,
      );
      await expectLater(
        f.chatRepository.mutateLatestMessage(
          expected: recognized,
          nowUtc: DateTime.utc(2026, 3),
          replacement: recognized.copyWith(
            image: recognized.image!.recognized('覆盖'),
          ),
        ),
        throwsException,
      );
    },
  );
}
