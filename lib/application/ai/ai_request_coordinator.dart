import '../../data/ai/ai_provider_client.dart';

class AiRequestCoordinator {
  final Map<String, _ActiveAiRequest> _active = {};

  bool get hasActiveRequests => _active.isNotEmpty;

  AiRequestCancellation begin(
    String channel,
    String requestId, {
    String? scopeId,
  }) {
    cancel(channel);
    final cancellation = AiRequestCancellation();
    _active[channel] = _ActiveAiRequest(requestId, cancellation, scopeId);
    return cancellation;
  }

  bool isCurrent(String channel, String requestId) {
    return _active[channel]?.requestId == requestId;
  }

  bool cancel(String channel, {String? requestId}) {
    final active = _active[channel];
    if (active == null || requestId != null && active.requestId != requestId) {
      return false;
    }
    _active.remove(channel);
    active.cancellation.cancel();
    return true;
  }

  /// Cancels work for one deleted story without interrupting chat or other work.
  void cancelScope(String scopeId) {
    for (final channel in _active.keys.toList()) {
      if (_active[channel]?.scopeId == scopeId) cancel(channel);
    }
  }

  void finish(String channel, String requestId) {
    if (isCurrent(channel, requestId)) {
      _active.remove(channel);
    }
  }
}

class _ActiveAiRequest {
  const _ActiveAiRequest(this.requestId, this.cancellation, this.scopeId);

  final String requestId;
  final AiRequestCancellation cancellation;
  final String? scopeId;
}
