part of 'sqlite_tavern_repository.dart';

class _SQLiteTavernWorldInfo {
  _SQLiteTavernWorldInfo(this.db);
  final DatabaseExecutor db;
  static Map<String, Object?> stateRow(TavernWorldInfoSnapshot s) => {
    'id': s.storyLineId,
    'session_id': s.sessionId,
    'story_line_id': s.storyLineId,
    'version': s.version,
    'data_json': jsonEncode(s.data.toJson()),
    'initial_data_json': jsonEncode(s.initialData.toJson()),
    'provenance': s.provenance.name,
    'last_attempt_id': s.lastAttemptId,
    'initial_attempt_id': s.initialAttemptId,
  };
  static TavernWorldInfoSnapshot state(Map<String, Object?> row) {
    final result = TavernWorldInfoSnapshot(
      sessionId: row['session_id'] as String,
      storyLineId: row['story_line_id'] as String,
      version: row['version'] as int,
      data: TavernWorldInfoData.fromJson(
        jsonDecode(row['data_json'] as String) as Map<String, dynamic>,
      ),
      initialData: TavernWorldInfoData.fromJson(
        jsonDecode(row['initial_data_json'] as String) as Map<String, dynamic>,
      ),
      provenance: TavernWorldInfoProvenance.values.byName(
        row['provenance'] as String,
      ),
      lastAttemptId: row['last_attempt_id'] as String?,
      initialAttemptId: row['initial_attempt_id'] as String?,
    );
    if (row['id'] != result.storyLineId || result.version < 0) {
      throw const FormatException('Invalid durable state.');
    }
    return result;
  }

  static Map<String, Object?> journalRow(TavernWorldInfoJournal j) => {
    'id': j.plan.attemptId,
    'attempt_id': j.plan.attemptId,
    'session_id': j.plan.sessionId,
    'story_line_id': j.plan.storyLineId,
    'turn_id': j.plan.turnId,
    'alternative_id': j.plan.alternativeId,
    'expected_version': j.plan.expectedVersion,
    'compile_fingerprint': j.plan.compileFingerprint,
    'request_fingerprint': j.plan.requestFingerprint,
    'plan_identity': j.plan.identity,
    'plan_json': jsonEncode(j.plan.toJson()),
    'outcome': j.outcome.name,
    'committed_version': j.committedVersion,
    'reason': j.reason,
    'original_plan_identity': j.originalPlanIdentity,
  };
  static TavernWorldInfoJournal journal(Map<String, Object?> row) {
    final plan = TavernWorldInfoPlan.fromJson(
      jsonDecode(row['plan_json'] as String) as Map<String, dynamic>,
    );
    if (row['id'] != plan.attemptId ||
        row['attempt_id'] != plan.attemptId ||
        row['session_id'] != plan.sessionId ||
        row['story_line_id'] != plan.storyLineId ||
        row['turn_id'] != plan.turnId ||
        row['alternative_id'] != plan.alternativeId ||
        row['expected_version'] != plan.expectedVersion ||
        row['compile_fingerprint'] != plan.compileFingerprint ||
        row['request_fingerprint'] != plan.requestFingerprint ||
        row['plan_identity'] != plan.identity) {
      throw const FormatException('Invalid durable journal identity.');
    }
    return TavernWorldInfoJournal(
      plan: plan,
      outcome: TavernReconciliationOutcome.values.byName(
        row['outcome'] as String,
      ),
      committedVersion: row['committed_version'] as int?,
      reason: row['reason'] as String?,
      originalPlanIdentity: row['original_plan_identity'] as String?,
    );
  }

  Future<TavernWorldInfoSnapshot> load(String sessionId, String lineId) async {
    final rows = await db.query(
      'tavern_world_info_states',
      where: 'id = ? AND session_id = ?',
      whereArgs: [lineId, sessionId],
    );
    if (rows.length != 1) {
      throw const TavernReconciliationConflict('missing_state');
    }
    return state(rows.single);
  }

  Future<TavernWorldInfoJournal?> get(String attemptId) async {
    final rows = await db.query(
      'tavern_world_info_journal',
      where: 'id = ?',
      whereArgs: [attemptId],
    );
    return rows.isEmpty ? null : journal(rows.single);
  }

