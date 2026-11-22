import 'dart:async';

import '../../data/repositories/tavern_repository.dart';
import '../../domain/tavern/tavern_models.dart';
import '../../domain/tavern/tavern_world_info.dart';

enum TavernGenerationCommandKind { normal, retry, regenerate, continueTurn }

enum TavernExecutionPhase { preparing, streaming, completed, cancelled, failed }

enum TavernGenerationErrorKind {
  transport,
  timeout,
  rejected,
  invalidResponse,
  unsupported,
  invariant,
  interrupted,
}

class TavernGenerationError {
  const TavernGenerationError(this.kind, this.message, {this.reasonCode});
  final TavernGenerationErrorKind kind;
  final String message;
  final String? reasonCode;
}

class TavernGenerationCommand {
  const TavernGenerationCommand({
    required this.commandId,
    required this.sessionId,
    required this.storyLineId,
    required this.turnId,
    required this.alternativeId,
    required this.attemptId,
    required this.kind,
    this.participantId,
    this.contextTurnId,
    this.timeout,
    this.providerReference,
    this.modelReference,
    this.reconciliation,
  });
  final String commandId,
      sessionId,
      storyLineId,
      turnId,
      alternativeId,
      attemptId;
  final TavernGenerationCommandKind kind;
  final String? participantId, contextTurnId;
  final String? providerReference, modelReference;
  final TavernWorldInfoPlan? reconciliation;
  final Duration? timeout;
}

class TavernGenerationTarget {
  const TavernGenerationTarget(
    this.sessionId,
    this.storyLineId,
    this.turnId,
    this.alternativeId,
    this.attemptId,
  );
  final String sessionId, storyLineId, turnId, alternativeId, attemptId;
}

sealed class TavernGenerationEvent {
  const TavernGenerationEvent(this.attemptId);
  final String attemptId;
}

class TavernTextDelta extends TavernGenerationEvent {
  const TavernTextDelta(super.attemptId, this.text);
  final String text;
}

class TavernReasoningDelta extends TavernGenerationEvent {
  const TavernReasoningDelta(super.attemptId, this.text);
  final String text;
}

class TavernReasoningSummaryDelta extends TavernGenerationEvent {
  const TavernReasoningSummaryDelta(super.attemptId, this.text);
  final String text;
}

class TavernReasoningUnavailable extends TavernGenerationEvent {
  const TavernReasoningUnavailable(super.attemptId);
}

class TavernGenerationComplete extends TavernGenerationEvent {
  const TavernGenerationComplete(super.attemptId);
}

class TavernGenerationFailed extends TavernGenerationEvent {
  const TavernGenerationFailed(super.attemptId, this.error);
  final TavernGenerationError error;
}

class TavernGenerationCancellation {
  bool _cancelled = false;
  final Completer<void> _signal = Completer<void>();
  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _signal.future;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _signal.complete();
  }
}

abstract class TavernGenerationDriver {
  Stream<TavernGenerationEvent> generate(
    TavernGenerationTarget target,
    TavernGenerationCancellation cancellation,
  );
}

class TavernGenerationSnapshot {
  const TavernGenerationSnapshot(
    this.target,
    this.phase, {
    this.error,
    this.pendingText = '',
    this.pendingReasoning = '',
    this.pendingPart,
  });
  final TavernGenerationTarget target;
  final TavernExecutionPhase phase;
  final TavernGenerationError? error;
  final String pendingText, pendingReasoning;
  final TavernContentPart? pendingPart;
}

class TavernGenerationHandle {
  TavernGenerationHandle._(this.target, this._runtime, this.timeout, this.kind)
    : _snapshot = TavernGenerationSnapshot(
        target,
        TavernExecutionPhase.preparing,
      );
  final TavernGenerationTarget target;
  final TavernGenerationRuntime _runtime;
  final Duration? timeout;
  final TavernGenerationCommandKind kind;
  String? _expectedSelectedAlternativeId;
  Object? _scopeKey;
  final StreamController<TavernGenerationSnapshot> _updates =
      StreamController<TavernGenerationSnapshot>.broadcast(sync: true);
  final Completer<TavernGenerationSnapshot> _done = Completer();
  final TavernGenerationCancellation cancellation =
      TavernGenerationCancellation();
  TavernGenerationSnapshot _snapshot;
  bool _terminal = false;
  Future<void> _operations = Future<void>.value();
  StreamIterator<TavernGenerationEvent>? _iterator;
  final List<(TavernContentKind, String)> _pending = [];
  int _nextPartPosition = 0;
  int _pendingLength = 0;
  bool _streamingPersisted = false;
  TavernGenerationSnapshot get snapshot => _snapshot;
  Stream<TavernGenerationSnapshot> get updates => _updates.stream;
  Future<TavernGenerationSnapshot> get done => _done.future;
  Future<void> cancel() => _runtime.cancel(this);
  void _emit(TavernGenerationSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_updates.isClosed) _updates.add(snapshot);
  }
}

