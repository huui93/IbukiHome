import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/plugins/plugin_manager.dart';
import 'package:ibukihome/application/plugins/plugin_creative_state.dart';
import 'package:ibukihome/application/plugins/plugin_providers.dart';
import 'package:ibukihome/data/memory/in_memory_plugin_registry.dart';
import 'package:ibukihome/data/memory/in_memory_plugin_storage_repository.dart';
import 'package:ibukihome/domain/plugins/ibuki_plugin_manifest.dart';
import 'package:ibukihome/domain/plugins/installed_plugin.dart';
import 'package:ibukihome/features/plugins/presentation/plugin_pages.dart';

import '../../helpers/plugin_test_helpers.dart';

void main() {
  Widget app(PluginManager manager, Widget child) {
    return ProviderScope(
      overrides: [pluginManagerProvider.overrideWithValue(manager)],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var index = 0; index < 8; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Settings plugin management shows empty state', (tester) async {
    final manager = _UiPluginManager();
    await tester.pumpWidget(app(manager, const PluginManagementPage()));
    await settle(tester);

    expect(find.byKey(const Key('plugin-empty-state')), findsOneWidget);
    expect(find.text('还没有安装插件'), findsOneWidget);
    expect(find.byKey(const Key('choose-plugin-button')), findsOneWidget);
  });

  testWidgets('file picker cancel leaves empty state unchanged', (
    tester,
  ) async {
    final manager = _UiPluginManager();
    await tester.pumpWidget(app(manager, const PluginManagementPage()));
    await settle(tester);
    await tester.tap(find.byKey(const Key('choose-plugin-button')));
    await settle(tester);

    expect(manager.pickCalls, 1);
    expect(find.byKey(const Key('plugin-empty-state')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('install selection shows preview before registry write', (
    tester,
  ) async {
    final manager = _UiPluginManager(prepared: _prepared());
    await tester.pumpWidget(app(manager, const PluginManagementPage()));
    await settle(tester);

    await tester.tap(find.byKey(const Key('choose-plugin-button')));
    await settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('安装插件'), findsWidgets);
    expect(find.text('Test Plugin'), findsOneWidget);
    expect(manager.items, isEmpty);

    await tester.tap(find.byKey(const Key('confirm-install-plugin-button')));
    await settle(tester);
    expect(find.byKey(const Key('plugin-card-dev.ibuki.test')), findsOneWidget);
    expect(manager.items.single.enabled, true);
  });

  testWidgets('installed plugin list switch persists disabled state', (
    tester,
  ) async {
    final manager = _UiPluginManager(items: [_installed()]);
    await tester.pumpWidget(app(manager, const PluginManagementPage()));
    await settle(tester);
    expect(find.text('Test Plugin'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plugin-switch-dev.ibuki.test')));
    await settle(tester);
    expect(manager.items.single.enabled, false);
  });

  testWidgets('plugin detail shows technical fields and uninstall confirms', (
    tester,
  ) async {
    final manager = _UiPluginManager(items: [_installed()]);
    await tester.pumpWidget(
      app(manager, const PluginDetailPage(pluginId: 'dev.ibuki.test')),
    );
    await settle(tester);

    expect(find.text('Plugin ID'), findsOneWidget);
    expect(find.text('dev.ibuki.test'), findsOneWidget);
    expect(find.text('Capabilities'), findsOneWidget);
    expect(find.text('demo'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('uninstall-plugin-button')),
      240,
    );
    await tester.tap(find.byKey(const Key('uninstall-plugin-button')));
    await settle(tester);
    expect(find.text('卸载“Test Plugin”？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-uninstall-plugin-button')));
    await settle(tester);
    expect(manager.items, isEmpty);
  });

  testWidgets('creative plugin detail renders scope and schema settings', (
    tester,
  ) async {
    final plugin = _installedCreative();
    final manager = _UiPluginManager(items: [plugin]);
    final registry = InMemoryPluginRegistry();
    await registry.upsertPlugin(plugin);
    final storage = InMemoryPluginStorageRepository();
    final states = PluginCreativeStateStore(
      registry: registry,
      storage: storage,
    );
    addTearDown(states.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluginManagerProvider.overrideWithValue(manager),
          pluginRegistryProvider.overrideWithValue(registry),
          pluginStorageRepositoryProvider.overrideWithValue(storage),
          pluginCreativeStateStoreProvider.overrideWithValue(states),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PluginDetailPage(pluginId: 'dev.ibuki.creative-ui'),
          ),
        ),
      ),
    );
    await settle(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('plugin-prompt-scope-section')),
      240,
    );
    expect(find.text('影响 AI 的范围'), findsOneWidget);
    expect(find.byKey(const Key('plugin-scope-global')), findsOneWidget);
    expect(find.text('插件设置'), findsOneWidget);
    expect(find.byKey(const Key('plugin-setting-tone')), findsOneWidget);

    await tester.tap(find.byKey(const Key('plugin-scope-global')));
    await settle(tester);
    expect(await states.bindingsFor(plugin.id), hasLength(1));
  });
}

