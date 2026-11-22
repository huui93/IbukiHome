import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/network/ai_provider_exceptions.dart';
import '../../data/ai/ai_provider_client.dart';
import '../../data/ai/ai_provider_registry.dart';
import '../../data/memory/in_memory_secure_value_store.dart';
import '../../data/repositories/ai_provider_config_repository.dart';
import '../../data/secure/secure_ai_provider_config_repository.dart';
import '../../data/secure/secure_storage_api_key_store.dart';
import '../../domain/ai/ai_default_selection.dart';
import '../../domain/ai/ai_provider_config.dart';
import '../../domain/ai/ai_provider_type.dart';
import '../common/utc_clock.dart';
import '../security/secure_value_store.dart';
import 'secure_api_key_store.dart';

final aiSecureValueStoreProvider = Provider<SecureValueStore>((ref) {
  return InMemorySecureValueStore();
});

final aiProviderConfigRepositoryProvider = Provider<AiProviderConfigRepository>(
  (ref) =>
      SecureAiProviderConfigRepository(ref.watch(aiSecureValueStoreProvider)),
);

final secureApiKeyStoreProvider = Provider<SecureApiKeyStore>((ref) {
  return SecureStorageApiKeyStore(ref.watch(aiSecureValueStoreProvider));
});

final aiHttpClientFactoryProvider = Provider<http.Client Function()>((ref) {
  return http.Client.new;
});

final aiProviderRegistryProvider = Provider<AiProviderRegistry>((ref) {
  return AiProviderRegistry(
    httpClientFactory: ref.watch(aiHttpClientFactoryProvider),
  );
});

final aiSettingsClockProvider = Provider<UtcClock>((ref) => const UtcClock());

final aiSettingsControllerProvider =
    AsyncNotifierProvider<AiSettingsController, AiSettingsState>(
      AiSettingsController.new,
    );

class AiSettingsState {
  const AiSettingsState({
    required this.configs,
    required this.providerIdsWithKeys,
    this.defaultSelection,
  });

  final List<AiProviderConfig> configs;
  final Set<String> providerIdsWithKeys;
  final AiDefaultSelection? defaultSelection;

  AiProviderConfig? configById(String id) {
    for (final config in configs) {
      if (config.id == id) {
        return config;
      }
    }
    return null;
  }

  bool hasKey(AiProviderConfig config) =>
      providerIdsWithKeys.contains(config.id);

  bool isConfigured(AiProviderConfig config) {
    final fieldsReady =
        config.displayName.trim().isNotEmpty &&
        config.baseUrl.trim().isNotEmpty &&
        config.selectedModel.trim().isNotEmpty;
    return fieldsReady && (!config.type.requiresApiKey || hasKey(config));
  }
}

class AiProviderTestResult {
  const AiProviderTestResult({
    required this.models,
    required this.verifiedAtUtc,
    this.verifiedModel,
    this.verifiedModels = const [],
    this.incompatibleModels = const [],
  });

  final List<String> models;
  final DateTime verifiedAtUtc;
  final String? verifiedModel;
  final List<String> verifiedModels;
  final List<String> incompatibleModels;
}

class AiSettingsController extends AsyncNotifier<AiSettingsState> {
  AiProviderConfigRepository get _repository =>
      ref.read(aiProviderConfigRepositoryProvider);
  SecureApiKeyStore get _apiKeyStore => ref.read(secureApiKeyStoreProvider);
  UtcClock get _clock => ref.read(aiSettingsClockProvider);

  @override
  Future<AiSettingsState> build() => _load();

  Future<String?> loadApiKey(String providerId) async {
    final current = state.value;
    final config =
        current?.configById(providerId) ??
        await _repository.getConfig(providerId);
    if (config == null) {
      return null;
    }
    return _apiKeyStore.read(config.apiKeyRef);
  }

  AiProviderConfig newCustomConfig({
    required String id,
    String displayName = '',
  }) {
    final now = _clock.now();
    return AiProviderConfig(
      id: id,
      type: AiProviderType.custom,
      displayName: displayName,
      baseUrl: '',
      apiKeyRef: 'ai.api_key.$id',
      selectedModel: '',
      enabled: true,
      connectionStatus: AiProviderConnectionStatus.untested,
      availableModels: const [],
      createdAtUtc: now,
      updatedAtUtc: now,
    );
  }

