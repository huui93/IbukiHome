import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/backup/backup_archive_codec.dart';
import 'package:ibukihome/data/memory/in_memory_tavern_repository.dart';
import 'package:ibukihome/data/repositories/tavern_repository.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_backup_snapshot_store.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:ibukihome/data/sqlite/sqlite_tavern_repository.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _now = DateTime.utc(2026, 10, 1);

TavernSession _session(String id) => TavernSession(
  id: id,
  title: 'Test story',
  createdAt: _now,
  updatedAt: _now,
  metadata: const {'fixture': true},
  worldAssetType: 'worldCard',
  worldAssetId: 'world-asset',
);
TavernStoryLine _root(String sessionId) => TavernStoryLine(
  id: '$sessionId-main',
  sessionId: sessionId,
  name: 'Main',
  position: 0,
  createdAt: _now,
);
TavernParticipant _participant(String sessionId) => TavernParticipant(
  id: '$sessionId-speaker',
  sessionId: sessionId,
  kind: TavernParticipantKind.character,
  entityId: 'card-asset',
  displayName: 'Mira',
  position: 0,
);
TavernTurn _turn(String id, String sessionId, String lineId, int position) =>
    TavernTurn(
      id: id,
      sessionId: sessionId,
      storyLineId: lineId,
      position: position,
      participantId: '$sessionId-speaker',
      role: TavernTurnRole.character,
      createdAt: _now,
      updatedAt: _now,
    );
TavernAlternative _alt(String id, String turnId, int position) =>
    TavernAlternative(
      id: id,
      turnId: turnId,
      position: position,
      origin: TavernAlternativeOrigin.generated,
      createdAt: _now,
    );
TavernContentPart _text(String id, String altId, String value) =>
    TavernContentPart(
      id: id,
      alternativeId: altId,
      position: 0,
      kind: TavernContentKind.text,
      text: value,
      createdAt: _now,
    );

Future<void> _seed(TavernRepository repository, {String id = 's'}) async {
  await repository.createSession(_session(id), _root(id));
  await repository.addParticipant(_participant(id));
}