IbukiPluginManifest _manifest() =>
    IbukiPluginManifest.fromJson(pluginManifest().cast<String, dynamic>());

InstalledPlugin _installed({bool enabled = true}) => InstalledPlugin(
  manifest: _manifest(),
  installedPath: '/private/plugins/installed/dev.ibuki.test',
  dataPath: '/private/plugin_data/dev.ibuki.test',
  enabled: enabled,
  installedAt: DateTime.utc(2026, 8, 26),
  updatedAt: DateTime.utc(2026, 8, 26),
  packageSize: 100,
  extractedSize: 200,
);

InstalledPlugin _installedCreative() => InstalledPlugin(
  manifest: IbukiPluginManifest.fromJson(
    {
      ...pluginManifest(id: 'dev.ibuki.creative-ui'),
      'permissions': ['ai.prompt.modify', 'storage.private'],
      'promptContributions': [
        {
          'id': 'style',
          'operations': ['novel.generate'],
          'styleInstruction': 'test',
        },
      ],
      'settingsSchema': {
        'tone': {
          'type': 'enum',
          'values': ['light', 'balanced'],
          'default': 'balanced',
        },
      },
    }.cast<String, dynamic>(),
  ),
  installedPath: '/private/plugins/installed/dev.ibuki.creative-ui',
  dataPath: '/private/plugin_data/dev.ibuki.creative-ui',
  enabled: true,
  installedAt: DateTime.utc(2026, 8, 27),
  updatedAt: DateTime.utc(2026, 8, 27),
);

PreparedPluginInstall _prepared() => PreparedPluginInstall(
  manifest: _manifest(),
  sourceFileName: 'hello_ibuki.ibuki',
  packagePath: '/temporary/plugin.ibuki',
  operationDirectory: '/temporary/install',
  packageSize: 100,
  extractedSize: 200,
  isUpdate: false,
);

class _UiPluginManager extends PluginManager {
  _UiPluginManager({List<InstalledPlugin>? items, this.prepared})
    : items = [...?items],
      super(
        registry: InMemoryPluginRegistry(),
        applicationSupportDirectory: Directory.systemTemp,
        picker: FakePluginPicker(),
      );

  final List<InstalledPlugin> items;
  final PreparedPluginInstall? prepared;
  int pickCalls = 0;

  @override
  Future<List<InstalledPlugin>> getInstalledPlugins() async =>
      List.unmodifiable(items);

  @override
  Future<PreparedPluginInstall?> pickAndPrepareInstall() async {
    pickCalls += 1;
    return prepared;
  }

  @override
  Future<InstalledPlugin> installPrepared(
    PreparedPluginInstall prepared,
  ) async {
    final plugin = _installed();
    items.add(plugin);
    return plugin;
  }

  @override
  Future<void> discardPrepared(PreparedPluginInstall prepared) async {}

  @override
  Future<void> enablePlugin(String id) async => _setEnabled(id, true);

  @override
  Future<void> disablePlugin(String id) async => _setEnabled(id, false);

  void _setEnabled(String id, bool enabled) {
    final index = items.indexWhere((item) => item.id == id);
    items[index] = items[index].copyWith(enabled: enabled);
  }

  @override
  Future<void> uninstallPlugin(
    String id, {
    PluginDataPolicy dataPolicy = PluginDataPolicy.keep,
  }) async {
    items.removeWhere((item) => item.id == id);
  }
}
