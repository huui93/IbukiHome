import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/plugins/ibuki_hook_bus.dart';
import 'package:ibukihome/application/plugins/plugin_contributions.dart';
import 'package:ibukihome/application/plugins/plugin_manager.dart';
import 'package:ibukihome/application/plugins/plugin_package_picker.dart';
import 'package:ibukihome/application/plugins/plugin_runtime.dart';
import 'package:ibukihome/application/plugins/plugin_storage.dart';
import 'package:ibukihome/application/plugins/plugin_web_bundle.dart';
import 'package:ibukihome/core/errors/plugin_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_plugin_registry.dart';
import 'package:ibukihome/data/memory/in_memory_plugin_storage_repository.dart';
import 'package:ibukihome/domain/plugins/ibuki_plugin_manifest.dart';
import 'package:ibukihome/domain/plugins/installed_plugin.dart';
import 'package:path/path.dart' as p;

import '../helpers/plugin_test_helpers.dart';

void main() {
  group('local Web Plugin surface', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('plugin_web_');
    });

    tearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });

    test('loads only declared local HTML CSS and JS', () async {
      final plugin = await _writeWebPlugin(directory);
      final bundle = await const PluginWebBundleLoader().load(
        plugin,
        _contribution(),
      );
      expect(bundle.html, contains('Content-Security-Policy'));
      expect(bundle.html, contains('connect-src \'none\''));
      expect(bundle.html, contains('window.ibuki'));
      expect(bundle.html, contains('.ruby { color: red; }'));
      expect(bundle.html, contains('document.body.dataset.ready'));
    });

    test('rejects entry path outside installed root', () async {
      final plugin = await _writeWebPlugin(directory);
      const escaped = PluginUiContribution(
        pluginId: 'compat.sillytavern.ruby.poc',
        id: 'bad',
        label: 'Bad',
        entry: '../outside.html',
      );
      await expectLater(
        const PluginWebBundleLoader().load(plugin, escaped),
        throwsA(isA<PluginException>()),
      );
    });

    test('missing local asset is isolated as runtime failure', () async {
      final plugin = await _writeWebPlugin(directory);
      const missing = PluginUiContribution(
        pluginId: 'compat.sillytavern.ruby.poc',
        id: 'missing',
        label: 'Missing',
        entry: 'web/missing.html',
      );
      await expectLater(
        const PluginWebBundleLoader().load(plugin, missing),
        throwsA(
          isA<PluginException>().having(
            (error) => error.category,
            'category',
            PluginErrorCategory.pluginRuntimeFailure,
          ),
        ),
      );
    });

    test(
      'synchronous plugin JS is wrapped in a visible failure boundary',
      () async {
        final plugin = await _writeWebPlugin(
          directory,
          script: 'throw new Error("test");',
        );
        final bundle = await const PluginWebBundleLoader().load(
          plugin,
          _contribution(),
        );
        expect(bundle.html, contains('try { (() =>'));
        expect(bundle.html, contains('插件运行异常'));
      },
    );

    for (final url in [
      'http://example.com',
      'https://example.com',
      'file:///data/user/0/private',
      'content://downloads/item',
      'intent://open',
      'market://details',
      'javascript:alert(1)',
    ]) {
      test('navigation policy blocks $url', () {
        expect(PluginWebSecurityPolicy.allowsNavigation(url), false);
      });
    }

    test('navigation policy permits only host-created in-memory documents', () {
      expect(PluginWebSecurityPolicy.allowsNavigation('about:blank'), true);
      expect(
        PluginWebSecurityPolicy.allowsNavigation('data:text/html,local'),
        true,
      );
    });
  });

  group(
    'RUBY package lifecycle',
    () {
      late Directory directory;
      late InMemoryPluginRegistry registry;
      late InMemoryPluginStorageRepository storageRepository;
      late PluginContributionRegistry contributions;
      late IbukiHookBus hooks;
      late PluginManager manager;

      setUp(() async {
        directory = await Directory.systemTemp.createTemp('ruby_lifecycle_');
        registry = InMemoryPluginRegistry();
        storageRepository = InMemoryPluginStorageRepository();
        contributions = PluginContributionRegistry();
        hooks = IbukiHookBus();
        manager = PluginManager(
          registry: registry,
          storageRepository: storageRepository,
          applicationSupportDirectory: directory,
          picker: FakePluginPicker(),
          runtime: DeclarativePluginRuntime(
            contributions: contributions,
            hooks: hooks,
          ),
          hookBus: hooks,
          operationId: () => 'ruby-operation',
        );
      });

      tearDown(() async {
        contributions.dispose();
        if (directory.existsSync()) await directory.delete(recursive: true);
      });

      test(
        'real RUBY .ibuki has safe manifest and no original card/script',
        () {
          final package = _rubyPackage();
          expect(package.existsSync(), true);
          final archive = ZipDecoder().decodeBytes(package.readAsBytesSync());
          final names = archive.files.map((file) => file.name).toSet();
          expect(
            names,
            containsAll(['manifest.json', 'web/index.html', 'web/ruby_poc.js']),
          );
          expect(names.any((name) => name.endsWith('2_5.png')), false);
          final manifest = IbukiPluginManifest.parse(
            utf8.decode(
              (archive.findFile('manifest.json')!.content as List<int>),
            ),
          );
          expect(manifest.id, 'compat.sillytavern.ruby.poc');
          expect(manifest.permissions, isNot(contains('network')));
          expect(manifest.permissions, isNot(contains('ai.generate')));
          final script = utf8.decode(
            archive.findFile('web/ruby_poc.js')!.content as List<int>,
          );
          expect(script, isNot(contains('window.SillyTavern')));
          expect(script, isNot(contains('fetch(')));
          expect(script, contains('renderCycleInfo'));
          expect(script, contains('renderPlayerSchedule'));
        },
      );

      test(
        'install registers RUBY panel and separates install/data paths',
        () async {
          final plugin = await _install(manager);
          expect(plugin.enabled, true);
          expect(
            plugin.installedPath,
            contains(p.join('plugins', 'installed')),
          );
          expect(plugin.dataPath, contains('plugin_data'));
          expect(p.equals(plugin.installedPath, plugin.dataPath), false);
          expect(contributions.chatPanels.single.label, 'RUBY');
        },
      );

      test(
        'disable removes panel and every owned hook but keeps storage',
        () async {
          final plugin = await _install(manager);
          final storage = PluginStorage(
            pluginId: plugin.id,
            repository: storageRepository,
          );
          await storage.set('ui.displayMode', 'compact');
          hooks.subscribe(
            pluginId: plugin.id,
            hook: IbukiHook.afterChatMessageSaved,
            handler: (_) {},
          );
          await manager.disablePlugin(plugin.id);
          expect(contributions.chatPanels, isEmpty);
          expect(hooks.subscriptionCount(plugin.id), 0);
          expect(await storage.get('ui.displayMode'), 'compact');
        },
      );

      test(
        're-enable restores one panel without duplicating registrations',
        () async {
          final plugin = await _install(manager);
          await manager.disablePlugin(plugin.id);
          await manager.enablePlugin(plugin.id);
          await manager.enablePlugin(plugin.id);
          expect(contributions.chatPanels, hasLength(1));
        },
      );

      test('restart restores only enabled valid contributions', () async {
        final plugin = await _install(manager);
        contributions.unregisterPlugin(plugin.id);
        final restartedContributions = PluginContributionRegistry();
        addTearDown(restartedContributions.dispose);
        final restartedHooks = IbukiHookBus();
        final restarted = PluginManager(
          registry: registry,
          storageRepository: storageRepository,
          applicationSupportDirectory: directory,
          picker: FakePluginPicker(),
          runtime: DeclarativePluginRuntime(
            contributions: restartedContributions,
            hooks: restartedHooks,
          ),
          hookBus: restartedHooks,
        );
        final loaded = await restarted.loadEnabledPlugins();
        expect(loaded.single.enabled, true);
        expect(restartedContributions.chatPanels.single.label, 'RUBY');
      });

      test(
        'default uninstall removes install/registry but retains plugin data',
        () async {
          final plugin = await _install(manager);
          final storage = PluginStorage(
            pluginId: plugin.id,
            repository: storageRepository,
          );
          await storage.set('ui.displayMode', 'detailed');
          await manager.uninstallPlugin(plugin.id);
          expect(await registry.getPlugin(plugin.id), isNull);
          expect(Directory(plugin.installedPath).existsSync(), false);
          expect(contributions.chatPanels, isEmpty);
          expect(await storage.get('ui.displayMode'), 'detailed');
        },
      );

      test(
        'explicit delete-data uninstall clears directory and SQLite namespace',
        () async {
          final plugin = await _install(manager);
          final storage = PluginStorage(
            pluginId: plugin.id,
            repository: storageRepository,
          );
          await storage.set('ui.displayMode', 'compact');
          await manager.uninstallPlugin(
            plugin.id,
            dataPolicy: PluginDataPolicy.delete,
          );
          expect(Directory(plugin.dataPath).existsSync(), false);
          expect(await storage.get('ui.displayMode'), isNull);
        },
      );
    },
    skip: !_rubyPackage().existsSync()
        ? 'Requires a local RUBY test package'
        : false,
  );
}

