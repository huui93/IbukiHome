import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/core/network/ai_provider_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/data/secure/secure_ai_provider_config_repository.dart';
import 'package:ibukihome/data/secure/secure_storage_api_key_store.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';

void main() {
  final now = DateTime.utc(2026, 8, 10, 9);

  test('API key store writes and reads a key', () async {
    final values = InMemorySecureValueStore();
    final keys = SecureStorageApiKeyStore(values);
    await keys.write('ref', 'test-key');
    expect(await keys.read('ref'), 'test-key');
  });

  test('API key store deletes empty values', () async {
    final values = InMemorySecureValueStore();
    final keys = SecureStorageApiKeyStore(values);
    await keys.write('ref', 'test-key');
    await keys.write('ref', '');
    expect(await keys.contains('ref'), isFalse);
  });

  test('provider metadata never contains API key plaintext', () async {
    final values = InMemorySecureValueStore();
    final repository = SecureAiProviderConfigRepository(values);
    await repository.saveConfig(_config(now));
    await SecureStorageApiKeyStore(
      values,
    ).write('ai.api_key.openai', 'secret-test-key');
    final metadata = values.debugSnapshot['ai.provider_configs.v1']!;
    expect(metadata, isNot(contains('secret-test-key')));
    expect(metadata, contains('ai.api_key.openai'));
  });

  test('provider metadata survives repository recreation', () async {
    final values = InMemorySecureValueStore();
    await SecureAiProviderConfigRepository(values).saveConfig(_config(now));
    final restored = await SecureAiProviderConfigRepository(
      values,
    ).getConfig('openai');
    expect(restored, _config(now));
  });

  test('default selection survives repository recreation', () async {
    final container = _container(values: InMemorySecureValueStore(), now: now);
    addTearDown(container.dispose);
    var state = await container.read(aiSettingsControllerProvider.future);
    var config = state.configById('openai')!;
    config = config.copyWith(
      selectedModel: 'gpt-test',
      connectionStatus: AiProviderConnectionStatus.connected,
      lastVerifiedAtUtc: now,
    );
    await container
        .read(aiSettingsControllerProvider.notifier)
        .saveConfig(config, apiKey: 'test-key');
    await container
        .read(aiSettingsControllerProvider.notifier)
        .setDefault('openai', 'gpt-test');
    state = container.read(aiSettingsControllerProvider).requireValue;
    expect(state.defaultSelection?.modelId, 'gpt-test');
  });

  test('controller seeds all official providers', () async {
    final container = _container(values: InMemorySecureValueStore(), now: now);
    addTearDown(container.dispose);
    final state = await container.read(aiSettingsControllerProvider.future);
    expect(state.configs.where((item) => !item.isCustom), hasLength(8));
  });

  test('official provider starts unconfigured', () async {
    final container = _container(values: InMemorySecureValueStore(), now: now);
    addTearDown(container.dispose);
    final state = await container.read(aiSettingsControllerProvider.future);
    expect(state.isConfigured(state.configById('openai')!), isFalse);
  });

  test('saving official provider stores key separately', () async {
    final values = InMemorySecureValueStore();
    final container = _container(values: values, now: now);
    addTearDown(container.dispose);
    final state = await container.read(aiSettingsControllerProvider.future);
    final config = state
        .configById('openai')!
        .copyWith(selectedModel: 'gpt-test');
    await container
        .read(aiSettingsControllerProvider.notifier)
        .saveConfig(config, apiKey: 'test-key');
    expect(values.debugSnapshot['ai.api_key.openai'], 'test-key');
    expect(
      values.debugSnapshot['ai.provider_configs.v1'],
      isNot(contains('test-key')),
    );
  });

  test(
    'Gemini connection test resolves a model before one is selected',
    () async {
      final requests = <http.Request>[];
      final container = _container(
        values: InMemorySecureValueStore(),
        now: now,
        handler: (request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response(
              '{"models":['
              '{"name":"models/gemini-live",'
              '"supportedGenerationMethods":["generateContent"]}'
              ']}',
              200,
            );
          }
          return http.Response(
            '{"candidates":[{"content":{"parts":[{"text":"OK"}]},'
            '"finishReason":"STOP"}]}',
            200,
          );
        },
      );
      addTearDown(container.dispose);
      final state = await container.read(aiSettingsControllerProvider.future);
      final draft = state.configById('gemini')!;

      final result = await container
          .read(aiSettingsControllerProvider.notifier)
          .testConnection(draft, apiKey: 'unsaved-unit-test-key');

      expect(result.models, ['gemini-live']);
      expect(result.verifiedModel, 'gemini-live');
      expect(requests, hasLength(2));
      expect(requests.first.url.path, '/v1beta/models');
      expect(
        requests.last.url.path,
        '/v1beta/models/gemini-live:generateContent',
      );
      expect(requests.last.headers['x-goog-api-key'], 'unsaved-unit-test-key');
      expect(requests.last.headers.containsKey('Authorization'), isFalse);
    },
  );

  test('custom provider allows an empty key', () async {
    final container = _container(values: InMemorySecureValueStore(), now: now);
    addTearDown(container.dispose);
    await container.read(aiSettingsControllerProvider.future);
    final controller = container.read(aiSettingsControllerProvider.notifier);
    final custom = controller
        .newCustomConfig(id: 'custom-1')
        .copyWith(
          displayName: 'Local',
          baseUrl: 'http://127.0.0.1:9000/v1',
          selectedModel: 'local-model',
        );
    await controller.saveConfig(custom, apiKey: '');
    final state = container.read(aiSettingsControllerProvider).requireValue;
    expect(state.isConfigured(state.configById('custom-1')!), isTrue);
  });

  test('custom provider requires a name', () async {
    final container = _container(values: InMemorySecureValueStore(), now: now);
    addTearDown(container.dispose);
    await container.read(aiSettingsControllerProvider.future);
    final custom = container
        .read(aiSettingsControllerProvider.notifier)
        .newCustomConfig(id: 'custom-1')
        .copyWith(baseUrl: 'http://localhost:9000/v1');
    expect(
      () => container
          .read(aiSettingsControllerProvider.notifier)
          .saveConfig(custom, apiKey: ''),
      throwsA(isA<AiProviderValidationException>()),
    );
  });

  test('custom provider requires a valid base URL', () async {
    final container = _container(values: InMemorySecureValueStore(), now: now);
    addTearDown(container.dispose);
    await container.read(aiSettingsControllerProvider.future);
    final custom = container
        .read(aiSettingsControllerProvider.notifier)
        .newCustomConfig(id: 'custom-1')
        .copyWith(displayName: 'Local', baseUrl: 'file:///tmp/model');
    expect(
      () => container
          .read(aiSettingsControllerProvider.notifier)
          .saveConfig(custom, apiKey: ''),
      throwsA(isA<AiProviderValidationException>()),
    );
  });

  test('custom provider can be deleted with its key', () async {
    final values = InMemorySecureValueStore();
    final container = _container(values: values, now: now);
    addTearDown(container.dispose);
    await container.read(aiSettingsControllerProvider.future);
    final controller = container.read(aiSettingsControllerProvider.notifier);
    final custom = controller
        .newCustomConfig(id: 'custom-1')
        .copyWith(
          displayName: 'Local',
          baseUrl: 'http://localhost:9000/v1',
          selectedModel: 'local',
        );
    await controller.saveConfig(custom, apiKey: 'custom-key');
    await controller.deleteCustomConfig('custom-1');
    final state = container.read(aiSettingsControllerProvider).requireValue;
    expect(state.configById('custom-1'), isNull);
    expect(values.debugSnapshot, isNot(contains('ai.api_key.custom-1')));
  });

  test('official provider cannot be deleted as custom', () async {
    final container = _container(values: InMemorySecureValueStore(), now: now);
    addTearDown(container.dispose);
    await container.read(aiSettingsControllerProvider.future);
    expect(
      () => container
          .read(aiSettingsControllerProvider.notifier)
          .deleteCustomConfig('openai'),
      throwsA(isA<AiProviderValidationException>()),
    );
  });

  test('clearing official provider removes key and model', () async {
    final values = InMemorySecureValueStore();
    final container = _container(values: values, now: now);
    addTearDown(container.dispose);
    var state = await container.read(aiSettingsControllerProvider.future);
    final controller = container.read(aiSettingsControllerProvider.notifier);
    await controller.saveConfig(
      state.configById('openai')!.copyWith(selectedModel: 'gpt-test'),
      apiKey: 'test-key',
    );
    await controller.clearOfficialConfig('openai');
    state = container.read(aiSettingsControllerProvider).requireValue;
    expect(state.configById('openai')!.selectedModel, isEmpty);
    expect(state.hasKey(state.configById('openai')!), isFalse);
  });

  test('untested provider cannot become default', () async {
    final container = _container(values: InMemorySecureValueStore(), now: now);
    addTearDown(container.dispose);
    await container.read(aiSettingsControllerProvider.future);
    expect(
      () => container
          .read(aiSettingsControllerProvider.notifier)
          .setDefault('openai', 'gpt-test'),
      throwsA(isA<AiProviderValidationException>()),
    );
  });

  test('maskApiKey reveals only the final four characters', () {
    expect(maskApiKey('sk-test-12345678'), '••••••••5678');
    expect(maskApiKey(''), '未填写');
  });
}

ProviderContainer _container({
  required InMemorySecureValueStore values,
  required DateTime now,
  Future<http.Response> Function(http.Request request)? handler,
}) {
  return ProviderContainer(
    overrides: [
      aiSecureValueStoreProvider.overrideWithValue(values),
      aiSettingsClockProvider.overrideWithValue(_FixedClock(now)),
      aiHttpClientFactoryProvider.overrideWithValue(
        () => MockClient(
          handler ?? (request) async => http.Response('{"data": []}', 200),
        ),
      ),
    ],
  );
}

class _FixedClock extends UtcClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

AiProviderConfig _config(DateTime now) {
  return AiProviderConfig(
    id: 'openai',
    type: AiProviderType.openai,
    displayName: 'OpenAI',
    baseUrl: AiProviderType.openai.defaultBaseUrl,
    apiKeyRef: 'ai.api_key.openai',
    selectedModel: 'gpt-test',
    enabled: true,
    connectionStatus: AiProviderConnectionStatus.connected,
    availableModels: const ['gpt-test'],
    createdAtUtc: now,
    updatedAtUtc: now,
    lastVerifiedAtUtc: now,
  );
}
