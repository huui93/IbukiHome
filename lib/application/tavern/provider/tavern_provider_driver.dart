import '../../../data/ai/tavern_provider_adapter.dart';
import '../tavern_generation_runtime.dart';
import 'tavern_provider_models.dart';

class TavernProviderRunMetadata {
  TavernProviderRunMetadata({
    required this.providerId,
    required this.model,
    required this.protocol,
    required this.requestFingerprint,
  });
  final String providerId, model, requestFingerprint;
  final TavernProviderProtocol protocol;
  int visibleCharacters = 0, reasoningCharacters = 0;
  int? inputTokens, outputTokens;
  TavernReasoningAvailability reasoning =
      TavernReasoningAvailability.unavailable;
  TavernProviderFailure? failure;
}

class _Prepared {
  const _Prepared(this.request, this.credential, this.metadata);
  final TavernProviderRequest request;
  final String credential;
  final TavernProviderRunMetadata metadata;
}

class TavernProviderDriver implements TavernGenerationDriver {
  TavernProviderDriver(this.adapter, {this.onStage});
  final TavernProviderAdapter adapter;
  final void Function(String attemptId, bool streaming)? onStage;
  final Map<String, _Prepared> _requests = {};

  void register(
    String attemptId,
    TavernProviderRequest request,
    String credential,
    TavernProviderRunMetadata metadata,
  ) {
    if (_requests.containsKey(attemptId)) {
      throw StateError('Duplicate Provider request.');
    }
    _requests[attemptId] = _Prepared(request, credential, metadata);
  }

  void discard(String attemptId) => _requests.remove(attemptId);

  @override
  Stream<TavernGenerationEvent> generate(
    TavernGenerationTarget target,
    TavernGenerationCancellation cancellation,
  ) async* {
    final prepared = _requests.remove(target.attemptId);
    if (prepared == null) {
      yield TavernGenerationFailed(
        target.attemptId,
        const TavernGenerationError(
          TavernGenerationErrorKind.invariant,
          'No prepared Provider request.',
        ),
      );
      return;
    }
    final metadata = prepared.metadata;
    var receivedReasoning = false;
    try {
      onStage?.call(target.attemptId, false);
      await for (final event in adapter.generate(
        prepared.request,
        prepared.credential,
        cancellation,
        expectedFingerprint: metadata.requestFingerprint,
      )) {
        if (cancellation.isCancelled) return;
        if (event is TavernProviderText) {
          metadata.visibleCharacters += event.text.length;
          onStage?.call(target.attemptId, true);
          yield TavernTextDelta(target.attemptId, event.text);
        } else if (event is TavernProviderReasoning) {
          if (event.text.isEmpty) continue;
          receivedReasoning = true;
          metadata.reasoning = event.kind;
          metadata.reasoningCharacters += event.text.length;
          onStage?.call(target.attemptId, true);
          yield event.kind == TavernReasoningAvailability.summary
              ? TavernReasoningSummaryDelta(target.attemptId, event.text)
              : TavernReasoningDelta(target.attemptId, event.text);
        } else if (event is TavernProviderUsage) {
          metadata.inputTokens = event.inputTokens;
          metadata.outputTokens = event.outputTokens;
        } else if (event is TavernProviderFinished) {
          if (!receivedReasoning) {
            yield TavernReasoningUnavailable(target.attemptId);
          }
          yield TavernGenerationComplete(target.attemptId);
          return;
        }
      }
    } on TavernProviderFailure catch (error) {
      metadata.failure = error;
      yield TavernGenerationFailed(
        target.attemptId,
        TavernGenerationError(
          switch (error.kind) {
            TavernProviderErrorKind.timeout =>
              TavernGenerationErrorKind.timeout,
            TavernProviderErrorKind.unsupportedCapability =>
              TavernGenerationErrorKind.unsupported,
            TavernProviderErrorKind.malformedResponse ||
            TavernProviderErrorKind.incompleteStream =>
              TavernGenerationErrorKind.invalidResponse,
            TavernProviderErrorKind.transport =>
              TavernGenerationErrorKind.transport,
            _ => TavernGenerationErrorKind.rejected,
          },
          error.kind.name,
          reasonCode: error.kind.name,
        ),
      );
    }
  }
}
