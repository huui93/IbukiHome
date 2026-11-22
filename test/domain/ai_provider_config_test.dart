import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/domain/ai/ai_default_selection.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';

void main() {
  final now = DateTime.utc(2026, 8, 10, 8);

  test('provider catalog contains eight built-in providers', () {
    final configs = AiProviderCatalog.builtIns(now);
    expect(configs.map((item) => item.type), [
      AiProviderType.openai,
      AiProviderType.gemini,
      AiProviderType.deepseek,
      AiProviderType.kimi,
      AiProviderType.qwen,
      AiProviderType.grok,
      AiProviderType.glm,
      AiProviderType.claude,
    ]);
  });

  test('provider display names are stable', () {
    expect(AiProviderType.openai.displayName, 'OpenAI');
    expect(AiProviderType.gemini.displayName, 'Gemini');
    expect(AiProviderType.deepseek.displayName, 'DeepSeek');
    expect(AiProviderType.kimi.displayName, 'Kimi');
    expect(AiProviderType.custom.displayName, '自定义');
  });

  test('official base URLs use HTTPS', () {
    for (final type in AiProviderType.values.where((item) => item.isBuiltIn)) {
      expect(Uri.parse(type.defaultBaseUrl).scheme, 'https');
    }
  });

  test('custom provider can omit API key', () {
    expect(AiProviderType.custom.requiresApiKey, isFalse);
  });

  test('provider config JSON round trip preserves values', () {
    final config = _config(now);
    expect(AiProviderConfig.fromJson(config.toJson()), config);
  });

  test('legacy provider config defaults capability lists to empty', () {
    final json = _config(now).toJson()
      ..remove('verified_models')
      ..remove('incompatible_models');
    final restored = AiProviderConfig.fromJson(json);
    expect(restored.verifiedModels, isEmpty);
    expect(restored.incompatibleModels, isEmpty);
  });

  test('provider config ignores unknown JSON fields', () {
    final json = {..._config(now).toJson(), 'future_field': 'ignored'};
    expect(AiProviderConfig.fromJson(json).id, 'openai');
  });

  test('provider config restores dates to UTC', () {
    final json = _config(now).toJson()
      ..['updated_at_utc'] = '2026-08-10T16:00:00+08:00';
    expect(AiProviderConfig.fromJson(json).updatedAtUtc, now);
  });

  test('provider config rejects missing fields', () {
    final json = _config(now).toJson()..remove('id');
    expect(
      () => AiProviderConfig.fromJson(json),
      throwsA(isA<DataFormatException>()),
    );
  });

  test('provider config rejects unknown type', () {
    final json = _config(now).toJson()..['type'] = 'other';
    expect(
      () => AiProviderConfig.fromJson(json),
      throwsA(isA<DataFormatException>()),
    );
  });

  test('provider config rejects malformed model list', () {
    final json = _config(now).toJson()..['available_models'] = [1];
    expect(
      () => AiProviderConfig.fromJson(json),
      throwsA(isA<DataFormatException>()),
    );
  });

  test('copyWith keeps unmodified provider identity', () {
    final config = _config(now);
    final copy = config.copyWith(selectedModel: 'gpt-new');
    expect(copy.id, config.id);
    expect(copy.type, config.type);
    expect(copy.apiKeyRef, config.apiKeyRef);
    expect(copy.createdAtUtc, config.createdAtUtc);
  });

  test('copyWith can clear last verification time', () {
    final config = _config(now).copyWith(lastVerifiedAtUtc: now);
    expect(config.copyWith(lastVerifiedAtUtc: null).lastVerifiedAtUtc, isNull);
  });

  test('default selection JSON round trip preserves values', () {
    final selection = AiDefaultSelection(
      providerId: 'openai',
      modelId: 'gpt-test',
      updatedAtUtc: now,
    );
    expect(AiDefaultSelection.fromJson(selection.toJson()), selection);
  });

  test('default selection rejects malformed JSON', () {
    expect(
      () => AiDefaultSelection.fromJson(const {'provider_id': 1}),
      throwsA(isA<DataFormatException>()),
    );
  });
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
    availableModels: const ['gpt-test', 'gpt-other'],
    verifiedModels: const ['gpt-test'],
    incompatibleModels: const ['gpt-old'],
    createdAtUtc: now,
    updatedAtUtc: now,
    lastVerifiedAtUtc: now,
  );
}
