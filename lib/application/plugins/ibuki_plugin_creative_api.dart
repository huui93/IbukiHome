import '../../domain/plugins/installed_plugin.dart';
import '../../domain/plugins/plugin_creative_manifest.dart';
import 'plugin_creative_state.dart';

class IbukiPluginPromptApi {
  const IbukiPluginPromptApi(this.plugin);

  final InstalledPlugin plugin;

  List<PluginPromptContribution> get contributions =>
      plugin.manifest.parsePromptContributions();

  Set<String> get operations =>
      contributions.expand((item) => item.operationKeys).toSet();
}

class IbukiPluginScopeApi {
  const IbukiPluginScopeApi({
    required this.plugin,
    required this.currentScope,
    required this.states,
  });

  final InstalledPlugin plugin;
  final PluginScopeRef currentScope;
  final PluginCreativeStateStore states;

  Future<bool> isAppliedToCurrentScope() async {
    final bindings = await states.bindingsFor(plugin.id);
    return bindings.any((item) => item.scope == currentScope);
  }
}

class IbukiPluginSettingsApi {
  const IbukiPluginSettingsApi({
    required this.plugin,
    required this.currentScope,
    required this.states,
  });

  final InstalledPlugin plugin;
  final PluginScopeRef currentScope;
  final PluginCreativeStateStore states;

  Future<Map<String, Object?>> getAll() {
    return states.settingsFor(plugin.manifest, currentScope);
  }

  Future<void> set(String key, Object? value) {
    return states.setSetting(
      manifest: plugin.manifest,
      scope: currentScope,
      key: key,
      value: value,
    );
  }
}
