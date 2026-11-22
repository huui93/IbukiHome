import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/ai_draft_update.dart';
import 'package:ibukihome/application/ai/auto_story_runner.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';

void main() {
  test(
    'auto story generates serially and rebuilds each segment request',
    () async {
      late AutoStoryRunner runner;
      final requests = <_RecordedRequest>[];
      var active = 0;
      var maximumActive = 0;
      var savedSegments = 0;
      var id = 0;
      runner = AutoStoryRunner(
        generateSegment:
            ({
              required projectId,
              required userInstruction,
              required selectedCharacterIds,
              required selectedWorldCardIds,
              required requestId,
              required segmentId,
              required nowUtc,
            }) async* {
              active += 1;
              maximumActive = maximumActive < active ? active : maximumActive;
              requests.add(
                _RecordedRequest(
                  projectId: projectId,
                  instruction: userInstruction,
                  requestId: requestId,
                  segmentId: segmentId,
                  visibleSavedSegments: savedSegments,
                ),
              );
              yield AiDraftUpdate(
                requestId: requestId,
                draft: '正文 ${requests.length}',
                status: AiDraftStatus.streaming,
              );
              savedSegments += 1;
              active -= 1;
              yield AiDraftUpdate(
                requestId: requestId,
                draft: '正文 ${requests.length}',
                status: AiDraftStatus.completed,
              );
            },
        cancelGeneration: (_) => true,
        nextId: (prefix) => '$prefix-${id++}',
        now: () => DateTime.utc(2026, 8, 25),
      );
      addTearDown(runner.dispose);
      final subscription = runner.updates.listen((update) {
        if (update.status == AutoStoryRunStatus.segmentCompleted &&
            update.generatedCount == 3) {
          runner.stop(projectId: 'project');
        }
      });
      addTearDown(subscription.cancel);

      await runner.start(
        projectId: 'project',
        initialInstruction: '第一段方向',
        selectedCharacterIds: const {'character'},
        selectedWorldCardIds: const {'world'},
      );

      expect(maximumActive, 1);
      expect(requests, hasLength(3));
      expect(requests.map((request) => request.projectId).toSet(), {'project'});
      expect(requests.map((request) => request.instruction), ['第一段方向', '', '']);
      expect(requests.map((request) => request.visibleSavedSegments), [
        0,
        1,
        2,
      ]);
      expect(
        requests.map((request) => request.requestId).toSet(),
        hasLength(3),
      );
      expect(
        requests.map((request) => request.segmentId).toSet(),
        hasLength(3),
      );
    },
  );

  test('stop between segments prevents the next request', () async {
    late AutoStoryRunner runner;
    var calls = 0;
    runner = _runner(
      generate: (requestId) async* {
        calls += 1;
        yield AiDraftUpdate(
          requestId: requestId,
          draft: 'saved',
          status: AiDraftStatus.completed,
        );
      },
    );
    addTearDown(runner.dispose);
    final subscription = runner.updates.listen((update) {
      if (update.status == AutoStoryRunStatus.segmentCompleted) {
        runner.stop(projectId: 'project');
      }
    });
    addTearDown(subscription.cancel);

    await _start(runner);

    expect(calls, 1);
  });

  test('stop during streaming cancels the active request', () async {
    final cancellation = Completer<void>();
    final started = Completer<void>();
    String? cancelledRequestId;
    late AutoStoryRunner runner;
    runner = _runner(
      generate: (requestId) async* {
        yield AiDraftUpdate(
          requestId: requestId,
          draft: 'partial',
          status: AiDraftStatus.streaming,
        );
        if (!started.isCompleted) started.complete();
        await cancellation.future;
        yield AiDraftUpdate(
          requestId: requestId,
          draft: 'partial',
          status: AiDraftStatus.cancelled,
        );
      },
      cancel: (requestId) {
        cancelledRequestId = requestId;
        if (!cancellation.isCompleted) cancellation.complete();
        return true;
      },
    );
    addTearDown(runner.dispose);

    final future = _start(runner);
    await started.future;
    runner.stop(projectId: 'project');
    await future;

    expect(cancelledRequestId, isNotNull);
    expect(runner.isRunning, isFalse);
  });

  test('provider failure pauses without launching another segment', () async {
    var calls = 0;
    final runner = _runner(
      generate: (requestId) async* {
        calls += 1;
        throw StateError('provider failed');
      },
    );
    addTearDown(runner.dispose);
    final updates = <AutoStoryRunUpdate>[];
    final subscription = runner.updates.listen(updates.add);
    addTearDown(subscription.cancel);

    await _start(runner);

    expect(calls, 1);
    expect(updates.last.status, AutoStoryRunStatus.paused);
    expect(updates.last.error, isA<StateError>());
  });

  test('segment save failure is a hard pause', () async {
    final runner = _runner(
      generate: (requestId) async* {
        throw const AiPersistenceException(
          stage: AiPersistenceStage.segmentSave,
          causeType: 'ConstraintException',
          message: '正文已经生成，但本地保存失败。',
        );
      },
    );
    addTearDown(runner.dispose);
    final updates = <AutoStoryRunUpdate>[];
    final subscription = runner.updates.listen(updates.add);
    addTearDown(subscription.cancel);

    await _start(runner);

    expect(updates.last.status, AutoStoryRunStatus.paused);
    expect(updates.last.error, isA<AiPersistenceException>());
  });

  test('background pause cancels once and does not restart', () async {
    final cancellation = Completer<void>();
    final started = Completer<void>();
    var calls = 0;
    late AutoStoryRunner runner;
    runner = _runner(
      generate: (requestId) async* {
        calls += 1;
        if (!started.isCompleted) started.complete();
        await cancellation.future;
        yield AiDraftUpdate(
          requestId: requestId,
          draft: '',
          status: AiDraftStatus.cancelled,
        );
      },
      cancel: (_) {
        if (!cancellation.isCompleted) cancellation.complete();
        return true;
      },
    );
    addTearDown(runner.dispose);
    final updates = <AutoStoryRunUpdate>[];
    final subscription = runner.updates.listen(updates.add);
    addTearDown(subscription.cancel);

    final future = _start(runner);
    await started.future;
    runner.stop(projectId: 'project', reason: AutoStoryStopReason.background);
    await future;
    await Future<void>.delayed(Duration.zero);

    expect(calls, 1);
    expect(updates.last.status, AutoStoryRunStatus.paused);
    expect(updates.last.stopReason, AutoStoryStopReason.background);
  });

  test('project change cancels the old project lifecycle', () async {
    final cancellation = Completer<void>();
    final started = Completer<void>();
    late AutoStoryRunner runner;
    runner = _runner(
      generate: (requestId) async* {
        if (!started.isCompleted) started.complete();
        await cancellation.future;
        yield AiDraftUpdate(
          requestId: requestId,
          draft: '',
          status: AiDraftStatus.cancelled,
        );
      },
      cancel: (_) {
        if (!cancellation.isCompleted) cancellation.complete();
        return true;
      },
    );
    addTearDown(runner.dispose);

    final future = _start(runner);
    await started.future;
    runner.stop(
      projectId: 'project',
      reason: AutoStoryStopReason.projectChanged,
    );
    await future;

    expect(runner.activeProjectId, isNull);
    expect(runner.isRunning, isFalse);
  });
}

typedef _Generate = Stream<AiDraftUpdate> Function(String requestId);

AutoStoryRunner _runner({
  required _Generate generate,
  AutoStoryCancelGeneration? cancel,
}) {
  var id = 0;
  return AutoStoryRunner(
    generateSegment:
        ({
          required projectId,
          required userInstruction,
          required selectedCharacterIds,
          required selectedWorldCardIds,
          required requestId,
          required segmentId,
          required nowUtc,
        }) => generate(requestId),
    cancelGeneration: cancel ?? (_) => true,
    nextId: (prefix) => '$prefix-${id++}',
    now: () => DateTime.utc(2026, 8, 25),
  );
}

Future<void> _start(AutoStoryRunner runner) {
  return runner.start(
    projectId: 'project',
    initialInstruction: '方向',
    selectedCharacterIds: const {},
    selectedWorldCardIds: const {},
  );
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.projectId,
    required this.instruction,
    required this.requestId,
    required this.segmentId,
    required this.visibleSavedSegments,
  });

  final String projectId;
  final String instruction;
  final String requestId;
  final String segmentId;
  final int visibleSavedSegments;
}