class TavernGenerationRuntime {
  TavernGenerationRuntime(
    this.repository,
    this.driver, {
    this.flushCharacters = 512,
  }) : assert(flushCharacters > 0);
  final TavernRepository repository;
  final TavernGenerationDriver driver;
  final int flushCharacters;
  final Map<String, TavernGenerationHandle> _active = {};
  final Map<String, TavernGenerationHandle> _commands = {};
  static final Map<Object, Set<String>> _sessionsByScope = {};
  static final Set<Object> _recoveringScopes = {};
  bool _disposed = false;

  Future<List<TavernGenerationAttempt>> recoverInterrupted() async {
    if (_active.isNotEmpty) {
      throw StateError('Cannot recover while generations are active.');
    }
    final scope = await repository.generationScopeKey;
    if (_sessionsByScope[scope]?.isNotEmpty == true ||
        !_recoveringScopes.add(scope)) {
      throw StateError('Cannot recover while generations are active.');
    }
    try {
      return await repository.recoverInterruptedAttempts();
    } finally {
      _recoveringScopes.remove(scope);
    }
  }

  Future<TavernGenerationHandle> start(TavernGenerationCommand command) async {
    if (_disposed) throw StateError('Generation runtime is disposed.');
    final repeated = _commands[command.commandId];
    if (repeated != null) {
      if (repeated.target.sessionId != command.sessionId ||
          repeated.target.storyLineId != command.storyLineId ||
          repeated.target.turnId != command.turnId ||
          repeated.target.alternativeId != command.alternativeId ||
          repeated.target.attemptId != command.attemptId) {
        throw StateError('Command ID already belongs to another target.');
      }
      return repeated;
    }
    if (_active.containsKey(command.sessionId)) {
      throw StateError('One active generation per session.');
    }
    final target = TavernGenerationTarget(
      command.sessionId,
      command.storyLineId,
      command.turnId,
      command.alternativeId,
      command.attemptId,
    );
    final handle = TavernGenerationHandle._(
      target,
      this,
      command.timeout,
      command.kind,
    );
    _active[command.sessionId] = handle;
    _commands[command.commandId] = handle;
    try {
      final scope = await repository.generationScopeKey;
      if (_recoveringScopes.contains(scope) ||
          !(_sessionsByScope[scope] ??= <String>{}).add(command.sessionId)) {
        throw StateError('One active generation per session.');
      }
      handle._scopeKey = scope;
      await _prepare(command, handle);
      unawaited(_run(handle));
      return handle;
    } catch (_) {
      _active.remove(command.sessionId);
      _commands.remove(command.commandId);
      _releaseScope(handle);
      await handle._updates.close();
      rethrow;
    }
  }

