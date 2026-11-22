import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ibukihome/application/backup/backup_archive_codec.dart';
import 'package:ibukihome/application/tavern/tavern_generation_runtime.dart';
import 'package:ibukihome/application/tavern/tavern_source_resolver.dart';
import 'package:ibukihome/application/tavern/provider/tavern_provider_models.dart';
import 'package:ibukihome/application/tavern/prompt/prompt_models.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_scan_context.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_models.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_runtime.dart';
import 'package:ibukihome/application/tavern/world_info/world_info_durable_plan.dart';
import 'package:ibukihome/data/ai/tavern_provider_adapter.dart';
import 'package:ibukihome/data/repositories/tavern_repository.dart';
import 'package:ibukihome/data/repositories/tavern_world_info_repository.dart';
import 'package:ibukihome/data/memory/in_memory_tavern_repository.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:ibukihome/data/sqlite/sqlite_tavern_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/data/sqlite/sqlite_character_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_world_roleplay_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_project_repository.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';
import 'package:ibukihome/domain/tavern/tavern_world_info.dart';
import 'tavern_orchestrator_test.dart' as integration;
import 'tavern_provider_adapter_test.dart' as protocol;

final _now = DateTime.utc(2026, 10, 15);
Project _project(String id) => Project(
  metadata: EntityMetadata(
    id: id,
    createdAt: _now,
    updatedAt: _now,
    revision: 1,
  ),
  title: 'Synthetic $id',
  description: '',
);

class _TimerSources implements TavernSourceResolver {
  _TimerSources(this.delegate, {this.large = false});
  final TavernSourceResolver delegate;
  final bool large;
  int calls = 0;
  @override
  Future<TavernSourceBundle> resolve(
    TavernTranscriptProjection projection,
    String speaker,
  ) async {
    calls++;
    final bundle = await delegate.resolve(projection, speaker);
    return TavernSourceBundle(
      sources: bundle.sources,
      worldId: bundle.worldId,
      personaId: bundle.personaId,
      characterIds: bundle.characterIds,
      entries: [
        const WorldInfoEntry(
          bookId: 'book',
          entryId: 'lore',
          title: 'Timer',
          content: 'Eligible timer lore',
          primaryKeys: ['north'],
          stickyMessages: 2,
          cooldownMessages: 3,
          priority: 100,
        ),
        if (large)
          WorldInfoEntry(
            bookId: 'book',
            entryId: 'budget-dropped',
            title: 'Huge',
            content: 'X' * 30000,
            constant: true,
            stickyMessages: 9,
          ),
      ],
    );
  }
}

class _HoldingAdapter extends TavernProviderAdapter {
  _HoldingAdapter() : super(() => throw StateError('HTTP must not start'));
  final reached = Completer<void>();
  @override
  Stream<TavernProviderEvent> generate(
    TavernProviderRequest request,
    String credential,
    TavernGenerationCancellation cancellation, {
    String? expectedFingerprint,
  }) async* {
    reached.complete();
    await cancellation.whenCancelled;
  }
}

class _LiveFixture extends http.BaseClient {
  final reached = Completer<void>();
  final stream = StreamController<List<int>>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    reached.complete();
    return http.StreamedResponse(stream.stream, 200);
  }

  @override
  void close() {
    closed = true;
    if (!stream.isClosed) unawaited(stream.close());
  }
}

class _NotificationFailureRepository extends SQLiteTavernRepository {
  _NotificationFailureRepository(super.database);
  bool fail = true;
  @override
  Future<TavernReconciliationOutcome> reconcileWorldInfoAttempt(
    String id,
  ) async {
    final result = await super.reconcileWorldInfoAttempt(id);
    if (fail && result == TavernReconciliationOutcome.committed) {
      fail = false;
      throw StateError('Synthetic observer failure');
    }
    return result;
  }
}

class _RecoveryFailureRepository extends SQLiteTavernRepository {
  _RecoveryFailureRepository(super.database);
  bool fail = true;
  @override
  Future<void> reconcileWorldInfo() async {
    if (fail) {
      fail = false;
      throw StateError('Synthetic recovery read fault');
    }
    await super.reconcileWorldInfo();
  }
}

class _Rig {
  _Rig(this.directory, this.db, this.env);
  final Directory directory;
  final IbukiDatabase db;
  final integration.TavernTestEnvironment env;
  SQLiteTavernRepository get repo => env.repo as SQLiteTavernRepository;
  IbukiDatabase database(String name) => IbukiDatabase(
    pathResolver: () async => p.join(directory.path, name),
    databaseFactory: databaseFactoryFfi,
  );
  static Future<_Rig> fresh({
    bool notificationFailure = false,
    bool recoveryFailure = false,
  }) async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('tavern_durable_');
    final db = IbukiDatabase(
      pathResolver: () async => p.join(dir.path, 'source.db'),
      databaseFactory: databaseFactoryFfi,
    );
    await SQLiteProjectRepository(db).upsertProject(_project('project'));
    final repo = recoveryFailure
        ? _RecoveryFailureRepository(db)
        : notificationFailure
        ? _NotificationFailureRepository(db)
        : SQLiteTavernRepository(db);
    final chars = SQLiteCharacterRepository(db),
        worlds = SQLiteWorldRoleplayRepository(db);
    await integration.seed(repo, chars, worlds);
    final env = integration.TavernTestEnvironment(repo, chars, worlds);
    await env.initialize();
    final sources = _TimerSources(env.owner.sources);
    await env.owner.dispose();
    await env.initialize(sources: sources);
    return _Rig(dir, db, env);
  }

  Future<integration.TavernTestEnvironment> reopen() async {
    await env.owner.dispose();
    await db.close();
    final reopened = database('source.db');
    final env2 = integration.TavernTestEnvironment(
      SQLiteTavernRepository(reopened),
      SQLiteCharacterRepository(reopened),
      SQLiteWorldRoleplayRepository(reopened),
    );
    await env2.initialize();
    addTearDown(() async {
      await env2.owner.dispose();
      await reopened.close();
    });
    return env2;
  }

  Future<integration.TavernTestEnvironment> crashImage(
    BackupSnapshot snapshot,
  ) async {
    await env.owner.dispose();
    final target = database('crash.db');
    await SQLiteBackupSnapshotStore(target).restore(
      snapshot,
      mode: BackupRestoreMode.fresh,
      restoredAssets: const {},
    );
    final replacement = integration.TavernTestEnvironment(
      SQLiteTavernRepository(target),
      SQLiteCharacterRepository(target),
      SQLiteWorldRoleplayRepository(target),
    );
    await replacement.initialize();
    addTearDown(() async {
      await replacement.owner.dispose();
      await target.close();
    });
    return replacement;
  }

  Future<void> close() async {
    await env.owner.dispose();
    await db.close();
  }
}

