import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/backup/backup_archive_codec.dart';
import 'package:ibukihome/application/tavern/tavern_generation_runtime.dart';
import 'package:ibukihome/data/memory/in_memory_tavern_repository.dart';
import 'package:ibukihome/data/repositories/tavern_repository.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/data/sqlite/sqlite_tavern_repository.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _now = DateTime.utc(2026, 10, 12);

class _Driver implements TavernGenerationDriver {
  final Map<String, Stream<TavernGenerationEvent>> scripts = {};
  final List<TavernGenerationTarget> targets = [];
  final Map<String, Completer<void>> _started = {};

  Future<void> whenStarted(String attemptId) =>
      _started.putIfAbsent(attemptId, Completer<void>.new).future;

  @override
  Stream<TavernGenerationEvent> generate(
    TavernGenerationTarget target,
    TavernGenerationCancellation cancellation,
  ) async* {
    targets.add(target);
    _started.putIfAbsent(target.attemptId, Completer<void>.new).complete();
    yield* scripts[target.attemptId] ?? const Stream.empty();
  }
}

TavernGenerationCommand _command(
  String session,
  String attempt, {
  TavernGenerationCommandKind kind = TavernGenerationCommandKind.normal,
  String? turn,
  String? alternative,
  String? commandId,
  Duration? timeout,
}) => TavernGenerationCommand(
  commandId: commandId ?? attempt,
  sessionId: session,
  storyLineId: '$session-main',
  turnId: turn ?? '$session-reply',
  alternativeId: alternative ?? '$session-answer',
  attemptId: attempt,
  kind: kind,
  participantId: '$session-character',
  contextTurnId: '$session-user',
  timeout: timeout,
);

Future<void> _seed(TavernRepository repo, String session) async {
  await repo.createSession(
    TavernSession(
      id: session,
      title: 'Fixture',
      createdAt: _now,
      updatedAt: _now,
    ),
    TavernStoryLine(
      id: '$session-main',
      sessionId: session,
      name: 'Main',
      position: 0,
      createdAt: _now,
    ),
  );
  await repo.addParticipant(
    TavernParticipant(
      id: '$session-player',
      sessionId: session,
      kind: TavernParticipantKind.persona,
      entityId: 'player-card',
      position: 0,
    ),
  );
  await repo.addParticipant(
    TavernParticipant(
      id: '$session-character',
      sessionId: session,
      kind: TavernParticipantKind.character,
      entityId: 'character-card',
      position: 1,
    ),
  );
  await repo.appendTurn(
    TavernTurn(
      id: '$session-user',
      sessionId: session,
      storyLineId: '$session-main',
      position: 0,
      participantId: '$session-player',
      role: TavernTurnRole.player,
      createdAt: _now,
      updatedAt: _now,
    ),
    TavernAlternative(
      id: '$session-user-answer',
      turnId: '$session-user',
      position: 0,
      origin: TavernAlternativeOrigin.manual,
      createdAt: _now,
    ),
  );
}