  Future<void> _prepare(
    TavernGenerationCommand command,
    TavernGenerationHandle handle,
  ) async {
    final session = await repository.getSession(command.sessionId);
    final line = await repository.getStoryLine(command.storyLineId);
    if (line.sessionId != session.id ||
        line.archivedAt != null ||
        session.archivedAt != null ||
        session.deletedAt != null) {
      throw StateError('Generation target is not an active session line.');
    }
    final transcript = await repository.loadTranscript(
      command.sessionId,
      storyLineId: command.storyLineId,
    );
    final ownTurns = transcript.turns
        .where((item) => item.turn.storyLineId == command.storyLineId)
        .toList();
    final now = DateTime.now().toUtc();
    if (command.kind == TavernGenerationCommandKind.normal) {
      if (command.participantId == null ||
          command.contextTurnId == null ||
          transcript.turns.isEmpty ||
          transcript.turns.last.turn.id != command.contextTurnId ||
          transcript.turns.last.turn.role != TavernTurnRole.player) {
        throw StateError('Normal reply requires the latest player turn.');
      }
      final position = ownTurns.isEmpty ? 0 : ownTurns.last.turn.position + 1;
      final attempt = _attempt(command, 0, now);
      await repository.appendTurn(
        TavernTurn(
          id: command.turnId,
          sessionId: command.sessionId,
          storyLineId: command.storyLineId,
          position: position,
          participantId: command.participantId!,
          role: TavernTurnRole.character,
          createdAt: now,
          updatedAt: now,
        ),
        TavernAlternative(
          id: command.alternativeId,
          turnId: command.turnId,
          position: 0,
          origin: TavernAlternativeOrigin.generated,
          createdAt: now,
        ),
        attempt: attempt,
        reconciliation: command.reconciliation,
      );
    } else {
      final targetTurn = transcript.turns
          .where((item) => item.turn.id == command.turnId)
          .firstOrNull;
      if (targetTurn == null ||
          targetTurn.turn.storyLineId != command.storyLineId ||
          targetTurn.turn.role != TavernTurnRole.character) {
        throw StateError('Target turn is not an owned character turn.');
      }
      if (command.kind == TavernGenerationCommandKind.regenerate) {
        handle._expectedSelectedAlternativeId =
            targetTurn.selectedAlternative.id;
        final position = targetTurn.alternatives.last.position + 1;
        await repository.addAlternative(
          TavernAlternative(
            id: command.alternativeId,
            turnId: command.turnId,
            position: position,
            origin: TavernAlternativeOrigin.generated,
            createdAt: now,
          ),
          attempt: _attempt(command, 0, now),
          reconciliation: command.reconciliation,
        );
      } else {
        if (!targetTurn.alternatives.any(
              (alt) => alt.id == command.alternativeId,
            ) ||
            (command.kind == TavernGenerationCommandKind.continueTurn &&
                targetTurn.selectedAlternative.id != command.alternativeId)) {
          throw StateError('Generation target is not an eligible Alternative.');
        }
        final attempts = await repository.listAttempts(command.alternativeId);
        if (attempts.any((item) => !_isTerminal(item.status))) {
          throw StateError('Alternative already has an active Attempt.');
        }
        if (command.kind == TavernGenerationCommandKind.retry &&
            (attempts.isEmpty ||
                !{
                  TavernGenerationStatus.failed,
                  TavernGenerationStatus.cancelled,
                }.contains(attempts.last.status))) {
          throw StateError('Retry requires a failed or cancelled Attempt.');
        }
        if (command.kind == TavernGenerationCommandKind.continueTurn &&
            (attempts.isEmpty ||
                !attempts.any(
                  (item) => item.status == TavernGenerationStatus.completed,
                ))) {
          throw StateError('Continue requires completed content.');
        }
        if (command.kind == TavernGenerationCommandKind.retry) {
          handle._expectedSelectedAlternativeId =
              targetTurn.selectedAlternative.id;
        }
        final parts = await repository.listContentParts(command.alternativeId);
        handle._nextPartPosition = parts.isEmpty ? 0 : parts.last.position + 1;
        final next = attempts.isEmpty ? 0 : attempts.last.position + 1;
        await repository.recordAttempt(
          _attempt(
            command,
            next,
            now,
            retryType:
                command.kind == TavernGenerationCommandKind.retry &&
                    attempts.last.type == TavernGenerationType.continueTurn
                ? TavernGenerationType.continueTurn
                : null,
          ),
          reconciliation: command.reconciliation,
        );
      }
    }
  }

  void _releaseScope(TavernGenerationHandle handle) {
    final scope = handle._scopeKey;
    if (scope == null) return;
    final sessions = _sessionsByScope[scope];
    sessions?.remove(handle.target.sessionId);
    if (sessions?.isEmpty == true) _sessionsByScope.remove(scope);
    handle._scopeKey = null;
  }

  TavernGenerationAttempt _attempt(
    TavernGenerationCommand command,
    int position,
    DateTime now, {
    TavernGenerationType? retryType,
  }) => TavernGenerationAttempt(
    id: command.attemptId,
    sessionId: command.sessionId,
    storyLineId: command.storyLineId,
    turnId: command.turnId,
    alternativeId: command.alternativeId,
    position: position,
    status: TavernGenerationStatus.queued,
    type: switch (command.kind) {
      TavernGenerationCommandKind.normal => TavernGenerationType.normal,
      TavernGenerationCommandKind.retry =>
        retryType ?? TavernGenerationType.regenerate,
      TavernGenerationCommandKind.regenerate =>
        TavernGenerationType.alternative,
      TavernGenerationCommandKind.continueTurn =>
        TavernGenerationType.continueTurn,
    },
    createdAt: now,
    providerReference: command.providerReference,
    modelReference: command.modelReference,
    metadata: command.reconciliation == null
        ? const {}
        : {
            'worldInfoPlanIdentity': command.reconciliation!.identity,
            'worldInfoCompileFingerprint':
                command.reconciliation!.compileFingerprint,
            'worldInfoRequestFingerprint':
                command.reconciliation!.requestFingerprint,
          },
  );

