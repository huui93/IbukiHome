part of 'sqlite_tavern_repository.dart';

class TavernWorldInfoBackup {
  static Map<String, List<Map<String, Object?>>> rewrite(
    Map<String, List<Map<String, Object?>>> collections,
    Map<String, Map<String, String>> mappings,
  ) {
    final result = {
      for (final entry in collections.entries)
        entry.key: entry.value.map(Map<String, Object?>.from).toList(),
    };
    String id(String collection, String value) =>
        mappings[collection]?[value] ?? value;
    String marker(String value) {
      if (value.isEmpty) return value;
      if (RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) return value;
      throw const FormatException('Invalid durable history fingerprint.');
    }

    TavernLoreIdentity lore(TavernLoreIdentity value) =>
        (id('worldBooks', value.$1), id('loreEntries', value.$2));
    TavernLoreTimer timer(TavernLoreTimer t) => TavernLoreTimer(
      bookId: id('worldBooks', t.bookId),
      entryId: id('loreEntries', t.entryId),
      activatedAt: t.activatedAt,
      definitionFingerprint: t.definitionFingerprint,
      stickyUntil: t.stickyUntil,
      cooldownUntil: t.cooldownUntil,
      delayMessages: t.delayMessages,
    );
    TavernWorldInfoData data(TavernWorldInfoData d) => TavernWorldInfoData(
      messageCount: d.messageCount,
      historyMarker: marker(d.historyMarker),
      timers: List.unmodifiable(d.timers.map(timer)),
    );
    TavernWorldInfoDelta delta(TavernWorldInfoDelta d) => TavernWorldInfoDelta(
      messageCount: d.messageCount,
      historyMarker: marker(d.historyMarker),
      upserts: List.unmodifiable(d.upserts.map(timer)),
      removed: List.unmodifiable(d.removed.map(lore)),
    );
    final sourceStates = {
      for (final row
          in collections['tavernWorldInfoStates'] ?? <Map<String, Object?>>[])
        row['id'] as String: _SQLiteTavernWorldInfo.state(row),
    };
    final sourceJournals =
        (collections['tavernWorldInfoJournal'] ?? <Map<String, Object?>>[])
            .map(_SQLiteTavernWorldInfo.journal)
            .toList();
    final sourceJournalsByAttempt = {
      for (final record in sourceJournals) record.plan.attemptId: record,
    };
    final baseHashes = <String, Map<int, (String, String)>>{};
    for (final state in sourceStates.values) {
      var original = state.initialData;
      var mapped = data(original);
      var version = 0;
      final hashes = baseHashes[state.storyLineId] = {
        0: (original.fingerprint, mapped.fingerprint),
      };
      final history =
          sourceJournals
              .where(
                (j) =>
                    j.plan.storyLineId == state.storyLineId &&
                    j.outcome == TavernReconciliationOutcome.committed,
              )
              .toList()
            ..sort(
              (a, b) => a.committedVersion!.compareTo(b.committedVersion!),
            );
      for (final record in history) {
        if (record.plan.expectedVersion != version ||
            record.committedVersion != version + 1 ||
            record.plan.baseFingerprint != original.fingerprint) {
          throw const FormatException('Archive durable history conflict.');
        }
        original = record.plan.delta.apply(original);
        mapped = delta(record.plan.delta).apply(mapped);
        version++;
        hashes[version] = (original.fingerprint, mapped.fingerprint);
      }
      final blocked = sourceJournals.any(
        (j) =>
            j.plan.storyLineId == state.storyLineId &&
            j.outcome == TavernReconciliationOutcome.conflict,
      );
      if (!blocked &&
          (version != state.version ||
              original.fingerprint != state.data.fingerprint)) {
        throw const FormatException('Archive durable snapshot mismatch.');
      }
    }
    result['tavernWorldInfoStates'] = sourceStates.values
        .map(
          (s) => _SQLiteTavernWorldInfo.stateRow(
            TavernWorldInfoSnapshot(
              sessionId: id('tavernSessions', s.sessionId),
              storyLineId: id('tavernStoryLines', s.storyLineId),
              version: s.version,
              data: data(s.data),
              initialData: data(s.initialData),
              provenance: s.provenance,
              lastAttemptId: s.lastAttemptId == null
                  ? null
                  : id('tavernGenerationAttempts', s.lastAttemptId!),
              initialAttemptId: s.initialAttemptId == null
                  ? null
                  : id('tavernGenerationAttempts', s.initialAttemptId!),
            ),
          ),
        )
        .toList();
    final mappedJournals = <String, TavernWorldInfoJournal>{};
    for (final j in sourceJournals) {
      final p = j.plan;
      final hashes = baseHashes[p.storyLineId]?[p.expectedVersion];
      if (hashes != null && hashes.$1 != p.baseFingerprint) {
        throw const FormatException('Archive plan base mismatch.');
      }
      if (hashes == null && j.outcome != TavernReconciliationOutcome.conflict) {
        throw const FormatException('Archive plan checkpoint missing.');
      }
      final mapped = TavernWorldInfoPlan(
        attemptId: id('tavernGenerationAttempts', p.attemptId),
        sessionId: id('tavernSessions', p.sessionId),
        storyLineId: id('tavernStoryLines', p.storyLineId),
        turnId: id('tavernTurns', p.turnId),
        alternativeId: id('tavernAlternatives', p.alternativeId),
        compileFingerprint: p.compileFingerprint,
        requestFingerprint: p.requestFingerprint,
        expectedVersion: p.expectedVersion,
        baseFingerprint: hashes?.$2 ?? p.baseFingerprint,
        delta: delta(p.delta),
        included: List.unmodifiable(p.included.map(lore)),
      );
      mappedJournals[p.attemptId] = TavernWorldInfoJournal(
        plan: mapped,
        outcome: hashes == null
            ? TavernReconciliationOutcome.conflict
            : j.outcome,
        committedVersion: j.committedVersion,
        reason: hashes == null ? 'archive_checkpoint_unavailable' : j.reason,
        originalPlanIdentity:
            j.originalPlanIdentity ??
            (mapped.identity == p.identity ? null : p.identity),
      );
    }
    result['tavernWorldInfoJournal'] = mappedJournals.values
        .map(_SQLiteTavernWorldInfo.journalRow)
        .toList();
    for (final row
        in result['tavernGenerationAttempts'] ?? <Map<String, Object?>>[]) {
      final journal = mappedJournals[row['id']];
      final metadata = Map<String, dynamic>.from(
        jsonDecode(row['metadata_json'] as String) as Map,
      );
      if (journal == null) {
        if (metadata.containsKey('worldInfoPlanIdentity')) {
          throw const FormatException('Archive Attempt journal missing.');
        }
        continue;
      }
      final old = sourceJournalsByAttempt[row['id']]!;
      if (metadata['worldInfoPlanIdentity'] != old.plan.identity ||
          metadata['worldInfoCompileFingerprint'] !=
              old.plan.compileFingerprint ||
          metadata['worldInfoRequestFingerprint'] !=
              old.plan.requestFingerprint) {
        throw const FormatException('Archive Attempt provenance mismatch.');
      }
      metadata['worldInfoPlanIdentity'] = journal.plan.identity;
      if (journal.originalPlanIdentity != null) {
        metadata['originalWorldInfoPlanIdentity'] =
            journal.originalPlanIdentity;
      }
      row['metadata_json'] = jsonEncode(metadata);
    }
    return result;
  }

