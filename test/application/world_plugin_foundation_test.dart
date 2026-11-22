import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/plugins/plugin_contributions.dart';
import 'package:ibukihome/application/plugins/plugin_creative_state.dart';
import 'package:ibukihome/core/errors/plugin_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_plugin_registry.dart';
import 'package:ibukihome/data/memory/in_memory_plugin_storage_repository.dart';
import 'package:ibukihome/domain/plugins/ibuki_plugin_manifest.dart';
import 'package:ibukihome/domain/plugins/installed_plugin.dart';

void main() {
  test(
    'world and worldSession scopes round-trip and persist independently',
    () async {
      const world = PluginScopeRef.world('world-a');
      const session = PluginScopeRef.worldSession('session-a');
      expect(PluginScopeRef.fromJson(world.toJson()), world);
      expect(PluginScopeRef.fromJson(session.toJson()), session);

      final registry = InMemoryPluginRegistry();
      final storage = InMemoryPluginStorageRepository();
      final plugin = _installed(_promptManifest());
      await registry.upsertPlugin(plugin);
      final state = PluginCreativeStateStore(
        registry: registry,
        storage: storage,
      );
      await state.bind(plugin: plugin, scope: world);
      await state.bind(plugin: plugin, scope: session);

      final reopened = PluginCreativeStateStore(
        registry: registry,
        storage: storage,
      );
      expect(
        (await reopened.bindingsFor(
          plugin.id,
        )).map((item) => item.scope).toSet(),
        {world, session},
      );
    },
  );

  test('world navigation contribution is generic, scoped, and removable', () {
    final contributions = PluginContributionRegistry();
    addTearDown(contributions.dispose);
    final plugin = _installed(
      IbukiPluginManifest.fromJson({
        'manifestVersion': 1,
        'extensionApiVersion': 1,
        'id': 'dev.ibuki.world.fixture',
        'name': 'World Fixture',
        'version': '1.0.0',
        'permissions': ['ui.extend'],
        'capabilities': ['future.world.tool'],
        'contributions': {
          'worldNavigation': [
            {
              'id': 'map-fixture',
              'label': '地图测试入口',
              'icon': 'map',
              'entry': 'web/map.html',
              'worldSessionId': 'session-a',
            },
          ],
        },
      }),
    );

    contributions.registerPlugin(plugin);
    final item = contributions.worldNavigation.single;
    expect(item.pluginId, plugin.id);
    expect(
      item.appliesTo(worldId: 'world-a', worldSessionId: 'session-a'),
      true,
    );
    expect(
      item.appliesTo(worldId: 'world-a', worldSessionId: 'session-b'),
      false,
    );
    contributions.unregisterPlugin(plugin.id);
    expect(contributions.worldNavigation, isEmpty);
  });

  test('world navigation contribution still requires ui.extend', () {
    final contributions = PluginContributionRegistry();
    addTearDown(contributions.dispose);
    final plugin = _installed(
      IbukiPluginManifest.fromJson({
        'manifestVersion': 1,
        'id': 'dev.ibuki.world.no_permission',
        'name': 'No Permission',
        'version': '1.0.0',
        'contributions': {
          'worldNavigation': [
            {'id': 'bad', 'label': 'Bad', 'entry': 'web/index.html'},
          ],
        },
      }),
    );
    expect(
      () => contributions.registerPlugin(plugin),
      throwsA(
        isA<PluginException>().having(
          (error) => error.category,
          'category',
          PluginErrorCategory.permissionDenied,
        ),
      ),
    );
  });
}

IbukiPluginManifest _promptManifest() => IbukiPluginManifest.fromJson({
  'manifestVersion': 1,
  'id': 'dev.ibuki.world.scope',
  'name': 'World Scope Fixture',
  'version': '1.0.0',
  'permissions': ['ai.prompt.modify'],
  'promptContributions': [
    {
      'id': 'scope-fixture',
      'operations': ['novel.generate'],
      'styleInstruction': 'fixture',
    },
  ],
});

InstalledPlugin _installed(IbukiPluginManifest manifest) => InstalledPlugin(
  manifest: manifest,
  installedPath: 'installed/${manifest.id}',
  dataPath: 'data/${manifest.id}',
  enabled: true,
  installedAt: DateTime.utc(2026, 8, 28),
  updatedAt: DateTime.utc(2026, 8, 28),
);
