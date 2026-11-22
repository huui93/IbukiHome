abstract class PluginStorageRepository {
  Future<Map<String, Object?>> listValues(String pluginId);
  Future<Object?> getValue(String pluginId, String key);

  Future<void> setValue(String pluginId, String key, Object? value);

  Future<void> removeValue(String pluginId, String key);

  Future<void> clearPlugin(String pluginId);

  Future<void> clearPluginUserValues(String pluginId);
}