  static Future<void> validate(DatabaseExecutor db) async {
    if (await _SQLiteTavernWorldInfo.hasOrphanPlan(db)) {
      throw const FormatException('Archive Attempt journal missing.');
    }
    final states = {
      for (final row in await db.query('tavern_world_info_states'))
        row['id'] as String: _SQLiteTavernWorldInfo.state(row),
    };
    final lines = {
      for (final row in await db.query('tavern_story_lines'))
        row['id'] as String: row,
    };
    if (!states.keys.toSet().containsAll(lines.keys)) {
      throw const FormatException('Archive missing durable Story Line state.');
    }
    final attempts = {
      for (final row in await db.rawQuery(
        '''SELECT g.* FROM tavern_generation_attempts g
      JOIN tavern_world_info_journal j ON j.attempt_id = g.id''',
      ))
        row['id'] as String: SQLiteTavernRepository._attempt(row),
    };
    final journals = (await db.query(
      'tavern_world_info_journal',
    )).map(_SQLiteTavernWorldInfo.journal).toList();
    for (final state in states.values) {
      if (lines[state.storyLineId]?['session_id'] != state.sessionId) {
        throw const FormatException('Archive state ownership mismatch.');
      }
      final blocked = journals.any(
        (j) =>
            j.plan.storyLineId == state.storyLineId &&
            j.outcome == TavernReconciliationOutcome.conflict,
      );
      for (final reference in [state.initialAttemptId, state.lastAttemptId]) {
        if (reference != null &&
            attempts[reference]?.sessionId != state.sessionId) {
          throw const FormatException(
            'Archive State Attempt ownership mismatch.',
          );
        }
      }
      if (state.lastAttemptId != null &&
          attempts[state.lastAttemptId]?.storyLineId != state.storyLineId) {
        throw const FormatException(
          'Archive State last Attempt scope mismatch.',
        );
      }
      if (!blocked) {
        final last = journals
            .where(
              (j) =>
                  j.plan.storyLineId == state.storyLineId &&
                  j.outcome == TavernReconciliationOutcome.committed &&
                  j.committedVersion == state.version,
            )
            .firstOrNull;
        if (replayWorldInfoState(state, journals, state.version).fingerprint !=
                state.data.fingerprint ||
            state.lastAttemptId != last?.plan.attemptId) {
          throw const FormatException(
            'Archive State version/reference mismatch.',
          );
        }
      }
    }
    for (final journal in journals) {
      final attempt = attempts[journal.plan.attemptId];
      if (attempt == null ||
          worldInfoIdentityError(journal, attempt) != null ||
          states[journal.plan.storyLineId]?.sessionId !=
              journal.plan.sessionId) {
        throw const FormatException('Archive reconciliation target mismatch.');
      }
      if (journal.outcome == TavernReconciliationOutcome.committed &&
          attempt.status != TavernGenerationStatus.completed) {
        throw const FormatException(
          'Archive commit without successful Attempt.',
        );
      }
    }
  }
}
