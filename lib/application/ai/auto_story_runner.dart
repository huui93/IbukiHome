// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'ai_draft_update.dart';

typedef AutoStoryGenerateSegment =
    Stream<AiDraftUpdate> Function({
      required String projectId,
      required String userInstruction,
      required Set<String> selectedCharacterIds,
      required Set<String> selectedWorldCardIds,
      required String requestId,
      required String segmentId,
      required DateTime nowUtc,
    });

typedef AutoStoryCancelGeneration = bool Function(String requestId);
typedef AutoStoryNextId = String Function(String prefix);
typedef AutoStoryNow = DateTime Function();

enum AutoStoryRunStatus {
  running,
  streaming,
  retrying,
  segmentCompleted,
  stopped,
  paused,
}

enum AutoStoryStopReason { user, background, projectChanged, pageDisposed }

class AutoStoryRunUpdate {
  const AutoStoryRunUpdate({
    required this.projectId,
    required this.status,
    required this.generatedCount,
    this.requestId,
    this.draft = '',
    this.error,
    this.stopReason,
    this.pluginNotice,
  });

  final String projectId;
  final AutoStoryRunStatus status;
  final int generatedCount;
  final String? requestId;
  final String draft;
  final Object? error;
  final AutoStoryStopReason? stopReason;
  final String? pluginNotice;
}

class AutoStoryRunner {
  AutoStoryRunner({
    required AutoStoryGenerateSegment generateSegment,
    required AutoStoryCancelGeneration cancelGeneration,
    required AutoStoryNextId nextId,
    required AutoStoryNow now,
  }) : _generateSegment = generateSegment,
       _cancelGeneration = cancelGeneration,
       _nextId = nextId,
       _now = now;

  final AutoStoryGenerateSegment _generateSegment;
  final AutoStoryCancelGeneration _cancelGeneration;
  final AutoStoryNextId _nextId;
  final AutoStoryNow _now;
  final StreamController<AutoStoryRunUpdate> _updates =
      StreamController<AutoStoryRunUpdate>.broadcast(sync: true);

  bool _running = false;
  bool _stopRequested = false;
  String? _activeProjectId;
  String? _activeRequestId;
  AutoStoryStopReason? _stopReason;

  Stream<AutoStoryRunUpdate> get updates => _updates.stream;
  bool get isRunning => _activeProjectId != null;
  String? get activeProjectId => _activeProjectId;

  Future<void> start({
    required String projectId,
    required String initialInstruction,
    required Set<String> selectedCharacterIds,
    required Set<String> selectedWorldCardIds,
  }) async {
    if (_activeProjectId != null) return;
    _running = true;
    _stopRequested = false;
    _stopReason = null;
    _activeProjectId = projectId;
    var generatedCount = 0;
    var instruction = initialInstruction;
    _emit(
      AutoStoryRunUpdate(
        projectId: projectId,
        status: AutoStoryRunStatus.running,
        generatedCount: generatedCount,
      ),
    );

    try {
      while (_running && !_stopRequested && _activeProjectId == projectId) {
        final requestId = _nextId('ai_request');
        final segmentId = _nextId('segment');
        _activeRequestId = requestId;
        var completed = false;

        await for (final update in _generateSegment(
          projectId: projectId,
          userInstruction: instruction,
          selectedCharacterIds: Set.unmodifiable(selectedCharacterIds),
          selectedWorldCardIds: Set.unmodifiable(selectedWorldCardIds),
          requestId: requestId,
          segmentId: segmentId,
          nowUtc: _now(),
        )) {
          if (_stopRequested || _activeProjectId != projectId) break;
          switch (update.status) {
            case AiDraftStatus.streaming:
            case AiDraftStatus.autoRecovering:
              _emit(
                AutoStoryRunUpdate(
                  projectId: projectId,
                  status: AutoStoryRunStatus.streaming,
                  generatedCount: generatedCount,
                  requestId: requestId,
                  draft: update.draft,
                  pluginNotice: update.pluginNotice,
                ),
              );
            case AiDraftStatus.retrying:
              _emit(
                AutoStoryRunUpdate(
                  projectId: projectId,
                  status: AutoStoryRunStatus.retrying,
                  generatedCount: generatedCount,
                  requestId: requestId,
                  draft: update.draft,
                  pluginNotice: update.pluginNotice,
                ),
              );
            case AiDraftStatus.completed:
              completed = true;
              generatedCount += 1;
              if (update.storyEnded) _stopRequested = true;
              _emit(
                AutoStoryRunUpdate(
                  projectId: projectId,
                  status: AutoStoryRunStatus.segmentCompleted,
                  generatedCount: generatedCount,
                  requestId: requestId,
                  draft: update.draft,
                  pluginNotice: update.pluginNotice,
                ),
              );
            case AiDraftStatus.cancelled:
              _stopRequested = true;
              break;
            case AiDraftStatus.limited:
            case AiDraftStatus.interrupted:
            case AiDraftStatus.contentFiltered:
            case AiDraftStatus.providerError:
              throw StateError('自动剧情在正文保存前以 ${update.status.name} 结束。');
          }
        }

        _activeRequestId = null;
        if (_stopRequested || !_running || _activeProjectId != projectId) {
          break;
        }
        if (!completed) {
          throw StateError('自动剧情生成流在正文保存前结束。');
        }
        instruction = '';
        await Future<void>.delayed(Duration.zero);
      }
    } catch (error) {
      if (!_stopRequested) {
        _emit(
          AutoStoryRunUpdate(
            projectId: projectId,
            status: AutoStoryRunStatus.paused,
            generatedCount: generatedCount,
            requestId: _activeRequestId,
            error: error,
          ),
        );
      }
    } finally {
      final reason = _stopReason;
      final stopped = _stopRequested;
      _running = false;
      _activeRequestId = null;
      _activeProjectId = null;
      if (stopped) {
        _emit(
          AutoStoryRunUpdate(
            projectId: projectId,
            status: reason == AutoStoryStopReason.user
                ? AutoStoryRunStatus.stopped
                : AutoStoryRunStatus.paused,
            generatedCount: generatedCount,
            stopReason: reason,
          ),
        );
      }
      _stopRequested = false;
      _stopReason = null;
    }
  }

  void stop({
    required String projectId,
    AutoStoryStopReason reason = AutoStoryStopReason.user,
  }) {
    if (!_running || _activeProjectId != projectId) return;
    _stopRequested = true;
    _stopReason = reason;
    _running = false;
    final requestId = _activeRequestId;
    if (requestId != null) _cancelGeneration(requestId);
  }

  void _emit(AutoStoryRunUpdate update) {
    if (!_updates.isClosed) _updates.add(update);
  }

  void dispose() {
    final projectId = _activeProjectId;
    if (projectId != null) {
      stop(projectId: projectId, reason: AutoStoryStopReason.pageDisposed);
    }
    unawaited(_updates.close());
  }
}
