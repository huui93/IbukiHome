import 'dart:async';

enum IbukiHook {
  beforePromptBuild,
  afterPromptBuild,
  beforeNovelPromptBuild,
  afterNovelPromptBuild,
  beforeChatPromptBuild,
  afterChatPromptBuild,
  beforePluginAiRequest,
  afterPluginAiResponse,
  afterAiResponse,
  afterChatMessageSaved,
  afterUserMessage,
  onChatSessionChanged,
  onCharacterChanged,
  onPluginEnabled,
  onPluginDisabled,
  beforeWorldTurn,
  afterDirectorDecision,
  beforeSpeakerSelection,
  afterSpeakerSelection,
  beforeWorldCharacterGeneration,
  afterWorldCharacterGeneration,
  beforeWorldMutation,
  afterWorldMutation,
  afterWorldTurn,
}

typedef PluginHookHandler = FutureOr<void> Function(Map<String, Object?> event);
typedef PluginTransformHookHandler =
    FutureOr<Map<String, Object?>?> Function(Map<String, Object?> event);

class PluginHookFailure {
  const PluginHookFailure({
    required this.pluginId,
    required this.hook,
    required this.errorType,
  });

  final String pluginId;
  final IbukiHook hook;
  final String errorType;
}

class PluginHookSubscription {
  PluginHookSubscription(this._cancel);

  final void Function() _cancel;
  bool _cancelled = false;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}

class IbukiHookBus {
  final Map<IbukiHook, List<_OwnedHookHandler>> _handlers = {};
  final Map<IbukiHook, List<_OwnedTransformHookHandler>> _transformHandlers =
      {};

  PluginHookSubscription subscribe({
    required String pluginId,
    required IbukiHook hook,
    required PluginHookHandler handler,
  }) {
    final owned = _OwnedHookHandler(pluginId, handler);
    (_handlers[hook] ??= <_OwnedHookHandler>[]).add(owned);
    return PluginHookSubscription(() => _handlers[hook]?.remove(owned));
  }

  PluginHookSubscription subscribeTransform({
    required String pluginId,
    required IbukiHook hook,
    required PluginTransformHookHandler handler,
  }) {
    final owned = _OwnedTransformHookHandler(pluginId, handler);
    (_transformHandlers[hook] ??= <_OwnedTransformHookHandler>[]).add(owned);
    return PluginHookSubscription(
      () => _transformHandlers[hook]?.remove(owned),
    );
  }

  Future<List<PluginHookFailure>> publish(
    IbukiHook hook,
    Map<String, Object?> event,
  ) async {
    final failures = <PluginHookFailure>[];
    for (final owned in List<_OwnedHookHandler>.from(
      _handlers[hook] ?? const [],
    )) {
      try {
        await owned.handler(Map.unmodifiable(event));
      } catch (error) {
        failures.add(
          PluginHookFailure(
            pluginId: owned.pluginId,
            hook: hook,
            errorType: error.runtimeType.toString(),
          ),
        );
      }
    }
    return List.unmodifiable(failures);
  }

  Future<PluginHookTransformResult> transform(
    IbukiHook hook,
    Map<String, Object?> event,
  ) async {
    var current = Map<String, Object?>.from(event);
    final failures = <PluginHookFailure>[];
    var invoked = 0;
    for (final owned in List<_OwnedTransformHookHandler>.from(
      _transformHandlers[hook] ?? const [],
    )) {
      invoked += 1;
      try {
        final updated = await owned.handler(Map.unmodifiable(current));
        if (updated != null) current = Map<String, Object?>.from(updated);
      } catch (error) {
        failures.add(
          PluginHookFailure(
            pluginId: owned.pluginId,
            hook: hook,
            errorType: error.runtimeType.toString(),
          ),
        );
      }
    }
    return PluginHookTransformResult(
      event: Map.unmodifiable(current),
      failures: List.unmodifiable(failures),
      invokedCount: invoked,
    );
  }

  void removePlugin(String pluginId) {
    for (final handlers in _handlers.values) {
      handlers.removeWhere((handler) => handler.pluginId == pluginId);
    }
    for (final handlers in _transformHandlers.values) {
      handlers.removeWhere((handler) => handler.pluginId == pluginId);
    }
  }

  int subscriptionCount(String pluginId) =>
      _handlers.values.fold(
        0,
        (count, handlers) =>
            count +
            handlers.where((handler) => handler.pluginId == pluginId).length,
      ) +
      _transformHandlers.values.fold(
        0,
        (count, handlers) =>
            count +
            handlers.where((handler) => handler.pluginId == pluginId).length,
      );
}

class PluginHookTransformResult {
  const PluginHookTransformResult({
    required this.event,
    required this.failures,
    required this.invokedCount,
  });

  final Map<String, Object?> event;
  final List<PluginHookFailure> failures;
  final int invokedCount;
}

class _OwnedHookHandler {
  const _OwnedHookHandler(this.pluginId, this.handler);

  final String pluginId;
  final PluginHookHandler handler;
}

class _OwnedTransformHookHandler {
  const _OwnedTransformHookHandler(this.pluginId, this.handler);

  final String pluginId;
  final PluginTransformHookHandler handler;
}
