import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/tavern/tavern_models.dart';
import '../../domain/tavern/tavern_world_info.dart';
import 'prompt/prompt_models.dart';
import 'provider/tavern_provider_models.dart';
import 'tavern_generation_orchestrator.dart';
import 'tavern_generation_runtime.dart';
import 'tavern_story_service.dart';

class TavernTraceCache {
  final _traces = <String, TavernOrchestrationTrace>{};
  TavernOrchestrationTrace? operator [](String id) => _traces[id];
  void put(TavernOrchestrationTrace trace) {
    _traces[trace.attemptId] = trace;
    while (_traces.length > 100) {
      _traces.remove(_traces.keys.first);
    }
  }
}

class TavernLivePresentation {
  const TavernLivePresentation({
    this.target,
    this.phase = TavernOrchestrationPhase.preparing,
    this.parts = const [],
  });
  final TavernGenerationTarget? target;
  final TavernOrchestrationPhase phase;
  final List<TavernContentPart> parts;
}

String tavernFriendlyError(Object error) {
  if (error is TavernReconciliationConflict) {
    return '这条故事线的世界书状态需要对账。当前已保护性暂停生成，请重试恢复或使用其他故事线。';
  }
  if (error is PromptCompileFailure) return '当前角色或设定超出了上下文额度。请调整设定或模型额度后重试。';
  if (error is TavernProviderFailure) {
    return switch (error.kind) {
      TavernProviderErrorKind.missingCredential =>
        '尚未填写 API Key。请到 API 设置完成配置。',
      TavernProviderErrorKind.unknownModel => '请先为这个故事选择可用的模型。',
      TavernProviderErrorKind.authentication ||
      TavernProviderErrorKind.permission => '模型服务未接受当前凭证，请检查 API 设置。',
      TavernProviderErrorKind.rateLimited => '模型服务暂时限流，请稍后重试。',
      TavernProviderErrorKind.quota => '模型服务额度不足，请检查服务账户。',
      TavernProviderErrorKind.contextExceeded => '模型无法容纳当前上下文，请调整额度或设定。',
      TavernProviderErrorKind.timeout => '回应超时了，可以重试这次回应。',
      TavernProviderErrorKind.unsupportedCapability => '当前模型配置不支持这项操作，请检查模型设置。',
      _ => '模型连接未完成，请检查网络后重试。',
    };
  }
  return '故事暂时无法完成这次操作，请检查角色、世界书与模型设置后重试。';
}

class TavernSessionController extends ChangeNotifier {
  TavernSessionController({
    required this.sessionId,
    required this.service,
    required this.owner,
    required this.traces,
  });
  final String sessionId;
  final TavernStoryService service;
  final TavernGenerationOrchestrator owner;
  final TavernTraceCache traces;
  final live = ValueNotifier(const TavernLivePresentation());
  TavernTranscriptProjection? projection;
  List<TavernParticipant> participants = const [];
  List<TavernStoryLine> lines = const [];
  final attempts = <String, List<TavernGenerationAttempt>>{};
  final partials = <String, List<TavernContentPart>>{};
  String? speakerId, error;
  bool loading = true,
      busy = false,
      _disposed = false,
      _cancelRequested = false;
  int _loadEpoch = 0;
  TavernOrchestrationHandle? _handle;
  Completer<void>? _startReady;
  Completer<void>? _settled;
  StreamSubscription<TavernGenerationSnapshot>? _partsSubscription;
  StreamSubscription<TavernOrchestrationUpdate>? _stageSubscription;
  Timer? _paintTimer;
  final _liveParts = <String, TavernContentPart>{};
  String? _savedUserId, _savedUserText;

  Future<void> load({bool initialize = true}) async {
    final epoch = ++_loadEpoch;
    if (initialize) {
      try {
        await owner.initialize();
      } catch (e) {
        error = tavernFriendlyError(e);
      }
    }
    try {
      final history = await service.repository.loadTranscript(sessionId);
      final cast = await service.repository.listParticipants(sessionId);
      final storyLines = await service.repository.listStoryLines(sessionId);
      if (_disposed || epoch != _loadEpoch) return;
      projection = history;
      participants = cast;
      lines = storyLines;
      if (!cast.any(
        (p) => p.id == speakerId && p.kind == TavernParticipantKind.character,
      )) {
        speakerId = cast
            .where((p) => p.kind == TavernParticipantKind.character)
            .firstOrNull
            ?.id;
      }
      loading = false;
      // Attempt details for visible rows are fetched on demand, not for all history.
      attempts.clear();
      partials.clear();
      if (history.turns.isNotEmpty) {
        final last = history.turns.last;
        await loadAttemptDetails(last.selectedAlternative.id, notify: false);
      }
    } catch (e) {
      if (!_disposed) {
        error = tavernFriendlyError(e);
        loading = false;
      }
    }
    _notify();
  }

