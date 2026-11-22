import 'dart:convert';

import '../../application/security/secure_value_store.dart';
import '../../core/errors/data_exceptions.dart';
import '../../domain/ai/ai_default_selection.dart';
import '../../domain/ai/ai_provider_config.dart';
import '../repositories/ai_provider_config_repository.dart';

class SecureAiProviderConfigRepository implements AiProviderConfigRepository {
  const SecureAiProviderConfigRepository(this._store);

  static const _configsKey = 'ai.provider_configs.v1';
  static const _defaultKey = 'ai.default_selection.v1';

  final SecureValueStore _store;

  @override
  Future<List<AiProviderConfig>> listConfigs() async {
    final raw = await _store.read(_configsKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const DataFormatException('AI provider config list is invalid.');
      }
      return List.unmodifiable(
        decoded.map((value) {
          if (value is! Map) {
            throw const DataFormatException('AI provider config is invalid.');
          }
          return AiProviderConfig.fromJson(Map<String, Object?>.from(value));
        }),
      );
    } on DataFormatException {
      rethrow;
    } catch (_) {
      throw const DataFormatException('AI provider config JSON is invalid.');
    }
  }

  @override
  Future<AiProviderConfig?> getConfig(String id) async {
    final configs = await listConfigs();
    for (final config in configs) {
      if (config.id == id) {
        return config;
      }
    }
    return null;
  }

  @override
  Future<void> saveConfig(AiProviderConfig config) async {
    final configs = (await listConfigs()).toList(growable: true);
    final index = configs.indexWhere((item) => item.id == config.id);
    if (index < 0) {
      configs.add(config);
    } else {
      configs[index] = config;
    }
    configs.sort(_sortConfigs);
    await _store.write(
      _configsKey,
      jsonEncode(configs.map((item) => item.toJson()).toList()),
    );
  }

  @override
  Future<void> deleteConfig(String id) async {
    final configs = (await listConfigs())
        .where((config) => config.id != id)
        .toList(growable: false);
    await _store.write(
      _configsKey,
      jsonEncode(configs.map((item) => item.toJson()).toList()),
    );
    final currentDefault = await loadDefault();
    if (currentDefault?.providerId == id) {
      await clearDefault();
    }
  }

  @override
  Future<AiDefaultSelection?> loadDefault() async {
    final raw = await _store.read(_defaultKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const DataFormatException('Default AI selection is invalid.');
      }
      return AiDefaultSelection.fromJson(Map<String, Object?>.from(decoded));
    } on DataFormatException {
      rethrow;
    } catch (_) {
      throw const DataFormatException('Default AI selection JSON is invalid.');
    }
  }

  @override
  Future<void> saveDefault(AiDefaultSelection selection) =>
      _store.write(_defaultKey, jsonEncode(selection.toJson()));

  @override
  Future<void> clearDefault() => _store.delete(_defaultKey);

  int _sortConfigs(AiProviderConfig first, AiProviderConfig second) {
    final firstOrder = first.type.index;
    final secondOrder = second.type.index;
    final typeResult = firstOrder.compareTo(secondOrder);
    if (typeResult != 0) {
      return typeResult;
    }
    final nameResult = first.displayName.compareTo(second.displayName);
    return nameResult != 0 ? nameResult : first.id.compareTo(second.id);
  }
}
