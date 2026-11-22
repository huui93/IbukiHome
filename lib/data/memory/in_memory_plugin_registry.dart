import '../../domain/plugins/installed_plugin.dart';
import '../repositories/plugin_registry.dart';

class InMemoryPluginRegistry implements PluginRegistry {
  final Map<String, InstalledPlugin> _plugins = {};

  @override
  Future<void> deletePlugin(String id) async {
    _plugins.remove(id);
  }

  @override
  Future<InstalledPlugin?> getPlugin(String id) async => _plugins[id];

  @override
  Future<List<InstalledPlugin>> listPlugins() async {
    final result = _plugins.values.toList()
      ..sort(
        (left, right) => left.manifest.name.compareTo(right.manifest.name),
      );
    return List.unmodifiable(result);
  }

  @override
  Future<void> upsertPlugin(InstalledPlugin plugin) async {
    _plugins[plugin.id] = plugin;
  }
}