  Future<void> saveConfig(
    AiProviderConfig config, {
    required String apiKey,
  }) async {
    final normalized = _validatedConfig(
      config,
    ).copyWith(updatedAtUtc: _clock.now());
    await _repository.saveConfig(normalized);
    await _apiKeyStore.write(normalized.apiKeyRef, apiKey);
    await _refresh();
  }

  Future<AiProviderTestResult> testConnection(
    AiProviderConfig draft, {
    required String apiKey,
    AiRequestCancellation? cancellation,
  }) async {
    final config = _validatedConfig(draft);
    final key = apiKey.trim();
    final secureKeyPresent = await _apiKeyStore.contains(config.apiKeyRef);
    debugPrint(
      'AI_SETTINGS provider=${config.type.name} stage=key_resolution '
      'formKeyPresent=${key.isNotEmpty} '
      'secureKeyPresent=$secureKeyPresent '
      'keySource=${key.isNotEmpty ? 'form' : 'none'}',
    );
    if (config.type.requiresApiKey && key.isEmpty) {
      throw const AiProviderValidationException('请先填写 API Key。');
    }
    if (cancellation?.isCancelled ?? false) {
      throw const AiProviderCancelledException();
    }
    final client = ref.read(aiProviderRegistryProvider).create(config, key);
    cancellation?.attach(client.close);
    try {
      final result = await client.testConnection(
        preferredModel: config.selectedModel,
      );
      if (cancellation?.isCancelled ?? false) {
        throw const AiProviderCancelledException();
      }
      return AiProviderTestResult(
        models: result.models,
        verifiedAtUtc: _clock.now(),
        verifiedModel: result.verifiedModel,
        verifiedModels: result.verifiedModels,
        incompatibleModels: result.incompatibleModels,
      );
    } on AiProviderException {
      rethrow;
    } catch (_) {
      throw const AiProviderNetworkException();
    } finally {
      cancellation?.detach();
      client.close();
    }
  }

  Future<List<String>> listDraftModels(
    AiProviderConfig draft, {
    required String apiKey,
    AiRequestCancellation? cancellation,
  }) async {
    final config = _validatedConfig(draft);
    if (config.type.requiresApiKey && apiKey.trim().isEmpty) {
      throw const AiProviderValidationException('请先填写 API Key。');
    }
    if (cancellation?.isCancelled == true) {
      throw const AiProviderCancelledException();
    }
    final client = ref
        .read(aiProviderRegistryProvider)
        .create(config, apiKey.trim());
    cancellation?.attach(client.close);
    try {
      final models = await client.listModels();
      if (cancellation?.isCancelled == true) {
        throw const AiProviderCancelledException();
      }
      return models;
    } on AiProviderException {
      rethrow;
    } catch (_) {
      throw const AiProviderNetworkException();
    } finally {
      cancellation?.detach();
      client.close();
    }
  }

