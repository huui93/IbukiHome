// ignore_for_file: prefer_initializing_formals

import '../../core/network/ai_provider_exceptions.dart';
import '../../data/ai/ai_provider_client.dart';
import '../../data/ai/ai_provider_registry.dart';
import '../../data/repositories/ai_provider_config_repository.dart';
import '../../domain/ai/ai_default_selection.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/ai/ai_provider_config.dart';
import '../../domain/ai/ai_provider_type.dart';
import 'secure_api_key_store.dart';

class AiResolvedProvider {
  const AiResolvedProvider({required this.config, required this.selection});

  final AiProviderConfig config;
  final AiDefaultSelection selection;

  String get displayLabel => '${config.displayName} · ${selection.modelId}';
}

/// Some reasoning providers require SSE transport. Disabling incremental output
/// buffers their text without changing the supported wire protocol.
Stream<AiStreamEvent> bufferAiOutput(
  Stream<AiStreamEvent> source, {
  required bool emitDeltas,
}) async* {
  if (emitDeltas) {
    yield* source;
    return;
  }
  final buffer = StringBuffer();
  try {
    await for (final event in source) {
      if (!event.isTerminal) {
        buffer.write(event.content);
        continue;
      }
      if (buffer.isNotEmpty) {
        yield AiStreamEvent.content(buffer.toString());
        buffer.clear();
      }
      yield event;
    }
    if (buffer.isNotEmpty) yield AiStreamEvent.content(buffer.toString());
  } catch (_) {
    if (buffer.isNotEmpty) yield AiStreamEvent.content(buffer.toString());
    rethrow;
  }
}

abstract class AiGenerationRuntime {
  Future<AiResolvedProvider> resolveDefault();

  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  });

  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  });
}

abstract class AiDetailedGenerationRuntime implements AiGenerationRuntime {
  Future<AiResolvedProvider> resolveSelection({
    String? providerConfigId,
    String? model,
  });

  Stream<AiStreamEvent> streamEvents(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  });
}

Stream<AiStreamEvent> runtimeStreamEvents(
  AiGenerationRuntime runtime,
  AiGenerationRequest request, {
  AiRequestCancellation? cancellation,
}) async* {
  if (runtime is AiDetailedGenerationRuntime) {
    yield* runtime.streamEvents(request, cancellation: cancellation);
    return;
  }
  await for (final chunk in runtime.stream(
    request,
    cancellation: cancellation,
  )) {
    yield AiStreamEvent.content(chunk);
  }
  yield const AiStreamEvent.finished(AiFinishReason.stop);
}

class AiGenerationService implements AiDetailedGenerationRuntime {
  AiGenerationService({
    required AiProviderConfigRepository configRepository,
    required SecureApiKeyStore apiKeyStore,
    required AiProviderRegistry registry,
    Future<bool> Function()? streamOutputEnabled,
  }) : _configRepository = configRepository,
       _apiKeyStore = apiKeyStore,
       _registry = registry,
       _streamOutputEnabled = streamOutputEnabled;

  final AiProviderConfigRepository _configRepository;
  final SecureApiKeyStore _apiKeyStore;
  final AiProviderRegistry _registry;
  final Future<bool> Function()? _streamOutputEnabled;
  final Map<String, List<_PooledProviderClient>> _clients = {};
  final clientPoolMetrics = AiClientPoolMetrics();