Future<void> _exercise(TavernRepository repository) async {
  await _seed(repository);
  expect((await repository.getSession('s')).metadata['fixture'], true);
  expect(
    (await repository.listParticipants('s')).single.entityId,
    'card-asset',
  );
  await repository.appendTurn(
    _turn('t0', 's', 's-main', 0),
    _alt('a0', 't0', 0),
  );
  await repository.appendContentPart(_text('p0', 'a0', 'first'));
  for (var i = 1; i < 5; i++) {
    await repository.addAlternative(_alt('a$i', 't0', i));
    await repository.appendContentPart(_text('p$i', 'a$i', 'answer $i'));
  }
  await repository.selectAlternative('t0', 'a2');
  var transcript = await repository.loadTranscript('s');
  expect(transcript.turns.single.alternatives, hasLength(5));
  expect(transcript.turns.single.selectedAlternative.id, 'a2');
  expect(transcript.turns.single.selectedParts.single.text, 'answer 2');

  final child = TavernStoryLine(
    id: 'child',
    sessionId: 's',
    name: 'Another path',
    position: 1,
    parentId: 's-main',
    originTurnId: 't0',
    originAlternativeId: 'a3',
    createdAt: _now,
  );
  await repository.createStoryLine(child, activate: true);
  await repository.appendTurn(
    _turn('t1', 's', 'child', 0),
    _alt('a5', 't1', 0),
  );
  await repository.appendContentPart(_text('p5', 'a5', 'child only'));
  final grandchild = TavernStoryLine(
    id: 'grandchild',
    sessionId: 's',
    name: 'Nested path',
    position: 2,
    parentId: 'child',
    originTurnId: 't1',
    originAlternativeId: 'a5',
    createdAt: _now,
  );
  await repository.createStoryLine(grandchild, activate: true);
  await repository.appendTurn(
    _turn('t2', 's', 'grandchild', 0),
    _alt('a6', 't2', 0),
  );
  transcript = await repository.loadTranscript('s');
  expect(transcript.turns.map((t) => t.turn.id), ['t0', 't1', 't2']);
  expect(transcript.turns.first.selectedAlternative.id, 'a3');
  await repository.selectAlternative('t0', 'a4');
  expect(
    (await repository.loadTranscript('s')).turns.first.selectedAlternative.id,
    'a3',
  );
  await repository.selectStoryLine('s', 's-main');
  expect(
    (await repository.loadTranscript('s')).turns.single.selectedAlternative.id,
    'a4',
  );
  await repository.selectStoryLine('s', 'grandchild');
  expect((await repository.getSession('s')).activeStoryLineId, 'grandchild');
  await expectLater(repository.deleteAlternative('a3'), throwsStateError);
  await repository.selectAlternative('t0', 'a2');
  await expectLater(repository.deleteAlternative('a4'), completes);

  await repository.appendContentPart(
    TavernContentPart(
      id: 'reason',
      alternativeId: 'a5',
      position: 1,
      kind: TavernContentKind.reasoning,
      text: 'private reasoning',
      createdAt: _now,
    ),
  );
  await repository.appendContentPart(
    TavernContentPart(
      id: 'tool',
      alternativeId: 'a5',
      position: 2,
      kind: TavernContentKind.toolCall,
      toolName: 'lookup',
      toolCallId: 'call-1',
      arguments: const {'q': 'x'},
      createdAt: _now,
    ),
  );
  await repository.appendContentPart(
    TavernContentPart(
      id: 'result',
      alternativeId: 'a5',
      position: 3,
      kind: TavernContentKind.toolResult,
      toolCallId: 'call-1',
      result: const {'ok': true},
      createdAt: _now,
    ),
  );
  expect(
    (await repository.loadTranscript('s')).turns[1].selectedParts,
    hasLength(4),
  );
  expect(
    (await repository.loadTranscript('s')).turns[1].visibleParts,
    hasLength(1),
  );
  await expectLater(
    repository.appendContentPart(
      TavernContentPart(
        id: 'invalid',
        alternativeId: 'a5',
        position: 4,
        kind: TavernContentKind.toolCall,
        createdAt: _now,
      ),
    ),
    throwsArgumentError,
  );

  for (var i = 0; i < 3; i++) {
    await repository.recordAttempt(
      TavernGenerationAttempt(
        id: 'attempt-$i',
        sessionId: 's',
        storyLineId: 'child',
        turnId: 't1',
        alternativeId: 'a5',
        position: i,
        status: TavernGenerationStatus.queued,
        type: i == 0
            ? TavernGenerationType.normal
            : TavernGenerationType.regenerate,
        createdAt: _now,
      ),
    );
  }
  await repository.updateAttempt(
    'attempt-0',
    TavernGenerationStatus.failed,
    reason: 'provider unavailable',
  );
  await repository.updateAttempt(
    'attempt-1',
    TavernGenerationStatus.cancelled,
    reason: 'user stop',
    hasPartialContent: true,
  );
  await repository.updateAttempt('attempt-2', TavernGenerationStatus.completed);
  final attempts = await repository.listAttempts('a5');
  expect(attempts.map((a) => a.status), [
    TavernGenerationStatus.failed,
    TavernGenerationStatus.cancelled,
    TavernGenerationStatus.completed,
  ]);
  expect(attempts[1].hasPartialContent, isTrue);
  await expectLater(
    repository.updateAttempt('attempt-0', TavernGenerationStatus.running),
    throwsStateError,
  );
  await expectLater(repository.archiveStoryLine('child'), throwsStateError);
  await repository.archiveSession('s');
  expect((await repository.getSession('s')).archivedAt, isNotNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('in-memory runtime semantics, rich content and attempts', () async {
    await _exercise(InMemoryTavernRepository());
  });

  test(
    'branch freezes all inherited selections without copying content',
    () async {
      Future<void> exercise(TavernRepository repository) async {
        await _seed(repository);
        await repository.appendTurn(
          _turn('early', 's', 's-main', 0),
          _alt('early-a', 'early', 0),
        );
        await repository.addAlternative(_alt('early-b', 'early', 1));
        await repository.selectAlternative('early', 'early-b');
        await repository.appendTurn(
          _turn('fork', 's', 's-main', 1),
          _alt('fork-a', 'fork', 0),
        );
        await repository.createStoryLine(
          TavernStoryLine(
            id: 'child',
            sessionId: 's',
            name: 'Child',
            position: 1,
            parentId: 's-main',
            originTurnId: 'fork',
            originAlternativeId: 'fork-a',
            createdAt: _now,
          ),
        );
        await repository.selectAlternative('early', 'early-a');
        expect(
          (await repository.loadTranscript(
            's',
          )).turns.first.selectedAlternative.id,
          'early-a',
        );
        expect(
          (await repository.loadTranscript(
            's',
            storyLineId: 'child',
          )).turns.first.selectedAlternative.id,
          'early-b',
        );
        await expectLater(
          repository.deleteAlternative('early-b'),
          throwsStateError,
        );
      }

      await exercise(InMemoryTavernRepository());
      final dir = await Directory.systemTemp.createTemp('ibuki_tavern_branch_');
      addTearDown(() => dir.delete(recursive: true));
      final db = _database(p.join(dir.path, 'branch.db'));
      await exercise(SQLiteTavernRepository(db));
      await db.close();
    },
  );

  test(
    'SQLite runtime semantics, reopen, transaction rollback and isolation',
    () async {
      final dir = await Directory.systemTemp.createTemp('ibuki_tavern_');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'data.db');
      var db = _database(path);
      var repository = SQLiteTavernRepository(db);
      await _exercise(repository);
      await _seed(repository, id: 'other');
      final failed = _turn('bad', 's', 's-main', 5);
      await expectLater(
        repository.appendTurn(failed, _alt('bad-alt', 'bad', 1)),
        throwsArgumentError,
      );
      expect(
        await (await db.database).query(
          'tavern_turns',
          where: 'id = ?',
          whereArgs: ['bad'],
        ),
        isEmpty,
      );
      await expectLater(
        repository.appendTurn(
          _turn('rollback', 's', 's-main', 5),
          _alt('rollback-alt', 'rollback', 0),
          attempt: TavernGenerationAttempt(
            id: 'attempt-0',
            sessionId: 's',
            storyLineId: 's-main',
            turnId: 'rollback',
            alternativeId: 'rollback-alt',
            position: 0,
            status: TavernGenerationStatus.queued,
            type: TavernGenerationType.normal,
            createdAt: _now,
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        await (await db.database).query(
          'tavern_turns',
          where: 'id = ?',
          whereArgs: ['rollback'],
        ),
        isEmpty,
      );
      await expectLater(
        repository.appendTurn(
          _turn('cross', 's', 's-main', 5).withParticipant('other-speaker'),
          _alt('cross-alt', 'cross', 0),
        ),
        throwsStateError,
      );
      await db.close();
      db = _database(path);
      repository = SQLiteTavernRepository(db);
      expect(
        (await repository.getSession('s')).activeStoryLineId,
        'grandchild',
      );
      expect((await repository.loadTranscript('s')).turns, hasLength(3));
      expect((await repository.listAttempts('a5')), hasLength(3));
      await repository.deleteSession('s');
      expect(await (await db.database).query('tavern_turns'), isEmpty);
      expect(await repository.getSession('other'), isNotNull);
      await db.close();
    },
  );

  test('v12 migrates through v13 to v14 without touching old rows', () async {
    final dir = await Directory.systemTemp.createTemp('ibuki_tavern_v12_');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'data.db');
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 12,
        onCreate: (db, _) async {
          for (final statement in SqliteSchema.createTableStatements) {
            if (!statement.contains('tavern_')) await db.execute(statement);
          }
          for (final statement in SqliteSchema.createIndexStatements) {
            if (!statement.contains('tavern_')) await db.execute(statement);
          }
          await db.insert('projects', {
            'id': 'old-project',
            'title': 'Novel kept',
            'created_at': _now.toIso8601String(),
            'updated_at': _now.toIso8601String(),
            'revision': 1,
          });
        },
      ),
    );
    await old.close();
    final db = _database(path);
    expect(await (await db.database).getVersion(), SqliteSchema.version);
    expect(await (await db.database).query('projects'), hasLength(1));
    await _seed(SQLiteTavernRepository(db));
    await db.close();
    final reopened = _database(path);
    expect(await (await reopened.database).getVersion(), SqliteSchema.version);
    expect(await (await reopened.database).query('projects'), hasLength(1));
    expect(
      await (await reopened.database).query('tavern_sessions'),
      hasLength(1),
    );
    await reopened.close();
  });

  test('failed v12 migration chain leaves old data and version intact', () async {
    final dir = await Directory.systemTemp.createTemp(
      'ibuki_tavern_failed_migration_',
    );
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'data.db');
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 12,
        onCreate: (db, _) async {
          for (final statement in SqliteSchema.createTableStatements) {
            if (!statement.contains('tavern_')) await db.execute(statement);
          }
          for (final statement in SqliteSchema.createIndexStatements) {
            if (!statement.contains('tavern_')) await db.execute(statement);
          }
          await db.insert('projects', {
            'id': 'keep-project',
            'title': 'Keep',
            'created_at': _now.toIso8601String(),
            'updated_at': _now.toIso8601String(),
            'revision': 1,
          });
          await db.execute(
            'CREATE VIEW tavern_generation_attempts AS SELECT 1 AS id',
          );
        },
      ),
    );
    await old.close();
    final upgrading = _database(path);
    await expectLater(upgrading.database, throwsA(isA<Exception>()));
    final inspect = await databaseFactoryFfi.openDatabase(path);
    expect(await inspect.getVersion(), 12);
    expect(await inspect.query('projects'), hasLength(1));
    final tavernTables = await inspect.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'tavern_%'",
    );
    expect(tavernTables, isEmpty);
    await inspect.close();
  });

  test('logical archive restores Tavern lineage and selections', () async {
    final dir = await Directory.systemTemp.createTemp('ibuki_tavern_archive_');
    addTearDown(() => dir.delete(recursive: true));
    final source = _database(p.join(dir.path, 'source.db'));
    final repo = SQLiteTavernRepository(source);
    await _seed(repo);
    await repo.addParticipant(
      TavernParticipant(
        id: 'persona',
        sessionId: 's',
        kind: TavernParticipantKind.persona,
        entityId: 'player-asset',
        position: 1,
      ),
    );
    await repo.appendTurn(_turn('t0', 's', 's-main', 0), _alt('a0', 't0', 0));
    for (var i = 1; i < 5; i++) {
      await repo.addAlternative(_alt('a$i', 't0', i));
    }
    await repo.selectAlternative('t0', 'a1');
    await repo.appendContentPart(_text('p0', 'a1', 'restored'));
    await repo.createStoryLine(
      TavernStoryLine(
        id: 'child',
        sessionId: 's',
        name: 'Child',
        position: 1,
        parentId: 's-main',
        originTurnId: 't0',
        originAlternativeId: 'a1',
        createdAt: _now,
      ),
      activate: true,
    );
    await repo.appendTurn(_turn('t1', 's', 'child', 0), _alt('a5', 't1', 0));
    for (var i = 0; i < 3; i++) {
      await repo.recordAttempt(
        TavernGenerationAttempt(
          id: 'attempt-$i',
          sessionId: 's',
          storyLineId: 'child',
          turnId: 't1',
          alternativeId: 'a5',
          position: i,
          status: TavernGenerationStatus.queued,
          type: TavernGenerationType.normal,
          createdAt: _now,
        ),
      );
    }
    await repo.appendContentPart(
      TavernContentPart(
        id: 'old-part',
        alternativeId: 'a5',
        position: 0,
        kind: TavernContentKind.text,
        text: 'failed partial',
        generationAttemptId: 'attempt-0',
        createdAt: _now,
      ),
    );
    await repo.updateAttempt(
      'attempt-0',
      TavernGenerationStatus.failed,
      hasPartialContent: true,
    );
    await repo.updateAttempt(
      'attempt-1',
      TavernGenerationStatus.cancelled,
      hasPartialContent: true,
    );
    await repo.appendContentPart(
      TavernContentPart(
        id: 'final-part',
        alternativeId: 'a5',
        position: 1,
        kind: TavernContentKind.text,
        text: 'finished content',
        generationAttemptId: 'attempt-2',
        createdAt: _now,
      ),
    );
    await repo.appendContentPart(
      TavernContentPart(
        id: 'call-part',
        alternativeId: 'a5',
        position: 2,
        kind: TavernContentKind.toolCall,
        toolName: 'lookup',
        toolCallId: 'invocation',
        arguments: const {'q': 'x'},
        generationAttemptId: 'attempt-2',
        createdAt: _now,
      ),
    );
    await repo.appendContentPart(
      TavernContentPart(
        id: 'result-part',
        alternativeId: 'a5',
        position: 3,
        kind: TavernContentKind.toolResult,
        toolCallId: 'invocation',
        result: const {'ok': true},
        generationAttemptId: 'attempt-2',
        createdAt: _now,
      ),
    );
    await repo.appendContentPart(
      TavernContentPart(
        id: 'reasoning-part',
        alternativeId: 'a5',
        position: 4,
        kind: TavernContentKind.reasoning,
        text: 'private reasoning',
        generationAttemptId: 'attempt-2',
        createdAt: _now,
      ),
    );
    await repo.updateAttempt('attempt-2', TavernGenerationStatus.completed);
    await repo.createStoryLine(
      TavernStoryLine(
        id: 'nested',
        sessionId: 's',
        name: 'Nested',
        position: 2,
        parentId: 'child',
        originTurnId: 't1',
        originAlternativeId: 'a5',
        createdAt: _now,
      ),
      activate: true,
    );
    await repo.appendTurn(_turn('t2', 's', 'nested', 0), _alt('a6', 't2', 0));
    await repo.selectAlternative('t0', 'a4');
    final snapshot = await SQLiteBackupSnapshotStore(source).buildSnapshot();
    expect(snapshot.collections['tavernAlternatives'], hasLength(7));
    final codec = BackupArchiveCodec(applicationSupportDirectory: dir);
    final archive = File(p.join(dir.path, 'tavern.ibukibackup'));
    await codec.write(
      snapshot: snapshot,
      destination: archive,
      appVersion: 'foundation-test',
      schemaVersion: SqliteSchema.version,
    );
    final decoded = await codec.read(
      source: archive,
      staging: Directory(p.join(dir.path, 'staging')),
    );
    expect(decoded.preview.manifest.schemaVersion, SqliteSchema.version);
    final target = _database(p.join(dir.path, 'target.db'));
    await SQLiteBackupSnapshotStore(target).restore(
      decoded.snapshot,
      mode: BackupRestoreMode.fresh,
      restoredAssets: const {},
    );
    final restored = SQLiteTavernRepository(target);
    expect((await restored.getSession('s')).activeStoryLineId, 'nested');
    expect((await restored.listParticipants('s')), hasLength(2));
    final transcript = await restored.loadTranscript('s');
    expect(transcript.turns.map((item) => item.turn.id), ['t0', 't1', 't2']);
    expect(transcript.turns.first.alternatives, hasLength(5));
    expect(transcript.turns.first.selectedAlternative.id, 'a1');
    expect(transcript.turns.first.selectedParts.single.text, 'restored');
    expect(transcript.turns[1].selectedParts.map((part) => part.id), [
      'final-part',
      'call-part',
      'result-part',
      'reasoning-part',
    ]);
    expect((await restored.listAttempts('a5')).map((a) => a.status), [
      TavernGenerationStatus.failed,
      TavernGenerationStatus.cancelled,
      TavernGenerationStatus.completed,
    ]);
    await SQLiteBackupSnapshotStore(target).restore(
      decoded.snapshot,
      mode: BackupRestoreMode.merge,
      restoredAssets: const {},
    );
    final rows = await (await target.database).query('tavern_sessions');
    expect(rows, hasLength(2));
    final mergedId =
        rows.singleWhere((row) => row['id'] != 's')['id']! as String;
    final mergedSession = await restored.getSession(mergedId);
    expect(mergedSession.activeStoryLineId, isNot('nested'));
    final merged = await restored.loadTranscript(mergedId);
    expect(merged.turns, hasLength(3));
    expect(merged.turns.first.selectedAlternative.id, isNot('a1'));
    expect(merged.turns.first.selectedParts.single.text, 'restored');
    expect(
      merged.turns[1].selectedParts.map((p) => p.text).first,
      'finished content',
    );
    expect(merged.turns[1].selectedParts.map((p) => p.position), [1, 2, 3, 4]);
    expect(
      merged.turns[1].selectedParts[1].toolCallId,
      merged.turns[1].selectedParts[2].toolCallId,
    );
    final mergedAttempts = await restored.listAttempts(
      merged.turns[1].selectedAlternative.id,
    );
    expect(mergedAttempts, hasLength(3));
    expect(
      mergedAttempts.every(
        (a) =>
            a.sessionId == mergedId &&
            a.turnId == merged.turns[1].turn.id &&
            a.alternativeId == merged.turns[1].selectedAlternative.id,
      ),
      isTrue,
    );
    expect((await restored.listParticipants(mergedId)), hasLength(2));
    await source.close();
    await target.close();
  });

  test('100, 500 and 1000 turn projections with five alternatives', () async {
    final dir = await Directory.systemTemp.createTemp('ibuki_tavern_scale_');
    addTearDown(() => dir.delete(recursive: true));
    final db = _database(p.join(dir.path, 'scale.db'));
    final repository = SQLiteTavernRepository(db);
    await _seed(repository);
    final executor = await db.database;
    await executor.transaction((txn) async {
      for (var i = 0; i < 1000; i++) {
        final id = 'turn-$i';
        await txn.insert('tavern_turns', {
          'id': id,
          'session_id': 's',
          'story_line_id': 's-main',
          'position': i,
          'participant_id': 's-speaker',
          'role': 'character',
          'created_at': _now.toIso8601String(),
          'updated_at': _now.toIso8601String(),
        });
        for (var a = 0; a < 5; a++) {
          final altId = '$id-alt-$a';
          await txn.insert('tavern_alternatives', {
            'id': altId,
            'turn_id': id,
            'position': a,
            'origin': 'generated',
            'created_at': _now.toIso8601String(),
          });
          await txn.insert('tavern_content_parts', {
            'id': '$altId-part',
            'alternative_id': altId,
            'position': 0,
            'kind': 'text',
            'text_value': 'Synthetic reply',
            'created_at': _now.toIso8601String(),
          });
        }
        await txn.update(
          'tavern_turns',
          {'selected_alternative_id': '$id-alt-0'},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
    final watch = Stopwatch()..start();
    final projection = await repository.loadTranscript('s');
    watch.stop();
    // Synthetic timing only; no user content or prompt text is logged.
    debugPrint('TAVERN_PROJECTION_1000_MS=${watch.elapsedMilliseconds}');
    expect(projection.turns, hasLength(1000));
    expect(projection.turns.first.alternatives, hasLength(5));
    expect(projection.turns.last.selectedParts.single.text, 'Synthetic reply');
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    for (final count in [100, 500]) {
      final line = TavernStoryLine(
        id: 'branch-$count',
        sessionId: 's',
        name: 'Fork at $count',
        position: count,
        parentId: 's-main',
        originTurnId: 'turn-${count - 1}',
        originAlternativeId: 'turn-${count - 1}-alt-1',
        createdAt: _now,
      );
      await repository.createStoryLine(line);
      expect(
        (await repository.loadTranscript('s', storyLineId: line.id)).turns,
        hasLength(count),
      );
    }
    await db.close();
  });

  test(
    'nested branch freezes ancestors and archive preserves descendants',
    () async {
      Future<void> exercise(TavernRepository repository) async {
        await _seed(repository);
        await repository.appendTurn(
          _turn('one', 's', 's-main', 0),
          _alt('one-a', 'one', 0),
        );
        await repository.appendTurn(
          _turn('three', 's', 's-main', 20),
          _alt('three-a', 'three', 0),
        );
        await repository.addAlternative(_alt('three-b', 'three', 1));
        await repository.appendTurn(
          _turn('two', 's', 's-main', 10),
          _alt('two-a', 'two', 0),
        );
        expect(
          (await repository.loadTranscript('s')).turns.map((t) => t.turn.id),
          ['one', 'two', 'three'],
        );
        await repository.createStoryLine(
          TavernStoryLine(
            id: 'A',
            sessionId: 's',
            name: 'A',
            position: 1,
            parentId: 's-main',
            originTurnId: 'three',
            originAlternativeId: 'three-a',
            createdAt: _now,
          ),
        );
        await repository.appendTurn(
          _turn('a-turn', 's', 'A', 0),
          _alt('a-turn-a', 'a-turn', 0),
        );
        await repository.addAlternative(_alt('a-turn-b', 'a-turn', 1));
        await repository.createStoryLine(
          TavernStoryLine(
            id: 'A2',
            sessionId: 's',
            name: 'A2',
            position: 2,
            parentId: 'A',
            originTurnId: 'a-turn',
            originAlternativeId: 'a-turn-a',
            createdAt: _now,
          ),
        );
        await repository.appendTurn(
          _turn('a2-turn', 's', 'A2', 0),
          _alt('a2-turn-a', 'a2-turn', 0),
        );
        await repository.selectAlternative('three', 'three-b');
        await repository.selectAlternative('a-turn', 'a-turn-b');
        final nested = await repository.loadTranscript('s', storyLineId: 'A2');
        expect(nested.turns.map((t) => t.turn.id), [
          'one',
          'two',
          'three',
          'a-turn',
          'a2-turn',
        ]);
        expect(nested.turns[2].selectedAlternative.id, 'three-a');
        expect(nested.turns[3].selectedAlternative.id, 'a-turn-a');
        expect((await repository.getStoryLine('A2')).originTurnId, 'a-turn');
        expect(
          (await repository.loadTranscript(
            's',
          )).turns[2].selectedAlternative.id,
          'three-b',
        );
        await expectLater(repository.archiveStoryLine('A'), throwsStateError);
        await repository.selectStoryLine('s', 's-main');
        await repository.archiveStoryLine('A2');
        await repository.archiveStoryLine('A');
        expect(
          (await repository.loadTranscript(
            's',
            storyLineId: 'A2',
          )).turns[2].selectedAlternative.id,
          'three-a',
        );
        await expectLater(
          repository.selectStoryLine('s', 'A'),
          throwsStateError,
        );
      }

      await exercise(InMemoryTavernRepository());
      final dir = await Directory.systemTemp.createTemp('ibuki_tavern_nested_');
      addTearDown(() => dir.delete(recursive: true));
      final db = _database(p.join(dir.path, 'nested.db'));
      await exercise(SQLiteTavernRepository(db));
      await db.close();
    },
  );

  test('alternative, rich parts and retry attempts remain separate', () async {
    Future<void> exercise(TavernRepository repository) async {
      await _seed(repository);
      await repository.addParticipant(
        TavernParticipant(
          id: 'player',
          sessionId: 's',
          kind: TavernParticipantKind.persona,
          entityId: 'persona-asset',
          position: 1,
        ),
      );
      await repository.appendTurn(
        TavernTurn(
          id: 'user-turn',
          sessionId: 's',
          storyLineId: 's-main',
          position: 0,
          participantId: 'player',
          role: TavernTurnRole.player,
          createdAt: _now,
          updatedAt: _now,
        ),
        TavernAlternative(
          id: 'user-manual',
          turnId: 'user-turn',
          position: 0,
          origin: TavernAlternativeOrigin.manual,
          createdAt: _now,
        ),
      );
      await repository.addAlternative(
        TavernAlternative(
          id: 'user-imported',
          turnId: 'user-turn',
          position: 1,
          origin: TavernAlternativeOrigin.imported,
          createdAt: _now,
        ),
      );
      await repository.appendTurn(
        _turn('reply', 's', 's-main', 1),
        _alt('reply-a', 'reply', 0),
      );
      await expectLater(
        repository.selectAlternative('reply', 'user-imported'),
        throwsStateError,
      );
      await expectLater(
        repository.deleteAlternative('reply-a'),
        throwsStateError,
      );
      for (var i = 0; i < 3; i++) {
        await repository.recordAttempt(
          TavernGenerationAttempt(
            id: 'try-$i',
            sessionId: 's',
            storyLineId: 's-main',
            turnId: 'reply',
            alternativeId: 'reply-a',
            position: i,
            status: TavernGenerationStatus.queued,
            type: TavernGenerationType.normal,
            createdAt: _now,
          ),
        );
      }
      await repository.appendContentPart(
        TavernContentPart(
          id: 'failed-text',
          alternativeId: 'reply-a',
          position: 0,
          kind: TavernContentKind.text,
          generationAttemptId: 'try-0',
          text: 'failed partial',
          createdAt: _now,
        ),
      );
      await repository.updateAttempt(
        'try-0',
        TavernGenerationStatus.failed,
        reason: 'transport',
        hasPartialContent: true,
      );
      await repository.appendContentPart(
        TavernContentPart(
          id: 'stopped-text',
          alternativeId: 'reply-a',
          position: 1,
          kind: TavernContentKind.text,
          generationAttemptId: 'try-1',
          text: 'stopped partial',
          createdAt: _now,
        ),
      );
      await repository.updateAttempt(
        'try-1',
        TavernGenerationStatus.cancelled,
        reason: 'user stop',
        hasPartialContent: true,
      );
      await repository.appendContentPart(
        TavernContentPart(
          id: 'final-text',
          alternativeId: 'reply-a',
          position: 2,
          kind: TavernContentKind.text,
          generationAttemptId: 'try-2',
          text: 'finished',
          createdAt: _now,
        ),
      );
      await repository.updateAttempt('try-2', TavernGenerationStatus.completed);
      await repository.appendContentPart(
        TavernContentPart(
          id: 'call',
          alternativeId: 'reply-a',
          position: 3,
          kind: TavernContentKind.toolCall,
          toolName: 'lookup',
          toolCallId: 'invocation-1',
          arguments: const {'query': 'x'},
          generationAttemptId: 'try-2',
          createdAt: _now,
        ),
      );
      await repository.appendContentPart(
        TavernContentPart(
          id: 'result',
          alternativeId: 'reply-a',
          position: 4,
          kind: TavernContentKind.toolResult,
          toolCallId: 'invocation-1',
          result: const {'ok': true},
          generationAttemptId: 'try-2',
          createdAt: _now,
        ),
      );
      await repository.appendContentPart(
        TavernContentPart(
          id: 'future',
          alternativeId: 'reply-a',
          position: 5,
          kind: TavernContentKind.unknown,
          unknownKind: 'futureVisualPart',
          metadata: const {'source': 'synthetic'},
          createdAt: _now,
        ),
      );
      await repository.appendContentPart(
        TavernContentPart(
          id: 'summary',
          alternativeId: 'reply-a',
          position: 6,
          kind: TavernContentKind.reasoningSummary,
          text: 'short reasoning summary',
          createdAt: _now,
        ),
      );
      await repository.appendContentPart(
        TavernContentPart(
          id: 'unavailable',
          alternativeId: 'reply-a',
          position: 7,
          kind: TavernContentKind.reasoningUnavailable,
          createdAt: _now,
        ),
      );
      await repository.appendContentPart(
        TavernContentPart(
          id: 'attachment',
          alternativeId: 'reply-a',
          position: 8,
          kind: TavernContentKind.attachment,
          assetReference: 'asset-1',
          mimeType: 'image/png',
          createdAt: _now,
        ),
      );
      await repository.appendContentPart(
        TavernContentPart(
          id: 'event',
          alternativeId: 'reply-a',
          position: 9,
          kind: TavernContentKind.event,
          text: 'scene changed',
          createdAt: _now,
        ),
      );
      await expectLater(
        repository.appendContentPart(
          TavernContentPart(
            id: 'cross-attempt',
            alternativeId: 'user-manual',
            position: 0,
            kind: TavernContentKind.text,
            text: 'no',
            generationAttemptId: 'try-2',
            createdAt: _now,
          ),
        ),
        throwsStateError,
      );
      final projection = (await repository.loadTranscript('s')).turns.last;
      expect(projection.selectedParts.map((part) => part.id), [
        'final-text',
        'call',
        'result',
        'future',
        'summary',
        'unavailable',
        'attachment',
        'event',
      ]);
      expect(projection.visibleParts.map((part) => part.id), [
        'final-text',
        'attachment',
        'event',
      ]);
      final call = projection.selectedParts.firstWhere((p) => p.id == 'call');
      final result = projection.selectedParts.firstWhere(
        (p) => p.id == 'result',
      );
      expect(result.toolCallId, call.toolCallId);
      expect(result.result, const {'ok': true});
      expect(
        projection.selectedParts
            .firstWhere((p) => p.id == 'future')
            .unknownKind,
        'futureVisualPart',
      );
      expect((await repository.listAttempts('reply-a')).map((a) => a.status), [
        TavernGenerationStatus.failed,
        TavernGenerationStatus.cancelled,
        TavernGenerationStatus.completed,
      ]);
      await repository.addAlternative(
        _alt('reply-b', 'reply', 1),
        attempt: TavernGenerationAttempt(
          id: 'regenerate',
          sessionId: 's',
          storyLineId: 's-main',
          turnId: 'reply',
          alternativeId: 'reply-b',
          position: 0,
          status: TavernGenerationStatus.queued,
          type: TavernGenerationType.regenerate,
          createdAt: _now,
        ),
      );
      expect((await repository.listAttempts('reply-a')), hasLength(3));
      expect((await repository.listAttempts('reply-b')), hasLength(1));
      await expectLater(
        repository.addAlternative(
          _alt('reply-c', 'reply', 2),
          attempt: TavernGenerationAttempt(
            id: 'bad-bundle',
            sessionId: 's',
            storyLineId: 's-main',
            turnId: 'reply',
            alternativeId: 'reply-a',
            position: 0,
            status: TavernGenerationStatus.queued,
            type: TavernGenerationType.regenerate,
            createdAt: _now,
          ),
        ),
        throwsStateError,
      );
      expect(
        (await repository.loadTranscript('s')).turns.last.alternatives,
        hasLength(2),
      );
      await expectLater(
        repository.addAlternative(
          _alt('reply-c', 'reply', 2),
          attempt: TavernGenerationAttempt(
            id: 'regenerate',
            sessionId: 's',
            storyLineId: 's-main',
            turnId: 'reply',
            alternativeId: 'reply-c',
            position: 0,
            status: TavernGenerationStatus.queued,
            type: TavernGenerationType.regenerate,
            createdAt: _now,
          ),
        ),
        throwsA(anything),
      );
      expect(
        (await repository.loadTranscript('s')).turns.last.alternatives,
        hasLength(2),
      );
      await repository.appendTurn(
        _turn('placeholder', 's', 's-main', 2),
        _alt('placeholder-a', 'placeholder', 0),
      );
      expect(
        (await repository.loadTranscript('s')).turns.last.selectedParts,
        isEmpty,
      );
    }

    await exercise(InMemoryTavernRepository());
    final dir = await Directory.systemTemp.createTemp('ibuki_tavern_rich_');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'rich.db');
    var db = _database(path);
    await exercise(SQLiteTavernRepository(db));
    await db.close();
    db = _database(path);
    final restored = (await SQLiteTavernRepository(
      db,
    ).loadTranscript('s')).turns.firstWhere((item) => item.turn.id == 'reply');
    expect(
      restored.selectedParts.firstWhere((p) => p.id == 'future').unknownKind,
      'futureVisualPart',
    );
    expect(
      restored.selectedParts
          .firstWhere((p) => p.id == 'final-text')
          .generationAttemptId,
      'try-2',
    );
    await db.close();
  });
}

IbukiDatabase _database(String path) => IbukiDatabase(
  pathResolver: () async => path,
  databaseFactory: databaseFactoryFfi,
);

extension on TavernTurn {
  TavernTurn withParticipant(String id) => TavernTurn(
    id: this.id,
    sessionId: sessionId,
    storyLineId: storyLineId,
    position: position,
    participantId: id,
    role: role,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
