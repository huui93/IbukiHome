import '../../domain/plugins/ibuki_plugin_manifest.dart';
import '../../domain/plugins/installed_plugin.dart';
import 'ibuki_hook_bus.dart';
import 'plugin_contributions.dart';

abstract class PluginRuntime {
  bool supports(IbukiPluginManifest manifest);

  Future<void> load(InstalledPlugin plugin);

  Future<void> unload(InstalledPlugin plugin);
}

class NoExecutablePluginRuntime implements PluginRuntime {
  const NoExecutablePluginRuntime();

  @override
  bool supports(IbukiPluginManifest manifest) => manifest.runtime == null;

  @override
  Future<void> load(InstalledPlugin plugin) async {}

  @override
  Future<void> unload(InstalledPlugin plugin) async {}
}

class DeclarativePluginRuntime implements PluginRuntime {
  DeclarativePluginRuntime({required this.contributions, required this.hooks});

  final PluginContributionRegistry contributions;
  final IbukiHookBus hooks;

  @override
  bool supports(IbukiPluginManifest manifest) {
    final type = manifest.runtime?['type'];
    return type == null || type == 'declarative' || type == 'web';
  }

  @override
  Future<void> load(InstalledPlugin plugin) async {
    contributions.registerPlugin(plugin);
  }

  @override
  Future<void> unload(InstalledPlugin plugin) async {
    contributions.unregisterPlugin(plugin.id);
    hooks.removePlugin(plugin.id);
  }
}

abstract class PluginLifecycle {
  Future<void> onInstall(InstalledPlugin plugin);

  Future<void> onEnable(InstalledPlugin plugin);

  Future<void> onDisable(InstalledPlugin plugin);

  Future<void> onUninstall(InstalledPlugin plugin);

  Future<void> onAppStart(InstalledPlugin plugin);
}

class NoopPluginLifecycle implements PluginLifecycle {
  const NoopPluginLifecycle();

  @override
  Future<void> onAppStart(InstalledPlugin plugin) async {}

  @override
  Future<void> onDisable(InstalledPlugin plugin) async {}

  @override
  Future<void> onEnable(InstalledPlugin plugin) async {}

  @override
  Future<void> onInstall(InstalledPlugin plugin) async {}

  @override
  Future<void> onUninstall(InstalledPlugin plugin) async {}
}

// Security boundary: plugin runtimes must never receive provider API keys,
// Authorization headers, or Secure Storage access. Future AI extensions must
// call a capability-scoped Core API that resolves and invokes providers.