  Future<void> loadAttemptDetails(String altId, {bool notify = true}) async {
    final data = await service.repository.listAttempts(altId);
    if (_disposed) return;
    attempts[altId] = data;
    if (data.isNotEmpty &&
        (data.last.status == TavernGenerationStatus.failed ||
            data.last.status == TavernGenerationStatus.cancelled)) {
      final raw = await service.repository.listContentParts(altId);
      if (_disposed) return;
      partials[altId] = raw
          .where((p) => p.generationAttemptId == data.last.id)
          .toList(growable: false);
    }
    if (notify) _notify();
  }

  void selectSpeaker(String id) {
    if (participants.any(
      (p) => p.id == id && p.kind == TavernParticipantKind.character,
    )) {
      speakerId = id;
      _notify();
    }
  }

  Future<bool> send(String text, {VoidCallback? onAccepted}) async {
    if (busy || text.trim().isEmpty || projection == null) return false;
    return _generate(
      TavernGenerationCommandKind.normal,
      text: text.trim(),
      onAccepted: onAccepted,
    );
  }

  Future<bool> act(
    TavernGenerationCommandKind kind,
    TavernTurnProjection row,
  ) async {
    if (busy ||
        projection == null ||
        row.turn.storyLineId != projection!.storyLine.id) {
      return false;
    }
    return _generate(kind, row: row);
  }

  Future<bool> _generate(
    TavernGenerationCommandKind kind, {
    String? text,
    TavernTurnProjection? row,
    VoidCallback? onAccepted,
  }) async {
    busy = true;
    error = null;
    _cancelRequested = false;
    _startReady = Completer<void>();
    _settled = Completer<void>();
    _liveParts.clear();
    live.value = const TavernLivePresentation();
    _notify();
    var accepted = false;
    try {
      final history = projection!;
      final settings = history.session.metadata['tavernBindingV1'];
      final binding = await service.resolveBinding(
        settings is Map ? Map<String, Object?>.from(settings) : const {},
      );
      if (_cancelRequested || _disposed) return false;
      final participant = kind == TavernGenerationCommandKind.normal
          ? speakerId
          : row!.turn.participantId;
      if (participant == null) throw StateError('Choose a Character first.');
      var contextTurn = row?.turn.id;
      if (kind == TavernGenerationCommandKind.normal) {
        final player = participants
            .where((p) => p.kind == TavernParticipantKind.persona)
            .firstOrNull;
        if (player == null) throw StateError('Player identity missing.');
        if (_savedUserText == text &&
            history.turns.lastOrNull?.turn.id == _savedUserId) {
          contextTurn = _savedUserId;
        } else {
          final own = history.turns
              .where((r) => r.turn.storyLineId == history.storyLine.id)
              .toList();
          final id = service.ids.nextId('tavern_user'),
              alt = service.ids.nextId('tavern_input');
          await service.repository.appendTurn(
            TavernTurn(
              id: id,
              sessionId: sessionId,
              storyLineId: history.storyLine.id,
              position: own.isEmpty ? 0 : own.last.turn.position + 1,
              participantId: player.id,
              role: TavernTurnRole.player,
              createdAt: service.clock.now(),
              updatedAt: service.clock.now(),
            ),
            TavernAlternative(
              id: alt,
              turnId: id,
              position: 0,
              origin: TavernAlternativeOrigin.manual,
              createdAt: service.clock.now(),
            ),
            initialParts: [
              TavernContentPart(
                id: service.ids.nextId('tavern_part'),
                alternativeId: alt,
                position: 0,
                kind: TavernContentKind.text,
                text: text,
                createdAt: service.clock.now(),
              ),
            ],
          );
          contextTurn = _savedUserId = id;
          _savedUserText = text;
        }
      }
      if (_cancelRequested || _disposed) return false;
      final attempt = service.ids.nextId('tavern_attempt');
      _stageSubscription = owner.updates
          .where((u) => u.attemptId == attempt)
          .listen((update) {
            if (!_disposed) {
              live.value = TavernLivePresentation(
                target: live.value.target,
                phase: update.phase,
                parts: live.value.parts,
              );
            }
          });
      final handle = await owner.start(
        TavernGenerationCommand(
          commandId: service.ids.nextId('tavern_command'),
          sessionId: sessionId,
          storyLineId: history.storyLine.id,
          turnId: row?.turn.id ?? service.ids.nextId('tavern_reply'),
          alternativeId:
              kind == TavernGenerationCommandKind.regenerate || row == null
              ? service.ids.nextId('tavern_answer')
              : row.selectedAlternative.id,
          attemptId: attempt,
          kind: kind,
          participantId: participant,
          contextTurnId: contextTurn,
        ),
        binding,
      );
      _handle = handle;
      accepted = true;
      _savedUserId = _savedUserText = null;
      onAccepted?.call();
      final runtime = handle.runtimeHandle;
      void update(TavernGenerationSnapshot snapshot) {
        if (_disposed) return;
        if (snapshot.pendingPart != null) {
          _liveParts[snapshot.pendingPart!.id] = snapshot.pendingPart!;
        }
        _paintTimer ??= Timer(const Duration(milliseconds: 80), () {
          _paintTimer = null;
          _publish(runtime.target);
        });
      }

      _partsSubscription = runtime.updates.listen(update);
      update(runtime.snapshot);
      _startReady!.complete();
      if (_cancelRequested || _disposed) await handle.cancel();
      final initialParts = await service.repository.listContentParts(
        runtime.target.alternativeId,
      );
      for (final part in initialParts.where(
        (p) => p.generationAttemptId == attempt,
      )) {
        final newer = _liveParts[part.id];
        if (newer == null ||
            (newer.text?.length ?? 0) <= (part.text?.length ?? 0)) {
          _liveParts[part.id] = part;
        }
      }
      await load(initialize: false);
      final result = await handle.done;
      traces.put(result.trace);
      if (!_disposed) {
        if (result.ledgerFailure) {
          error = tavernFriendlyError(
            const TavernReconciliationConflict('settlement'),
          );
        } else if (result.generation.phase == TavernExecutionPhase.failed) {
          final failure = result.trace.provider.failure;
          error = failure == null
              ? '回应没有完成，可以重试。'
              : tavernFriendlyError(failure);
        }
      }
    } catch (e) {
      if (!_disposed) error = tavernFriendlyError(e);
    } finally {
      if (!_startReady!.isCompleted) _startReady!.complete();
      await _partsSubscription?.cancel();
      await _stageSubscription?.cancel();
      _partsSubscription = null;
      _stageSubscription = null;
      _paintTimer?.cancel();
      _paintTimer = null;
      _handle = null;
      busy = false;
      if (!_disposed) {
        live.value = const TavernLivePresentation();
        await load(initialize: false);
      }
      _notify();
      _settled?.complete();
    }
    return accepted;
  }

