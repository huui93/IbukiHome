import '../../../domain/tavern/tavern_models.dart';
import '../prompt/prompt_models.dart';
import 'world_info_models.dart';
import 'world_info_runtime.dart';

typedef _Scope = (String sessionId, String storyLineId);

enum WorldInfoSettlement { committed, discarded, stale, duplicate }

class _PendingPlan {
  const _PendingPlan(this.attempt, this.plan, this.baseVersion);
  final TavernGenerationAttempt attempt;
  final WorldInfoActivationPlan plan;
  final int baseVersion;
}

// Transient application boundary; the generation orchestrator owns this ledger.
class WorldInfoAttemptLedger {
  WorldInfoAttemptLedger({this._runtime = const WorldInfoRuntime()});

  final WorldInfoRuntime _runtime;
  final Map<_Scope, WorldInfoRuntimeState> _states = {};
  final Map<_Scope, int> _versions = {};
  final Map<String, _PendingPlan> _pending = {};
  final Map<String, (TavernGenerationAttempt, WorldInfoSettlement)> _settled =
      {};

  WorldInfoRuntimeState stateFor(String sessionId, String storyLineId) =>
      _states[(sessionId, storyLineId)] ??
      WorldInfoRuntimeState(sessionId: sessionId, storyLineId: storyLineId);

  void restoreState(WorldInfoRuntimeState state, int version) {
    final scope = (state.sessionId, state.storyLineId);
    if (_pending.values.any(
      (p) =>
          p.attempt.sessionId == scope.$1 && p.attempt.storyLineId == scope.$2,
    )) {
      throw StateError('Cannot replace an active World Info plan.');
    }
    _states[scope] = state;
    _versions[scope] = version;
  }

  void releasePreparedMirror(String attemptId) => _pending.remove(attemptId);

  WorldInfoRuntimeState eligibleState(
    TavernGenerationAttempt attempt,
    CompiledPrompt compiled,
  ) {
    final pending = _pending[attempt.id];
    if (pending == null) throw StateError('World Info attempt has no plan.');
    _checkIdentity(pending.attempt, attempt);
    final included = _includedSources(pending.plan, compiled);
    final timed = Map<WorldInfoEntryId, WorldInfoTimedState>.of(
      pending.plan.nextState.timed,
    );
    for (var i = 0; i < pending.plan.activated.length; i++) {
      if (!included.contains(pending.plan.promptSources[i].id)) {
        timed.remove(pending.plan.activated[i]);
      }
    }
    final next = pending.plan.nextState;
    return WorldInfoRuntimeState(
      sessionId: next.sessionId,
      storyLineId: next.storyLineId,
      observedMessageCount: next.observedMessageCount,
      historyMarker: next.historyMarker,
      timed: Map.unmodifiable(timed),
    );
  }

  void seedBranch(WorldInfoRuntimeState snapshot) {
    final scope = (snapshot.sessionId, snapshot.storyLineId);
    if (_states.containsKey(scope) ||
        _pending.values.any(
          (item) =>
              item.attempt.sessionId == scope.$1 &&
              item.attempt.storyLineId == scope.$2,
        )) {
      throw StateError('World Info branch already has state or pending work.');
    }
    _states[scope] = WorldInfoRuntimeState(
      sessionId: snapshot.sessionId,
      storyLineId: snapshot.storyLineId,
      observedMessageCount: snapshot.observedMessageCount,
      historyMarker: snapshot.historyMarker,
      timed: Map.unmodifiable(snapshot.timed),
    );
    _versions[scope] = 0;
  }

  WorldInfoActivationPlan prepare({
    required TavernGenerationAttempt attempt,
    required List<WorldInfoEntry> entries,
    required WorldInfoActivationContext context,
    required WorldInfoRandomSource random,
    WorldInfoSettings settings = const WorldInfoSettings(),
  }) {
    if (attempt.sessionId != context.sessionId ||
        attempt.storyLineId != context.storyLineId ||
        !_matchesGenerationType(attempt.type, context.generationType) ||
        _terminal(attempt.status) ||
        _pending.containsKey(attempt.id) ||
        _settled.containsKey(attempt.id)) {
      throw StateError('Invalid or duplicate World Info attempt.');
    }
    final scope = (context.sessionId, context.storyLineId);
    final plan = _runtime.evaluate(
      entries: entries,
      context: context,
      state: stateFor(scope.$1, scope.$2),
      random: random,
      settings: settings,
    );
    _pending[attempt.id] = _PendingPlan(attempt, plan, _versions[scope] ?? 0);
    return plan;
  }