  Future<List<String>> refreshModels(String providerId) async {
    final snapshot = state.value ?? await _load();
    final config = snapshot.configById(providerId);
    if (config == null || !config.enabled) {
      throw const AiProviderValidationException('选择的 AI 配置不可用。');
    }
    final apiKey = await _apiKeyStore.read(config.apiKeyRef) ?? '';
    if (config.type.requiresApiKey && apiKey.trim().isEmpty) {
      throw AiProviderValidationException('${config.displayName} API Key 未配置。');
    }
    final client = ref.read(aiProviderRegistryProvider).create(config, apiKey);
    try {
      final models = (await client.listModels())
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false);
      await _repository.saveConfig(
        config.copyWith(availableModels: models, updatedAtUtc: _clock.now()),
      );
      await _refresh();
      return models;
    } on AiProviderException {
      rethrow;
    } catch (_) {
      throw const AiProviderNetworkException();
    } finally {
      client.close();
    }
  }

  Future<void> clearOfficialConfig(String providerId) async {
    final current =
        state.value?.configById(providerId) ??
        await _repository.getConfig(providerId);
    if (current == null || current.isCustom) {
      throw const AiProviderValidationException('只能清除官方 Provider 配置。');
    }
    await _apiKeyStore.delete(current.apiKeyRef);
    await _repository.saveConfig(
      current.copyWith(
        baseUrl: current.type.defaultBaseUrl,
        selectedModel: '',
        availableModels: const [],
        verifiedModels: const [],
        incompatibleModels: const [],
        connectionStatus: AiProviderConnectionStatus.untested,
        lastVerifiedAtUtc: null,
        updatedAtUtc: _clock.now(),
      ),
    );
    if (state.value?.defaultSelection?.providerId == providerId) {
      await _repository.clearDefault();
    }
    await _refresh();
  }

  Future<void> deleteCustomConfig(String providerId) async {
    final current =
        state.value?.configById(providerId) ??
        await _repository.getConfig(providerId);
    if (current == null || !current.isCustom) {
      throw const AiProviderValidationException('只能删除自定义 Provider。');
    }
    await _apiKeyStore.delete(current.apiKeyRef);
    await _repository.deleteConfig(providerId);
    await _refresh();
  }

  Future<void> setDefault(String providerId, String modelId) async {
    final current = state.value;
    final config = current?.configById(providerId);
    final model = modelId.trim();
    if (config?.type == AiProviderType.gemini &&
        config!.incompatibleModels.contains(model)) {
      throw const AiProviderNativeInterfaceIncompatibleException();
    }
    if (config == null ||
        config.connectionStatus != AiProviderConnectionStatus.connected ||
        !current!.isConfigured(config) ||
        model.isEmpty) {
      throw const AiProviderValidationException('只能选择已经配置并测试成功的 Provider。');
    }
    await _repository.saveDefault(
      AiDefaultSelection(
        providerId: providerId,
        modelId: model,
        updatedAtUtc: _clock.now(),
      ),
    );
    await _refresh();
  }

  Future<AiSettingsState> _load() async {
    final configs = (await _repository.listConfigs()).toList(growable: true);
    final existingIds = configs.map((item) => item.id).toSet();
    for (final builtIn in AiProviderCatalog.builtIns(_clock.now())) {
      if (existingIds.add(builtIn.id)) {
        configs.add(builtIn);
        await _repository.saveConfig(builtIn);
      }
    }
    configs.sort(_sortConfigs);
    final providerIdsWithKeys = <String>{};
    for (final config in configs) {
      if (await _apiKeyStore.contains(config.apiKeyRef)) {
        providerIdsWithKeys.add(config.id);
      }
    }
    var defaultSelection = await _repository.loadDefault();
    if (defaultSelection != null &&
        !configs.any((item) => item.id == defaultSelection!.providerId)) {
      await _repository.clearDefault();
      defaultSelection = null;
    }
    return AiSettingsState(
      configs: List.unmodifiable(configs),
      providerIdsWithKeys: Set.unmodifiable(providerIdsWithKeys),
      defaultSelection: defaultSelection,
    );
  }

  Future<void> _refresh() async {
    state = AsyncData(await _load());
  }

  AiProviderConfig _validatedConfig(AiProviderConfig config) {
    final name = config.displayName.trim();
    if (name.isEmpty) {
      throw const AiProviderValidationException('Provider 名称不能为空。');
    }
    final baseUrl = config.baseUrl.trim();
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const AiProviderValidationException(
        'Base URL 无效，请输入 HTTP 或 HTTPS 地址。',
      );
    }
    final normalizedBaseUri = normalizeAiProviderBaseUri(config.type, uri);
    return config.copyWith(
      displayName: name,
      baseUrl: normalizedBaseUri.toString(),
      selectedModel: config.selectedModel.trim(),
      availableModels:
          config.availableModels
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList()
            ..sort(),
      verifiedModels:
          config.verifiedModels
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList()
            ..sort(),
      incompatibleModels:
          config.incompatibleModels
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList()
            ..sort(),
    );
  }

  int _sortConfigs(AiProviderConfig first, AiProviderConfig second) {
    final typeResult = first.type.index.compareTo(second.type.index);
    if (typeResult != 0) {
      return typeResult;
    }
    final nameResult = first.displayName.compareTo(second.displayName);
    return nameResult != 0 ? nameResult : first.id.compareTo(second.id);
  }
}

String maskApiKey(String? apiKey) {
  final value = apiKey?.trim() ?? '';
  if (value.isEmpty) {
    return '未填写';
  }
  final suffix = value.length <= 4 ? value : value.substring(value.length - 4);
  return '••••••••$suffix';
}
