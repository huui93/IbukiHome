import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/core/network/ai_network_diagnostics.dart';
import 'package:ibukihome/core/network/ai_provider_exceptions.dart';
import 'package:ibukihome/data/ai/ai_provider_registry.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/data/secure/secure_ai_provider_config_repository.dart';
import 'package:ibukihome/data/secure/secure_storage_api_key_store.dart';
import 'package:ibukihome/domain/ai/ai_default_selection.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';

void main() {
  test('missing secure key stops before any HTTP request', () async {
    final fixture = await _RuntimeFixture.create(writeKey: false);

    expect(
      fixture.runtime.generate(_request()),
      throwsA(
        isA<AiProviderValidationException>().having(
          (error) => error.message,
          'message',
          contains('API Key'),
        ),
      ),
    );
    expect(fixture.requests, isEmpty);
  });

  test('a stale selected model stops before any HTTP request', () async {
    final fixture = await _RuntimeFixture.create(
      selectedModel: 'deepseek-chat',
      availableModels: const ['deepseek-v4-flash'],
    );

    expect(
      fixture.runtime.generate(_request()),
      throwsA(isA<AiProviderModelUnavailableException>()),
    );
    expect(fixture.requests, isEmpty);
  });

  test('a Gemini Native incompatible model stops before HTTP', () async {
    final fixture = await _RuntimeFixture.create(
      providerType: AiProviderType.gemini,
      selectedModel: 'antigravity-preview-05-2026',
      availableModels: const ['antigravity-preview-05-2026'],
      incompatibleModels: const ['antigravity-preview-05-2026'],
      baseUrl: AiProviderType.gemini.defaultBaseUrl,
    );

    expect(
      fixture.runtime.generate(
        _request().copyWith(
          providerConfigId: 'gemini',
          model: 'antigravity-preview-05-2026',
        ),
      ),
      throwsA(isA<AiProviderNativeInterfaceIncompatibleException>()),
    );
    expect(fixture.requests, isEmpty);
  });

  test('runtime follows provider id to config and secure key ref', () async {
    final fixture = await _RuntimeFixture.create(
      keyRef: 'secure.deepseek.primary',
    );

    expect(await fixture.runtime.generate(_request()), 'OK');
    expect(fixture.requests.single.url.host, 'api.deepseek.com');
    expect(fixture.requests.single.url.path, '/chat/completions');
    expect(
      fixture.requests.single.headers['Authorization'],
      'Bearer unit-test-secret',
    );
  });

  test('runtime non-stream generation sends stream false', () async {
    final fixture = await _RuntimeFixture.create();

    await fixture.runtime.generate(_request());

    final body = jsonDecode(fixture.requests.single.body) as Map;
    expect(body['stream'], isFalse);
  });

  test('runtime streaming uses the same config and endpoint', () async {
    final fixture = await _RuntimeFixture.create();

    expect(await fixture.runtime.stream(_request()).join(), 'streamed');

    final request = fixture.requests.single;
    final body = jsonDecode(request.body) as Map;
    expect(request.url.toString(), 'https://api.deepseek.com/chat/completions');
    expect(body['model'], 'deepseek-v4-flash');
    expect(body['stream'], isTrue);
  });

  test('sequential generation reuses one provider HTTP client', () async {
    final fixture = await _RuntimeFixture.create();

    expect(await fixture.runtime.generate(_request()), 'OK');
    expect(await fixture.runtime.generate(_request()), 'OK');

    expect(fixture.clientCreations(), 1);
    expect(fixture.runtime.clientPoolMetrics.creations, 1);
    expect(fixture.runtime.clientPoolMetrics.reuses, 1);
  });

  test('interrupted stream evicts its HTTP client before recovery', () async {
    final fixture = await _RuntimeFixture.create(firstStreamAbnormal: true);

    expect(
      fixture.runtime.streamEvents(_request()).drain<void>(),
      throwsA(isA<AiProviderInterruptedException>()),
    );
    expect(
      await fixture.runtime
          .streamEvents(_request().copyWith(requestId: 'recovery'))
          .where((event) => !event.isTerminal)
          .map((event) => event.content)
          .join(),
      'streamed',
    );

    expect(fixture.clientCreations(), 2);
    expect(fixture.runtime.clientPoolMetrics.evictions, 1);
  });

  test(
    'connection test and generation share normalized provider transport',
    () async {
      final fixture = await _RuntimeFixture.create(
        baseUrl: 'https://api.deepseek.com/v1/chat/completions',
      );
      final config = await fixture.repository.getConfig('deepseek');
      final client = fixture.registry.create(config!, 'unit-test-secret');

      expect((await client.testConnection()).models, ['deepseek-v4-flash']);
      client.close();
      expect(await fixture.runtime.generate(_request()), 'OK');

      expect(fixture.requests.map((request) => request.url.path), [
        '/models',
        '/chat/completions',
      ]);
    },
  );
}