Future<InstalledPlugin> _writeWebPlugin(
  Directory directory, {
  String script = 'document.body.dataset.ready = "true";',
}) async {
  final web = Directory(p.join(directory.path, 'web'));
  await web.create(recursive: true);
  await File(p.join(web.path, 'index.html')).writeAsString(
    '<!doctype html><html><head><!-- IBUKI_PLUGIN_STYLE --></head>'
    '<body class="ruby"><main>RUBY</main><!-- IBUKI_PLUGIN_SCRIPT --></body></html>',
  );
  await File(
    p.join(web.path, 'ruby_poc.css'),
  ).writeAsString('.ruby { color: red; }');
  await File(p.join(web.path, 'ruby_poc.js')).writeAsString(script);
  return InstalledPlugin(
    manifest: _manifest(),
    installedPath: directory.path,
    dataPath: p.join(directory.path, 'data'),
    enabled: true,
    installedAt: DateTime.utc(2026, 8, 26),
    updatedAt: DateTime.utc(2026, 8, 26),
  );
}

IbukiPluginManifest _manifest() => IbukiPluginManifest.fromJson({
  'manifestVersion': 1,
  'extensionApiVersion': 1,
  'id': 'compat.sillytavern.ruby.poc',
  'name': 'RUBY Compatibility PoC',
  'version': '0.1.0',
  'permissions': [
    'chat.read',
    'character.read',
    'storage.private',
    'ui.extend',
  ],
  'capabilities': ['chat-panel', 'web-ui', 'storage'],
  'contributions': {
    'chatPanels': [
      {
        'id': 'ruby-status',
        'label': 'RUBY',
        'entry': 'web/index.html',
        'style': 'web/ruby_poc.css',
        'script': 'web/ruby_poc.js',
      },
    ],
  },
  'runtime': {'type': 'web'},
});

PluginUiContribution _contribution() => const PluginUiContribution(
  pluginId: 'compat.sillytavern.ruby.poc',
  id: 'ruby-status',
  label: 'RUBY',
  entry: 'web/index.html',
  style: 'web/ruby_poc.css',
  script: 'web/ruby_poc.js',
);

File _rubyPackage() =>
    File(p.join('artifacts', 'plugin-packages', 'RUBY-Ibuki-PoC.ibuki'));

Future<InstalledPlugin> _install(PluginManager manager) async {
  final prepared = await manager.prepareInstall(
    FilePluginPackageSource(_rubyPackage()),
  );
  return manager.installPrepared(prepared);
}