Future<void> _forBoth(Future<void> Function(TavernRepository) exercise) async {
  await exercise(InMemoryTavernRepository());
  final directory = await Directory.systemTemp.createTemp('ibuki_generation_');
  try {
    final db = IbukiDatabase(
      pathResolver: () async => p.join(directory.path, 'test.db'),
      databaseFactory: databaseFactoryFfi,
    );
    await exercise(SQLiteTavernRepository(db));
    await db.close();
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<void> _seedInterruptedAttempt(
  TavernRepository repo,
  String session,
  String attemptId,
) async {
  await repo.appendTurn(
    TavernTurn(
      id: '$session-reply',
      sessionId: session,
      storyLineId: '$session-main',
      position: 1,
      participantId: '$session-character',
      role: TavernTurnRole.character,
      createdAt: _now,
      updatedAt: _now,
    ),
    TavernAlternative(
      id: '$session-answer',
      turnId: '$session-reply',
      position: 0,
      origin: TavernAlternativeOrigin.generated,
      createdAt: _now,
    ),
    attempt: TavernGenerationAttempt(
      id: attemptId,
      sessionId: session,
      storyLineId: '$session-main',
      turnId: '$session-reply',
      alternativeId: '$session-answer',
      position: 0,
      status: TavernGenerationStatus.queued,
      type: TavernGenerationType.normal,
      createdAt: _now,
    ),
  );
  await repo.updateAttempt(attemptId, TavernGenerationStatus.running);
  await repo.persistGenerationBatch(attemptId, [
    TavernContentPart(
      id: '$attemptId:0',
      alternativeId: '$session-answer',
      generationAttemptId: attemptId,
      position: 0,
      kind: TavernContentKind.text,
      text: 'partial',
      createdAt: _now,
    ),
  ]);
}

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'normal, reasoning, retry, regenerate and continue preserve provenance',
    () async {
      await _forBoth((repo) async {
        await _seed(repo, 's');
        final driver = _Driver();
        final runtime = TavernGenerationRuntime(
          repo,
          driver,
          flushCharacters: 3,
        );
        driver.scripts['initial'] = Stream.fromIterable([
          const TavernReasoningDelta('initial', 'think'),
          const TavernTextDelta('initial', 'First.'),
          const TavernGenerationComplete('initial'),
        ]);
        final initial = await runtime.start(_command('s', 'initial'));
        expect((await initial.done).phase, TavernExecutionPhase.completed);
        var reply = (await repo.loadTranscript('s')).turns.last;
        expect(reply.visibleParts.map((part) => part.text), ['First.']);
        expect(reply.selectedParts.map((part) => part.kind), [
          TavernContentKind.reasoning,
          TavernContentKind.text,
        ]);

        driver.scripts['continue-fail'] = Stream.fromIterable([
          const TavernTextDelta('continue-fail', 'bad'),
          const TavernGenerationFailed(
            'continue-fail',
            TavernGenerationError(TavernGenerationErrorKind.timeout, 'stall'),
          ),
        ]);
        final failedContinue = await runtime.start(
          _command(
            's',
            'continue-fail',
            kind: TavernGenerationCommandKind.continueTurn,
          ),
        );
        expect((await failedContinue.done).phase, TavernExecutionPhase.failed);
        reply = (await repo.loadTranscript('s')).turns.last;
        expect(reply.visibleParts.map((part) => part.text), ['First.']);

        driver.scripts['continue-ok'] = Stream.fromIterable([
          const TavernTextDelta('continue-ok', 'Second.'),
          const TavernGenerationComplete('continue-ok'),
        ]);
        final continued = await runtime.start(
          _command(
            's',
            'continue-ok',
            kind: TavernGenerationCommandKind.continueTurn,
          ),
        );
        expect((await continued.done).phase, TavernExecutionPhase.completed);
        reply = (await repo.loadTranscript('s')).turns.last;
        expect(reply.visibleParts.map((part) => part.text), [
          'First.',
          'Second.',
        ]);
        expect((await repo.listAttempts('s-answer')), hasLength(3));

        driver.scripts['other-fail'] = Stream.fromIterable([
          const TavernTextDelta('other-fail', 'unselected'),
          const TavernGenerationFailed(
            'other-fail',
            TavernGenerationError(
              TavernGenerationErrorKind.rejected,
              'rejected',
            ),
          ),
        ]);
        final other = await runtime.start(
          _command(
            's',
            'other-fail',
            kind: TavernGenerationCommandKind.regenerate,
            alternative: 's-answer-2',
          ),
        );
        expect((await other.done).phase, TavernExecutionPhase.failed);
        expect(
          (await repo.loadTranscript('s')).turns.last.selectedAlternative.id,
          's-answer',
        );
        driver.scripts['other-retry'] = Stream.fromIterable([
          const TavernTextDelta('other-retry', 'Another.'),
          const TavernGenerationComplete('other-retry'),
        ]);
        final retry = await runtime.start(
          _command(
            's',
            'other-retry',
            kind: TavernGenerationCommandKind.retry,
            alternative: 's-answer-2',
          ),
        );
        expect((await retry.done).phase, TavernExecutionPhase.completed);
        reply = (await repo.loadTranscript('s')).turns.last;
        expect(reply.selectedAlternative.id, 's-answer-2');
        expect(reply.visibleParts.map((part) => part.text), ['Another.']);
        expect((await repo.listAttempts('s-answer-2')), hasLength(2));
        expect((await repo.listContentParts('s-answer-2')), hasLength(2));
        expect(driver.targets.map((target) => target.storyLineId).toSet(), {
          's-main',
        });
      });
    },
  );

  test(
    'cancel is idempotent and late events cannot complete an attempt',
    () async {
      await _forBoth((repo) async {
        await _seed(repo, 's');
        final driver = _Driver();
        final events = StreamController<TavernGenerationEvent>();
        driver.scripts['cancelled'] = events.stream;
        final runtime = TavernGenerationRuntime(
          repo,
          driver,
          flushCharacters: 100,
        );
        final handle = await runtime.start(_command('s', 'cancelled'));
        final updates = handle.updates.toList();
        final streaming = handle.updates.firstWhere(
          (snapshot) => snapshot.phase == TavernExecutionPhase.streaming,
        );
        await driver.whenStarted('cancelled');
        events.add(const TavernTextDelta('cancelled', 'partial'));
        await streaming;
        expect(
          (await repo.listAttempts('s-answer')).single.status,
          TavernGenerationStatus.streaming,
        );
        await Future.wait([handle.cancel(), handle.cancel(), handle.cancel()]);
        events.add(const TavernTextDelta('cancelled', 'late'));
        events.add(const TavernGenerationComplete('cancelled'));
        await events.close();
        expect((await handle.done).phase, TavernExecutionPhase.cancelled);
        expect((await updates).map((snapshot) => snapshot.phase), [
          TavernExecutionPhase.streaming,
          TavernExecutionPhase.cancelled,
        ]);
        expect(
          (await repo.listAttempts('s-answer')).single.status,
          TavernGenerationStatus.cancelled,
        );
        expect(
          (await repo.loadTranscript('s')).turns.last.visibleParts,
          isEmpty,
        );
        expect(
          (await repo.listContentParts('s-answer')).single.text,
          'partial',
        );

        driver.scripts['retry'] = Stream.fromIterable([
          const TavernTextDelta('cancelled', 'old attempt ignored'),
          const TavernTextDelta('retry', 'Good'),
          const TavernGenerationComplete('retry'),
        ]);
        final retry = await runtime.start(
          _command('s', 'retry', kind: TavernGenerationCommandKind.retry),
        );
        expect((await retry.done).phase, TavernExecutionPhase.completed);
        expect(
          (await repo.loadTranscript('s')).turns.last.visibleParts.single.text,
          'Good',
        );
      });
    },
  );

  test(
    'double start is deduplicated, same-session conflict and parallel sessions',
    () async {
      await _forBoth((repo) async {
        await _seed(repo, 's');
        await _seed(repo, 'other');
        final driver = _Driver();
        final firstEvents = StreamController<TavernGenerationEvent>();
        final secondEvents = StreamController<TavernGenerationEvent>();
        driver.scripts['one'] = firstEvents.stream;
        driver.scripts['two'] = secondEvents.stream;
        final runtime = TavernGenerationRuntime(repo, driver);
        final first = await runtime.start(_command('s', 'one'));
        expect(
          identical(first, await runtime.start(_command('s', 'one'))),
          isTrue,
        );
        await expectLater(
          runtime.start(_command('s', 'conflict')),
          throwsStateError,
        );
        final second = await runtime.start(_command('other', 'two'));
        firstEvents.add(const TavernGenerationComplete('one'));
        secondEvents.add(const TavernGenerationComplete('two'));
        await firstEvents.close();
        await secondEvents.close();
        expect((await first.done).phase, TavernExecutionPhase.completed);
        expect((await second.done).phase, TavernExecutionPhase.completed);
        expect(driver.targets, hasLength(2));
        expect((await repo.loadTranscript('s')).turns, hasLength(2));
        expect((await repo.loadTranscript('other')).turns, hasLength(2));
      });
    },
  );

  test(
    'restart recovery is idempotent and leaves partial output hidden',
    () async {
      await _forBoth((repo) async {
        await _seed(repo, 's');
        final driver = _Driver();
        final runtime = TavernGenerationRuntime(
          repo,
          driver,
          flushCharacters: 1,
        );
        await _seedInterruptedAttempt(repo, 's', 'interrupted');
        final restarted = TavernGenerationRuntime(repo, _Driver());
        expect(await restarted.recoverInterrupted(), hasLength(1));
        expect(await restarted.recoverInterrupted(), isEmpty);
        expect(
          (await repo.listAttempts('s-answer')).single.failureReason,
          'runtime_restart',
        );
        expect(
          (await repo.loadTranscript('s')).turns.last.visibleParts,
          isEmpty,
        );
        await runtime.dispose();
      });
    },
  );

  test('failed initial attempt retries on the same Alternative', () async {
    await _forBoth((repo) async {
      await _seed(repo, 's');
      final driver = _Driver();
      final runtime = TavernGenerationRuntime(repo, driver, flushCharacters: 2);
      driver.scripts['failed'] = Stream.fromIterable([
        const TavernReasoningDelta('failed', 'old reasoning'),
        const TavernTextDelta('failed', 'old partial'),
        const TavernGenerationFailed(
          'failed',
          TavernGenerationError(TavernGenerationErrorKind.transport, 'lost'),
        ),
      ]);
      final first = await runtime.start(_command('s', 'failed'));
      expect((await first.done).phase, TavernExecutionPhase.failed);
      expect((await repo.loadTranscript('s')).turns.last.visibleParts, isEmpty);
      driver.scripts['success'] = Stream.fromIterable([
        const TavernReasoningDelta('success', 'private'),
        const TavernTextDelta('success', 'fresh'),
        const TavernReasoningDelta('success', 'more private'),
        const TavernTextDelta('success', ' answer'),
        const TavernGenerationComplete('success'),
      ]);
      final retry = await runtime.start(
        _command('s', 'success', kind: TavernGenerationCommandKind.retry),
      );
      expect((await retry.done).phase, TavernExecutionPhase.completed);
      final reply = (await repo.loadTranscript('s')).turns.last;
      expect(reply.alternatives, hasLength(1));
      expect(
        reply.visibleParts.map((part) => part.text).join(),
        'fresh answer',
      );
      expect(
        reply.selectedParts.where(
          (part) => part.kind == TavernContentKind.reasoning,
        ),
        hasLength(2),
      );
      expect((await repo.listAttempts('s-answer')).map((a) => a.status), [
        TavernGenerationStatus.failed,
        TavernGenerationStatus.completed,
      ]);
      expect(
        (await repo.listContentParts('s-answer')).length,
        greaterThan(reply.selectedParts.length),
      );
    });
  });

  test(
    'retry of failed Continue preserves earlier completed content',
    () async {
      await _forBoth((repo) async {
        await _seed(repo, 's');
        final driver = _Driver();
        final runtime = TavernGenerationRuntime(repo, driver);
        driver.scripts['initial'] = Stream.fromIterable([
          const TavernTextDelta('initial', 'A'),
          const TavernGenerationComplete('initial'),
        ]);
        await (await runtime.start(_command('s', 'initial'))).done;
        driver.scripts['continue-fail'] = Stream.fromIterable([
          const TavernTextDelta('continue-fail', 'B'),
          const TavernGenerationFailed(
            'continue-fail',
            TavernGenerationError(
              TavernGenerationErrorKind.transport,
              'offline',
            ),
          ),
        ]);
        await (await runtime.start(
          _command(
            's',
            'continue-fail',
            kind: TavernGenerationCommandKind.continueTurn,
          ),
        )).done;
        driver.scripts['retry'] = Stream.fromIterable([
          const TavernTextDelta('retry', 'C'),
          const TavernGenerationComplete('retry'),
        ]);
        await (await runtime.start(
          _command('s', 'retry', kind: TavernGenerationCommandKind.retry),
        )).done;
        final reply = (await repo.loadTranscript('s')).turns.last;
        expect(reply.visibleParts.map((part) => part.text), ['A', 'C']);
        expect(
          (await repo.listAttempts('s-answer')).last.type,
          TavernGenerationType.continueTurn,
        );
        expect(
          (await repo.listContentParts('s-answer')).map((part) => part.text),
          ['A', 'B', 'C'],
        );
      });
    },
  );

  test('5000 deltas batch into bounded rows without losing order', () async {
    await _forBoth((repo) async {
      await _seed(repo, 's');
      final driver = _Driver();
      driver.scripts['flood'] = Stream.fromIterable([
        for (var i = 0; i < 5000; i++) const TavernTextDelta('flood', 'x'),
        const TavernGenerationComplete('flood'),
      ]);
      final runtime = TavernGenerationRuntime(repo, driver);
      final handle = await runtime.start(_command('s', 'flood'));
      expect((await handle.done).phase, TavernExecutionPhase.completed);
      final parts = await repo.listContentParts('s-answer');
      expect(parts.length, lessThan(20));
      expect(parts.map((part) => part.text).join().length, 5000);
    });
  });

  test('cancel and completion race has one terminal outcome', () async {
    await _forBoth((repo) async {
      await _seed(repo, 's');
      final driver = _Driver();
      final events = StreamController<TavernGenerationEvent>();
      driver.scripts['race'] = events.stream;
      final runtime = TavernGenerationRuntime(repo, driver);
      final handle = await runtime.start(_command('s', 'race'));
      await driver.whenStarted('race');
      events.add(const TavernTextDelta('race', 'final chunk'));
      await handle.cancel();
      events.add(const TavernGenerationComplete('race'));
      await events.close();
      expect((await handle.done).phase, TavernExecutionPhase.cancelled);
      expect(
        (await repo.listAttempts('s-answer')).single.status,
        TavernGenerationStatus.cancelled,
      );
      expect((await repo.loadTranscript('s')).turns.last.visibleParts, isEmpty);

      driver.scripts['retry-race'] = Stream.fromIterable([
        const TavernTextDelta('retry-race', 'Done'),
        const TavernGenerationComplete('retry-race'),
        const TavernGenerationComplete('retry-race'),
      ]);
      final retry = await runtime.start(
        _command('s', 'retry-race', kind: TavernGenerationCommandKind.retry),
      );
      expect((await retry.done).phase, TavernExecutionPhase.completed);
      await retry.cancel();
      expect(
        (await repo.listAttempts('s-answer')).last.status,
        TavernGenerationStatus.completed,
      );
    });
  });

  test('two runtimes sharing a repository reject the same session', () async {
    await _forBoth((repo) async {
      await _seed(repo, 's');
      final events = StreamController<TavernGenerationEvent>();
      final driver = _Driver()..scripts['first'] = events.stream;
      final firstRuntime = TavernGenerationRuntime(repo, driver);
      final secondRuntime = TavernGenerationRuntime(repo, _Driver());
      final first = await firstRuntime.start(_command('s', 'first'));
      await driver.whenStarted('first');
      await expectLater(
        secondRuntime.start(_command('s', 'second')),
        throwsStateError,
      );
      await expectLater(secondRuntime.recoverInterrupted(), throwsStateError);
      expect((await repo.listAttempts('s-answer')), hasLength(1));
      await first.cancel();
      await events.close();
      expect((await first.done).phase, TavernExecutionPhase.cancelled);
      await secondRuntime.dispose();
    });
  });

  test(
    'separate SQLite repository objects share the same generation scope',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ibuki_gen_scope_',
      );
      try {
        final path = p.join(directory.path, 'shared.db');
        IbukiDatabase open() => IbukiDatabase(
          pathResolver: () async => path,
          databaseFactory: databaseFactoryFfi,
        );
        final firstDb = open();
        final secondDb = open();
        final firstRepo = SQLiteTavernRepository(firstDb);
        await _seed(firstRepo, 's');
        final events = StreamController<TavernGenerationEvent>();
        final driver = _Driver()..scripts['first'] = events.stream;
        final runtime = TavernGenerationRuntime(firstRepo, driver);
        final other = TavernGenerationRuntime(
          SQLiteTavernRepository(secondDb),
          _Driver(),
        );
        final handle = await runtime.start(_command('s', 'first'));
        await driver.whenStarted('first');
        await expectLater(
          other.start(_command('s', 'second')),
          throwsStateError,
        );
        await runtime.dispose();
        await events.close();
        expect((await handle.done).phase, TavernExecutionPhase.cancelled);
        await secondDb.close();
        await firstDb.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'manual selection beats regenerate completion and Continue is pinned',
    () async {
      await _forBoth((repo) async {
        await _seed(repo, 's');
        final driver = _Driver();
        final runtime = TavernGenerationRuntime(repo, driver);
        driver.scripts['first'] = Stream.fromIterable([
          const TavernTextDelta('first', 'Original'),
          const TavernGenerationComplete('first'),
        ]);
        expect(
          (await (await runtime.start(_command('s', 'first'))).done).phase,
          TavernExecutionPhase.completed,
        );
        final events = StreamController<TavernGenerationEvent>();
        driver.scripts['regenerate'] = events.stream;
        final regenerating = await runtime.start(
          _command(
            's',
            'regenerate',
            kind: TavernGenerationCommandKind.regenerate,
            alternative: 's-answer-2',
          ),
        );
        await driver.whenStarted('regenerate');
        expect(
          (await repo.loadTranscript('s')).turns.last.selectedAlternative.id,
          's-answer',
        );
        await repo.addAlternative(
          TavernAlternative(
            id: 's-answer-3',
            turnId: 's-reply',
            position: 2,
            origin: TavernAlternativeOrigin.manual,
            createdAt: _now,
          ),
        );
        await repo.selectAlternative('s-reply', 's-answer-3');
        events.add(const TavernTextDelta('regenerate', 'New'));
        events.add(const TavernGenerationComplete('regenerate'));
        await events.close();
        expect((await regenerating.done).phase, TavernExecutionPhase.completed);
        expect(
          (await repo.loadTranscript('s')).turns.last.selectedAlternative.id,
          's-answer-3',
        );
        expect((await repo.listContentParts('s-answer-2')).single.text, 'New');

        await repo.selectAlternative('s-reply', 's-answer');
        final continuationEvents = StreamController<TavernGenerationEvent>();
        driver.scripts['continue'] = continuationEvents.stream;
        final continuing = await runtime.start(
          _command(
            's',
            'continue',
            kind: TavernGenerationCommandKind.continueTurn,
          ),
        );
        await driver.whenStarted('continue');
        await repo.selectAlternative('s-reply', 's-answer-3');
        continuationEvents.add(const TavernTextDelta('continue', ' more'));
        continuationEvents.add(const TavernGenerationComplete('continue'));
        await continuationEvents.close();
        expect((await continuing.done).phase, TavernExecutionPhase.completed);
        expect(
          (await repo.loadTranscript('s')).turns.last.selectedAlternative.id,
          's-answer-3',
        );
        expect((await repo.listContentParts('s-answer')).map((p) => p.text), [
          'Original',
          ' more',
        ]);
      });
    },
  );

  test('failure and completion races keep the first terminal result', () async {
    await _forBoth((repo) async {
      await _seed(repo, 's');
      final driver = _Driver();
      final runtime = TavernGenerationRuntime(repo, driver);
      driver.scripts['failed'] = Stream.fromIterable([
        const TavernGenerationFailed(
          'failed',
          TavernGenerationError(TavernGenerationErrorKind.transport, 'offline'),
        ),
        const TavernGenerationComplete('failed'),
      ]);
      expect(
        (await (await runtime.start(_command('s', 'failed'))).done).phase,
        TavernExecutionPhase.failed,
      );
      driver.scripts['completed'] = Stream.fromIterable([
        const TavernGenerationComplete('completed'),
        const TavernGenerationFailed(
          'completed',
          TavernGenerationError(TavernGenerationErrorKind.transport, 'late'),
        ),
      ]);
      expect(
        (await (await runtime.start(
          _command('s', 'completed', kind: TavernGenerationCommandKind.retry),
        )).done).phase,
        TavernExecutionPhase.completed,
      );
      expect((await repo.listAttempts('s-answer')).map((a) => a.status), [
        TavernGenerationStatus.failed,
        TavernGenerationStatus.completed,
      ]);
    });
  });

  test('normal initialization failure leaves no half-created reply', () async {
    await _forBoth((repo) async {
      await _seed(repo, 's');
      await _seed(repo, 'other');
      await _seedInterruptedAttempt(repo, 'other', 'colliding-attempt');
      final runtime = TavernGenerationRuntime(repo, _Driver());
      await expectLater(
        runtime.start(_command('s', 'colliding-attempt')),
        throwsA(anything),
      );
      expect((await repo.loadTranscript('s')).turns, hasLength(1));
      expect(await repo.listAttempts('other-answer'), hasLength(1));
    });
  });

  test('recovery handles multiple stale sessions once', () async {
    await _forBoth((repo) async {
      for (final session in ['a', 'b', 'c']) {
        await _seed(repo, session);
        await _seedInterruptedAttempt(repo, session, '$session-stale');
      }
      final runtime = TavernGenerationRuntime(repo, _Driver());
      expect(await runtime.recoverInterrupted(), hasLength(3));
      expect(await runtime.recoverInterrupted(), isEmpty);
      for (final session in ['a', 'b', 'c']) {
        final attempt = (await repo.listAttempts('$session-answer')).single;
        expect(attempt.status, TavernGenerationStatus.failed);
        expect(attempt.failureReason, 'runtime_restart');
        expect(
          (await repo.loadTranscript(session)).turns.last.visibleParts,
          isEmpty,
        );
      }
    });
  });

  test(
    'timeout, wrong-attempt event and active line switch stay isolated',
    () async {
      await _forBoth((repo) async {
        await _seed(repo, 's');
        final driver = _Driver();
        final events = StreamController<TavernGenerationEvent>();
        driver.scripts['stall'] = events.stream;
        final runtime = TavernGenerationRuntime(repo, driver);
        final handle = await runtime.start(
          _command('s', 'stall', timeout: const Duration(milliseconds: 30)),
        );
        await repo.createStoryLine(
          TavernStoryLine(
            id: 'child',
            sessionId: 's',
            name: 'Child',
            position: 1,
            parentId: 's-main',
            originTurnId: 's-user',
            originAlternativeId: 's-user-answer',
            createdAt: _now,
          ),
          activate: true,
        );
        events.add(const TavernTextDelta('another-attempt', 'wrong'));
        expect(
          (await handle.done).error?.kind,
          TavernGenerationErrorKind.timeout,
        );
        expect((await repo.listContentParts('s-answer')), isEmpty);
        expect((await repo.getSession('s')).activeStoryLineId, 'child');
        expect(
          (await repo.loadTranscript('s', storyLineId: 's-main')).turns,
          hasLength(2),
        );
        expect((await repo.loadTranscript('s')).turns, hasLength(1));
        await events.close();
      });
    },
  );

  test('final batch failure rolls back content and terminal status', () async {
    await _forBoth((repo) async {
      await _seed(repo, 's');
      final attempt = TavernGenerationAttempt(
        id: 'atomic',
        sessionId: 's',
        storyLineId: 's-main',
        turnId: 's-reply',
        alternativeId: 's-answer',
        position: 0,
        status: TavernGenerationStatus.queued,
        type: TavernGenerationType.normal,
        createdAt: _now,
      );
      await repo.appendTurn(
        TavernTurn(
          id: 's-reply',
          sessionId: 's',
          storyLineId: 's-main',
          position: 1,
          participantId: 's-character',
          role: TavernTurnRole.character,
          createdAt: _now,
          updatedAt: _now,
        ),
        TavernAlternative(
          id: 's-answer',
          turnId: 's-reply',
          position: 0,
          origin: TavernAlternativeOrigin.generated,
          createdAt: _now,
        ),
        attempt: attempt,
      );
      TavernContentPart part(String id) => TavernContentPart(
        id: id,
        alternativeId: 's-answer',
        generationAttemptId: 'atomic',
        position: 0,
        kind: TavernContentKind.text,
        text: id,
        createdAt: _now,
      );
      await expectLater(
        repo.persistGenerationBatch(
          'atomic',
          [part('first'), part('duplicate-position')],
          terminalStatus: TavernGenerationStatus.completed,
          selectAlternative: true,
        ),
        throwsA(anything),
      );
      expect(await repo.listContentParts('s-answer'), isEmpty);
      expect(
        (await repo.listAttempts('s-answer')).single.status,
        TavernGenerationStatus.queued,
      );
    });
  });

  test(
    'SQLite close and reopen recovers an interrupted streamed attempt',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ibuki_generation_reopen_',
      );
      try {
        final path = p.join(directory.path, 'data.db');
        IbukiDatabase open() => IbukiDatabase(
          pathResolver: () async => path,
          databaseFactory: databaseFactoryFfi,
        );
        final originalDb = open();
        final original = SQLiteTavernRepository(originalDb);
        await _seed(original, 's');
        await _seedInterruptedAttempt(original, 's', 'interrupted');
        expect(await original.listContentParts('s-answer'), hasLength(1));
        await originalDb.close();
        final reopenedDb = open();
        final reopened = SQLiteTavernRepository(reopenedDb);
        final newRuntime = TavernGenerationRuntime(reopened, _Driver());
        expect(await newRuntime.recoverInterrupted(), hasLength(1));
        expect(await newRuntime.recoverInterrupted(), isEmpty);
        expect(
          (await reopened.listAttempts('s-answer')).single.failureReason,
          'runtime_restart',
        );
        expect(
          (await reopened.loadTranscript('s')).turns.last.visibleParts,
          isEmpty,
        );
        await reopenedDb.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'complex runtime history survives archive restore and SQLite reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ibuki_gen_archive_',
      );
      try {
        IbukiDatabase open(String name) => IbukiDatabase(
          pathResolver: () async => p.join(directory.path, name),
          databaseFactory: databaseFactoryFfi,
        );
        final sourceDb = open('source.db');
        final source = SQLiteTavernRepository(sourceDb);
        await _seed(source, 's');
        final driver = _Driver();
        final runtime = TavernGenerationRuntime(source, driver);
        Future<void> run(
          String id,
          TavernGenerationCommandKind kind,
          String alternative,
          List<TavernGenerationEvent> events,
        ) async {
          driver.scripts[id] = Stream.fromIterable(events);
          await (await runtime.start(
            _command('s', id, kind: kind, alternative: alternative),
          )).done;
        }

        await run('normal', TavernGenerationCommandKind.normal, 's-answer', [
          const TavernReasoningDelta('normal', 'thought'),
          const TavernTextDelta('normal', 'One'),
          const TavernGenerationComplete('normal'),
        ]);
        final cancelEvents = StreamController<TavernGenerationEvent>();
        driver.scripts['regen-cancel'] = cancelEvents.stream;
        final cancelled = await runtime.start(
          _command(
            's',
            'regen-cancel',
            kind: TavernGenerationCommandKind.regenerate,
            alternative: 's-answer-2',
          ),
        );
        await driver.whenStarted('regen-cancel');
        await cancelled.cancel();
        await cancelEvents.close();
        await run(
          'retry-fail',
          TavernGenerationCommandKind.retry,
          's-answer-2',
          [
            const TavernTextDelta('retry-fail', 'discard'),
            const TavernGenerationFailed(
              'retry-fail',
              TavernGenerationError(
                TavernGenerationErrorKind.transport,
                'offline',
              ),
            ),
          ],
        );
        await run('retry-ok', TavernGenerationCommandKind.retry, 's-answer-2', [
          const TavernTextDelta('retry-ok', 'Two'),
          const TavernGenerationComplete('retry-ok'),
        ]);
        await run(
          'regen-ok',
          TavernGenerationCommandKind.regenerate,
          's-answer-3',
          [
            const TavernTextDelta('regen-ok', 'Three'),
            const TavernGenerationComplete('regen-ok'),
          ],
        );
        await run(
          'continue-fail',
          TavernGenerationCommandKind.continueTurn,
          's-answer-3',
          [
            const TavernTextDelta('continue-fail', 'discard-more'),
            const TavernGenerationFailed(
              'continue-fail',
              TavernGenerationError(
                TavernGenerationErrorKind.transport,
                'offline',
              ),
            ),
          ],
        );
        await run(
          'continue-ok',
          TavernGenerationCommandKind.continueTurn,
          's-answer-3',
          [
            const TavernTextDelta('continue-ok', ' plus'),
            const TavernGenerationComplete('continue-ok'),
          ],
        );

        Future<String> signature(TavernRepository repo) async {
          final turn = (await repo.loadTranscript('s')).turns.last;
          final attempts = <String>[];
          final parts = <String>[];
          for (final alternative in turn.alternatives) {
            attempts.addAll(
              (await repo.listAttempts(
                alternative.id,
              )).map((a) => '${a.id}:${a.status.name}:${a.type.name}'),
            );
            parts.addAll(
              (await repo.listContentParts(alternative.id)).map(
                (part) =>
                    '${part.generationAttemptId}:${part.kind.name}:${part.text}',
              ),
            );
          }
          return [
            turn.selectedAlternative.id,
            turn.visibleParts.map((part) => part.text).join(),
            attempts.join('|'),
            parts.join('|'),
          ].join('\n');
        }

        final before = await signature(source);
        expect(before, contains('normal:reasoning:thought'));
        expect(before, contains('continue-ok:text: plus'));
        expect(before, contains('regen-cancel:cancelled'));
        final codec = BackupArchiveCodec(
          applicationSupportDirectory: directory,
        );
        final archive = File(p.join(directory.path, 'runtime.ibukibackup'));
        await codec.write(
          snapshot: await SQLiteBackupSnapshotStore(sourceDb).buildSnapshot(),
          destination: archive,
          appVersion: 'generation-test',
          schemaVersion: SqliteSchema.version,
        );
        final decoded = await codec.read(
          source: archive,
          staging: Directory(p.join(directory.path, 'staging')),
        );
        final targetDb = open('target.db');
        await SQLiteBackupSnapshotStore(targetDb).restore(
          decoded.snapshot,
          mode: BackupRestoreMode.fresh,
          restoredAssets: const {},
        );
        expect(await signature(SQLiteTavernRepository(targetDb)), before);
        await targetDb.close();
        final reopened = open('target.db');
        expect(await signature(SQLiteTavernRepository(reopened)), before);
        await reopened.close();
        await sourceDb.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
