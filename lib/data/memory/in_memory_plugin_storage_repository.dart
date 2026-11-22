import '../repositories/plugin_storage_repository.dart';

class InMemoryPluginStorageRepository implements PluginStorageRepository {
  final Map<String, Map<String, Object?>> _values = {};
  @override
  Future<Map<String, Object?>> listValues(String pluginId) async =>
      Map.unmodifiable(_values[pluginId] ?? const {});

  @override
  Future<void> clearPlugin(String pluginId) async {
    _values.remove(pluginId);
  }

  @override
  Future<void> clearPluginUserValues(String pluginId) async {
    _values[pluginId]?.removeWhere(
      (key, value) => !key.startsWith('__ibuki_host__:'),
    );
  }

  @override
  Future<Object?> getValue(String pluginId, String key) async {
    return _values[pluginId]?[key];
  }

  @override
  Future<void> removeValue(String pluginId, String key) async {
    _values[pluginId]?.remove(key);
  }

  @override
  Future<void> setValue(String pluginId, String key, Object? value) async {
    (_values[pluginId] ??= <String, Object?>{})[key] = value;
  }
}