Future<void> _cleanup(_Rig rig) async {
  await rig.close();
  // Per-test directory was allocated inside the approved D-drive TEMP root.
  if (await rig.directory.exists()) {
    if (!p.isWithin(
      Directory.systemTemp.absolute.path,
      rig.directory.absolute.path,
    )) {
      throw StateError('Test cleanup target outside TEMP');
    }
    await rig.directory.delete(recursive: true);
  }
}

Future<TavernWorldInfoSnapshot> _state(
  integration.TavernTestEnvironment env,
  String line,
) => (env.repo as TavernWorldInfoRepository).loadWorldInfoState('s', line);

Future<void> _canonicalGeneration(
  TavernRepository repo,
  TavernWorldInfoRepository durable,
  int index, {
  String line = 'main',
  String session = 's',
  String participant = 'speaker',
  TavernGenerationStatus terminalStatus = TavernGenerationStatus.completed,
  int? position,
}) async {
  final base = await durable.loadWorldInfoState(session, line);
  final next = TavernWorldInfoData(
    messageCount: index,
    historyMarker: tavernDigest(['synthetic-visible-prefix', index]),
    timers: [
      TavernLoreTimer(
        bookId: 'book',
        entryId: 'lore',
        activatedAt: index,
        definitionFingerprint: tavernDigest('definition'),
        stickyUntil: index + 3,
        cooldownUntil: index + 7,
        delayMessages: 0,
      ),
    ],
  );
  final turn = '$line-turn-$index',
      alt = '$turn-alt',
      attempt = '$turn-attempt';
  final plan = TavernWorldInfoPlan(
    attemptId: attempt,
    sessionId: session,
    storyLineId: line,
    turnId: turn,
    alternativeId: alt,
    compileFingerprint: tavernDigest('compile-$index'),
    requestFingerprint: tavernDigest('request-$index'),
    expectedVersion: base.version,
    baseFingerprint: base.data.fingerprint,
    delta: TavernWorldInfoDelta.between(base.data, next),
    included: const [('book', 'lore')],
  );
  await repo.appendTurn(
    TavernTurn(
      id: turn,
      sessionId: session,
      storyLineId: line,
      participantId: participant,
      role: TavernTurnRole.character,
      position: position ?? index,
      createdAt: _now,
      updatedAt: _now,
    ),
    TavernAlternative(
      id: alt,
      turnId: turn,
      position: 0,
      origin: TavernAlternativeOrigin.generated,
      createdAt: _now,
    ),
    attempt: TavernGenerationAttempt(
      id: attempt,
      sessionId: session,
      storyLineId: line,
      turnId: turn,
      alternativeId: alt,
      position: 0,
      status: TavernGenerationStatus.queued,
      type: TavernGenerationType.normal,
      createdAt: _now,
      metadata: {
        'worldInfoPlanIdentity': plan.identity,
        'worldInfoCompileFingerprint': plan.compileFingerprint,
        'worldInfoRequestFingerprint': plan.requestFingerprint,
      },
    ),
    reconciliation: plan,
  );
  await repo.persistGenerationBatch(attempt, [
    TavernContentPart(
      id: '$attempt-text',
      alternativeId: alt,
      generationAttemptId: attempt,
      position: 0,
      kind: TavernContentKind.text,
      text: 'Synthetic $index',
      createdAt: _now,
    ),
  ], terminalStatus: terminalStatus);
}

