import '../../domain/plugins/installed_plugin.dart';

abstract class PluginRegistry {
  Future<List<InstalledPlugin>> listPlugins();

  Future<InstalledPlugin?> getPlugin(String id);

  Future<void> upsertPlugin(InstalledPlugin plugin);

  Future<void> deletePlugin(String id);
}
