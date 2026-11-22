import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/tavern/tavern_generation_runtime.dart';
import 'package:ibukihome/application/tavern/tavern_story_service.dart';
import 'package:ibukihome/application/tavern/tavern_source_resolver.dart';
import 'package:ibukihome/application/tavern/tavern_presentation_providers.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/data/sqlite/sqlite_tavern_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_migrations.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_models.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import '../support/tavern_ui_rig.dart';
import 'tavern_provider_adapter_test.dart' as fixtures;

void main() {
  late TavernUiRig rig;
  setUp(() async {
    rig = TavernUiRig();
    await rig.initialize();
  });
  tearDown(() async => rig.dispose());
  test(
    'invalid answer/line navigation is visible without changing history',
    () async {
      final c = rig.controller();
      await c.load();
      await c.send('north');
      final before = c.projection!;
      await c.selectAnswer(before.turns.last, 'absent-answer');
      expect(c.error, isNotNull);
      expect(
        c.projection!.turns.last.selectedAlternative.id,
        before.turns.last.selectedAlternative.id,
      );
      await c.switchLine('absent-line');
      expect(c.error, isNotNull);
      expect(c.projection!.storyLine.id, before.storyLine.id);
      expect(
        (await rig.repo.loadTranscript('s')).storyLine.id,
        before.storyLine.id,
      );
    },
  );
  test(
    'legacy Persona without visibility metadata does not expose background/private notes',
    () async {
      final persona = await rig.service.worlds.getPersona('persona');
      await rig.service.worlds.upsertPersona(
        persona.copyWith(
          metadata: {},
          background: 'DIRECTOR-ONLY-FACT',
          notes: 'PRIVATE-FACT',
        ),
      );
      final bundle = await rig.env.owner.sources.resolve(
        await rig.repo.loadTranscript('s'),
        'speaker',
      );
      final text = bundle.sources
          .map((s) => s.atoms.map((a) => a.text).join())
          .join();
      expect(text, contains('Public identity'));
      expect(text, isNot(contains('DIRECTOR-ONLY-FACT')));
      expect(text, isNot(contains('PRIVATE-FACT')));
    },
  );
  test(
    'Android portable v14 schema keeps generation, fork, archive and strict journal validation',
    () async {
      final db = await rig.db.database;
      final states = await db.query('tavern_world_info_states');
      await db.execute('DROP TABLE tavern_world_info_journal');
      await db.execute('DROP TABLE tavern_world_info_states');
      await createTavernWorldInfoV14Schema(db, jsonFunctions: false);
      for (final row in states) {
        await db.insert('tavern_world_info_states', row);
      }
      final schema = (await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE name LIKE 'tavern_world_info_%' AND type='table'",
      )).map((r) => r['sql']).join();
      expect(schema, isNot(contains('json_valid')));
      expect(schema, isNot(contains('json_extract')));
      final c = rig.controller();
      await c.load();
      await c.send('north');
      final attempt = (await rig.repo.listAttempts(
        c.projection!.turns.last.selectedAlternative.id,
      )).single;
      final checkpoint = await rig.repo.loadWorldInfoState('s', 'main');
      expect(checkpoint.version, 1);
      await c.fork(c.projection!.turns.last, 'Portable branch');
      expect(
        (await rig.repo.loadWorldInfoState(
          's',
          c.projection!.storyLine.id,
        )).initialData.fingerprint,
        checkpoint.data.fingerprint,
      );
      final snapshot = await SQLiteBackupSnapshotStore(rig.db).buildSnapshot();
      final target = rig.database('portable-restore.db');
      await SQLiteBackupSnapshotStore(
        target,
      ).restore(snapshot, mode: BackupRestoreMode.fresh, restoredAssets: {});
      expect(
        (await SQLiteTavernRepository(
          target,
        ).loadWorldInfoState('s', 'main')).data.fingerprint,
        checkpoint.data.fingerprint,
      );
      await target.close();
      await db.update(
        'tavern_world_info_journal',
        {'plan_json': '{}'},
        where: 'attempt_id=?',
        whereArgs: [attempt.id],
      );
      await expectLater(
        rig.repo.getWorldInfoJournal(attempt.id),
        throwsA(isA<TypeError>()),
      );
    },
  );
  test(
    'portable orphan detection protects recovery and archive without SQL JSON functions',
    () async {
      final c = rig.controller();
      await c.load();
      await c.send('north');
      final attempt = (await rig.repo.listAttempts(
        c.projection!.turns.last.selectedAlternative.id,
      )).single;
      await (await rig.db.database).delete(
        'tavern_world_info_journal',
        where: 'attempt_id=?',
        whereArgs: [attempt.id],
      );
      await expectLater(
        rig.repo.reconcileWorldInfo(),
        throwsA(isA<Exception>()),
      );
      final snapshot = await SQLiteBackupSnapshotStore(rig.db).buildSnapshot();
      final target = rig.database('orphan-restore.db');
      await expectLater(
        SQLiteBackupSnapshotStore(
          target,
        ).restore(snapshot, mode: BackupRestoreMode.fresh, restoredAssets: {}),
        throwsA(isA<Exception>()),
      );
      expect(
        (await SQLiteTavernRepository(target).listSessions()).isEmpty,
        true,
      );
      await target.close();
    },
  );
  test(
    '50 explicit Lore sources are activated by the one formal engine within compile budget',
    () async {
      final now = DateTime.now(), refs = <String, Object?>{};
      EntityMetadata entity(String id) =>
          EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);
      for (var i = 0; i < 50; i++) {
        await rig.service.worlds.upsertWorldBook(
          WorldBook(entity: entity('book-$i'), name: 'Book $i'),
        );
        await rig.service.worlds.upsertLoreEntry(
          LoreEntry(
            entity: entity('lore-$i'),
            worldBookId: 'book-$i',
            title: 'Lore $i',
            content: 'Public fact $i',
            activationMode: LoreActivationMode.always,
          ),
        );
        refs['book-$i'] = {'enabled': true, 'priority': i};
      }
      await rig.service.saveSettings('s', {'tavernBookReferencesV1': refs});
      final c = rig.controller();
      await c.load();
      await c.send('north');
      final trace =
          c.traces[c
              .attempts[c.projection!.turns.last.selectedAlternative.id]!
              .last
              .id]!;
      expect(trace.activation.checked, 51);
      expect(trace.activation.active, 51);
      expect(
        trace.compilation.usedInputTokens,
        lessThanOrEqualTo(trace.compilation.usableInputTokens),
      );
      expect(
        trace.activation.decisions.map((d) => d.identity).toSet().length,
        51,
      );
    },
  );
  test(
    'real asset catalog and independent reusable identity create atomic formal session',
    () async {
      final assets = await rig.service.loadAssets();
      expect(assets.characters.single.id, 'character');
      expect(assets.worlds.length, 2);
      final s = await rig.service.createStory(
        TavernStoryDraft(
          title: 'Saved Story',
          characterIds: {'character'},
          personaName: 'Lia',
          personaDescription: 'Public traveler',
          world: assets.worlds.first,
          bookIds: {'book'},
        ),
      );
      final projection = await rig.repo.loadTranscript(s.id);
      expect(projection.turns, isEmpty);
      expect(projection.storyLine.parentId, isNull);
      final participants = await rig.repo.listParticipants(s.id);
      expect(participants.length, 2);
      expect(participants.last.entityId, 'character');
      expect(
        (await rig.service.loadAssets()).personas.any(
          (p) => p.id == s.personaId,
        ),
        true,
      );
      expect((await rig.service.worlds.listSessions('world')).isEmpty, true);
      final newDb = rig.database('source.db');
      final reopened = SQLiteTavernRepository(newDb);
      expect((await reopened.getSession(s.id)).personaId, s.personaId);
      await newDb.close();
    },
  );
  test(
    'home summaries reflect real selected visible text, no reasoning or failed content',
    () async {
      final c = rig.controller();
      await c.load();
      expect(await c.send('Look north'), true);
      final summary = (await rig.repo.listStorySummaries()).single;
      expect(summary.excerpt, isNotEmpty);
      expect(summary.excerpt, '你好');
      expect(summary.excerpt, isNot(contains('reasoning')));
      expect(summary.participants.length, 2);
      expect(
        summary.session.updatedAt.isAfter(summary.session.createdAt),
        true,
      );
      await rig.service.rename('s', 'New Name');
      expect((await rig.repo.listSessions()).single.title, 'New Name');
      await rig.repo.archiveSession('s');
      expect(await rig.repo.listSessions(), isEmpty);
      expect((await rig.repo.listSessions(archived: true)).single.id, 's');
    },
  );
  test(
    'send, retry, regenerate, continue, alternative and fork use official owner',
    () async {
      final c = rig.controller();
      await c.load();
      await c.send('Look north');
      var row = c.projection!.turns.last;
      final original = row.selectedAlternative.id;
      await c.act(TavernGenerationCommandKind.regenerate, row);
      row = c.projection!.turns.last;
      expect(row.alternatives.length, 2);
      final second = row.selectedAlternative.id;
      expect(second, isNot(original));
      await c.selectAnswer(row, original);
      expect(c.projection!.turns.last.selectedAlternative.id, original);
      await c.act(
        TavernGenerationCommandKind.continueTurn,
        c.projection!.turns.last,
      );
      expect(c.projection!.turns.last.selectedAlternative.id, original);
      expect((await rig.repo.listAttempts(original)).length, 2);
      await c.fork(c.projection!.turns.last, 'Side Story');
      final child = c.projection!.storyLine.id;
      expect(c.projection!.turns.last.selectedAlternative.id, original);
      await c.switchLine('main');
      await c.selectAnswer(c.projection!.turns.last, second);
      await c.switchLine(child);
      expect(c.projection!.turns.last.selectedAlternative.id, original);
      expect((await rig.repo.listStorySummaries()).single.excerpt, '你好你好');
      expect(
        (await rig.repo.loadWorldInfoState('s', child)).provenance.name,
        'forkCheckpoint',
      );
    },
  );
  test(
    'double-send has one request; actual stream cancellation settles before navigation',
    () async {
      final c = rig.controller();
      await c.load();
      final transport = ControlledTavernTransport();
      rig.env.clients.add(transport);
      final sending = c.send('Hello');
      expect(await c.send('Again'), false);
      await transport.started.future;
      transport.text('A partial answer');
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!c.live.value.parts.any(
            (p) => p.text?.contains('partial') ?? false,
          ) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.live.value.parts.map((p) => p.text).join(), contains('partial'));
      await c.stop();
      await sending;
      expect(c.busy, false);
      expect(transport.closed, true);
      final row = c.projection!.turns.last;
      expect(
        (await rig.repo.listAttempts(row.selectedAlternative.id)).single.status,
        TavernGenerationStatus.cancelled,
      );
      await c.act(TavernGenerationCommandKind.retry, row);
      final attempts = await rig.repo.listAttempts(row.selectedAlternative.id);
      expect(attempts.map((a) => a.status), [
        TavernGenerationStatus.cancelled,
        TavernGenerationStatus.completed,
      ]);
    },
  );
  test(
    'provider failure does not invent a reply; retry retains same Alternative',
    () async {
      final c = rig.controller();
      await c.load();
      rig.env.clients.add(
        fixtures.FixtureTransport(utf8.encode('{}'), status: 429),
      );
      await c.send('Failure');
      expect(c.error, contains('限流'));
      final row = c.projection!.turns.last;
      expect(row.visibleParts, isEmpty);
      await c.act(TavernGenerationCommandKind.retry, row);
      expect(
        c.projection!.turns.last.selectedAlternative.id,
        row.selectedAlternative.id,
      );
      expect(
        (await rig.repo.listAttempts(row.selectedAlternative.id)).length,
        2,
      );
    },
  );
  test('missing binding preserves input and has zero transport', () async {
    await rig.service.saveSettings('s', {'tavernBindingV1': {}});
    final c = rig.controller();
    await c.load();
    expect(await c.send('Keep my draft'), false);
    expect(rig.env.sent, isEmpty);
    expect(c.projection!.turns.length, 1);
    expect(c.error, contains('模型'));
  });
  test(
    'WorldCard and explicit books flow through authorized native source resolver',
    () async {
      final assets = await rig.service.loadAssets();
      final s = await rig.service.createStory(
        TavernStoryDraft(
          title: 'World card story',
          characterIds: {'character'},
          personaId: 'persona',
          world: assets.worlds.firstWhere((w) => w.type == 'worldCard'),
          bookIds: {'book'},
          sceneName: 'Garden',
        ),
      );
      final resolver = NativeTavernSourceResolver(
        repository: rig.repo,
        characters: rig.service.characters,
        worlds: rig.service.worlds,
        worldCards: rig.service.worldCards,
      );
      final participants = await rig.repo.listParticipants(s.id);
      final bundle = await resolver.resolve(
        await rig.repo.loadTranscript(s.id),
        participants.last.id,
      );
      expect(
        bundle.sources.map((s) => s.atoms.map((a) => a.text).join()).join(),
        contains('World card content'),
      );
      expect(
        bundle.sources.map((s) => s.atoms.map((a) => a.text).join()).join(),
        contains('Garden'),
      );
      expect(
        bundle.entries.map((e) => e.identity).toSet().length,
        bundle.entries.length,
      );
      expect(bundle.entries.single.entryId, 'lore');
      expect(
        bundle.sources.map((s) => s.atoms.map((a) => a.text).join()).join(),
        isNot(contains('SECRET-NOT-FOR-SPEAKER')),
      );
      await rig.service.saveSettings(s.id, {
        'worldInfoBookOverridesV1': {'book': 'disabled'},
      });
      expect(
        (await resolver.resolve(
          await rig.repo.loadTranscript(s.id),
          participants.last.id,
        )).entries,
        isEmpty,
      );
    },
  );
  test(
    'story settings archive fresh restore and merge remap explicit books; no credentials',
    () async {
      await rig.service.saveSettings('s', {
        'tavernBookReferencesV1': {
          'book': {'enabled': true, 'priority': 3},
        },
      });
      final snapshot = await SQLiteBackupSnapshotStore(rig.db).buildSnapshot();
      expect(
        jsonEncode(snapshot.collections),
        isNot(contains('synthetic-credential')),
      );
      final target = rig.database('restore.db');
      final store = SQLiteBackupSnapshotStore(target);
      await store.restore(
        snapshot,
        mode: BackupRestoreMode.fresh,
        restoredAssets: {},
      );
      final repo = SQLiteTavernRepository(target);
      expect((await repo.getSession('s')).metadata['tavernBookReferencesV1'], {
        'book': {'enabled': true, 'priority': 3},
      });
      await store.restore(
        snapshot,
        mode: BackupRestoreMode.merge,
        restoredAssets: {},
      );
      final rows = await repo.listSessions();
      expect(rows.length, 2);
      final merged = rows.firstWhere((s) => s.id != 's');
      final refs = merged.metadata['tavernBookReferencesV1'] as Map;
      expect(refs.keys.single, isNot('book'));
      final books = await (await target.database).query(
        'world_books',
        where: 'id=?',
        whereArgs: [refs.keys.single],
      );
      expect(books.length, 1);
      await target.close();
    },
  );
  test(
    'reading preferences are line-isolated and reopen; not canonical Session metadata',
    () async {
      final secure = InMemorySecureValueStore();
      final store = TavernReadingStore(secure);
      await store.save(
        's',
        'main',
        const TavernReadingAnchor(
          turnId: 't',
          y: 30,
          following: false,
          pixelHint: 430,
        ),
      );
      expect(await store.load('s', 'child'), isNull);
      expect((await TavernReadingStore(secure).load('s', 'main'))!.turnId, 't');
      expect(
        (await rig.repo.getSession('s')).metadata.containsKey('scroll'),
        false,
      );
    },
  );
  test(
    'invalid initial parts roll back user Turn/Alternative together',
    () async {
      final now = DateTime.now();
      await expectLater(
        rig.repo.appendTurn(
          TavernTurn(
            id: 'bad',
            sessionId: 's',
            storyLineId: 'main',
            position: 1,
            participantId: 'player',
            role: TavernTurnRole.player,
            createdAt: now,
            updatedAt: now,
          ),
          TavernAlternative(
            id: 'bad-a',
            turnId: 'bad',
            position: 0,
            origin: TavernAlternativeOrigin.manual,
            createdAt: now,
          ),
          initialParts: [
            TavernContentPart(
              id: 'bad-p',
              alternativeId: 'other',
              position: 0,
              kind: TavernContentKind.text,
              text: 'No',
              createdAt: now,
            ),
          ],
        ),
        throwsStateError,
      );
      expect((await rig.repo.loadTranscript('s')).turns.length, 1);
    },
  );
}