class _RuntimeFixture {
  _RuntimeFixture({
    required this.runtime,
    required this.repository,
    required this.registry,
    required this.requests,
    required this.clientCreations,
  });

  final AiGenerationService runtime;
  final SecureAiProviderConfigRepository repository;
  final AiProviderRegistry registry;
  final List<http.Request> requests;
  final int Function() clientCreations;

  static Future<_RuntimeFixture> create({
    bool writeKey = true,
    String keyRef = 'ai.api_key.deepseek',
    String selectedModel = 'deepseek-v4-flash',
    List<String> availableModels = const ['deepseek-v4-flash'],
    List<String> incompatibleModels = const [],
    AiProviderType providerType = AiProviderType.deepseek,
    String baseUrl = 'https://api.deepseek.com',
    bool firstStreamAbnormal = false,
  }) async {
    final now = DateTime.utc(2026, 8, 11);
    final values = InMemorySecureValueStore();
    final repository = SecureAiProviderConfigRepository(values);
    final keys = SecureStorageApiKeyStore(values);
    final requests = <http.Request>[];
    var clientCreations = 0;
    var streamRequests = 0;
    final config = AiProviderConfig(
      id: providerType.name,
      type: providerType,
      displayName: providerType.displayName,
      baseUrl: baseUrl,
      apiKeyRef: keyRef,
      selectedModel: selectedModel,
      enabled: true,
      connectionStatus: AiProviderConnectionStatus.connected,
      availableModels: availableModels,
      incompatibleModels: incompatibleModels,
      createdAtUtc: now,
      updatedAtUtc: now,
      lastVerifiedAtUtc: now,
    );
    await repository.saveConfig(config);
    await repository.saveDefault(
      AiDefaultSelection(
        providerId: config.id,
        modelId: selectedModel,
        updatedAtUtc: now,
      ),
    );
    if (writeKey) {
      await keys.write(keyRef, 'unit-test-secret');
    }
    final registry = AiProviderRegistry(
      diagnostics: const NoopAiNetworkDiagnostics(),
      httpClientFactory: () {
        clientCreations += 1;
        return MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response('{"data":[{"id":"deepseek-v4-flash"}]}', 200);
          }
          final body = jsonDecode(request.body) as Map;
          if (body['stream'] == true) {
            streamRequests += 1;
            if (firstStreamAbnormal && streamRequests == 1) {
              return http.Response(
                'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
                200,
              );
            }
            return http.Response(
              'data: {"choices":[{"delta":{"content":"streamed"}}]}\n\n'
              'data: [DONE]\n\n',
              200,
            );
          }
          return http.Response(
            '{"choices":[{"message":{"content":"OK"}}]}',
            200,
          );
        });
      },
    );
    return _RuntimeFixture(
      runtime: AiGenerationService(
        configRepository: repository,
        apiKeyStore: keys,
        registry: registry,
      ),
      repository: repository,
      registry: registry,
      requests: requests,
      clientCreations: () => clientCreations,
    );
  }
}

AiGenerationRequest _request() {
  return const AiGenerationRequest(
    requestId: 'network-test',
    systemPrompt: 'Reply briefly.',
    messages: [AiGenerationMessage(role: AiMessageRole.user, content: 'Hello')],
  );
}