  void _publish(TavernGenerationTarget target) {
    if (_disposed) return;
    final parts = _liveParts.values.toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    live.value = TavernLivePresentation(
      target: target,
      phase: live.value.phase,
      parts: List.unmodifiable(parts),
    );
  }

  Future<void> stop() async {
    _cancelRequested = true;
    await _startReady?.future;
    final handle = _handle;
    if (handle != null) {
      await handle.cancel();
      await handle.done;
    }
    await _settled?.future;
  }

  Future<void> switchLine(String id) async {
    await _edit(() async {
      if (busy) await stop();
      await service.repository.selectStoryLine(sessionId, id);
      _savedUserId = _savedUserText = null;
      await load(initialize: false);
    });
  }

  Future<void> selectAnswer(TavernTurnProjection row, String altId) async {
    if (row.turn.storyLineId != projection?.storyLine.id) return;
    await _edit(() async {
      await service.repository.selectAlternative(row.turn.id, altId);
      await load(initialize: false);
    });
  }

  Future<void> fork(
    TavernTurnProjection row,
    String name, {
    bool enter = true,
  }) async {
    await _edit(() => _fork(row, name, enter: enter));
  }

  Future<void> _fork(
    TavernTurnProjection row,
    String name, {
    required bool enter,
  }) async {
    if (busy) await stop();
    final history = projection!;
    final all = await service.repository.listStoryLines(sessionId);
    await service.repository.createStoryLine(
      TavernStoryLine(
        id: service.ids.nextId('tavern_line'),
        sessionId: sessionId,
        name: name.trim().isEmpty ? '新的故事线' : name.trim(),
        parentId: history.storyLine.id,
        originTurnId: row.turn.id,
        originAlternativeId: row.selectedAlternative.id,
        position: all.isEmpty ? 0 : all.last.position + 1,
        createdAt: service.clock.now(),
      ),
      activate: enter,
    );
    await load(initialize: false);
  }

  Future<void> _edit(Future<void> Function() action) async {
    try {
      error = null;
      await action();
    } catch (e) {
      error = tavernFriendlyError(e);
      _notify();
    }
  }

  Future<void> retryRecovery() async {
    try {
      await owner.retryRecovery();
      error = null;
      await load(initialize: false);
    } catch (e) {
      error = tavernFriendlyError(e);
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRequested = true;
    unawaited(stop());
    _paintTimer?.cancel();
    live.dispose();
    super.dispose();
  }
}