  @override
  Future<AiResolvedProvider> resolveDefault() async {
    final selection = await _configRepository.loadDefault();
    if (selection == null) {
      throw const AiProviderValidationException('还没有配置默认 AI。');
    }
    final config = await _configRepository.getConfig(selection.providerId);
    if (config == null || !config.enabled) {
      throw const AiProviderValidationException('默认 AI 配置不可用。');
    }
    if (selection.modelId.trim().isEmpty) {
      throw const AiProviderModelUnavailableException();
    }
    await _validateCredentialAndModel(config, selection.modelId);
    return AiResolvedProvider(config: config, selection: selection);
  }

  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    await for (final event in streamEvents(
      request,
      cancellation: cancellation,
    )) {
      if (event.content.isNotEmpty) yield event.content;
    }
  }

  @override
  Future<AiResolvedProvider> resolveSelection({
    String? providerConfigId,
    String? model,
  }) {
    return _resolve(
      AiGenerationRequest(
        requestId: 'resolve-selection',
        systemPrompt: '',
        messages: const [],
        providerConfigId: providerConfigId,
        model: model,
      ),
    );
  }

  @override
  Stream<AiStreamEvent> streamEvents(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    final emitDeltas =
        request.streamOutput ?? await _streamOutputEnabled?.call() ?? true;
    final resolved = await _resolve(request);
    final apiKey = await _apiKeyStore.read(resolved.config.apiKeyRef) ?? '';
    final lease = _acquireClient(resolved.config, apiKey);
    var discardClient = false;
    try {
      request.reportTransportStarted(
        resolved.config.id,
        resolved.selection.modelId,
      );
      await for (final event in bufferAiOutput(
        lease.client.streamEvents(
          request.copyWith(
            providerConfigId: resolved.config.id,
            model: resolved.selection.modelId,
          ),
          cancellation: cancellation,
        ),
        emitDeltas: emitDeltas,
      )) {
        yield event;
      }
    } on AiProviderInterruptedException {
      discardClient = true;
      rethrow;
    } on AiProviderException {
      rethrow;
    } catch (_) {
      throw const AiProviderUnknownException();
    } finally {
      _releaseClient(
        lease,
        discard: discardClient || cancellation?.isCancelled == true,
      );
    }
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled == true) {
      throw const AiProviderCancelledException();
    }
    final resolved = await _resolve(request);
    final apiKey = await _apiKeyStore.read(resolved.config.apiKeyRef) ?? '';
    if (cancellation?.isCancelled == true) {
      throw const AiProviderCancelledException();
    }
    final lease = _acquireClient(resolved.config, apiKey);
    try {
      request.reportTransportStarted(
        resolved.config.id,
        resolved.selection.modelId,
      );
      return await lease.client.generate(
        request.copyWith(
          providerConfigId: resolved.config.id,
          model: resolved.selection.modelId,
        ),
        cancellation: cancellation,
      );
    } on AiProviderException {
      rethrow;
    } catch (_) {
      throw const AiProviderUnknownException();
    } finally {
      _releaseClient(lease, discard: cancellation?.isCancelled == true);
    }
  }

  void close() {
    for (final entries in _clients.values) {
      for (final entry in entries) {
        entry.client.close();
      }
    }
    _clients.clear();
  }

  _PooledProviderClient _acquireClient(AiProviderConfig config, String apiKey) {
    final signature =
        '${config.type.name}|${config.baseUrl}|${config.apiKeyRef}';
    final entries = _clients.putIfAbsent(config.id, () => []);
    for (final entry in entries.toList()) {
      final matches = entry.signature == signature && entry.apiKey == apiKey;
      if (!matches && !entry.inUse) {
        entry.client.close();
        entries.remove(entry);
      } else if (!matches) {
        entry.retireAfterUse = true;
      } else if (!entry.inUse) {
        entry.inUse = true;
        clientPoolMetrics.reuses += 1;
        return entry;
      }
    }
    final created = _PooledProviderClient(
      signature: signature,
      apiKey: apiKey,
      client: _registry.create(config, apiKey),
    )..inUse = true;
    entries.add(created);
    clientPoolMetrics.creations += 1;
    return created;
  }

  void _releaseClient(_PooledProviderClient lease, {required bool discard}) {
    List<_PooledProviderClient>? entries;
    for (final candidates in _clients.values) {
      if (candidates.contains(lease)) {
        entries = candidates;
        break;
      }
    }
    if (entries == null) {
      return;
    }
    if (discard || lease.retireAfterUse) {
      lease.client.close();
      entries.remove(lease);
      clientPoolMetrics.evictions += 1;
      return;
    }
    lease.inUse = false;
  }

  Future<AiResolvedProvider> _resolve(AiGenerationRequest request) async {
    if (request.providerConfigId == null && request.model == null) {
      return resolveDefault();
    }
    final defaultSelection = await _configRepository.loadDefault();
    final providerId = request.providerConfigId?.trim().isNotEmpty == true
        ? request.providerConfigId!.trim()
        : defaultSelection?.providerId;
    if (providerId == null) {
      throw const AiProviderValidationException('还没有配置默认 AI。');
    }
    final config = await _configRepository.getConfig(providerId);
    if (config == null || !config.enabled) {
      throw const AiProviderValidationException('选择的 AI 配置不可用。');
    }
    final model = request.model?.trim().isNotEmpty == true
        ? request.model!.trim()
        : defaultSelection?.providerId == providerId
        ? defaultSelection!.modelId
        : config.selectedModel;
    if (model.trim().isEmpty) {
      throw const AiProviderModelUnavailableException();
    }
    await _validateCredentialAndModel(config, model);
    return AiResolvedProvider(
      config: config,
      selection: AiDefaultSelection(
        providerId: providerId,
        modelId: model,
        updatedAtUtc: defaultSelection?.updatedAtUtc ?? config.updatedAtUtc,
      ),
    );
  }

  Future<void> _validateCredentialAndModel(
    AiProviderConfig config,
    String model,
  ) async {
    final apiKey = await _apiKeyStore.read(config.apiKeyRef) ?? '';
    if (config.type.requiresApiKey && apiKey.trim().isEmpty) {
      throw AiProviderValidationException('${config.displayName} API Key 未配置。');
    }
    if (config.availableModels.isNotEmpty &&
        !config.availableModels.contains(model.trim())) {
      throw const AiProviderModelUnavailableException();
    }
    if (config.type == AiProviderType.gemini &&
        config.incompatibleModels.contains(model.trim())) {
      throw const AiProviderNativeInterfaceIncompatibleException();
    }
  }
}

class AiClientPoolMetrics {
  int creations = 0;
  int reuses = 0;
  int evictions = 0;
}

class _PooledProviderClient {
  _PooledProviderClient({
    required this.signature,
    required this.apiKey,
    required this.client,
  });

  final String signature;
  final String apiKey;
  final AiProviderClient client;
  bool inUse = false;
  bool retireAfterUse = false;
}