  WorldInfoSettlement settle({
    required TavernGenerationAttempt attempt,
    CompiledPrompt? compiledPrompt,
  }) {
    if (!_terminal(attempt.status)) {
      throw StateError('World Info attempt has no terminal outcome.');
    }
    final previous = _settled[attempt.id];
    if (previous != null) {
      _checkIdentity(previous.$1, attempt);
      if (previous.$1.status != attempt.status) {
        throw StateError('World Info attempt terminal outcome changed.');
      }
      return WorldInfoSettlement.duplicate;
    }
    final pending = _pending[attempt.id];
    if (pending == null) throw StateError('World Info attempt has no plan.');
    _checkIdentity(pending.attempt, attempt);
    final scope = (attempt.sessionId, attempt.storyLineId);
    if (attempt.status != TavernGenerationStatus.completed) {
      _pending.remove(attempt.id);
      _settled[attempt.id] = (attempt, WorldInfoSettlement.discarded);
      return WorldInfoSettlement.discarded;
    }
    if (compiledPrompt == null) {
      throw StateError('Completed World Info attempt needs a compiled prompt.');
    }
    final included = _includedSources(pending.plan, compiledPrompt);
    _pending.remove(attempt.id);
    if ((_versions[scope] ?? 0) != pending.baseVersion) {
      _settled[attempt.id] = (attempt, WorldInfoSettlement.stale);
      return WorldInfoSettlement.stale;
    }
    final timed = Map<WorldInfoEntryId, WorldInfoTimedState>.of(
      pending.plan.nextState.timed,
    );
    for (var index = 0; index < pending.plan.activated.length; index++) {
      if (!included.contains(pending.plan.promptSources[index].id)) {
        timed.remove(pending.plan.activated[index]);
      }
    }
    final next = pending.plan.nextState;
    _states[scope] = WorldInfoRuntimeState(
      sessionId: scope.$1,
      storyLineId: scope.$2,
      observedMessageCount: next.observedMessageCount,
      historyMarker: next.historyMarker,
      timed: Map.unmodifiable(timed),
    );
    _versions[scope] = pending.baseVersion + 1;
    _settled[attempt.id] = (attempt, WorldInfoSettlement.committed);
    return WorldInfoSettlement.committed;
  }

  static Set<String> _includedSources(
    WorldInfoActivationPlan plan,
    CompiledPrompt compiled,
  ) {
    final byId = <String, PromptCompileDecision>{};
    for (final decision in compiled.trace.decisions) {
      if (byId.containsKey(decision.sourceId)) {
        throw StateError('Duplicate compiled World Info source.');
      }
      byId[decision.sourceId] = decision;
    }
    final included = <String>{};
    for (final source in plan.promptSources) {
      final decision = byId[source.id];
      if (decision == null ||
          decision.sourceType != source.type ||
          decision.origin.type != source.origin.type ||
          decision.origin.id != source.origin.id ||
          decision.origin.parentId != source.origin.parentId) {
        throw StateError('Compiled prompt does not match World Info plan.');
      }
      if (decision.outcome == PromptCompileOutcome.included ||
          decision.outcome == PromptCompileOutcome.trimmed) {
        included.add(source.id);
      }
    }
    return included;
  }

  static bool _terminal(TavernGenerationStatus status) =>
      status == TavernGenerationStatus.completed ||
      status == TavernGenerationStatus.failed ||
      status == TavernGenerationStatus.cancelled;

  static bool _matchesGenerationType(
    TavernGenerationType attemptType,
    WorldInfoGenerationType scanType,
  ) => switch (scanType) {
    WorldInfoGenerationType.normal =>
      attemptType == TavernGenerationType.normal,
    WorldInfoGenerationType.regenerate =>
      attemptType == TavernGenerationType.regenerate ||
          attemptType == TavernGenerationType.alternative,
    WorldInfoGenerationType.continueTurn =>
      attemptType == TavernGenerationType.continueTurn,
  };

  static void _checkIdentity(
    TavernGenerationAttempt expected,
    TavernGenerationAttempt actual,
  ) {
    if (expected.id != actual.id ||
        expected.sessionId != actual.sessionId ||
        expected.storyLineId != actual.storyLineId ||
        expected.turnId != actual.turnId ||
        expected.alternativeId != actual.alternativeId) {
      throw StateError('World Info attempt identity changed.');
    }
  }
}
