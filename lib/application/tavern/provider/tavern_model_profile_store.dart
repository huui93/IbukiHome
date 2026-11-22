import 'dart:convert';
import '../../security/secure_value_store.dart';
import '../../../domain/ai/ai_provider_config.dart';
import '../../../domain/ai/ai_provider_type.dart';
import 'tavern_provider_models.dart';

class TavernModelProfileStore {
  const TavernModelProfileStore(this.store);
  final SecureValueStore store;
  String _key(String providerId, String model) =>
      'tavern.model-profile.v1.${Uri.encodeComponent(providerId)}.${Uri.encodeComponent(model)}';

  Future<({int context, int output})?> savedLimits(
    String providerId,
    String model,
  ) async {
    final raw = await store.read(_key(providerId, model));
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map;
      final context = data['contextWindow'];
      final output = data['maximumOutput'];
      if (context is int && output is int && context > 128 && output > 0) {
        return (context: context, output: output);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> save(TavernProviderBinding binding) async {
    final c = binding.capabilities;
    await store.write(
      _key(binding.config.id, binding.model),
      jsonEncode({
        'protocol': binding.protocol.name,
        'contextWindow': c.contextWindow,
        'maximumOutput': c.maximumOutput,
        'outputTokens': binding.outputTokens,
        'systemRole': c.systemRole,
        'developerRole': c.developerRole,
        'streaming': c.streaming,
        'streamUsage': c.streamUsage,
        'reasoning': c.reasoning.name,
        'continuation': c.continuation.name,
        'toolCalling': c.toolCalling,
        'multimodal': c.multimodal,
        'tokenAccuracy': c.tokenAccuracy.name,
        'allowedParameters': c.allowedParameters.toList()..sort(),
        'parameters': binding.parameters,
        'allowLocalHttp': binding.allowLocalHttp,
        'timeoutMs': binding.timeout.inMilliseconds,
      }),
    );
  }

  Future<TavernProviderBinding> load(
    AiProviderConfig config,
    String model,
  ) async {
    final raw = await store.read(_key(config.id, model));
    if (raw == null) {
      return TavernProviderBinding(
        config: config,
        model: model,
        capabilities: const TavernModelCapabilities(),
        protocol: switch (config.type) {
          AiProviderType.gemini => TavernProviderProtocol.geminiNative,
          AiProviderType.claude => TavernProviderProtocol.claudeMessages,
          _ => TavernProviderProtocol.chatCompletions,
        },
      );
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return TavernProviderBinding(
        config: config,
        model: model,
        protocol: TavernProviderProtocol.values.byName(
          data['protocol'] as String,
        ),
        capabilities: TavernModelCapabilities(
          contextWindow: data['contextWindow'] as int,
          maximumOutput: data['maximumOutput'] as int,
          streaming: data['streaming'] as bool,
          streamUsage: data['streamUsage'] == true,
          systemRole: data['systemRole'] as bool,
          developerRole: data['developerRole'] as bool,
          reasoning: TavernReasoningAvailability.values.byName(
            data['reasoning'] as String,
          ),
          continuation: TavernContinuation.values.byName(
            data['continuation'] as String,
          ),
          toolCalling: data['toolCalling'] as bool,
          multimodal: data['multimodal'] as bool,
          tokenAccuracy: TavernTokenAccuracy.values.byName(
            data['tokenAccuracy'] as String,
          ),
          allowedParameters: Set.unmodifiable(
            (data['allowedParameters'] as List).cast<String>(),
          ),
        ),
        outputTokens: data['outputTokens'] as int,
        parameters: Map.unmodifiable(
          data['parameters'] as Map<String, dynamic>,
        ),
        allowLocalHttp: data['allowLocalHttp'] as bool,
        timeout: Duration(milliseconds: data['timeoutMs'] as int),
      );
    } catch (_) {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.unsupportedCapability,
      );
    }
  }
}
