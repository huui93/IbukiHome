import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/memory/in_memory_plugin_registry.dart';
import '../../data/memory/in_memory_plugin_storage_repository.dart';
import '../../data/repositories/plugin_registry.dart';
import '../../data/repositories/plugin_storage_repository.dart';
import '../../domain/plugins/installed_plugin.dart';
import 'ibuki_hook_bus.dart';
import 'ibuki_web_plugin_bridge.dart';
import 'plugin_contributions.dart';
import 'plugin_creative_state.dart';
import 'ibuki_prompt_pipeline.dart';
import 'plugin_manager.dart';
import 'plugin_package_picker.dart';
import 'plugin_runtime.dart';

final pluginRegistryProvider = Provider<PluginRegistry>((ref) {
  return InMemoryPluginRegistry();
});

final pluginPackagePickerProvider = Provider<PluginPackagePicker>((ref) {
  return const SafPluginPackagePicker();
});

final pluginStorageRepositoryProvider = Provider<PluginStorageRepository>((
  ref,
) {
  return InMemoryPluginStorageRepository();
});

final pluginContributionRegistryProvider = Provider<PluginContributionRegistry>(
  (ref) {
    final registry = PluginContributionRegistry();
    ref.onDispose(registry.dispose);
    return registry;
  },
);

final pluginCreativeStateStoreProvider = Provider<PluginCreativeStateStore>((
  ref,
) {
  final store = PluginCreativeStateStore(
    registry: ref.watch(pluginRegistryProvider),
    storage: ref.watch(pluginStorageRepositoryProvider),
  );
  ref.onDispose(store.dispose);
  return store;
});

final pluginPromptDiagnosticsLoggerProvider =
    Provider<PluginPromptDiagnosticsLogger>((ref) {
      return PluginPromptDiagnosticsLogger(sink: debugPrint);
    });

final ibukiPromptPipelineProvider = Provider<IbukiPromptPipeline>((ref) {
  return CorePluginPromptPipeline(
    contributions: ref.watch(pluginContributionRegistryProvider),
    states: ref.watch(pluginCreativeStateStoreProvider),
    registry: ref.watch(pluginRegistryProvider),
    hooks: ref.watch(ibukiHookBusProvider),
    diagnosticsLogger: ref.watch(pluginPromptDiagnosticsLoggerProvider),
  );
});

final ibukiHookBusProvider = Provider<IbukiHookBus>((ref) => IbukiHookBus());

final pluginBridgeLoggerProvider = Provider<PluginBridgeLogger>((ref) {
  return RollingPluginBridgeLogger();
});

final pluginRuntimeProvider = Provider<PluginRuntime>((ref) {
  return DeclarativePluginRuntime(
    contributions: ref.watch(pluginContributionRegistryProvider),
    hooks: ref.watch(ibukiHookBusProvider),
  );
});

final pluginManagerProvider = Provider<PluginManager>((ref) {
  return PluginManager(
    registry: ref.watch(pluginRegistryProvider),
    applicationSupportDirectory: Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}ibukihome-plugin-preview',
    ),
    picker: ref.watch(pluginPackagePickerProvider),
    runtime: ref.watch(pluginRuntimeProvider),
    hookBus: ref.watch(ibukiHookBusProvider),
    storageRepository: ref.watch(pluginStorageRepositoryProvider),
  );
});

final installedPluginsProvider = FutureProvider<List<InstalledPlugin>>((ref) {
  return ref.watch(pluginManagerProvider).getInstalledPlugins();
});

final pluginChatPanelsProvider = StreamProvider<List<PluginUiContribution>>((
  ref,
) {
  return ref.watch(pluginContributionRegistryProvider).watchChatPanels();
});

final pluginWorldNavigationProvider =
    StreamProvider<List<PluginWorldNavigationContribution>>((ref) {
      return ref
          .watch(pluginContributionRegistryProvider)
          .watchWorldNavigation();
    });
