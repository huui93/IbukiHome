import '../../domain/tavern/tavern_models.dart';
import '../../domain/tavern/tavern_world_info.dart';
import '../repositories/tavern_repository.dart';
import '../repositories/tavern_world_info_repository.dart';
import '../repositories/tavern_reconciliation_rules.dart';

class InMemoryTavernRepository
    implements TavernRepository, TavernWorldInfoRepository {
  @override
  Future<Object> get generationScopeKey async => this;
  final sessions = <String, TavernSession>{};
  final lines = <String, TavernStoryLine>{};
  final participants = <String, TavernParticipant>{};
  final turns = <String, TavernTurn>{};
  final alternatives = <String, TavernAlternative>{};
  final lineSelections = <String, Map<String, String>>{};
  final parts = <String, TavernContentPart>{};
  final attempts = <String, TavernGenerationAttempt>{};
  final worldInfoStates = <String, TavernWorldInfoSnapshot>{};
  final worldInfoJournals = <String, TavernWorldInfoJournal>{};

  T _require<T>(T? value, String id) {
    if (value == null) throw StateError('Not found: $id');
    return value;
  }

  @override
  Future<TavernSession> createSession(
    TavernSession session,
    TavernStoryLine root, {
    List<TavernParticipant> participants = const [],
  }) async {
    if (sessions.containsKey(session.id) ||
        lines.containsKey(root.id) ||
        root.sessionId != session.id ||
        root.parentId != null ||
        root.originTurnId != null ||
        root.originAlternativeId != null ||
        session.activeStoryLineId != null) {
      throw StateError('Invalid session root.');
    }
    if (participants.map((p) => p.id).toSet().length != participants.length ||
        participants.map((p) => p.position).toSet().length !=
            participants.length ||
        participants.any(
          (p) =>
              this.participants.containsKey(p.id) ||
              p.sessionId != session.id ||
              p.id.isEmpty ||
              p.position < 0 ||
              ((p.kind == TavernParticipantKind.character ||
                      p.kind == TavernParticipantKind.persona) &&
                  (p.entityId?.isEmpty ?? true)),
        )) {
      throw ArgumentError('Invalid story participants.');
    }
    lines[root.id] = root;
    final saved = TavernSession(
      id: session.id,
      title: session.title,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      activeStoryLineId: root.id,
      worldAssetType: session.worldAssetType,
      worldAssetId: session.worldAssetId,
      personaType: session.personaType,
      personaId: session.personaId,
      runtimeConfigId: session.runtimeConfigId,
      metadata: session.metadata,
    );
    sessions[session.id] = saved;
    for (final participant in participants) {
      this.participants[participant.id] = participant;
    }
    worldInfoStates[root.id] = TavernWorldInfoSnapshot(
      sessionId: session.id,
      storyLineId: root.id,
    );
    return saved;
  }

  @override
  Future<List<TavernSession>> listSessions({
    bool archived = false,
    int limit = 100,
  }) async =>
      (sessions.values
              .where(
                (s) =>
                    s.deletedAt == null && (s.archivedAt != null) == archived,
              )
              .toList()
            ..sort((a, b) {
              final time = b.updatedAt.compareTo(a.updatedAt);
              return time == 0 ? a.id.compareTo(b.id) : time;
            }))
          .take(limit.clamp(1, 200))
          .toList(growable: false);

  @override
  Future<List<TavernStorySummary>> listStorySummaries({
    bool archived = false,
    int limit = 100,
  }) async {
    final result = <TavernStorySummary>[];
    for (final session in await listSessions(
      archived: archived,
      limit: limit,
    )) {
      final history = await loadTranscript(session.id);
      final texts = history.turns.isEmpty
          ? const <String>[]
          : history.turns.last.visibleParts
                .where((p) => p.kind == TavernContentKind.text)
                .map((p) => p.text ?? '')
                .toList();
      final text = texts.skip((texts.length - 4).clamp(0, texts.length)).join();
      result.add(
        TavernStorySummary(
          session: session,
          participants: await listParticipants(session.id),
          excerpt: text.length > 240 ? text.substring(text.length - 240) : text,
        ),
      );
    }
    return result;
  }

  @override
  Future<void> saveSession(TavernSession session) async {
    final old = _require(sessions[session.id], session.id);
    if (session.activeStoryLineId != old.activeStoryLineId ||
        session.createdAt != old.createdAt) {
      throw StateError('Session edit cannot change canonical line ownership.');
    }
    sessions[session.id] = session;
  }

  @override
  Future<List<TavernStoryLine>> listStoryLines(String sessionId) async =>
      (lines.values.where((l) => l.sessionId == sessionId).toList()
        ..sort((a, b) {
          final order = a.position.compareTo(b.position);
          return order == 0 ? a.id.compareTo(b.id) : order;
        }));

  @override
  Future<TavernSession> getSession(String id) async =>
      _require(sessions[id], id);

  @override
  Future<TavernParticipant> addParticipant(
    TavernParticipant participant,
  ) async {
    _require(sessions[participant.sessionId], participant.sessionId);
    if (participants.containsKey(participant.id) ||
        participant.position < 0 ||
        ((participant.kind == TavernParticipantKind.persona ||
                participant.kind == TavernParticipantKind.character) &&
            participant.entityId == null) ||
        participants.values.any(
          (p) =>
              p.sessionId == participant.sessionId &&
              p.position == participant.position,
        )) {
      throw StateError('Duplicate participant.');
    }
    participants[participant.id] = participant;
    return participant;
  }

  @override
  Future<List<TavernParticipant>> listParticipants(String sessionId) async =>
      participants.values.where((p) => p.sessionId == sessionId).toList()
        ..sort((a, b) => a.position.compareTo(b.position));

  @override
  Future<TavernStoryLine> createStoryLine(
    TavernStoryLine line, {
    bool activate = false,
  }) async {
    final parent = _require(lines[line.parentId], line.parentId ?? 'parent');
    final origin = _require(
      turns[line.originTurnId],
      line.originTurnId ?? 'origin',
    );
    final alt = _require(
      alternatives[line.originAlternativeId],
      line.originAlternativeId ?? 'alternative',
    );
    if (lines.containsKey(line.id) ||
        parent.sessionId != line.sessionId ||
        parent.archivedAt != null ||
        origin.storyLineId != parent.id ||
        alt.turnId != origin.id ||
        lines.values.any(
          (l) => l.sessionId == line.sessionId && l.position == line.position,
        )) {
      throw StateError('Invalid branch origin.');
    }
    final parentTranscript = await loadTranscript(
      line.sessionId,
      storyLineId: parent.id,
    );
    final originIndex = parentTranscript.turns.indexWhere(
      (item) => item.turn.id == origin.id,
    );
    if (originIndex < 0) throw StateError('Branch origin is not visible.');
    final selections = {
      for (final item in parentTranscript.turns.take(originIndex + 1))
        item.turn.id: item.turn.id == origin.id
            ? alt.id
            : item.selectedAlternative.id,
    };
    final checkpoint = forkWorldInfoSnapshot(
      line,
      parentTranscript.turns
          .take(originIndex + 1)
          .map((t) => (t.turn.id, selections[t.turn.id]!))
          .toList(),
      worldInfoStates,
      worldInfoJournals.values.toList(),
    );
    lineSelections[line.id] = selections;
    lines[line.id] = line;
    worldInfoStates[line.id] = checkpoint;
    if (activate) await selectStoryLine(line.sessionId, line.id);
    return line;
  }

  @override
  Future<TavernStoryLine> getStoryLine(String id) async =>
      _require(lines[id], id);

  @override
  Future<void> selectStoryLine(String sessionId, String storyLineId) async {
    final session = _require(sessions[sessionId], sessionId);
    final line = _require(lines[storyLineId], storyLineId);
    if (line.sessionId != sessionId || line.archivedAt != null) {
      throw StateError('Story line unavailable in session.');
    }
    sessions[sessionId] = TavernSession(
      id: session.id,
      title: session.title,
      createdAt: session.createdAt,
      updatedAt: DateTime.now(),
      activeStoryLineId: storyLineId,
      worldAssetType: session.worldAssetType,
      worldAssetId: session.worldAssetId,
      personaType: session.personaType,
      personaId: session.personaId,
      runtimeConfigId: session.runtimeConfigId,
      metadata: session.metadata,
      archivedAt: session.archivedAt,
      deletedAt: session.deletedAt,
    );
  }

  @override
  Future<void> archiveStoryLine(String id) async {
    final line = _require(lines[id], id);
    if (sessions[line.sessionId]?.activeStoryLineId == id ||
        lines.values.any((l) => l.parentId == id && l.archivedAt == null)) {
      throw StateError('Cannot archive active or parent story line.');
    }
    lines[id] = TavernStoryLine(
      id: line.id,
      sessionId: line.sessionId,
      name: line.name,
      position: line.position,
      createdAt: line.createdAt,
      parentId: line.parentId,
      originTurnId: line.originTurnId,
      originAlternativeId: line.originAlternativeId,
      archivedAt: DateTime.now(),
      metadata: line.metadata,
    );
  }

  @override
  Future<TavernTurn> appendTurn(
    TavernTurn turn,
    TavernAlternative first, {
    TavernGenerationAttempt? attempt,
    TavernWorldInfoPlan? reconciliation,
    List<TavernContentPart> initialParts = const [],
  }) async {
    final line = _require(lines[turn.storyLineId], turn.storyLineId);
    final participant = _require(
      participants[turn.participantId],
      turn.participantId,
    );
    if (turns.containsKey(turn.id) ||
        alternatives.containsKey(first.id) ||
        line.sessionId != turn.sessionId ||
        participant.sessionId != turn.sessionId ||
        line.archivedAt != null ||
        first.turnId != turn.id ||
        first.position != 0 ||
        turn.selectedAlternativeId != null ||
        turns.values.any(
          (t) =>
              t.storyLineId == turn.storyLineId && t.position == turn.position,
        ) ||
        (attempt != null &&
            (attempts.containsKey(attempt.id) ||
                attempt.turnId != turn.id ||
                attempt.alternativeId != first.id ||
                attempt.sessionId != turn.sessionId ||
                attempt.storyLineId != turn.storyLineId))) {
      throw StateError('Invalid initial turn bundle.');
    }
    final journal = _prepareWorldInfo(attempt, reconciliation);
    final partIds = <String>{}, positions = <int>{};
    for (final part in initialParts) {
      part.validate();
      if (part.alternativeId != first.id ||
          part.generationAttemptId != null ||
          parts.containsKey(part.id) ||
          !partIds.add(part.id) ||
          !positions.add(part.position)) {
        throw StateError('Invalid initial content.');
      }
    }
    final saved = TavernTurn(
      id: turn.id,
      sessionId: turn.sessionId,
      storyLineId: turn.storyLineId,
      position: turn.position,
      participantId: turn.participantId,
      role: turn.role,
      selectedAlternativeId: first.id,
      createdAt: turn.createdAt,
      updatedAt: turn.updatedAt,
      editedAt: turn.editedAt,
      metadata: turn.metadata,
    );
    turns[turn.id] = saved;
    alternatives[first.id] = first;
    for (final part in initialParts) {
      parts[part.id] = part;
    }
    if (attempt != null) attempts[attempt.id] = attempt;
    if (journal != null) worldInfoJournals[journal.plan.attemptId] = journal;
    return saved;
  }

  @override
  Future<TavernAlternative> addAlternative(
    TavernAlternative alternative, {
    TavernGenerationAttempt? attempt,
    TavernWorldInfoPlan? reconciliation,
  }) async {
    final turn = _require(turns[alternative.turnId], alternative.turnId);
    if (alternatives.containsKey(alternative.id) ||
        (attempt != null &&
            (attempts.containsKey(attempt.id) ||
                attempt.turnId != turn.id ||
                attempt.alternativeId != alternative.id ||
                attempt.sessionId != turn.sessionId ||
                attempt.storyLineId != turn.storyLineId)) ||
        alternatives.values.any(
          (a) =>
              a.turnId == alternative.turnId &&
              a.position == alternative.position,
        )) {
      throw StateError('Duplicate alternative.');
    }
    final journal = _prepareWorldInfo(attempt, reconciliation);
    alternatives[alternative.id] = alternative;
    if (attempt != null) attempts[attempt.id] = attempt;
    if (journal != null) worldInfoJournals[journal.plan.attemptId] = journal;
    return alternative;
  }

  @override
  Future<void> selectAlternative(String turnId, String alternativeId) async {
    final turn = _require(turns[turnId], turnId);
    final alt = _require(alternatives[alternativeId], alternativeId);
    if (alt.turnId != turnId) {
      throw StateError('Alternative belongs to another turn.');
    }
    turns[turnId] = TavernTurn(
      id: turn.id,
      sessionId: turn.sessionId,
      storyLineId: turn.storyLineId,
      position: turn.position,
      participantId: turn.participantId,
      role: turn.role,
      selectedAlternativeId: alternativeId,
      createdAt: turn.createdAt,
      updatedAt: DateTime.now(),
      editedAt: turn.editedAt,
      metadata: turn.metadata,
    );
  }

  @override
  Future<void> deleteAlternative(String id) async {
    final alt = _require(alternatives[id], id);
    if (turns[alt.turnId]?.selectedAlternativeId == id ||
        lines.values.any((line) => line.originAlternativeId == id) ||
        lineSelections.values.any((choices) => choices.containsValue(id))) {
      throw StateError('Alternative is selected or anchors a branch.');
    }
    if (worldInfoJournals.values.any(
      (j) =>
          j.plan.alternativeId == id &&
          j.outcome != TavernReconciliationOutcome.discarded,
    )) {
      throw const TavernReconciliationConflict('protected_history');
    }
    worldInfoJournals.removeWhere((_, j) => j.plan.alternativeId == id);
    alternatives.remove(id);
    parts.removeWhere((_, part) => part.alternativeId == id);
    attempts.removeWhere((_, attempt) => attempt.alternativeId == id);
  }

  @override
  Future<TavernContentPart> appendContentPart(TavernContentPart part) async {
    part.validate();
    _require(alternatives[part.alternativeId], part.alternativeId);
    if (part.generationAttemptId != null &&
        _require(
              attempts[part.generationAttemptId],
              part.generationAttemptId!,
            ).alternativeId !=
            part.alternativeId) {
      throw StateError('Content part crosses generation attempt target.');
    }
    if (parts.containsKey(part.id) ||
        parts.values.any(
          (p) =>
              p.alternativeId == part.alternativeId &&
              p.position == part.position,
        )) {
      throw StateError('Duplicate content position.');
    }
    parts[part.id] = part;
    return part;
  }

  @override
  Future<List<TavernContentPart>> listContentParts(
    String alternativeId,
  ) async =>
      parts.values.where((part) => part.alternativeId == alternativeId).toList()
        ..sort((a, b) => a.position.compareTo(b.position));

  @override
  Future<void> persistGenerationBatch(
    String attemptId,
    List<TavernContentPart> batch, {
    TavernGenerationStatus? terminalStatus,
    String? reason,
    bool selectAlternative = false,
    String? expectedSelectedAlternativeId,
  }) async {
    final attempt = _require(attempts[attemptId], attemptId);
    const terminal = {
      TavernGenerationStatus.completed,
      TavernGenerationStatus.failed,
      TavernGenerationStatus.cancelled,
    };
    if (terminal.contains(attempt.status) ||
        (terminalStatus != null && !terminal.contains(terminalStatus)) ||
        (selectAlternative &&
            terminalStatus != TavernGenerationStatus.completed)) {
      throw StateError('Invalid generation finalization.');
    }
    final existing = parts.values
        .where((part) => part.alternativeId == attempt.alternativeId)
        .map((part) => part.position)
        .toSet();
    final ids = parts.keys.toSet();
    for (final part in batch) {
      part.validate();
      if (part.generationAttemptId != attemptId ||
          part.alternativeId != attempt.alternativeId ||
          !existing.add(part.position) ||
          !ids.add(part.id)) {
        throw StateError('Invalid generation content batch.');
      }
    }
    if (worldInfoJournals.containsKey(attemptId)) {
      _require(worldInfoStates[attempt.storyLineId], attempt.storyLineId);
    }
    for (final part in batch) {
      parts[part.id] = part;
    }
    if (terminalStatus != null) {
      await updateAttempt(
        attemptId,
        terminalStatus,
        reason: reason,
        hasPartialContent:
            terminalStatus != TavernGenerationStatus.completed &&
            (batch.isNotEmpty ||
                parts.values.any(
                  (part) => part.generationAttemptId == attemptId,
                )),
      );
      if (selectAlternative &&
          (expectedSelectedAlternativeId == null ||
              turns[attempt.turnId]?.selectedAlternativeId ==
                  expectedSelectedAlternativeId)) {
        await this.selectAlternative(attempt.turnId, attempt.alternativeId);
      }
    }
  }

  @override
  Future<List<TavernGenerationAttempt>> recoverInterruptedAttempts() async {
    const terminal = {
      TavernGenerationStatus.completed,
      TavernGenerationStatus.failed,
      TavernGenerationStatus.cancelled,
    };
    final interrupted = attempts.values
        .where((attempt) => !terminal.contains(attempt.status))
        .toList(growable: false);
    for (final attempt in interrupted) {
      await updateAttempt(
        attempt.id,
        TavernGenerationStatus.failed,
        reason: 'runtime_restart',
        hasPartialContent: parts.values.any(
          (part) => part.generationAttemptId == attempt.id,
        ),
      );
    }
    return interrupted;
  }

  @override
  Future<TavernGenerationAttempt> recordAttempt(
    TavernGenerationAttempt attempt, {
    TavernWorldInfoPlan? reconciliation,
  }) async {
    final alt = _require(
      alternatives[attempt.alternativeId],
      attempt.alternativeId,
    );
    final turn = _require(turns[alt.turnId], alt.turnId);
    if (attempts.containsKey(attempt.id) ||
        turn.id != attempt.turnId ||
        turn.storyLineId != attempt.storyLineId ||
        turn.sessionId != attempt.sessionId ||
        attempts.values.any(
          (a) =>
              a.alternativeId == attempt.alternativeId &&
              a.position == attempt.position,
        )) {
      throw StateError('Invalid attempt.');
    }
    final journal = _prepareWorldInfo(attempt, reconciliation);
    attempts[attempt.id] = attempt;
    if (journal != null) worldInfoJournals[attempt.id] = journal;
    return attempt;
  }

  @override
  Future<void> updateAttempt(
    String id,
    TavernGenerationStatus status, {
    String? reason,
    bool hasPartialContent = false,
  }) async {
    final old = _require(attempts[id], id);
    const terminal = {
      TavernGenerationStatus.cancelled,
      TavernGenerationStatus.failed,
      TavernGenerationStatus.completed,
    };
    if (terminal.contains(old.status) ||
        (status.index <= old.status.index && !terminal.contains(status))) {
      throw StateError('Invalid attempt transition.');
    }
    final next = TavernGenerationAttempt(
      id: old.id,
      sessionId: old.sessionId,
      storyLineId: old.storyLineId,
      turnId: old.turnId,
      alternativeId: old.alternativeId,
      position: old.position,
      status: status,
      type: old.type,
      createdAt: old.createdAt,
      startedAt: old.startedAt ?? DateTime.now(),
      endedAt: terminal.contains(status) ? DateTime.now() : null,
      failureReason: status == TavernGenerationStatus.failed ? reason : null,
      cancelReason: status == TavernGenerationStatus.cancelled ? reason : null,
      providerReference: old.providerReference,
      modelReference: old.modelReference,
      hasPartialContent: hasPartialContent || old.hasPartialContent,
      metadata: old.metadata,
    );
    final journal = worldInfoJournals[id];
    if (journal != null && terminal.contains(status)) {
      final state = _require(worldInfoStates[old.storyLineId], old.storyLineId);
      final result = settleDurableWorldInfo(state, journal, next);
      worldInfoStates[old.storyLineId] = result.$1;
      worldInfoJournals[id] = result.$2;
    }
    attempts[id] = next;
  }

  @override
  Future<List<TavernGenerationAttempt>> listAttempts(
    String alternativeId,
  ) async =>
      attempts.values.where((a) => a.alternativeId == alternativeId).toList()
        ..sort((a, b) => a.position.compareTo(b.position));

  @override
  Future<TavernTranscriptProjection> loadTranscript(
    String sessionId, {
    String? storyLineId,
  }) async {
    final session = _require(sessions[sessionId], sessionId);
    final line = _require(
      lines[storyLineId ?? session.activeStoryLineId],
      storyLineId ?? session.activeStoryLineId ?? 'active line',
    );
    if (line.sessionId != sessionId) {
      throw StateError('Cross-session transcript.');
    }
    final visible = <TavernTurn>[];
    final overrides = lineSelections[line.id] ?? const <String, String>{};
    final visiting = <String>{};
    void collect(TavernStoryLine current) {
      if (!visiting.add(current.id)) throw StateError('Story line cycle.');
      if (current.parentId != null) {
        collect(_require(lines[current.parentId], current.parentId!));
        final index = visible.indexWhere(
          (turn) => turn.id == current.originTurnId,
        );
        if (index < 0) throw StateError('Branch origin is not visible.');
        visible.removeRange(index + 1, visible.length);
      }
      final own =
          turns.values.where((turn) => turn.storyLineId == current.id).toList()
            ..sort((a, b) => a.position.compareTo(b.position));
      visible.addAll(own);
      visiting.remove(current.id);
    }

    collect(line);
    final projections = visible
        .map((turn) {
          final alts =
              alternatives.values.where((a) => a.turnId == turn.id).toList()
                ..sort((a, b) => a.position.compareTo(b.position));
          final selected = _require(
            alternatives[overrides[turn.id] ?? turn.selectedAlternativeId],
            turn.id,
          );
          final selectedParts =
              parts.values.where((p) => p.alternativeId == selected.id).toList()
                ..sort((a, b) => a.position.compareTo(b.position));
          return TavernTurnProjection(
            turn: turn,
            selectedAlternative: selected,
            alternatives: alts,
            selectedParts: selectTavernContentParts(
              selectedParts,
              attempts.values
                  .where((a) => a.alternativeId == selected.id)
                  .toList(),
            ),
          );
        })
        .toList(growable: false);
    return TavernTranscriptProjection(
      session: session,
      storyLine: line,
      turns: projections,
    );
  }

  @override
  Future<void> archiveSession(String id) async {
    final session = _require(sessions[id], id);
    sessions[id] = TavernSession(
      id: session.id,
      title: session.title,
      createdAt: session.createdAt,
      updatedAt: DateTime.now(),
      activeStoryLineId: session.activeStoryLineId,
      worldAssetType: session.worldAssetType,
      worldAssetId: session.worldAssetId,
      personaType: session.personaType,
      personaId: session.personaId,
      runtimeConfigId: session.runtimeConfigId,
      metadata: session.metadata,
      archivedAt: DateTime.now(),
      deletedAt: session.deletedAt,
    );
  }

  @override
  Future<void> deleteSession(String id) async {
    _require(sessions[id], id);
    worldInfoStates.removeWhere((_, s) => s.sessionId == id);
    worldInfoJournals.removeWhere((_, j) => j.plan.sessionId == id);
    final ownTurnIds = turns.values
        .where((turn) => turn.sessionId == id)
        .map((turn) => turn.id)
        .toSet();
    final ownAltIds = alternatives.values
        .where((alt) => ownTurnIds.contains(alt.turnId))
        .map((alt) => alt.id)
        .toSet();
    attempts.removeWhere((_, attempt) => attempt.sessionId == id);
    parts.removeWhere((_, part) => ownAltIds.contains(part.alternativeId));
    alternatives.removeWhere((_, alt) => ownAltIds.contains(alt.id));
    turns.removeWhere((_, turn) => turn.sessionId == id);
    lines.removeWhere((_, line) => line.sessionId == id);
    lineSelections.removeWhere((lineId, _) => !lines.containsKey(lineId));
    participants.removeWhere((_, participant) => participant.sessionId == id);
    sessions.remove(id);
  }

  TavernWorldInfoJournal? _prepareWorldInfo(
    TavernGenerationAttempt? attempt,
    TavernWorldInfoPlan? plan,
  ) {
    if (plan == null) {
      if (attempt?.metadata.containsKey('worldInfoPlanIdentity') == true) {
        throw const TavernReconciliationConflict('missing_plan');
      }
      return null;
    }
    if (attempt == null) {
      throw const TavernReconciliationConflict('missing_attempt');
    }
    final snapshot = _require(
      worldInfoStates[attempt.storyLineId],
      attempt.storyLineId,
    );
    final frozen = TavernWorldInfoPlan.fromJson(
      Map<String, dynamic>.from(plan.toJson()),
    );
    validateWorldInfoPreparation(
      frozen,
      attempt,
      snapshot,
      worldInfoJournals.values.where(
        (j) => j.plan.storyLineId == attempt.storyLineId,
      ),
    );
    return TavernWorldInfoJournal(plan: frozen);
  }

  @override
  Future<TavernWorldInfoSnapshot> loadWorldInfoState(
    String sessionId,
    String storyLineId,
  ) async {
    final snapshot = _require(worldInfoStates[storyLineId], storyLineId);
    if (snapshot.sessionId != sessionId) {
      throw const TavernReconciliationConflict('state_scope');
    }
    return snapshot;
  }

  @override
  Future<TavernWorldInfoJournal?> getWorldInfoJournal(String attemptId) async =>
      worldInfoJournals[attemptId];

  @override
  Future<void> reconcileWorldInfo() async {
    if (attempts.values.any(
      (a) =>
          a.metadata.containsKey('worldInfoPlanIdentity') &&
          !worldInfoJournals.containsKey(a.id),
    )) {
      throw const TavernReconciliationConflict('missing_journal');
    }
    for (final id in worldInfoJournals.keys.toList()) {
      await reconcileWorldInfoAttempt(id);
    }
    final histories = <String, List<TavernWorldInfoJournal>>{};
    for (final record in worldInfoJournals.values) {
      histories.putIfAbsent(record.plan.storyLineId, () => []).add(record);
    }
    for (final snapshot in worldInfoStates.values) {
      final history =
          histories[snapshot.storyLineId] ?? const <TavernWorldInfoJournal>[];
      if (history.any(
        (j) => j.outcome == TavernReconciliationOutcome.conflict,
      )) {
        continue;
      }
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
        worldInfoJournals[marker.plan.attemptId] = marker.settled(
          TavernReconciliationOutcome.conflict,
          reason: 'state_integrity',
        );
      }
    }
  }

  @override
  Future<TavernReconciliationOutcome> reconcileWorldInfoAttempt(
    String attemptId,
  ) async {
    final journal = _require(worldInfoJournals[attemptId], attemptId);
    final attempt = _require(attempts[attemptId], attemptId);
    final snapshot = _require(
      worldInfoStates[attempt.storyLineId],
      attempt.storyLineId,
    );
    final result = settleDurableWorldInfo(snapshot, journal, attempt);
    worldInfoStates[attempt.storyLineId] = result.$1;
    worldInfoJournals[attemptId] = result.$2;
    return result.$2.outcome;
  }

  @override
  Future<void> requireWorldInfoReady(
    String sessionId,
    String storyLineId,
  ) async {
    await loadWorldInfoState(sessionId, storyLineId);
    if (worldInfoJournals.values.any(
      (j) =>
          j.plan.sessionId == sessionId &&
          j.plan.storyLineId == storyLineId &&
          (j.outcome == TavernReconciliationOutcome.prepared ||
              j.outcome == TavernReconciliationOutcome.conflict),
    )) {
      throw const TavernReconciliationConflict('pending_or_conflict');
    }
  }
}
