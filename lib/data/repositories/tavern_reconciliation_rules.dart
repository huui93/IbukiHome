import '../../domain/tavern/tavern_models.dart';
import '../../domain/tavern/tavern_world_info.dart';

void validateWorldInfoPreparation(
  TavernWorldInfoPlan plan,
  TavernGenerationAttempt attempt,
  TavernWorldInfoSnapshot snapshot,
  Iterable<TavernWorldInfoJournal> records,
) {
  TavernWorldInfoPlan.fromJson(Map<String, dynamic>.from(plan.toJson()));
  final record = TavernWorldInfoJournal(plan: plan);
  if (worldInfoIdentityError(record, attempt) != null ||
      snapshot.sessionId != plan.sessionId ||
      snapshot.storyLineId != plan.storyLineId ||
      snapshot.version != plan.expectedVersion ||
      snapshot.data.fingerprint != plan.baseFingerprint ||
      records.any(
        (r) =>
            r.plan.attemptId == plan.attemptId ||
            r.outcome == TavernReconciliationOutcome.prepared ||
            r.outcome == TavernReconciliationOutcome.conflict,
      )) {
    throw const TavernReconciliationConflict('invalid_preparation');
  }
}

String? worldInfoIdentityError(
  TavernWorldInfoJournal journal,
  TavernGenerationAttempt attempt,
) {
  final p = journal.plan;
  if (p.attemptId != attempt.id ||
      p.sessionId != attempt.sessionId ||
      p.storyLineId != attempt.storyLineId ||
      p.turnId != attempt.turnId ||
      p.alternativeId != attempt.alternativeId) {
    return 'target_identity';
  }
  if (attempt.metadata['worldInfoPlanIdentity'] != p.identity ||
      attempt.metadata['worldInfoCompileFingerprint'] != p.compileFingerprint ||
      attempt.metadata['worldInfoRequestFingerprint'] != p.requestFingerprint) {
    return 'compile_identity';
  }
  return null;
}

(TavernWorldInfoSnapshot, TavernWorldInfoJournal) settleDurableWorldInfo(
  TavernWorldInfoSnapshot state,
  TavernWorldInfoJournal journal,
  TavernGenerationAttempt attempt,
) {
  final error = worldInfoIdentityError(journal, attempt);
  if (error != null) {
    return (
      state,
      journal.settled(TavernReconciliationOutcome.conflict, reason: error),
    );
  }
  if (journal.outcome == TavernReconciliationOutcome.committed ||
      journal.outcome == TavernReconciliationOutcome.discarded) {
    final successful = journal.outcome == TavernReconciliationOutcome.committed;
    final discardedTerminal =
        attempt.status == TavernGenerationStatus.failed ||
        attempt.status == TavernGenerationStatus.cancelled;
    if (successful
        ? attempt.status != TavernGenerationStatus.completed
        : !discardedTerminal) {
      return (
        state,
        journal.settled(
          TavernReconciliationOutcome.conflict,
          reason: 'terminal_identity',
        ),
      );
    }
    if (successful &&
        (journal.committedVersion != journal.plan.expectedVersion + 1 ||
            state.version < journal.committedVersion!)) {
      return (
        state,
        journal.settled(
          TavernReconciliationOutcome.conflict,
          reason: 'committed_state_missing',
        ),
      );
    }
    return (state, journal);
  }
  if (attempt.status == TavernGenerationStatus.failed ||
      attempt.status == TavernGenerationStatus.cancelled) {
    return (state, journal.settled(TavernReconciliationOutcome.discarded));
  }
  if (attempt.status != TavernGenerationStatus.completed) {
    return (state, journal);
  }
  if (state.sessionId != journal.plan.sessionId ||
      state.storyLineId != journal.plan.storyLineId ||
      state.version != journal.plan.expectedVersion ||
      state.data.fingerprint != journal.plan.baseFingerprint) {
    return (
      state,
      journal.settled(
        TavernReconciliationOutcome.conflict,
        reason: 'state_version',
      ),
    );
  }
  final next = state.committed(journal.plan);
  return (
    next,
    journal.settled(
      TavernReconciliationOutcome.committed,
      version: next.version,
    ),
  );
}

TavernWorldInfoData replayWorldInfoState(
  TavernWorldInfoSnapshot state,
  Iterable<TavernWorldInfoJournal> journals,
  int version,
) {
  final ordered =
      journals
          .where(
            (j) =>
                j.plan.storyLineId == state.storyLineId &&
                j.outcome == TavernReconciliationOutcome.committed &&
                j.committedVersion! <= version,
          )
          .toList()
        ..sort((a, b) => a.committedVersion!.compareTo(b.committedVersion!));
  var data = state.initialData;
  var current = 0;
  for (final journal in ordered) {
    if (journal.plan.expectedVersion != current ||
        journal.committedVersion != current + 1 ||
        journal.plan.baseFingerprint != data.fingerprint) {
      throw const TavernReconciliationConflict('checkpoint_history');
    }
    data = journal.plan.delta.apply(data);
    current++;
  }
  if (current != version) {
    throw const TavernReconciliationConflict('checkpoint_unavailable');
  }
  return data;
}

TavernWorldInfoSnapshot forkWorldInfoSnapshot(
  TavernStoryLine child,
  List<(String turnId, String alternativeId)> inherited,
  Map<String, TavernWorldInfoSnapshot> states,
  List<TavernWorldInfoJournal> journals,
) {
  for (final selection in inherited.reversed) {
    final records = journals
        .where(
          (j) =>
              j.plan.turnId == selection.$1 &&
              j.plan.alternativeId == selection.$2,
        )
        .toList();
    if (records.any(
      (j) =>
          j.outcome == TavernReconciliationOutcome.conflict ||
          j.outcome == TavernReconciliationOutcome.prepared,
    )) {
      throw const TavernReconciliationConflict('fork_unsettled');
    }
    final committed =
        records
            .where((j) => j.outcome == TavernReconciliationOutcome.committed)
            .toList()
          ..sort((a, b) => b.committedVersion!.compareTo(a.committedVersion!));
    if (committed.isNotEmpty) {
      final origin = committed.first;
      final parent = states[origin.plan.storyLineId];
      if (parent == null) {
        throw const TavernReconciliationConflict('fork_checkpoint_missing');
      }
      final data = replayWorldInfoState(
        parent,
        journals,
        origin.committedVersion!,
      );
      return TavernWorldInfoSnapshot(
        sessionId: child.sessionId,
        storyLineId: child.id,
        data: data,
        initialData: data,
        provenance: TavernWorldInfoProvenance.forkCheckpoint,
        initialAttemptId: origin.plan.attemptId,
      );
    }
  }
  final parent = states[child.parentId];
  if (parent == null) {
    throw const TavernReconciliationConflict('fork_parent_state_missing');
  }
  return TavernWorldInfoSnapshot(
    sessionId: child.sessionId,
    storyLineId: child.id,
    provenance: parent.provenance == TavernWorldInfoProvenance.fresh
        ? TavernWorldInfoProvenance.fresh
        : TavernWorldInfoProvenance.historicalUnavailable,
  );
}