  Future<void> ready(String sessionId, String lineId) async {
    await load(sessionId, lineId);
    final rows = await db.query(
      'tavern_world_info_journal',
      columns: ['id'],
      where:
          "session_id = ? AND story_line_id = ? AND outcome IN ('prepared','conflict')",
      whereArgs: [sessionId, lineId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw const TavernReconciliationConflict('pending_or_conflict');
    }
  }

  Future<void> prepare(
    TavernGenerationAttempt attempt,
    TavernWorldInfoPlan? plan,
  ) async {
    if (plan == null) {
      if (attempt.metadata.containsKey('worldInfoPlanIdentity')) {
        throw const TavernReconciliationConflict('missing_plan');
      }
      return;
    }
    final snapshot = await load(attempt.sessionId, attempt.storyLineId);
    final records = (await db.query(
      'tavern_world_info_journal',
      where: "story_line_id = ? AND outcome IN ('prepared','conflict')",
      whereArgs: [attempt.storyLineId],
    )).map(journal);
    validateWorldInfoPreparation(plan, attempt, snapshot, records);
    await db.insert(
      'tavern_world_info_journal',
      journalRow(TavernWorldInfoJournal(plan: plan)),
    );
  }

  Future<TavernReconciliationOutcome?> settle(
    TavernGenerationAttempt attempt,
  ) async {
    final record = await get(attempt.id);
    if (record == null) {
      if (attempt.metadata.containsKey('worldInfoPlanIdentity')) {
        throw const TavernReconciliationConflict('missing_journal');
      }
      return null;
    }
    final snapshot = await load(attempt.sessionId, attempt.storyLineId);
    return _apply(snapshot, record, attempt);
  }

  Future<TavernReconciliationOutcome> _apply(
    TavernWorldInfoSnapshot snapshot,
    TavernWorldInfoJournal record,
    TavernGenerationAttempt attempt,
  ) async {
    final result = settleDurableWorldInfo(snapshot, record, attempt);
    if (!identical(snapshot, result.$1)) {
      final changed = await db.update(
        'tavern_world_info_states',
        stateRow(result.$1),
        where: 'id = ? AND version = ?',
        whereArgs: [snapshot.storyLineId, snapshot.version],
      );
      if (changed != 1) throw const TavernReconciliationConflict('state_cas');
    }
    if (!identical(record, result.$2)) {
      await db.update(
        'tavern_world_info_journal',
        journalRow(result.$2),
        where: 'id = ?',
        whereArgs: [record.plan.attemptId],
      );
    }
    return result.$2.outcome;
  }

  Future<void> recover() async {
    if (await hasOrphanPlan(db)) {
      throw const TavernReconciliationConflict('missing_journal');
    }
    // Batch-read canonical targets/state once, not once per completed journal.
    final snapshots = {
      for (final row in await db.query('tavern_world_info_states'))
        row['id'] as String: state(row),
    };
    final attempts = {
      for (final row in await db.rawQuery(
        '''SELECT g.* FROM tavern_generation_attempts g
      JOIN tavern_world_info_journal j ON j.attempt_id = g.id''',
      ))
        row['id'] as String: SQLiteTavernRepository._attempt(row),
    };
    final rows = await db.query(
      'tavern_world_info_journal',
      orderBy: 'story_line_id, expected_version, id',
    );
    await _recoverRows(rows, snapshots, attempts);
  }

  static Future<bool> hasOrphanPlan(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      '''SELECT g.metadata_json FROM tavern_generation_attempts g
      LEFT JOIN tavern_world_info_journal j ON j.attempt_id = g.id
      WHERE j.id IS NULL''',
    );
    return rows.any(
      (row) =>
          SQLiteTavernRepository._map(
            row['metadata_json'],
          )['worldInfoPlanIdentity'] !=
          null,
    );
  }

  Future<void> _recoverRows(
    List<Map<String, Object?>> rows,
    Map<String, TavernWorldInfoSnapshot> snapshots,
    Map<String, TavernGenerationAttempt> attempts,
  ) async {
    final histories = <String, List<TavernWorldInfoJournal>>{};
    final blocked = <String>{};
    for (final row in rows) {
      TavernWorldInfoJournal record;
      try {
        record = journal(row);
      } on FormatException {
        await db.update(
          'tavern_world_info_journal',
          {'outcome': 'conflict', 'reason': 'journal_integrity'},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        blocked.add(row['story_line_id'] as String);
        continue;
      }
      final attempt = attempts[record.plan.attemptId];
      final snapshot = snapshots[record.plan.storyLineId];
      if (attempt == null || snapshot == null) {
        throw const TavernReconciliationConflict('missing_canonical_target');
      }
      final result = settleDurableWorldInfo(snapshot, record, attempt);
      histories.putIfAbsent(snapshot.storyLineId, () => []).add(result.$2);
      if (result.$2.outcome == TavernReconciliationOutcome.conflict) {
        blocked.add(snapshot.storyLineId);
      }
      if (!identical(snapshot, result.$1)) {
        await db.update(
          'tavern_world_info_states',
          stateRow(result.$1),
          where: 'id = ? AND version = ?',
          whereArgs: [snapshot.storyLineId, snapshot.version],
        );
        snapshots[snapshot.storyLineId] = result.$1;
      }
      if (!identical(record, result.$2)) {
        await db.update(
          'tavern_world_info_journal',
          journalRow(result.$2),
          where: 'id = ?',
          whereArgs: [record.plan.attemptId],
        );
      }
    }
    for (final snapshot in snapshots.values) {
      if (blocked.contains(snapshot.storyLineId)) continue;
      final history =
          histories[snapshot.storyLineId] ?? const <TavernWorldInfoJournal>[];
      try {
        final replayed = replayWorldInfoState(
          snapshot,
          history,
          snapshot.version,
        );
        final last = history
            .where(
              (j) =>
                  j.outcome == TavernReconciliationOutcome.committed &&
                  j.committedVersion == snapshot.version,
            )
            .firstOrNull;
        if (replayed.fingerprint != snapshot.data.fingerprint ||
            snapshot.lastAttemptId != last?.plan.attemptId) {
          throw const TavernReconciliationConflict('state_integrity');
        }
      } on TavernReconciliationConflict {
        if (history.isEmpty) rethrow;
        final marker = history.last;
        await db.update(
          'tavern_world_info_journal',
          journalRow(
            marker.settled(
              TavernReconciliationOutcome.conflict,
              reason: 'state_integrity',
            ),
          ),
          where: 'id = ?',
          whereArgs: [marker.plan.attemptId],
        );
      }
    }
  }

  Future<void> fork(
    TavernStoryLine line,
    List<(String, String)> inherited,
  ) async {
    final states = {
      for (final row in await db.query(
        'tavern_world_info_states',
        where: 'session_id = ?',
        whereArgs: [line.sessionId],
      ))
        row['id'] as String: state(row),
    };
    final records = (await db.query(
      'tavern_world_info_journal',
      where: 'session_id = ?',
      whereArgs: [line.sessionId],
    )).map(journal).toList();
    final snapshot = forkWorldInfoSnapshot(line, inherited, states, records);
    await db.insert('tavern_world_info_states', stateRow(snapshot));
  }
}
