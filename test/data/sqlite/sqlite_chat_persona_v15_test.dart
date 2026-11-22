import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/chat/create_chat_persona.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/data/sqlite/sqlite_migrations.dart';
import 'package:ibukihome/data/sqlite/sqlite_value_codec.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'package:ibukihome/domain/chat/chat_preset_message.dart';
import 'sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);
  test(
    'v14 upgrade preserves legacy content and detaches novel links once',
    () async {
      final f = await SqliteFixture.create();
      final db = await f.database.database;
      await f.projects.upsertProject(project('novel'));
      await f.characters.upsertCharacter(characterCard('card', 'novel', 0));
      final legacy = chatPersona(
        'p',
      ).copyWith(background: '旧背景', autoMemoryEnabled: false);
      await f.personas.upsertPersona(legacy);
      await db.insert('chat_sessions', {
        ...chatSessionToSql(chatSession('s', 'novel')),
        'character_id': 'card',
      });
      await db.insert(
        'chat_messages',
        chatMessageToSql(chatMessage('m', 's', 'novel', hour: 1)),
      );
      await db.execute('ALTER TABLE chat_personas DROP COLUMN persona_prompt');
      await db.execute(
        'ALTER TABLE chat_personas DROP COLUMN preset_messages_json',
      );
      await db.execute('PRAGMA user_version = 14');
      await runMigrations(db, 14, 15);
      await db.execute('PRAGMA user_version = 15');
      final session = await f.chatRepository.getSession('s');
      expect(session.projectId, isNull);
      expect(session.characterId, isNull);
      final migrated = await f.personas.getPersona(session.personaId!);
      expect(
        migrated.personaPrompt,
        (await f.characters.getCharacter('card')).content,
      );
      expect((await f.chatRepository.listMessages('s')).single.content, 'm');
      expect(
        (await f.chatRepository.listMessages('s')).single.projectId,
        isNull,
      );
      expect(await f.personas.getPersona('p'), legacy);
      final before = await db.query('chat_personas');
      await ensureCurrentSchema(db);
      expect(await db.query('chat_personas'), before);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'prompt, examples and avatar survive reopen and archive collision merge',
    () async {
      final f = await SqliteFixture.create();
      final persona = await CreateChatPersona(f.personas)(
        id: 'p',
        name: '名字',
        personaPrompt: '人格提示词',
        avatarReference: 'mint',
        presetMessages: const [
          ChatPresetMessage(user: '问一', assistant: '答一'),
          ChatPresetMessage(user: '问二', assistant: '答二'),
        ],
        nowUtc: DateTime.utc(2026, 11, 21),
      );
      final reopened = await reopenFixture(f);
      expect(await reopened.personas.getPersona('p'), persona);
      final source = SQLiteBackupSnapshotStore(reopened.database);
      final snapshot = await source.buildSnapshot();
      final target = await SqliteFixture.create();
      final restore = SQLiteBackupSnapshotStore(target.database);
      await restore.restore(
        snapshot,
        mode: BackupRestoreMode.fresh,
        restoredAssets: {},
      );
      await restore.restore(
        snapshot,
        mode: BackupRestoreMode.merge,
        restoredAssets: {},
      );
      final all = await target.personas.listPersonas();
      expect(all, hasLength(2));
      for (final saved in all) {
        expect(saved.personaPrompt, persona.personaPrompt);
        expect(saved.presetMessages, persona.presetMessages);
        expect(saved.avatarReference, persona.avatarReference);
      }
    },
  );

  test('malformed preset pairs roll back the entire archive restore', () async {
    final f = await SqliteFixture.create();
    final row = chatPersonaToSql(chatPersona('bad'));
    row['preset_messages_json'] = jsonEncode([
      {'user': '问', 'assistant': ''},
    ]);
    final snapshot = BackupSnapshot(
      collections: {
        'projects': [projectToSql(project('novel'))],
        'chatPersonas': [row],
      },
    );
    await expectLater(
      SQLiteBackupSnapshotStore(
        f.database,
      ).restore(snapshot, mode: BackupRestoreMode.fresh, restoredAssets: {}),
      throwsA(anything),
    );
    expect(await f.projects.listProjects(), isEmpty);
    expect(await f.personas.listPersonas(), isEmpty);
  });
}