void main() {
  test(
    'five mixed Session outcomes recover together twice without cross-scope changes or HTTP',
    () async {
      final rig = await _Rig.fresh();
      addTearDown(() => _cleanup(rig));
      for (final suffix in ['A', 'B', 'C', 'D', 'E']) {
        final session = 'session-$suffix',
            line = 'line-$suffix',
            participant = 'speaker-$suffix';
        await rig.repo.createSession(
          TavernSession(
            id: session,
            title: 'Synthetic $suffix',
            createdAt: _now,
            updatedAt: _now,
          ),
          TavernStoryLine(
            id: line,
            sessionId: session,
            name: 'Main',
            position: 0,
            createdAt: _now,
          ),
        );
        await rig.repo.addParticipant(
          TavernParticipant(
            id: participant,
            sessionId: session,
            kind: TavernParticipantKind.character,
            entityId: 'character',
            position: 0,
          ),
        );
        await _canonicalGeneration(
          rig.repo,
          rig.repo,
          1,
          session: session,
          line: line,
          participant: participant,
          terminalStatus: suffix == 'C'
              ? TavernGenerationStatus.failed
              : suffix == 'D'
              ? TavernGenerationStatus.cancelled
              : TavernGenerationStatus.completed,
        );
      }
      final sql = await rig.db.database;
      final b = await rig.repo.loadWorldInfoState('session-B', 'line-B');
      await sql.transaction((tx) async {
        // A controlled Case C image; normal v14 terminal transactions cannot tear here.
        await tx.update(
          'tavern_world_info_states',
          {
            'version': 0,
            'last_attempt_id': null,
            'data_json': jsonEncode(b.initialData.toJson()),
          },
          where: 'id = ?',
          whereArgs: ['line-B'],
        );
        await tx.update(
          'tavern_world_info_journal',
          {'outcome': 'prepared', 'committed_version': null},
          where: 'id = ?',
          whereArgs: ['line-B-turn-1-attempt'],
        );
        await tx.update(
          'tavern_world_info_journal',
          {
            'outcome': 'conflict',
            'committed_version': null,
            'reason': 'state_version',
          },
          where: 'id = ?',
          whereArgs: ['line-E-turn-1-attempt'],
        );
      });
      final replacement = await rig.reopen();
      await replacement.owner.initialize();
      final durable = replacement.repo as TavernWorldInfoRepository;
      for (final suffix in ['A', 'B', 'C', 'D', 'E']) {
        final state = await durable.loadWorldInfoState(
          'session-$suffix',
          'line-$suffix',
        );
        expect(state.version, suffix == 'C' || suffix == 'D' ? 0 : 1);
        final journal = (await durable.getWorldInfoJournal(
          'line-$suffix-turn-1-attempt',
        ))!;
        expect(
          journal.outcome,
          suffix == 'E'
              ? TavernReconciliationOutcome.conflict
              : suffix == 'C' || suffix == 'D'
              ? TavernReconciliationOutcome.discarded
              : TavernReconciliationOutcome.committed,
        );
        if (suffix == 'C' || suffix == 'D') expect(state.data.timers, isEmpty);
        if (suffix == 'B') expect(state.data.fingerprint, b.data.fingerprint);
        if (suffix == 'E') {
          await expectLater(
            durable.requireWorldInfoReady('session-$suffix', 'line-$suffix'),
            throwsA(isA<TavernReconciliationConflict>()),
          );
        } else {
          await durable.requireWorldInfoReady(
            'session-$suffix',
            'line-$suffix',
          );
        }
        final projected = await replacement.repo.loadTranscript(
          'session-$suffix',
        );
        expect(
          projected.turns.single.visibleParts,
          suffix == 'C' || suffix == 'D' ? isEmpty : hasLength(1),
        );
      }
      final reopenedDb = (replacement.repo as SQLiteTavernRepository).database;
      final store = SQLiteBackupSnapshotStore(reopenedDb);
      final before = jsonEncode((await store.buildSnapshot()).collections);
      await replacement.owner.retryRecovery();
      await durable.reconcileWorldInfo();
      expect(jsonEncode((await store.buildSnapshot()).collections), before);
      expect(replacement.sent, isEmpty);
      expect(
        await (await reopenedDb.database).rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
    },
  );

  test('archive rejects a stale last-commit reference atomically', () async {
    final rig = await _Rig.fresh();
    addTearDown(() => _cleanup(rig));
    await _canonicalGeneration(rig.repo, rig.repo, 1);
    await _canonicalGeneration(rig.repo, rig.repo, 2);
    final source = await SQLiteBackupSnapshotStore(rig.db).buildSnapshot();
    final corrupt = BackupSnapshot(
      collections: {
        for (final entry in source.collections.entries)
          entry.key: [
            for (final row in entry.value)
              {
                ...row,
                if (entry.key == 'tavernWorldInfoStates' && row['id'] == 'main')
                  'last_attempt_id': 'main-turn-1-attempt',
              },
          ],
      },
    );
    final target = rig.database('stale-reference.db');
    addTearDown(target.close);
    await SQLiteProjectRepository(target).upsertProject(_project('KEEP-ME'));
    await expectLater(
      SQLiteBackupSnapshotStore(target).restore(
        corrupt,
        mode: BackupRestoreMode.merge,
        restoredAssets: const {},
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      (await SQLiteProjectRepository(target).getProject('KEEP-ME')).title,
      'Synthetic KEEP-ME',
    );
    expect(await (await target.database).query('tavern_sessions'), isEmpty);
  });

  test(
    'definition fingerprint keeps filter namespaces distinct and set order stable',
    () {
      const world = WorldInfoEntry(
        bookId: 'b',
        entryId: 'e',
        title: 'E',
        content: 'C',
        worldIds: {'same'},
      );
      const character = WorldInfoEntry(
        bookId: 'b',
        entryId: 'e',
        title: 'E',
        content: 'C',
        characterIds: {'same'},
      );
      expect(
        world.definitionFingerprint,
        isNot(character.definitionFingerprint),
      );
      const a = WorldInfoEntry(
        bookId: 'b',
        entryId: 'e',
        title: 'E',
        content: 'C',
        worldIds: {'a', 'b'},
      );
      const b = WorldInfoEntry(
        bookId: 'b',
        entryId: 'e',
        title: 'E',
        content: 'C',
        worldIds: {'b', 'a'},
      );
      expect(a.definitionFingerprint, b.definitionFingerprint);
    },
  );
  test(
    'history fingerprint is bounded, identity-remap safe and excludes hidden content',
    () {
      TavernTranscriptProjection projection(
        String prefix, {
        String visible = 'Visible',
        String hidden = 'Hidden',
      }) {
        final session = TavernSession(
          id: '$prefix-session',
          title: 'Synthetic',
          createdAt: _now,
          updatedAt: _now,
        );
        final line = TavernStoryLine(
          id: '$prefix-line',
          sessionId: session.id,
          name: 'Main',
          position: 0,
          createdAt: _now,
        );
        return TavernTranscriptProjection(
          session: session,
          storyLine: line,
          turns: List.generate(1000, (i) {
            final turn = TavernTurn(
              id: '$prefix-turn-$i',
              sessionId: session.id,
              storyLineId: line.id,
              participantId: 'speaker',
              role: i == 999 ? TavernTurnRole.player : TavernTurnRole.character,
              position: i,
              createdAt: _now,
              updatedAt: _now,
            );
            final alt = TavernAlternative(
              id: '$prefix-alt-$i',
              turnId: turn.id,
              position: 0,
              origin: TavernAlternativeOrigin.manual,
              createdAt: _now,
            );
            return TavernTurnProjection(
              turn: turn,
              selectedAlternative: alt,
              alternatives: [alt],
              selectedParts: [
                TavernContentPart(
                  id: '$prefix-text-$i',
                  alternativeId: alt.id,
                  position: 0,
                  kind: TavernContentKind.text,
                  text: '$visible $i',
                  createdAt: _now,
                ),
                TavernContentPart(
                  id: '$prefix-reasoning-$i',
                  alternativeId: alt.id,
                  position: 1,
                  kind: TavernContentKind.reasoning,
                  text: '$hidden $i',
                  createdAt: _now,
                ),
              ],
            );
          }),
        );
      }

      String marker(TavernTranscriptProjection p) =>
          const WorldInfoScanContextBuilder()
              .fromProjection(p, mode: PromptCompileMode.normal)
              .historyMarker;
      final original = marker(projection('original'));
      expect(original, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(
        marker(projection('remapped', hidden: 'Different hidden content')),
        original,
      );
      expect(
        marker(projection('original', visible: 'Edited visible text')),
        isNot(original),
      );
    },
  );

  for (final backend in ['memory', 'sqlite']) {
    test(
      '$backend missing journal fails recovery rather than using empty state',
      () async {
        final rig = await _Rig.fresh();
        addTearDown(() => _cleanup(rig));
        final env = backend == 'sqlite'
            ? rig.env
            : await integration.memoryEnvironment();
        if (backend == 'memory') addTearDown(env.owner.dispose);
        await _canonicalGeneration(
          env.repo,
          env.repo as TavernWorldInfoRepository,
          1,
        );
        await expectLater(
          env.repo.recordAttempt(
            TavernGenerationAttempt(
              id: 'missing-plan',
              sessionId: 's',
              storyLineId: 'main',
              turnId: 'main-turn-1',
              alternativeId: 'main-turn-1-alt',
              position: 1,
              status: TavernGenerationStatus.queued,
              type: TavernGenerationType.continueTurn,
              createdAt: _now,
              metadata: {'worldInfoPlanIdentity': tavernDigest('missing-plan')},
            ),
          ),
          throwsA(
            isA<TavernReconciliationConflict>().having(
              (e) => e.reason,
              'reason',
              'missing_plan',
            ),
          ),
        );
        expect(await env.repo.listAttempts('main-turn-1-alt'), hasLength(1));
        if (env.repo is InMemoryTavernRepository) {
          (env.repo as InMemoryTavernRepository).worldInfoJournals.clear();
        } else {
          await (await rig.db.database).delete('tavern_world_info_journal');
        }
        await expectLater(
          (env.repo as TavernWorldInfoRepository).reconcileWorldInfo(),
          throwsA(
            isA<TavernReconciliationConflict>().having(
              (e) => e.reason,
              'reason',
              'missing_journal',
            ),
          ),
        );
        expect(env.sent, isEmpty);
        expect((await _state(env, 'main')).version, 1);
      },
    );
  }

  test('corrupt current snapshot blocks only its line across reopen', () async {
    final rig = await _Rig.fresh();
    addTearDown(() => _cleanup(rig));
    await _canonicalGeneration(rig.repo, rig.repo, 1);
    await rig.repo.createStoryLine(
      TavernStoryLine(
        id: 'healthy',
        sessionId: 's',
        name: 'Healthy',
        position: 1,
        parentId: 'main',
        originTurnId: 'main-turn-1',
        originAlternativeId: 'main-turn-1-alt',
        createdAt: _now,
      ),
    );
    final db = await rig.db.database;
    final rows = await db.query(
      'tavern_world_info_states',
      where: 'id = ?',
      whereArgs: ['main'],
    );
    final corrupt = Map<String, dynamic>.from(
      jsonDecode(rows.single['data_json'] as String) as Map,
    );
    corrupt['messageCount'] = 999;
    await db.update(
      'tavern_world_info_states',
      {'data_json': jsonEncode(corrupt)},
      where: 'id = ?',
      whereArgs: ['main'],
    );
    final replacement = await rig.reopen();
    await replacement.owner.initialize();
    final durable = replacement.repo as TavernWorldInfoRepository;
    await expectLater(
      durable.requireWorldInfoReady('s', 'main'),
      throwsA(isA<TavernReconciliationConflict>()),
    );
    await durable.requireWorldInfoReady('s', 'healthy');
    expect(
      (await durable.getWorldInfoJournal('main-turn-1-attempt'))!.reason,
      'state_integrity',
    );
    expect(replacement.sent, isEmpty);
  });

  test('1000 isolated scope snapshots recover with batched reads', () async {
    final rig = await _Rig.fresh();
    addTearDown(() => _cleanup(rig));
    for (var i = 0; i < 1000; i++) {
      await rig.repo.createSession(
        TavernSession(
          id: 'scope-$i',
          title: 'Synthetic',
          createdAt: _now,
          updatedAt: _now,
        ),
        TavernStoryLine(
          id: 'scope-line-$i',
          sessionId: 'scope-$i',
          name: 'Main',
          position: 0,
          createdAt: _now,
        ),
      );
    }
    final watch = Stopwatch()..start();
    await rig.repo.reconcileWorldInfo();
    watch.stop();
    expect(
      await (await rig.db.database).query('tavern_world_info_states'),
      hasLength(1001),
    );
    expect(
      (await rig.repo.loadWorldInfoState(
        'scope-999',
        'scope-line-999',
      )).version,
      0,
    );
    await expectLater(
      rig.repo.loadWorldInfoState('scope-998', 'scope-line-999'),
      throwsA(isA<TavernReconciliationConflict>()),
    );
    debugPrint('WI_1000_SCOPES_RECOVERY_MS=${watch.elapsedMilliseconds}');
  });

  test(
    'root recovery failure gates generation and controlled retry sends no HTTP',
    () async {
      final rig = await _Rig.fresh(recoveryFailure: true);
      addTearDown(() => _cleanup(rig));
      await expectLater(
        rig.env.owner.start(integration.command('not-ready'), rig.env.binding),
        throwsStateError,
      );
      expect(rig.env.sent, isEmpty);
      expect(await rig.repo.listAttempts('answer'), isEmpty);
      await rig.env.owner.retryRecovery();
      expect(rig.env.sent, isEmpty);
      await rig.repo.requireWorldInfoReady('s', 'main');
      final result = await (await rig.env.owner.start(
        integration.command('ready'),
        rig.env.binding,
      )).done;
      expect(result.generation.phase, TavernExecutionPhase.completed);
      expect((await _state(rig.env, 'main')).version, 1);
    },
  );

  for (final change in [
    'unchanged',
    'content',
    'configuration',
    'disabled',
    'book-disabled',
    'deleted',
    'other-book',
  ]) {
    test(
      'persistent timers respect $change definition/asset lifecycle after reopen',
      () async {
        final rig = await _Rig.fresh();
        addTearDown(() => _cleanup(rig));
        await (await rig.env.owner.start(
          integration.command('timer'),
          rig.env.binding,
        )).done;
        final replacement = await rig.reopen();
        await replacement.owner.initialize();
        final snapshot = await _state(replacement, 'main');
        final entry = WorldInfoEntry(
          bookId: change == 'other-book' ? 'different' : 'book',
          entryId: 'lore',
          title: 'Timer',
          content: change == 'content' ? 'Edited' : 'Eligible timer lore',
          primaryKeys: const ['north'],
          stickyMessages: change == 'configuration' ? 99 : 2,
          cooldownMessages: 3,
          priority: 100,
          enabled: change != 'disabled',
          bookEnabled: change != 'book-disabled',
        );
        final plan = const WorldInfoRuntime().evaluate(
          entries: change == 'deleted' ? [] : [entry],
          state: restoreWorldInfoSnapshot(snapshot),
          context: const WorldInfoActivationContext(
            sessionId: 's',
            storyLineId: 'main',
            generationType: WorldInfoGenerationType.normal,
            messages: [
              WorldInfoScanMessage(turnId: 'one', text: 'quiet'),
              WorldInfoScanMessage(turnId: 'two', text: 'quiet'),
            ],
            historyMarker: 'after',
          ),
          random: const SeededWorldInfoRandom(1),
        );
        expect(
          plan.activated,
          change == 'unchanged' ? [('book', 'lore')] : isEmpty,
        );
        if (change != 'unchanged') expect(plan.nextState.timed, isEmpty);
        expect(replacement.sent, isEmpty);
      },
    );
  }
  test(
    'cooldown/delay remain message-count based; merely evaluating does not change durable state',
    () async {
      final rig = await _Rig.fresh();
      addTearDown(() => _cleanup(rig));
      await (await rig.env.owner.start(
        integration.command('timer'),
        rig.env.binding,
      )).done;
      final snapshot = await _state(rig.env, 'main');
      const entry = WorldInfoEntry(
        bookId: 'book',
        entryId: 'lore',
        title: 'Timer',
        content: 'Eligible timer lore',
        primaryKeys: ['north'],
        stickyMessages: 2,
        cooldownMessages: 3,
        priority: 100,
      );
      WorldInfoActivationContext context(int count) =>
          WorldInfoActivationContext(
            sessionId: 's',
            storyLineId: 'main',
            generationType: WorldInfoGenerationType.normal,
            messages: List.generate(
              count,
              (i) => WorldInfoScanMessage(turnId: 't$i', text: 'north'),
            ),
            historyMarker: 'after',
          );
      final cooling = const WorldInfoRuntime().evaluate(
        entries: [entry],
        state: restoreWorldInfoSnapshot(snapshot),
        context: context(4),
        random: const SeededWorldInfoRandom(1),
      );
      expect(
        cooling.trace.decisions.single.reason,
        WorldInfoActivationReason.cooldown,
      );
      const delay = WorldInfoEntry(
        bookId: 'book',
        entryId: 'delay',
        title: 'Delay',
        content: 'Delay lore',
        primaryKeys: ['north'],
        delayMessages: 5,
      );
      final delayed = const WorldInfoRuntime().evaluate(
        entries: [delay],
        state: restoreWorldInfoSnapshot(snapshot),
        context: context(4),
        random: const SeededWorldInfoRandom(1),
      );
      expect(
        delayed.trace.decisions.single.reason,
        WorldInfoActivationReason.delayPending,
      );
      final ready = const WorldInfoRuntime().evaluate(
        entries: [delay],
        state: restoreWorldInfoSnapshot(snapshot),
        context: context(5),
        random: const SeededWorldInfoRandom(1),
      );
      expect(ready.activated, [('book', 'delay')]);
      expect(
        (await _state(rig.env, 'main')).data.fingerprint,
        snapshot.data.fingerprint,
      );
      expect((await _state(rig.env, 'main')).version, 1);
    },
  );

  test(
    'archive fresh restore and collision merge preserve semantic checkpoints, provenance and remapped identities',
    () async {
      final rig = await _Rig.fresh();
      addTearDown(() => _cleanup(rig));
      await (await rig.env.owner.start(
        integration.command('first'),
        rig.env.binding,
      )).done;
      await rig.repo.createStoryLine(
        TavernStoryLine(
          id: 'child',
          sessionId: 's',
          name: 'Child',
          position: 1,
          createdAt: _now,
          parentId: 'main',
          originTurnId: 'reply',
          originAlternativeId: 'answer',
        ),
      );
      await integration.userTurn(
        rig.repo,
        'child-user',
        line: 'child',
        position: 0,
      );
      await (await rig.env.owner.start(
        integration.command(
          'child-response',
          line: 'child',
          user: 'child-user',
          turn: 'child-turn',
          alt: 'child-answer',
        ),
        rig.env.binding,
      )).done;
      final snapshot = await SQLiteBackupSnapshotStore(rig.db).buildSnapshot();
      final codec = BackupArchiveCodec(
        applicationSupportDirectory: rig.directory,
      );
      final file = File(p.join(rig.directory.path, 'durable.ibukibackup'));
      await codec.write(
        snapshot: snapshot,
        destination: file,
        appVersion: 'synthetic',
        schemaVersion: SqliteSchema.version,
      );
      final decoded = await codec.read(
        source: file,
        staging: Directory(p.join(rig.directory.path, 'stage')),
      );
      expect(decoded.preview.manifest.schemaVersion, SqliteSchema.version);
      final target = rig.database('restored.db');
      addTearDown(target.close);
      final store = SQLiteBackupSnapshotStore(target);
      await store.restore(
        decoded.snapshot,
        mode: BackupRestoreMode.fresh,
        restoredAssets: const {},
      );
      final restored = SQLiteTavernRepository(target);
      expect(
        (await restored.loadWorldInfoState('s', 'main')).data.fingerprint,
        (await _state(rig.env, 'main')).data.fingerprint,
      );
      expect(
        (await restored.loadWorldInfoState('s', 'child')).initialAttemptId,
        'first',
      );
      expect(
        (await restored.loadTranscript(
          's',
          storyLineId: 'child',
        )).turns.map((t) => t.turn.id),
        ['user', 'reply', 'child-user', 'child-turn'],
      );
      await store.restore(
        decoded.snapshot,
        mode: BackupRestoreMode.merge,
        restoredAssets: const {},
      );
      final sql = await target.database;
      final clone = (await sql.query(
        'tavern_sessions',
        where: 'id <> ?',
        whereArgs: ['s'],
      )).single;
      final sid = clone['id'] as String;
      final lines = await sql.query(
        'tavern_story_lines',
        where: 'session_id = ?',
        whereArgs: [sid],
      );
      final main =
          lines.singleWhere((r) => r['parent_id'] == null)['id'] as String;
      final child =
          lines.singleWhere((r) => r['parent_id'] != null)['id'] as String;
      final state = await restored.loadWorldInfoState(sid, main);
      expect(state.version, 1);
      expect(state.data.timers.single.bookId, isNot('book'));
      expect(state.data.timers.single.entryId, isNot('lore'));
      final journal = (await restored.getWorldInfoJournal(
        state.lastAttemptId!,
      ))!;
      expect(journal.plan.sessionId, sid);
      expect(journal.plan.storyLineId, main);
      expect(journal.originalPlanIdentity, isNotNull);
      expect(
        journal.plan.compileFingerprint,
        (await rig.repo.getWorldInfoJournal('first'))!.plan.compileFingerprint,
      );
      expect(
        (await restored.loadWorldInfoState(sid, child)).initialAttemptId,
        state.lastAttemptId,
      );
      final before = state.data.fingerprint;
      for (var i = 0; i < 10; i++) {
        await restored.reconcileWorldInfoAttempt(state.lastAttemptId!);
      }
      await restored.reconcileWorldInfo();
      expect(
        (await restored.loadWorldInfoState(sid, main)).data.fingerprint,
        before,
      );
      expect(clone['world_asset_id'], isNot('world'));
      expect(await sql.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  for (final status in ['prepared', 'conflict']) {
    test(
      'archive preserves $status journal/block rather than inventing an Inspector history',
      () async {
        final rig = await _Rig.fresh();
        addTearDown(() => _cleanup(rig));
        await (await rig.env.owner.start(
          integration.command('archive'),
          rig.env.binding,
        )).done;
        final state = await _state(rig.env, 'main');
        final sql = await rig.db.database;
        await sql.update(
          'tavern_world_info_journal',
          {
            'outcome': status,
            'committed_version': null,
            'reason': status == 'conflict' ? 'state_version' : null,
          },
          where: 'id = ?',
          whereArgs: ['archive'],
        );
        if (status == 'prepared') {
          await sql.update(
            'tavern_world_info_states',
            {
              'version': 0,
              'data_json': jsonEncode(state.initialData.toJson()),
              'last_attempt_id': null,
            },
            where: 'id = ?',
            whereArgs: ['main'],
          );
        }
        final source = await SQLiteBackupSnapshotStore(rig.db).buildSnapshot();
        final target = rig.database('pending.db');
        addTearDown(target.close);
        await SQLiteBackupSnapshotStore(target).restore(
          source,
          mode: BackupRestoreMode.fresh,
          restoredAssets: const {},
        );
        final repo = SQLiteTavernRepository(target);
        expect(
          (await repo.getWorldInfoJournal('archive'))!.outcome,
          TavernReconciliationOutcome.values.byName(status),
        );
        await repo.reconcileWorldInfo();
        expect(
          (await repo.getWorldInfoJournal('archive'))!.outcome,
          status == 'prepared'
              ? TavernReconciliationOutcome.committed
              : TavernReconciliationOutcome.conflict,
        );
        if (status == 'conflict') {
          await expectLater(
            repo.requireWorldInfoReady('s', 'main'),
            throwsA(isA<TavernReconciliationConflict>()),
          );
        } else {
          expect(
            (await repo.loadWorldInfoState('s', 'main')).data.fingerprint,
            state.data.fingerprint,
          );
        }
      },
    );
  }

  test(
    'archive capture concurrent with finalization is a coherent transaction image',
    () async {
      final rig = await _Rig.fresh();
      addTearDown(() => _cleanup(rig));
      final handle = await rig.env.owner.start(
        integration.command('archive-race'),
        rig.env.binding,
      );
      final snapshot = await SQLiteBackupSnapshotStore(rig.db).buildSnapshot();
      await handle.done;
      final state = snapshot.collections['tavernWorldInfoStates']!.single;
      final journal = snapshot.collections['tavernWorldInfoJournal']!.single;
      final attempt = snapshot.collections['tavernGenerationAttempts']!.single;
      if (journal['outcome'] == 'committed') {
        expect(attempt['status'], 'completed');
        expect(state['version'], 1);
      } else {
        expect(journal['outcome'], 'prepared');
        expect(state['version'], 0);
        expect(attempt['status'], isNot('completed'));
      }
    },
  );

  test(
    'restore merge failure rolls back every imported object and leaves KEEP-ME intact',
    () async {
      final rig = await _Rig.fresh();
      addTearDown(() => _cleanup(rig));
      await (await rig.env.owner.start(
        integration.command('one'),
        rig.env.binding,
      )).done;
      final snapshot = await SQLiteBackupSnapshotStore(rig.db).buildSnapshot();
      final target = rig.database('merge-failure.db');
      addTearDown(target.close);
      final store = SQLiteBackupSnapshotStore(target);
      await store.restore(
        snapshot,
        mode: BackupRestoreMode.fresh,
        restoredAssets: const {},
      );
      await SQLiteProjectRepository(target).upsertProject(_project('KEEP-ME'));
      final before = jsonEncode((await store.buildSnapshot()).collections);
      await (await target.database).execute(
        "CREATE TRIGGER injected BEFORE INSERT ON tavern_world_info_journal BEGIN SELECT RAISE(ABORT,'synthetic restore fault'); END",
      );
      await expectLater(
        store.restore(
          snapshot,
          mode: BackupRestoreMode.merge,
          restoredAssets: const {},
        ),
        throwsA(anything),
      );
      expect(jsonEncode((await store.buildSnapshot()).collections), before);
      expect(
        (await SQLiteProjectRepository(target).getProject('KEEP-ME')).title,
        'Synthetic KEEP-ME',
      );
    },
  );

  test(
    '1000 committed deltas recover without duplicates and remain linear-sized, with historical forks intact',
    () async {
      final rig = await _Rig.fresh();
      addTearDown(() => _cleanup(rig));
      for (var i = 1; i <= 1000; i++) {
        await _canonicalGeneration(rig.repo, rig.repo, i);
      }
      final before = await _state(rig.env, 'main');
      final watch = Stopwatch()..start();
      await rig.repo.reconcileWorldInfo();
      watch.stop();
      expect((await _state(rig.env, 'main')).version, 1000);
      expect(
        (await _state(rig.env, 'main')).data.fingerprint,
        before.data.fingerprint,
      );
      final rows = await (await rig.db.database).query(
        'tavern_world_info_journal',
      );
      expect(rows, hasLength(1000));
      final snapshot = await SQLiteBackupSnapshotStore(rig.db).buildSnapshot();
      final codec = BackupArchiveCodec(
        applicationSupportDirectory: rig.directory,
      );
      final full = File(p.join(rig.directory.path, '1000-durable.ibukibackup'));
      final canonicalOnly = File(
        p.join(
          rig.directory.path,
          '1000-canonical-only-size-comparison.ibukibackup',
        ),
      );
      await codec.write(
        snapshot: snapshot,
        destination: full,
        appVersion: 'synthetic',
        schemaVersion: 14,
      );
      await codec.write(
        snapshot: BackupSnapshot(
          collections: {
            for (final e in snapshot.collections.entries)
              if (e.key != 'tavernWorldInfoStates' &&
                  e.key != 'tavernWorldInfoJournal')
                e.key: e.value,
          },
        ),
        destination: canonicalOnly,
        appVersion: 'size-comparison-only',
        schemaVersion: 14,
      );
      final fullBytes = await full.length(),
          baselineBytes = await canonicalOnly.length();
      expect(fullBytes, greaterThan(baselineBytes));
      final bytes = utf8.encode(jsonEncode(rows)).length;
      expect(bytes, lessThan(2500000));
      expect(
        rows.every(
          (r) =>
              (jsonDecode(r['plan_json'] as String)['delta']['upserts'] as List)
                  .length ==
              1,
        ),
        isTrue,
      );
      await rig.repo.createStoryLine(
        TavernStoryLine(
          id: 'past',
          sessionId: 's',
          name: 'Past',
          position: 1,
          createdAt: _now,
          parentId: 'main',
          originTurnId: 'main-turn-20',
          originAlternativeId: 'main-turn-20-alt',
        ),
      );
      expect(
        (await rig.repo.loadWorldInfoState('s', 'past')).data.messageCount,
        20,
      );
      final replacement = await rig.reopen();
      final recovery = Stopwatch()..start();
      await replacement.owner.initialize();
      recovery.stop();
      expect((await _state(replacement, 'main')).version, 1000);
      expect((await _state(replacement, 'past')).data.messageCount, 20);
      expect(replacement.sent, isEmpty);
      debugPrint(
        'WI_1000_RECONCILE_MS=${watch.elapsedMilliseconds}; REOPEN_RECOVERY_MS=${recovery.elapsedMilliseconds}; JOURNAL_JSON_BYTES=$bytes; ARCHIVE_DURABLE_BYTES=$fullBytes; ARCHIVE_CANONICAL_ONLY_BYTES=$baselineBytes',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  for (final backend in ['memory', 'sqlite']) {
    test(
      '$backend Session cascade removes durable records, never global Character/Persona assets',
      () async {
        final rig = await _Rig.fresh();
        addTearDown(() => _cleanup(rig));
        final env = backend == 'sqlite'
            ? rig.env
            : await integration.memoryEnvironment();
        if (backend == 'memory') addTearDown(env.owner.dispose);
        await (await env.owner.start(
          integration.command('delete'),
          env.binding,
        )).done;
        await env.repo.deleteSession('s');
        expect((await env.characters.getCharacter('character')).name, 'Mira');
        expect((await env.worlds.getPersona('persona')).name, 'Player');
        if (env.repo is InMemoryTavernRepository) {
          expect(
            (env.repo as InMemoryTavernRepository).worldInfoJournals,
            isEmpty,
          );
          expect(
            (env.repo as InMemoryTavernRepository).worldInfoStates,
            isEmpty,
          );
        } else {
          expect(
            await (await rig.db.database).query('tavern_world_info_states'),
            isEmpty,
          );
          expect(
            await (await rig.db.database).query('tavern_world_info_journal'),
            isEmpty,
          );
        }
      },
    );
  }
  test(
    'entry definition fingerprint is deterministic across a new isolate',
    () async {
      const entry = WorldInfoEntry(
        bookId: 'book',
        entryId: 'e',
        title: 'same',
        content: 'same',
        stickyMessages: 4,
      );
      final other = await Isolate.run(
        () => const WorldInfoEntry(
          bookId: 'book',
          entryId: 'e',
          title: 'same',
          content: 'same',
          stickyMessages: 4,
        ).definitionFingerprint,
      );
      expect(other, entry.definitionFingerprint);
      expect(other, hasLength(64));
    },
  );
  test(
    'included entry persists; compiler-budget drop has no timer or journal inclusion',
    () async {
      final rig = await _Rig.fresh();
      addTearDown(() => _cleanup(rig));
      final sources = _TimerSources(rig.env.owner.sources, large: true);
      await rig.env.owner.dispose();
      await rig.env.initialize(sources: sources);
      final result = await (await rig.env.owner.start(
        integration.command('budget'),
        rig.env.binding,
      )).done;
      expect(result.ledgerFailure, isFalse);
      final state = await _state(rig.env, 'main');
      expect(state.version, 1);
      expect(state.data.timers.map((t) => t.identity), [('book', 'lore')]);
      final journal = (await rig.repo.getWorldInfoJournal('budget'))!;
      expect(journal.plan.included, [('book', 'lore')]);
      expect(journal.outcome, TavernReconciliationOutcome.committed);
      final raw = (await (await rig.db.database).query(
        'tavern_world_info_journal',
      )).single;
      expect(jsonEncode(raw), isNot(contains('Eligible timer lore')));
      expect(jsonEncode(raw), isNot(contains('synthetic-credential')));
      final reopened = await rig.reopen();
      expect(
        (await _state(reopened, 'main')).data.fingerprint,
        state.data.fingerprint,
      );
    },
  );

  for (final window in [
    'before-plan',
    'prepared-before-http',
    'streaming',
    'provider-complete',
    'ledger-transaction',
    'after-notification',
    'shutdown',
  ]) {
    test(
      'SQLite crash window $window has deterministic no-network recovery',
      () async {
        final rig = await _Rig.fresh(
          notificationFailure: window == 'after-notification',
        );
        addTearDown(() => _cleanup(rig));
        final sql = await rig.db.database;
        BackupSnapshot? image;
        if (window == 'before-plan') {
          await sql.execute(
            "CREATE TRIGGER injected BEFORE INSERT ON tavern_world_info_journal BEGIN SELECT RAISE(ABORT,'synthetic plan fault'); END",
          );
          await expectLater(
            rig.env.owner.start(integration.command('crash'), rig.env.binding),
            throwsA(anything),
          );
          expect(rig.env.sent, isEmpty);
          expect(await rig.repo.listAttempts('answer'), isEmpty);
          expect(await sql.query('tavern_world_info_journal'), isEmpty);
        } else if (window == 'prepared-before-http') {
          final adapter = _HoldingAdapter();
          await rig.env.owner.dispose();
          await rig.env.initialize(
            sources: _TimerSources(rig.env.owner.sources),
            adapter: adapter,
          );
          final handle = await rig.env.owner.start(
            integration.command('crash'),
            rig.env.binding,
          );
          await adapter.reached.future;
          expect(rig.env.sent, isEmpty);
          expect(
            (await rig.repo.getWorldInfoJournal('crash'))!.outcome,
            TavernReconciliationOutcome.prepared,
          );
          image = await SQLiteBackupSnapshotStore(rig.db).buildSnapshot();
          await handle.cancel();
        } else if (window == 'streaming' || window == 'shutdown') {
          final client = _LiveFixture();
          rig.env.clients.add(client);
          final handle = await rig.env.owner.start(
            integration.command('crash'),
            rig.env.binding,
          );
          await client.reached.future;
          client.stream.add(
            utf8.encode(
              protocol.frame({
                'choices': [
                  {
                    'delta': {'content': 'PARTIAL' * 100},
                    'finish_reason': null,
                  },
                ],
              }),
            ),
          );
          while ((await rig.repo.listContentParts('answer')).isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          if (window == 'streaming') {
            image = await SQLiteBackupSnapshotStore(rig.db).buildSnapshot();
          }
          await rig.env.owner.dispose();
          expect(client.closed, isTrue);
          expect(
            (await handle.done).generation.phase,
            TavernExecutionPhase.cancelled,
          );
          if (window == 'shutdown') {
            expect(
              (await rig.repo.getWorldInfoJournal('crash'))!.outcome,
              TavernReconciliationOutcome.discarded,
            );
          }
        } else {
          if (window == 'provider-complete') {
            await sql.execute(
              "CREATE TRIGGER injected BEFORE UPDATE OF status ON tavern_generation_attempts WHEN NEW.status='completed' BEGIN SELECT RAISE(ABORT,'synthetic terminal fault'); END",
            );
          }
          if (window == 'ledger-transaction') {
            await sql.execute(
              "CREATE TRIGGER injected BEFORE UPDATE OF outcome ON tavern_world_info_journal WHEN NEW.outcome='committed' BEGIN SELECT RAISE(ABORT,'synthetic ledger fault'); END",
            );
          }
          final result = await (await rig.env.owner.start(
            integration.command('crash'),
            rig.env.binding,
          )).done;
          expect(result.ledgerFailure, isTrue);
          if (window == 'after-notification') {
            expect(result.generation.phase, TavernExecutionPhase.completed);
            expect((await _state(rig.env, 'main')).version, 1);
          } else {
            expect(result.generation.phase, TavernExecutionPhase.failed);
            expect(
              (await rig.repo.listAttempts('answer')).single.status,
              isNot(TavernGenerationStatus.completed),
            );
            expect((await _state(rig.env, 'main')).version, 0);
            expect(
              (await rig.repo.getWorldInfoJournal('crash'))!.outcome,
              TavernReconciliationOutcome.prepared,
            );
            await sql.execute('DROP TRIGGER injected');
          }
        }
        final replacement = image == null
            ? await rig.reopen()
            : await rig.crashImage(image);
        await replacement.owner.initialize();
        await (replacement.repo as TavernWorldInfoRepository)
            .reconcileWorldInfo();
        await replacement.owner.initialize();
        expect(replacement.sent, isEmpty);
        final state = await _state(replacement, 'main');
        expect(state.version, window == 'after-notification' ? 1 : 0);
        final attempts = await replacement.repo.listAttempts('answer');
        if (window == 'before-plan') {
          expect(attempts, isEmpty);
        } else {
          expect(
            attempts.single.status,
            window == 'after-notification'
                ? TavernGenerationStatus.completed
                : window == 'shutdown'
                ? TavernGenerationStatus.cancelled
                : TavernGenerationStatus.failed,
          );
          expect(
            (await (replacement.repo as TavernWorldInfoRepository)
                    .getWorldInfoJournal('crash'))!
                .outcome,
            window == 'after-notification'
                ? TavernReconciliationOutcome.committed
                : TavernReconciliationOutcome.discarded,
          );
          if (window != 'after-notification') {
            expect(
              (await replacement.repo.loadTranscript(
                's',
              )).turns.last.visibleParts,
              isEmpty,
            );
          }
        }
      },
    );
  }

  test(
    'completed canonical Attempt plus prepared journal recovers once, without reroll or HTTP',
    () async {
      final rig = await _Rig.fresh();
      addTearDown(() => _cleanup(rig));
      await (await rig.env.owner.start(
        integration.command('completed'),
        rig.env.binding,
      )).done;
      final expected = await _state(rig.env, 'main');
      final sql = await rig.db.database;
      // A controlled split-commit image tests Case C; normal v14 commits cannot tear here.
      await sql.transaction((tx) async {
        await tx.update(
          'tavern_world_info_states',
          {
            'version': 0,
            'last_attempt_id': null,
            'data_json': jsonEncode(expected.initialData.toJson()),
          },
          where: 'id = ?',
          whereArgs: ['main'],
        );
        await tx.update(
          'tavern_world_info_journal',
          {'outcome': 'prepared', 'committed_version': null},
          where: 'id = ?',
          whereArgs: ['completed'],
        );
      });
      final replacement = await rig.reopen();
      await replacement.owner.initialize();
      final durable = replacement.repo as TavernWorldInfoRepository;
      for (var i = 0; i < 10; i++) {
        expect(
          await durable.reconcileWorldInfoAttempt('completed'),
          TavernReconciliationOutcome.committed,
        );
      }
      final actual = await _state(replacement, 'main');
      expect(actual.version, expected.version);
      expect(actual.data.fingerprint, expected.data.fingerprint);
      expect(actual.lastAttemptId, 'completed');
      expect(replacement.sent, isEmpty);
    },
  );

  for (final kind in ['compile-identity', 'version']) {
    test(
      'durable $kind conflict survives SQLite reopen and blocks only its line',
      () async {
        final rig = await _Rig.fresh();
        addTearDown(() => _cleanup(rig));
        await (await rig.env.owner.start(
          integration.command('conflict'),
          rig.env.binding,
        )).done;
        final sql = await rig.db.database;
        final state = await _state(rig.env, 'main');
        await sql.update(
          'tavern_world_info_journal',
          {'outcome': 'prepared', 'committed_version': null},
          where: 'id = ?',
          whereArgs: ['conflict'],
        );
        if (kind == 'compile-identity') {
          final row = (await sql.query(
            'tavern_generation_attempts',
            where: 'id = ?',
            whereArgs: ['conflict'],
          )).single;
          final metadata =
              jsonDecode(row['metadata_json'] as String)
                  as Map<String, dynamic>;
          metadata['worldInfoCompileFingerprint'] = tavernDigest('wrong');
          await sql.update(
            'tavern_generation_attempts',
            {'metadata_json': jsonEncode(metadata)},
            where: 'id = ?',
            whereArgs: ['conflict'],
          );
        }
        await rig.repo.createStoryLine(
          TavernStoryLine(
            id: 'other',
            sessionId: 's',
            name: 'Other',
            position: 1,
            createdAt: _now,
            parentId: 'main',
            originTurnId: 'user',
            originAlternativeId: 'user-alt',
          ),
        );
        final replacement = await rig.reopen();
        await replacement.owner.initialize();
        final durable = replacement.repo as TavernWorldInfoRepository;
        expect(
          (await durable.getWorldInfoJournal('conflict'))!.outcome,
          TavernReconciliationOutcome.conflict,
        );
        expect(
          (await _state(replacement, 'main')).data.fingerprint,
          state.data.fingerprint,
        );
        await expectLater(
          durable.requireWorldInfoReady('s', 'main'),
          throwsA(isA<TavernReconciliationConflict>()),
        );
        await durable.requireWorldInfoReady('s', 'other');
        expect(replacement.sent, isEmpty);
      },
    );
  }

  for (final backend in ['memory', 'sqlite']) {
    test(
      '$backend historical Turn 20 fork does not inherit Turn 50; nested state and IDs remain frozen',
      () async {
        final rig = await _Rig.fresh();
        addTearDown(() => _cleanup(rig));
        TavernRepository repo = rig.repo;
        if (backend == 'memory') {
          final env = await integration.memoryEnvironment();
          addTearDown(env.owner.dispose);
          repo = env.repo;
        }
        final durable = repo as TavernWorldInfoRepository;
        for (var i = 1; i <= 50; i++) {
          await _canonicalGeneration(repo, durable, i);
        }
        await repo.createStoryLine(
          TavernStoryLine(
            id: 'A',
            sessionId: 's',
            name: 'A',
            position: 1,
            createdAt: _now,
            parentId: 'main',
            originTurnId: 'main-turn-20',
            originAlternativeId: 'main-turn-20-alt',
          ),
        );
        final a = await durable.loadWorldInfoState('s', 'A');
        expect(a.data.messageCount, 20);
        expect(a.data.timers.single.activatedAt, 20);
        expect(a.initialAttemptId, 'main-turn-20-attempt');
        expect(
          (await durable.loadWorldInfoState('s', 'main')).data.messageCount,
          50,
        );
        await _canonicalGeneration(repo, durable, 21, line: 'A', position: 0);
        await repo.createStoryLine(
          TavernStoryLine(
            id: 'A2',
            sessionId: 's',
            name: 'A2',
            position: 2,
            createdAt: _now,
            parentId: 'A',
            originTurnId: 'A-turn-21',
            originAlternativeId: 'A-turn-21-alt',
          ),
        );
        expect(
          (await durable.loadWorldInfoState('s', 'A2')).data.messageCount,
          21,
        );
        await repo.addAlternative(
          TavernAlternative(
            id: 'other-answer',
            turnId: 'main-turn-20',
            position: 1,
            origin: TavernAlternativeOrigin.manual,
            createdAt: _now,
          ),
        );
        await repo.selectAlternative('main-turn-20', 'other-answer');
        expect(
          (await repo.loadTranscript('s', storyLineId: 'A2')).turns
              .singleWhere((t) => t.turn.id == 'main-turn-20')
              .selectedAlternative
              .id,
          'main-turn-20-alt',
        );
        expect(
          (await durable.loadWorldInfoState('s', 'A')).initialData.fingerprint,
          a.initialData.fingerprint,
        );
        expect(
          (await durable.loadWorldInfoState('s', 'A2')).data.messageCount,
          21,
        );
      },
    );
  }
}
