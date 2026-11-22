import '../../../domain/ai/ai_provider_config.dart';
import '../prompt/prompt_models.dart';

enum TavernProviderProtocol {
  chatCompletions,
  responses,
  geminiNative,
  claudeMessages,
}

enum TavernReasoningAvailability { native, summary, unavailable }

enum TavernContinuation { unsupported, instruction, deepSeekPrefix }

enum TavernTokenAccuracy { estimated, exact }

enum TavernProviderErrorKind {
  missingCredential,
  authentication,
  permission,
  unknownModel,
  unsupportedCapability,
  contextExceeded,
  rateLimited,
  quota,
  transport,
  timeout,
  malformedResponse,
  incompleteStream,
  contentFiltered,
  cancelled,
  outputLimit,
  serverAbort,
}

class TavernProviderFailure implements Exception {
  const TavernProviderFailure(this.kind, {this.httpStatus});
  final TavernProviderErrorKind kind;
  final int? httpStatus;
  @override
  String toString() =>
      'TavernProviderFailure(${kind.name}, status=$httpStatus)';
}

class TavernModelCapabilities {
  const TavernModelCapabilities({
    this.contextWindow = 4096,
    this.maximumOutput = 512,
    this.streaming = true,
    this.streamUsage = false,
    this.systemRole = true,
    this.developerRole = false,
    this.reasoning = TavernReasoningAvailability.unavailable,
    this.continuation = TavernContinuation.unsupported,
    this.toolCalling = false,
    this.multimodal = false,
    this.tokenAccuracy = TavernTokenAccuracy.estimated,
    this.allowedParameters = const {},
  });
  final int contextWindow, maximumOutput;
  final bool streaming,
      streamUsage,
      systemRole,
      developerRole,
      toolCalling,
      multimodal;
  final TavernReasoningAvailability reasoning;
  final TavernContinuation continuation;
  final TavernTokenAccuracy tokenAccuracy;
  final Set<String> allowedParameters;
}

class TavernProviderBinding {
  const TavernProviderBinding({
    required this.config,
    required this.model,
    required this.capabilities,
    required this.protocol,
    this.allowLocalHttp = false,
    this.timeout = const Duration(seconds: 90),
    this.outputTokens = 256,
    this.parameters = const {},
  });
  final AiProviderConfig config;
  final String model;
  final TavernModelCapabilities capabilities;
  final TavernProviderProtocol protocol;
  final bool allowLocalHttp;
  final Duration timeout;
  final int outputTokens;
  final Map<String, Object?> parameters;
}

class TavernProviderRequest {
  const TavernProviderRequest(this.binding, this.prompt);
  final TavernProviderBinding binding;
  final CompiledPrompt prompt;
}

sealed class TavernProviderEvent {
  const TavernProviderEvent();
}

class TavernProviderText extends TavernProviderEvent {
  const TavernProviderText(this.text);
  final String text;
}

class TavernProviderReasoning extends TavernProviderEvent {
  const TavernProviderReasoning(this.text, this.kind);
  final String text;
  final TavernReasoningAvailability kind;
}

class TavernProviderUsage extends TavernProviderEvent {
  const TavernProviderUsage({this.inputTokens, this.outputTokens});
  final int? inputTokens, outputTokens;
}

class TavernProviderFinished extends TavernProviderEvent {
  const TavernProviderFinished();
}