  static bool _isTerminal(TavernGenerationStatus status) =>
      status == TavernGenerationStatus.completed ||
      status == TavernGenerationStatus.failed ||
      status == TavernGenerationStatus.cancelled;

  Future<void> _run(TavernGenerationHandle handle) async {
    try {
      if (handle.cancellation.isCancelled) return;
      await repository.updateAttempt(
        handle.target.attemptId,
        TavernGenerationStatus.running,
      );
      if (handle.cancellation.isCancelled) return;
      final source = driver.generate(handle.target, handle.cancellation);
      final events = handle.timeout == null
          ? source
          : source.timeout(
              handle.timeout!,
              onTimeout: (sink) {
                sink.add(
                  TavernGenerationFailed(
                    handle.target.attemptId,
                    const TavernGenerationError(
                      TavernGenerationErrorKind.timeout,
                      'Generation timed out.',
                    ),
                  ),
                );
              },
            );
      final iterator = StreamIterator<TavernGenerationEvent>(events);
      handle._iterator = iterator;
      while (!handle.cancellation.isCancelled && await iterator.moveNext()) {
        final event = iterator.current;
        if (handle.cancellation.isCancelled || handle._terminal) break;
        if (event.attemptId != handle.target.attemptId) continue;
        await _serialize(handle, () => _receive(handle, event));
        if (handle._terminal) break;
      }
      if (!handle._terminal && !handle.cancellation.isCancelled) {
        await _serialize(
          handle,
          () => _finish(
            handle,
            TavernGenerationStatus.failed,
            error: const TavernGenerationError(
              TavernGenerationErrorKind.invalidResponse,
              'Driver ended without completion.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!handle._terminal && !handle.cancellation.isCancelled) {
        await _serialize(
          handle,
          () => _finish(
            handle,
            TavernGenerationStatus.failed,
            error: const TavernGenerationError(
              TavernGenerationErrorKind.transport,
              'Generation driver failed.',
            ),
          ),
        );
      }
    } finally {
      await handle._iterator?.cancel();
      handle._iterator = null;
    }
  }

  Future<void> _serialize(
    TavernGenerationHandle handle,
    Future<void> Function() action,
  ) {
    final next = handle._operations.then((_) => action());
    handle._operations = next.catchError((Object _) {});
    return next;
  }

  Future<void> _receive(
    TavernGenerationHandle handle,
    TavernGenerationEvent event,
  ) async {
    if (handle._terminal || handle.cancellation.isCancelled) return;
    if (event is TavernReasoningUnavailable) {
      handle._pending.add((TavernContentKind.reasoningUnavailable, ''));
    } else if (event is TavernTextDelta ||
        event is TavernReasoningDelta ||
        event is TavernReasoningSummaryDelta) {
      final kind = event is TavernTextDelta
          ? TavernContentKind.text
          : event is TavernReasoningSummaryDelta
          ? TavernContentKind.reasoningSummary
          : TavernContentKind.reasoning;
      final value = event is TavernTextDelta
          ? event.text
          : event is TavernReasoningSummaryDelta
          ? event.text
          : (event as TavernReasoningDelta).text;
      if (value.isEmpty) return;
      if (handle._pending.isNotEmpty && handle._pending.last.$1 == kind) {
        final last = handle._pending.removeLast();
        handle._pending.add((kind, last.$2 + value));
      } else {
        handle._pending.add((kind, value));
      }
      handle._pendingLength += value.length;
      if (!handle._streamingPersisted) {
        await repository.updateAttempt(
          handle.target.attemptId,
          TavernGenerationStatus.streaming,
        );
        handle._streamingPersisted = true;
      }
      handle._emit(
        TavernGenerationSnapshot(
          handle.target,
          TavernExecutionPhase.streaming,
          pendingText: kind == TavernContentKind.text ? value : '',
          pendingReasoning: kind == TavernContentKind.reasoning ? value : '',
          pendingPart: TavernContentPart(
            id: '${handle.target.attemptId}:${handle._nextPartPosition + handle._pending.length - 1}',
            alternativeId: handle.target.alternativeId,
            generationAttemptId: handle.target.attemptId,
            position: handle._nextPartPosition + handle._pending.length - 1,
            kind: kind,
            text: handle._pending.last.$2,
            createdAt: DateTime.now().toUtc(),
          ),
        ),
      );
      if (handle._pendingLength >= flushCharacters) await _flush(handle);
    } else if (event is TavernGenerationComplete) {
      await _finish(handle, TavernGenerationStatus.completed);
    } else if (event is TavernGenerationFailed) {
      await _finish(handle, TavernGenerationStatus.failed, error: event.error);
    }
  }

  List<TavernContentPart> _takeParts(TavernGenerationHandle handle) {
    final now = DateTime.now().toUtc();
    final parts = <TavernContentPart>[];
    for (final chunk in handle._pending) {
      final position = handle._nextPartPosition++;
      parts.add(
        TavernContentPart(
          id: '${handle.target.attemptId}:$position',
          alternativeId: handle.target.alternativeId,
          generationAttemptId: handle.target.attemptId,
          position: position,
          kind: chunk.$1,
          text: chunk.$2,
          metadata: switch (chunk.$1) {
            TavernContentKind.reasoning => const {'reasoningSource': 'native'},
            TavernContentKind.reasoningSummary => const {
              'reasoningSource': 'summary',
            },
            TavernContentKind.reasoningUnavailable => const {
              'reasoningSource': 'unavailable',
            },
            _ => const {},
          },
          createdAt: now,
        ),
      );
    }
    handle._pending.clear();
    handle._pendingLength = 0;
    return parts;
  }

  Future<void> _flush(TavernGenerationHandle handle) async {
    if (handle._pending.isEmpty) return;
    await repository.persistGenerationBatch(
      handle.target.attemptId,
      _takeParts(handle),
    );
  }

  Future<void> _finish(
    TavernGenerationHandle handle,
    TavernGenerationStatus status, {
    TavernGenerationError? error,
  }) async {
    if (handle._terminal) return;
    if (status == TavernGenerationStatus.completed &&
        handle.cancellation.isCancelled) {
      status = TavernGenerationStatus.cancelled;
    }
    final parts = _takeParts(handle);
    try {
      await repository.persistGenerationBatch(
        handle.target.attemptId,
        parts,
        terminalStatus: status,
        reason:
            error?.reasonCode ??
            error?.kind.name ??
            (status == TavernGenerationStatus.cancelled
                ? 'user_cancelled'
                : null),
        selectAlternative:
            status == TavernGenerationStatus.completed &&
            (handle.kind == TavernGenerationCommandKind.regenerate ||
                handle.kind == TavernGenerationCommandKind.retry),
        expectedSelectedAlternativeId: handle._expectedSelectedAlternativeId,
      );
      handle._terminal = true;
      final phase = switch (status) {
        TavernGenerationStatus.completed => TavernExecutionPhase.completed,
        TavernGenerationStatus.cancelled => TavernExecutionPhase.cancelled,
        _ => TavernExecutionPhase.failed,
      };
      handle._emit(
        TavernGenerationSnapshot(handle.target, phase, error: error),
      );
    } catch (_) {
      handle._terminal = true;
      handle._emit(
        TavernGenerationSnapshot(
          handle.target,
          TavernExecutionPhase.failed,
          error: const TavernGenerationError(
            TavernGenerationErrorKind.invariant,
            'Generation finalization failed.',
          ),
        ),
      );
    } finally {
      _active.remove(handle.target.sessionId);
      _releaseScope(handle);
      while (_commands.length > 256) {
        final oldest = _commands.keys.first;
        if (!_commands[oldest]!._terminal) break;
        _commands.remove(oldest);
      }
      if (!handle._done.isCompleted) handle._done.complete(handle.snapshot);
      await handle._updates.close();
    }
  }

  Future<void> cancel(TavernGenerationHandle handle) async {
    if (handle._terminal) return;
    handle.cancellation.cancel();
    await handle._iterator?.cancel();
    await _serialize(
      handle,
      () => _finish(handle, TavernGenerationStatus.cancelled),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    await Future.wait(_active.values.toList().map(cancel));
  }
}
