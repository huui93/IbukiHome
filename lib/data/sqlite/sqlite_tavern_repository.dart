import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/tavern/tavern_models.dart';
import '../../domain/tavern/tavern_world_info.dart';
import '../repositories/tavern_repository.dart';
import '../repositories/tavern_world_info_repository.dart';
import '../repositories/tavern_reconciliation_rules.dart';
import 'ibuki_database.dart';

part 'sqlite_tavern_world_info.dart';
part 'sqlite_tavern_world_info_backup.dart';

class SQLiteTavernRepository
    implements TavernRepository, TavernWorldInfoRepository {
  SQLiteTavernRepository(this.database);
  final IbukiDatabase database;

  @override
  Future<Object> get generationScopeKey async {
    await database.open();
    return 'sqlite:${database.path!.toLowerCase()}';
  }

  static String _date(DateTime value) => value.toUtc().toIso8601String();
  static String? _maybeDate(DateTime? value) =>
      value == null ? null : _date(value);
  static DateTime _readDate(Object? value) => DateTime.parse(value! as String);
  static DateTime? _readMaybeDate(Object? value) =>
      value == null ? null : _readDate(value);
  static String _json(Map<String, Object?> value) => jsonEncode(value);
  static Map<String, Object?> _map(Object? value) =>
      Map<String, Object?>.from(jsonDecode(value! as String) as Map);
  static Map<String, Object?>? _maybeMap(Object? value) =>
      value == null ? null : _map(value);
  static T _enum<T extends Enum>(List<T> values, Object? name) =>
      values.firstWhere((value) => value.name == name);

  static Map<String, Object?> _sessionRow(TavernSession s) => {
    'id': s.id,
    'title': s.title,
    'world_asset_type': s.worldAssetType,
    'world_asset_id': s.worldAssetId,
    'persona_type': s.personaType,
    'persona_id': s.personaId,
    'runtime_config_id': s.runtimeConfigId,
    'active_story_line_id': s.activeStoryLineId,
    'metadata_json': _json(s.metadata),
    'created_at': _date(s.createdAt),
    'updated_at': _date(s.updatedAt),
    'archived_at': _maybeDate(s.archivedAt),
    'deleted_at': _maybeDate(s.deletedAt),
  };
  static TavernSession _session(Map<String, Object?> r) => TavernSession(
    id: r['id']! as String,
    title: r['title']! as String,
    createdAt: _readDate(r['created_at']),
    updatedAt: _readDate(r['updated_at']),
    activeStoryLineId: r['active_story_line_id'] as String?,
    worldAssetType: r['world_asset_type'] as String?,
    worldAssetId: r['world_asset_id'] as String?,
    personaType: r['persona_type'] as String?,
    personaId: r['persona_id'] as String?,
    runtimeConfigId: r['runtime_config_id'] as String?,
    metadata: _map(r['metadata_json']),
    archivedAt: _readMaybeDate(r['archived_at']),
    deletedAt: _readMaybeDate(r['deleted_at']),
  );
  static Map<String, Object?> _lineRow(TavernStoryLine s) => {
    'id': s.id,
    'session_id': s.sessionId,
    'parent_id': s.parentId,
    'origin_turn_id': s.originTurnId,
    'origin_alternative_id': s.originAlternativeId,
    'name': s.name,
    'position': s.position,
    'metadata_json': _json(s.metadata),
    'created_at': _date(s.createdAt),
    'archived_at': _maybeDate(s.archivedAt),
  };
  static TavernStoryLine _line(Map<String, Object?> r) => TavernStoryLine(
    id: r['id']! as String,
    sessionId: r['session_id']! as String,
    name: r['name']! as String,
    position: r['position']! as int,
    createdAt: _readDate(r['created_at']),
    parentId: r['parent_id'] as String?,
    originTurnId: r['origin_turn_id'] as String?,
    originAlternativeId: r['origin_alternative_id'] as String?,
    archivedAt: _readMaybeDate(r['archived_at']),
    metadata: _map(r['metadata_json']),
  );
  static Map<String, Object?> _turnRow(TavernTurn t) => {
    'id': t.id,
    'session_id': t.sessionId,
    'story_line_id': t.storyLineId,
    'position': t.position,
    'participant_id': t.participantId,
    'role': t.role.name,
    'selected_alternative_id': t.selectedAlternativeId,
    'created_at': _date(t.createdAt),
    'updated_at': _date(t.updatedAt),
    'edited_at': _maybeDate(t.editedAt),
    'metadata_json': _json(t.metadata),
  };
  static TavernTurn _turn(Map<String, Object?> r) => TavernTurn(
    id: r['id']! as String,
    sessionId: r['session_id']! as String,
    storyLineId: r['story_line_id']! as String,
    position: r['position']! as int,
    participantId: r['participant_id']! as String,
    role: _enum(TavernTurnRole.values, r['role']),
    createdAt: _readDate(r['created_at']),
    updatedAt: _readDate(r['updated_at']),
    selectedAlternativeId: r['selected_alternative_id'] as String?,
    editedAt: _readMaybeDate(r['edited_at']),
    metadata: _map(r['metadata_json']),
  );
  static Map<String, Object?> _alternativeRow(TavernAlternative a) => {
    'id': a.id,
    'turn_id': a.turnId,
    'position': a.position,
    'origin': a.origin.name,
    'created_at': _date(a.createdAt),
    'edited_at': _maybeDate(a.editedAt),
    'metadata_json': _json(a.metadata),
  };
  static TavernAlternative _alternative(Map<String, Object?> r) =>
      TavernAlternative(
        id: r['id']! as String,
        turnId: r['turn_id']! as String,
        position: r['position']! as int,
        origin: _enum(TavernAlternativeOrigin.values, r['origin']),
        createdAt: _readDate(r['created_at']),
        editedAt: _readMaybeDate(r['edited_at']),
        metadata: _map(r['metadata_json']),
      );
  static Map<String, Object?> _partRow(TavernContentPart p) => {
    'id': p.id,
    'alternative_id': p.alternativeId,
    'position': p.position,
    'kind': p.unknownKind ?? p.kind.name,
    'text_value': p.text,
    'tool_name': p.toolName,
    'tool_call_id': p.toolCallId,
    'arguments_json': p.arguments == null ? null : _json(p.arguments!),
    'result_json': p.result == null ? null : _json(p.result!),
    'error_text': p.error,
    'asset_reference': p.assetReference,
    'mime_type': p.mimeType,
    'generation_attempt_id': p.generationAttemptId,
    'created_at': _date(p.createdAt),
    'metadata_json': _json(p.metadata),
  };
  static TavernContentPart _part(Map<String, Object?> r) => TavernContentPart(
    id: r['id']! as String,
    alternativeId: r['alternative_id']! as String,
    position: r['position']! as int,
    kind:
        TavernContentKind.values
            .where((kind) => kind.name == r['kind'])
            .firstOrNull ??
        TavernContentKind.unknown,
    createdAt: _readDate(r['created_at']),
    text: r['text_value'] as String?,
    toolName: r['tool_name'] as String?,
    toolCallId: r['tool_call_id'] as String?,
    arguments: _maybeMap(r['arguments_json']),
    result: _maybeMap(r['result_json']),
    error: r['error_text'] as String?,
    assetReference: r['asset_reference'] as String?,
    mimeType: r['mime_type'] as String?,
    generationAttemptId: r['generation_attempt_id'] as String?,
    unknownKind: TavernContentKind.values.any((kind) => kind.name == r['kind'])
        ? null
        : r['kind'] as String,
    metadata: _map(r['metadata_json']),
  );
  static Map<String, Object?> _attemptRow(TavernGenerationAttempt a) => {
    'id': a.id,
    'session_id': a.sessionId,
    'story_line_id': a.storyLineId,
    'turn_id': a.turnId,
    'alternative_id': a.alternativeId,
    'position': a.position,
    'status': a.status.name,
    'generation_type': a.type == TavernGenerationType.continueTurn
        ? 'continue'
        : a.type.name,
    'provider_reference': a.providerReference,
    'model_reference': a.modelReference,
    'failure_reason': a.failureReason,
    'cancel_reason': a.cancelReason,
    'has_partial_content': a.hasPartialContent ? 1 : 0,
    'created_at': _date(a.createdAt),
    'started_at': _maybeDate(a.startedAt),
    'ended_at': _maybeDate(a.endedAt),
    'metadata_json': _json(a.metadata),
  };
  static TavernGenerationAttempt _attempt(Map<String, Object?> r) =>
      TavernGenerationAttempt(
        id: r['id']! as String,
        sessionId: r['session_id']! as String,
        storyLineId: r['story_line_id']! as String,
        turnId: r['turn_id']! as String,
        alternativeId: r['alternative_id']! as String,
        position: r['position']! as int,
        status: _enum(TavernGenerationStatus.values, r['status']),
        type: r['generation_type'] == 'continue'
            ? TavernGenerationType.continueTurn
            : _enum(TavernGenerationType.values, r['generation_type']),
        createdAt: _readDate(r['created_at']),
        startedAt: _readMaybeDate(r['started_at']),
        endedAt: _readMaybeDate(r['ended_at']),
        failureReason: r['failure_reason'] as String?,
        cancelReason: r['cancel_reason'] as String?,
        providerReference: r['provider_reference'] as String?,
        modelReference: r['model_reference'] as String?,
        hasPartialContent: r['has_partial_content'] == 1,
        metadata: _map(r['metadata_json']),
      );

  Future<Map<String, Object?>> _one(
    DatabaseExecutor db,
    String table,
    String id,
  ) async {
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('$table not found: $id');
    return rows.single;
  }

  static List<TavernTurn> _visibleTurns(
    TavernStoryLine target,
    Map<String, TavernStoryLine> byLine,
    List<TavernTurn> turns,
  ) {
    final byTurn = {for (final turn in turns) turn.id: turn};
    final visible = <TavernTurn>[];
    final visiting = <String>{};
    void collect(TavernStoryLine line) {
      if (!visiting.add(line.id)) throw StateError('Story line cycle.');
      if (line.parentId != null) {
        final parent = byLine[line.parentId];
        final origin = byTurn[line.originTurnId];
        if (parent == null ||
            origin == null ||
            origin.storyLineId != parent.id) {
          throw StateError('Broken story line origin.');
        }
        collect(parent);
        final index = visible.indexWhere((turn) => turn.id == origin.id);
        if (index < 0) throw StateError('Origin turn not visible in parent.');
        visible.removeRange(index + 1, visible.length);
      }
      visible.addAll(turns.where((turn) => turn.storyLineId == line.id));
      visiting.remove(line.id);
    }

    collect(target);
    return visible;
  }

  @override
  Future<TavernSession> createSession(
    TavernSession session,
    TavernStoryLine root, {
    List<TavernParticipant> participants = const [],
  }) async {
    if (root.sessionId != session.id ||
        root.parentId != null ||
        root.originTurnId != null ||
        root.originAlternativeId != null ||
        session.activeStoryLineId != null) {
      throw ArgumentError('Invalid session root.');
    }
    if (participants.map((p) => p.id).toSet().length != participants.length ||
        participants.map((p) => p.position).toSet().length !=
            participants.length ||
        participants.any(
          (p) =>
              p.sessionId != session.id ||
              p.id.isEmpty ||
              p.position < 0 ||
              ((p.kind == TavernParticipantKind.character ||
                      p.kind == TavernParticipantKind.persona) &&
                  (p.entityId?.isEmpty ?? true)),
        )) {
      throw ArgumentError('Invalid story participants.');
    }
    final db = await database.database;
    await db.transaction((txn) async {
      await txn.insert('tavern_sessions', _sessionRow(session));
      await txn.insert('tavern_story_lines', _lineRow(root));
      for (final participant in participants) {
        await txn.insert('tavern_participants', _participantRow(participant));
      }
      await txn.insert(
        'tavern_world_info_states',
        _SQLiteTavernWorldInfo.stateRow(
          TavernWorldInfoSnapshot(sessionId: session.id, storyLineId: root.id),
        ),
      );
      await txn.update(
        'tavern_sessions',
        {'active_story_line_id': root.id},
        where: 'id = ?',
        whereArgs: [session.id],
      );
    });
    return getSession(session.id);
  }

  static Map<String, Object?> _participantRow(TavernParticipant p) => {
    'id': p.id,
    'session_id': p.sessionId,
    'kind': p.kind.name,
    'entity_id': p.entityId,
    'display_name': p.displayName,
    'position': p.position,
    'metadata_json': _json(p.metadata),
  };

  @override
  Future<List<TavernSession>> listSessions({
    bool archived = false,
    int limit = 100,
  }) async => (await (await database.database).query(
    'tavern_sessions',
    where:
        'deleted_at IS NULL AND archived_at IS ${archived ? 'NOT ' : ''}NULL',
    orderBy: 'updated_at DESC, id ASC',
    limit: limit.clamp(1, 200),
  )).map(_session).toList(growable: false);

  @override
  Future<List<TavernStorySummary>> listStorySummaries({
    bool archived = false,
    int limit = 100,
  }) async {
    final db = await database.database;
    final rows = await db.rawQuery(
      '''SELECT s.*, (
      SELECT substr(group_concat(piece, ''), -240) FROM (SELECT piece FROM (
        SELECT c.text_value AS piece, c.position FROM tavern_content_parts c
        LEFT JOIN tavern_generation_attempts a ON a.id = c.generation_attempt_id
        WHERE c.alternative_id = COALESCE(sel.alternative_id, t.selected_alternative_id)
          AND c.kind = 'text' AND (a.id IS NULL OR (a.status = 'completed' AND a.position >= COALESCE(
            (SELECT MAX(b.position) FROM tavern_generation_attempts b
              WHERE b.alternative_id = c.alternative_id AND b.status = 'completed' AND b.generation_type <> 'continue'), -1)))
        ORDER BY c.position DESC LIMIT 4
      ) ORDER BY position)
    ) AS latest_excerpt FROM tavern_sessions s
    LEFT JOIN tavern_story_lines l ON l.id = s.active_story_line_id
    LEFT JOIN tavern_turns t ON t.id = COALESCE(
      (SELECT id FROM tavern_turns WHERE story_line_id = l.id ORDER BY position DESC LIMIT 1), l.origin_turn_id)
    LEFT JOIN tavern_line_selections sel ON sel.story_line_id = l.id AND sel.turn_id = t.id
    WHERE s.deleted_at IS NULL AND s.archived_at IS ${archived ? 'NOT ' : ''}NULL
    ORDER BY s.updated_at DESC, s.id ASC LIMIT ?''',
      [limit.clamp(1, 200)],
    );
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r['id'] as String).toList();
    final cast = (await db.query(
      'tavern_participants',
      where: 'session_id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
      orderBy: 'session_id, position, id',
    )).map(_readParticipant).toList();
    return rows
        .map(
          (row) => TavernStorySummary(
            session: _session(row),
            participants: cast
                .where((p) => p.sessionId == row['id'])
                .toList(growable: false),
            excerpt: row['latest_excerpt'] as String? ?? '',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> saveSession(TavernSession session) async {
    final db = await database.database;
    await db.transaction((tx) async {
      final old = _session(await _one(tx, 'tavern_sessions', session.id));
      if (session.activeStoryLineId != old.activeStoryLineId ||
          session.createdAt != old.createdAt) {
        throw StateError(
          'Session edit cannot change canonical line ownership.',
        );
      }
      await tx.update(
        'tavern_sessions',
        _sessionRow(session),
        where: 'id = ?',
        whereArgs: [session.id],
      );
    });
  }

  @override
  Future<List<TavernStoryLine>> listStoryLines(String sessionId) async =>
      (await (await database.database).query(
        'tavern_story_lines',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'position ASC, id ASC',
      )).map(_line).toList(growable: false);

  @override
  Future<TavernSession> getSession(String id) async =>
      _session(await _one(await database.database, 'tavern_sessions', id));

  @override
  Future<TavernParticipant> addParticipant(
    TavernParticipant participant,
  ) async {
    if (participant.position < 0 ||
        ((participant.kind == TavernParticipantKind.persona ||
                participant.kind == TavernParticipantKind.character) &&
            participant.entityId == null)) {
      throw ArgumentError('Invalid participant.');
    }
    final db = await database.database;
    await db.insert('tavern_participants', {
      'id': participant.id,
      'session_id': participant.sessionId,
      'kind': participant.kind.name,
      'entity_id': participant.entityId,
      'display_name': participant.displayName,
      'position': participant.position,
      'metadata_json': _json(participant.metadata),
    });
    return participant;
  }

  @override
  Future<List<TavernParticipant>> listParticipants(String sessionId) async {
    final rows = await (await database.database).query(
      'tavern_participants',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'position ASC',
    );
    return rows
        .map(
          (r) => TavernParticipant(
            id: r['id']! as String,
            sessionId: r['session_id']! as String,
            kind: _enum(TavernParticipantKind.values, r['kind']),
            entityId: r['entity_id'] as String?,
            displayName: r['display_name']! as String,
            position: r['position']! as int,
            metadata: _map(r['metadata_json']),
          ),
        )
        .toList(growable: false);
  }

  static TavernParticipant _readParticipant(Map<String, Object?> r) =>
      TavernParticipant(
        id: r['id']! as String,
        sessionId: r['session_id']! as String,
        kind: _enum(TavernParticipantKind.values, r['kind']),
        entityId: r['entity_id'] as String?,
        displayName: r['display_name']! as String,
        position: r['position']! as int,
        metadata: _map(r['metadata_json']),
      );

  @override
  Future<TavernStoryLine> createStoryLine(
    TavernStoryLine line, {
    bool activate = false,
  }) async {
    if (line.parentId == null ||
        line.originTurnId == null ||
        line.originAlternativeId == null) {
      throw ArgumentError(
        'A branch requires parent, origin turn and alternative.',
      );
    }
    final db = await database.database;
    await db.transaction((txn) async {
      final parent = _line(
        await _one(txn, 'tavern_story_lines', line.parentId!),
      );
      final origin = _turn(await _one(txn, 'tavern_turns', line.originTurnId!));
      final alternative = _alternative(
        await _one(txn, 'tavern_alternatives', line.originAlternativeId!),
      );
      if (parent.sessionId != line.sessionId ||
          origin.storyLineId != parent.id ||
          alternative.turnId != origin.id ||
          parent.archivedAt != null) {
        throw StateError('Branch origin is outside its parent story line.');
      }
      final allLines = (await txn.query(
        'tavern_story_lines',
        where: 'session_id = ?',
        whereArgs: [line.sessionId],
      )).map(_line).toList();
      final allTurns = (await txn.query(
        'tavern_turns',
        where: 'session_id = ?',
        whereArgs: [line.sessionId],
        orderBy: 'story_line_id, position ASC',
      )).map(_turn).toList();
      final inherited = _visibleTurns(parent, {
        for (final item in allLines) item.id: item,
      }, allTurns);
      final originIndex = inherited.indexWhere((turn) => turn.id == origin.id);
      if (originIndex < 0) throw StateError('Branch origin is not visible.');
      final parentSelections = await txn.query(
        'tavern_line_selections',
        where: 'story_line_id = ?',
        whereArgs: [parent.id],
      );
      final selected = {
        for (final row in parentSelections)
          row['turn_id']! as String: row['alternative_id']! as String,
      };
      await txn.insert('tavern_story_lines', _lineRow(line));
      for (final turn in inherited.take(originIndex + 1)) {
        await txn.insert('tavern_line_selections', {
          'id': jsonEncode([line.id, turn.id]),
          'story_line_id': line.id,
          'turn_id': turn.id,
          'alternative_id': turn.id == origin.id
              ? alternative.id
              : (selected[turn.id] ?? turn.selectedAlternativeId),
        });
      }
      await _SQLiteTavernWorldInfo(txn).fork(
        line,
        inherited
            .take(originIndex + 1)
            .map(
              (turn) => (
                turn.id,
                turn.id == origin.id
                    ? alternative.id
                    : (selected[turn.id] ?? turn.selectedAlternativeId)!,
              ),
            )
            .toList(),
      );
      if (activate) {
        await txn.update(
          'tavern_sessions',
          {
            'active_story_line_id': line.id,
            'updated_at': _date(DateTime.now()),
          },
          where: 'id = ?',
          whereArgs: [line.sessionId],
        );
      }
    });
    return line;
  }

  @override
  Future<TavernStoryLine> getStoryLine(String id) async =>
      _line(await _one(await database.database, 'tavern_story_lines', id));

  @override
  Future<void> selectStoryLine(String sessionId, String storyLineId) async {
    final db = await database.database;
    await db.transaction((txn) async {
      final line = _line(await _one(txn, 'tavern_story_lines', storyLineId));
      if (line.sessionId != sessionId || line.archivedAt != null) {
        throw StateError('Story line is unavailable in this session.');
      }
      await txn.update(
        'tavern_sessions',
        {
          'active_story_line_id': storyLineId,
          'updated_at': _date(DateTime.now()),
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  @override
  Future<void> archiveStoryLine(String id) async {
    final db = await database.database;
    await db.transaction((txn) async {
      final line = _line(await _one(txn, 'tavern_story_lines', id));
      final session = _session(
        await _one(txn, 'tavern_sessions', line.sessionId),
      );
      if (session.activeStoryLineId == id) {
        throw StateError('Cannot archive active story line.');
      }
      final children = await txn.query(
        'tavern_story_lines',
        columns: ['id'],
        where: 'parent_id = ? AND archived_at IS NULL',
        whereArgs: [id],
        limit: 1,
      );
      if (children.isNotEmpty) {
        throw StateError('Cannot archive story line with active children.');
      }
      await txn.update(
        'tavern_story_lines',
        {'archived_at': _date(DateTime.now())},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  @override
  Future<TavernTurn> appendTurn(
    TavernTurn turn,
    TavernAlternative first, {
    TavernGenerationAttempt? attempt,
    TavernWorldInfoPlan? reconciliation,
    List<TavernContentPart> initialParts = const [],
  }) async {
    if (first.turnId != turn.id ||
        turn.selectedAlternativeId != null ||
        first.position != 0 ||
        (attempt != null &&
            (attempt.turnId != turn.id ||
                attempt.alternativeId != first.id ||
                attempt.storyLineId != turn.storyLineId ||
                attempt.sessionId != turn.sessionId))) {
      throw ArgumentError('Invalid initial turn bundle.');
    }
    final db = await database.database;
    await db.transaction((txn) async {
      final line = _line(
        await _one(txn, 'tavern_story_lines', turn.storyLineId),
      );
      final participant = await _one(
        txn,
        'tavern_participants',
        turn.participantId,
      );
      if (line.sessionId != turn.sessionId ||
          line.archivedAt != null ||
          participant['session_id'] != turn.sessionId) {
        throw StateError('Turn crosses session boundary.');
      }
      await txn.insert('tavern_turns', _turnRow(turn));
      await txn.insert('tavern_alternatives', _alternativeRow(first));
      for (final part in initialParts) {
        part.validate();
        if (part.alternativeId != first.id ||
            part.generationAttemptId != null) {
          throw StateError('Initial content crosses turn boundary.');
        }
        await txn.insert('tavern_content_parts', _partRow(part));
      }
      await txn.update(
        'tavern_turns',
        {'selected_alternative_id': first.id},
        where: 'id = ?',
        whereArgs: [turn.id],
      );
      if (attempt != null) {
        await txn.insert('tavern_generation_attempts', _attemptRow(attempt));
        await _SQLiteTavernWorldInfo(txn).prepare(attempt, reconciliation);
      } else if (reconciliation != null) {
        throw const TavernReconciliationConflict('missing_attempt');
      }
      await txn.update(
        'tavern_sessions',
        {'updated_at': _date(DateTime.now())},
        where: 'id = ?',
        whereArgs: [turn.sessionId],
      );
    });
    return _turn(await _one(db, 'tavern_turns', turn.id));
  }

  @override
  Future<TavernAlternative> addAlternative(
    TavernAlternative alternative, {
    TavernGenerationAttempt? attempt,
    TavernWorldInfoPlan? reconciliation,
  }) async {
    final db = await database.database;
    await db.transaction((txn) async {
      final turn = _turn(await _one(txn, 'tavern_turns', alternative.turnId));
      if (attempt != null &&
          (attempt.turnId != turn.id ||
              attempt.alternativeId != alternative.id ||
              attempt.sessionId != turn.sessionId ||
              attempt.storyLineId != turn.storyLineId)) {
        throw StateError('Generation attempt targets another alternative.');
      }
      await txn.insert('tavern_alternatives', _alternativeRow(alternative));
      if (attempt != null) {
        await txn.insert('tavern_generation_attempts', _attemptRow(attempt));
        await _SQLiteTavernWorldInfo(txn).prepare(attempt, reconciliation);
      } else if (reconciliation != null) {
        throw const TavernReconciliationConflict('missing_attempt');
      }
    });
    return alternative;
  }

  @override
  Future<void> selectAlternative(String turnId, String alternativeId) async {
    final db = await database.database;
    await db.transaction((txn) async {
      final alt = _alternative(
        await _one(txn, 'tavern_alternatives', alternativeId),
      );
      if (alt.turnId != turnId) {
        throw StateError('Alternative belongs to another turn.');
      }
      await txn.update(
        'tavern_turns',
        {
          'selected_alternative_id': alternativeId,
          'updated_at': _date(DateTime.now()),
        },
        where: 'id = ?',
        whereArgs: [turnId],
      );
    });
  }

  @override
  Future<void> deleteAlternative(String id) async {
    final db = await database.database;
    await db.transaction((txn) async {
      final alt = _alternative(await _one(txn, 'tavern_alternatives', id));
      final turn = _turn(await _one(txn, 'tavern_turns', alt.turnId));
      if (turn.selectedAlternativeId == id) {
        throw StateError('Cannot delete selected alternative.');
      }
      final branches = await txn.query(
        'tavern_story_lines',
        columns: ['id'],
        where: 'origin_alternative_id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (branches.isNotEmpty) {
        throw StateError('Cannot delete branch-origin alternative.');
      }
      final inherited = await txn.query(
        'tavern_line_selections',
        columns: ['id'],
        where: 'alternative_id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (inherited.isNotEmpty) {
        throw StateError(
          'Cannot delete alternative inherited by a story line.',
        );
      }
      await txn.delete(
        'tavern_content_parts',
        where: 'alternative_id = ?',
        whereArgs: [id],
      );
      final protected = await txn.query(
        'tavern_world_info_journal',
        columns: ['id'],
        where: "alternative_id = ? AND outcome <> 'discarded'",
        whereArgs: [id],
        limit: 1,
      );
      if (protected.isNotEmpty) {
        throw const TavernReconciliationConflict('protected_history');
      }
      await txn.delete(
        'tavern_world_info_journal',
        where: 'alternative_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'tavern_generation_attempts',
        where: 'alternative_id = ?',
        whereArgs: [id],
      );
      await txn.delete('tavern_alternatives', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<TavernContentPart> appendContentPart(TavernContentPart part) async {
    part.validate();
    final db = await database.database;
    await db.transaction((txn) async {
      await _one(txn, 'tavern_alternatives', part.alternativeId);
      if (part.generationAttemptId != null) {
        final attempt = _attempt(
          await _one(
            txn,
            'tavern_generation_attempts',
            part.generationAttemptId!,
          ),
        );
        if (attempt.alternativeId != part.alternativeId) {
          throw StateError('Content part crosses generation attempt target.');
        }
      }
      await txn.insert('tavern_content_parts', _partRow(part));
    });
    return part;
  }

  @override
  Future<List<TavernContentPart>> listContentParts(
    String alternativeId,
  ) async => (await (await database.database).query(
    'tavern_content_parts',
    where: 'alternative_id = ?',
    whereArgs: [alternativeId],
    orderBy: 'position ASC',
  )).map(_part).toList(growable: false);

  @override
  Future<void> persistGenerationBatch(
    String attemptId,
    List<TavernContentPart> parts, {
    TavernGenerationStatus? terminalStatus,
    String? reason,
    bool selectAlternative = false,
    String? expectedSelectedAlternativeId,
  }) async {
    const terminal = {
      TavernGenerationStatus.completed,
      TavernGenerationStatus.failed,
      TavernGenerationStatus.cancelled,
    };
    if ((terminalStatus != null && !terminal.contains(terminalStatus)) ||
        (selectAlternative &&
            terminalStatus != TavernGenerationStatus.completed)) {
      throw StateError('Invalid generation finalization.');
    }
    await (await database.database).transaction((txn) async {
      final attempt = _attempt(
        await _one(txn, 'tavern_generation_attempts', attemptId),
      );
      if (terminal.contains(attempt.status)) {
        throw StateError('Generation attempt is already terminal.');
      }
      for (final part in parts) {
        part.validate();
        if (part.generationAttemptId != attemptId ||
            part.alternativeId != attempt.alternativeId) {
          throw StateError('Content part crosses generation target.');
        }
        await txn.insert('tavern_content_parts', _partRow(part));
      }
      if (terminalStatus != null) {
        final partial =
            terminalStatus != TavernGenerationStatus.completed &&
            (parts.isNotEmpty ||
                attempt.hasPartialContent ||
                (await txn.query(
                  'tavern_content_parts',
                  columns: ['id'],
                  where: 'generation_attempt_id = ?',
                  whereArgs: [attemptId],
                  limit: 1,
                )).isNotEmpty);
        await txn.update(
          'tavern_generation_attempts',
          {
            'status': terminalStatus.name,
            'started_at':
                _maybeDate(attempt.startedAt) ?? _date(DateTime.now()),
            'ended_at': _date(DateTime.now()),
            'failure_reason': terminalStatus == TavernGenerationStatus.failed
                ? reason
                : null,
            'cancel_reason': terminalStatus == TavernGenerationStatus.cancelled
                ? reason
                : null,
            'has_partial_content': partial ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [attemptId],
        );
        if (selectAlternative) {
          await txn.update(
            'tavern_turns',
            {
              'selected_alternative_id': attempt.alternativeId,
              'updated_at': _date(DateTime.now()),
            },
            where: expectedSelectedAlternativeId == null
                ? 'id = ?'
                : 'id = ? AND selected_alternative_id = ?',
            whereArgs: expectedSelectedAlternativeId == null
                ? [attempt.turnId]
                : [attempt.turnId, expectedSelectedAlternativeId],
          );
        }
        await _SQLiteTavernWorldInfo(txn).settle(
          _attempt({..._attemptRow(attempt), 'status': terminalStatus.name}),
        );
        await txn.update(
          'tavern_sessions',
          {'updated_at': _date(DateTime.now())},
          where: 'id = ?',
          whereArgs: [attempt.sessionId],
        );
      }
    });
  }

  @override
  Future<List<TavernGenerationAttempt>> recoverInterruptedAttempts() async {
    return (await database.database).transaction((txn) async {
      final rows = await txn.query(
        'tavern_generation_attempts',
        where: "status NOT IN ('completed','failed','cancelled')",
      );
      final interrupted = rows.map(_attempt).toList(growable: false);
      for (final attempt in interrupted) {
        final hasParts = (await txn.query(
          'tavern_content_parts',
          columns: ['id'],
          where: 'generation_attempt_id = ?',
          whereArgs: [attempt.id],
          limit: 1,
        )).isNotEmpty;
        await txn.update(
          'tavern_generation_attempts',
          {
            'status': TavernGenerationStatus.failed.name,
            'failure_reason': 'runtime_restart',
            'started_at':
                _maybeDate(attempt.startedAt) ?? _date(DateTime.now()),
            'ended_at': _date(DateTime.now()),
            'has_partial_content': hasParts || attempt.hasPartialContent
                ? 1
                : 0,
          },
          where: 'id = ?',
          whereArgs: [attempt.id],
        );
        await _SQLiteTavernWorldInfo(
          txn,
        ).settle(_attempt({..._attemptRow(attempt), 'status': 'failed'}));
      }
      return interrupted;
    });
  }

  @override
  Future<TavernGenerationAttempt> recordAttempt(
    TavernGenerationAttempt attempt, {
    TavernWorldInfoPlan? reconciliation,
  }) async {
    final db = await database.database;
    await db.transaction((txn) async {
      final alt = _alternative(
        await _one(txn, 'tavern_alternatives', attempt.alternativeId),
      );
      final turn = _turn(await _one(txn, 'tavern_turns', alt.turnId));
      if (turn.id != attempt.turnId ||
          turn.storyLineId != attempt.storyLineId ||
          turn.sessionId != attempt.sessionId) {
        throw StateError('Attempt crosses turn boundary.');
      }
      await txn.insert('tavern_generation_attempts', _attemptRow(attempt));
      await _SQLiteTavernWorldInfo(txn).prepare(attempt, reconciliation);
    });
    return attempt;
  }

  @override
  Future<void> updateAttempt(
    String id,
    TavernGenerationStatus status, {
    String? reason,
    bool hasPartialContent = false,
  }) async {
    final db = await database.database;
    await db.transaction((txn) async {
      final old = _attempt(await _one(txn, 'tavern_generation_attempts', id));
      const terminal = {
        TavernGenerationStatus.cancelled,
        TavernGenerationStatus.failed,
        TavernGenerationStatus.completed,
      };
      if (terminal.contains(old.status) ||
          status.index <= old.status.index && !terminal.contains(status)) {
        throw StateError('Invalid attempt transition.');
      }
      await txn.update(
        'tavern_generation_attempts',
        {
          'status': status.name,
          'started_at':
              old.startedAt == null && status != TavernGenerationStatus.queued
              ? _date(DateTime.now())
              : _maybeDate(old.startedAt),
          'ended_at': terminal.contains(status) ? _date(DateTime.now()) : null,
          'failure_reason': status == TavernGenerationStatus.failed
              ? reason
              : null,
          'cancel_reason': status == TavernGenerationStatus.cancelled
              ? reason
              : null,
          'has_partial_content': hasPartialContent
              ? 1
              : (old.hasPartialContent ? 1 : 0),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (terminal.contains(status)) {
        await _SQLiteTavernWorldInfo(
          txn,
        ).settle(_attempt({..._attemptRow(old), 'status': status.name}));
      }
    });
  }

  @override
  Future<List<TavernGenerationAttempt>> listAttempts(
    String alternativeId,
  ) async {
    final rows = await (await database.database).query(
      'tavern_generation_attempts',
      where: 'alternative_id = ?',
      whereArgs: [alternativeId],
      orderBy: 'position ASC',
    );
    return rows.map(_attempt).toList(growable: false);
  }

  @override
  Future<TavernTranscriptProjection> loadTranscript(
    String sessionId, {
    String? storyLineId,
  }) async {
    final db = await database.database;
    return db.transaction((txn) async {
      final session = _session(await _one(txn, 'tavern_sessions', sessionId));
      final targetId = storyLineId ?? session.activeStoryLineId;
      if (targetId == null) {
        throw StateError('Session has no active story line.');
      }
      final lines = (await txn.query(
        'tavern_story_lines',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      )).map(_line).toList();
      final byLine = {for (final line in lines) line.id: line};
      final target = byLine[targetId];
      if (target == null) throw StateError('Story line is outside session.');
      final turns = (await txn.query(
        'tavern_turns',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'story_line_id, position ASC',
      )).map(_turn).toList();
      final visible = _visibleTurns(target, byLine, turns);
      final selectionRows = await txn.query(
        'tavern_line_selections',
        where: 'story_line_id = ?',
        whereArgs: [target.id],
      );
      final overrides = {
        for (final row in selectionRows)
          row['turn_id']! as String: row['alternative_id']! as String,
      };
      final ids = visible.map((turn) => turn.id).toSet();
      if (ids.isEmpty) {
        return TavernTranscriptProjection(
          session: session,
          storyLine: target,
          turns: const [],
        );
      }
      final alternatives = (await txn.rawQuery(
        '''
SELECT a.* FROM tavern_alternatives a
JOIN tavern_turns t ON t.id = a.turn_id
WHERE t.session_id = ?
ORDER BY a.turn_id, a.position
''',
        [sessionId],
      )).map(_alternative).where((alt) => ids.contains(alt.turnId)).toList();
      final altsByTurn = <String, List<TavernAlternative>>{};
      for (final alt in alternatives) {
        altsByTurn.putIfAbsent(alt.turnId, () => []).add(alt);
      }
      final selectedIds = <String>{};
      for (final turn in visible) {
        selectedIds.add(overrides[turn.id] ?? turn.selectedAlternativeId!);
      }
      final parts = (await txn.rawQuery(
        '''
SELECT p.* FROM tavern_content_parts p
JOIN tavern_alternatives a ON a.id = p.alternative_id
JOIN tavern_turns t ON t.id = a.turn_id
WHERE t.session_id = ?
ORDER BY p.alternative_id, p.position
''',
        [sessionId],
      )).map(_part).where((part) => selectedIds.contains(part.alternativeId));
      final partsByAlt = <String, List<TavernContentPart>>{};
      for (final part in parts) {
        partsByAlt.putIfAbsent(part.alternativeId, () => []).add(part);
      }
      final attemptRows = await txn.rawQuery(
        '''
SELECT g.* FROM tavern_generation_attempts g
JOIN tavern_turns t ON t.id = g.turn_id
WHERE t.session_id = ?
ORDER BY g.alternative_id, g.position
''',
        [sessionId],
      );
      final attemptsByAlt = <String, List<TavernGenerationAttempt>>{};
      for (final row in attemptRows) {
        final attempt = _attempt(row);
        if (selectedIds.contains(attempt.alternativeId)) {
          attemptsByAlt
              .putIfAbsent(attempt.alternativeId, () => [])
              .add(attempt);
        }
      }
      return TavernTranscriptProjection(
        session: session,
        storyLine: target,
        turns: visible
            .map((turn) {
              final alts = altsByTurn[turn.id] ?? const <TavernAlternative>[];
              final selectedId =
                  overrides[turn.id] ?? turn.selectedAlternativeId;
              final selected = alts.firstWhere((alt) => alt.id == selectedId);
              return TavernTurnProjection(
                turn: turn,
                selectedAlternative: selected,
                alternatives: alts,
                selectedParts: selectTavernContentParts(
                  partsByAlt[selected.id] ?? const [],
                  attemptsByAlt[selected.id] ?? const [],
                ),
              );
            })
            .toList(growable: false),
      );
    });
  }

  @override
  Future<void> archiveSession(String id) async {
    await (await database.database).update(
      'tavern_sessions',
      {'archived_at': _date(DateTime.now())},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteSession(String id) async {
    final db = await database.database;
    await db.transaction((txn) async {
      await _one(txn, 'tavern_sessions', id);
      await txn.delete(
        'tavern_world_info_states',
        where: 'session_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'tavern_world_info_journal',
        where: 'session_id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'tavern_sessions',
        {'active_story_line_id': null},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'tavern_line_selections',
        where:
            'story_line_id IN '
            '(SELECT id FROM tavern_story_lines WHERE session_id = ?)',
        whereArgs: [id],
      );
      final lines = await txn.query(
        'tavern_story_lines',
        columns: ['id'],
        where: 'session_id = ?',
        whereArgs: [id],
      );
      for (final line in lines) {
        await txn.update(
          'tavern_story_lines',
          {
            'origin_turn_id': null,
            'origin_alternative_id': null,
            'parent_id': null,
          },
          where: 'id = ?',
          whereArgs: [line['id']],
        );
      }
      await txn.update(
        'tavern_turns',
        {'selected_alternative_id': null},
        where: 'session_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'tavern_content_parts',
        where:
            'alternative_id IN '
            '(SELECT a.id FROM tavern_alternatives a JOIN tavern_turns t ON t.id = a.turn_id WHERE t.session_id = ?)',
        whereArgs: [id],
      );
      await txn.delete(
        'tavern_generation_attempts',
        where: 'session_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'tavern_alternatives',
        where:
            'turn_id IN '
            '(SELECT id FROM tavern_turns WHERE session_id = ?)',
        whereArgs: [id],
      );
      await txn.delete(
        'tavern_turns',
        where: 'session_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'tavern_story_lines',
        where: 'session_id = ?',
        whereArgs: [id],
      );
      await txn.delete('tavern_sessions', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<TavernWorldInfoSnapshot> loadWorldInfoState(
    String sessionId,
    String storyLineId,
  ) async => _SQLiteTavernWorldInfo(
    await database.database,
  ).load(sessionId, storyLineId);
  @override
  Future<TavernWorldInfoJournal?> getWorldInfoJournal(String attemptId) async =>
      _SQLiteTavernWorldInfo(await database.database).get(attemptId);
  @override
  Future<void> requireWorldInfoReady(
    String sessionId,
    String storyLineId,
  ) async => _SQLiteTavernWorldInfo(
    await database.database,
  ).ready(sessionId, storyLineId);
  @override
  Future<void> reconcileWorldInfo() async => (await database.database)
      .transaction((txn) => _SQLiteTavernWorldInfo(txn).recover());
  @override
  Future<TavernReconciliationOutcome> reconcileWorldInfoAttempt(
    String attemptId,
  ) async => (await database.database).transaction((txn) async {
    final attempt = _attempt(
      await _one(txn, 'tavern_generation_attempts', attemptId),
    );
    final result = await _SQLiteTavernWorldInfo(txn).settle(attempt);
    if (result == null) {
      throw const TavernReconciliationConflict('missing_journal');
    }
    return result;
  });
}
