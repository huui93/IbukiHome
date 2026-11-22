import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/plugins/plugin_manager.dart';
import 'package:ibukihome/application/plugins/plugin_package_picker.dart';
import 'package:ibukihome/application/plugins/plugin_runtime.dart';
import 'package:ibukihome/core/errors/plugin_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_plugin_registry.dart';
import 'package:ibukihome/domain/plugins/installed_plugin.dart';
import 'package:path/path.dart' as p;

import '../helpers/plugin_test_helpers.dart';

void main() {
  late List<Directory> directories;

  setUp(() => directories = []);
  tearDown(() async {
    for (final directory in directories) {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  Future<PluginTestContext> context({
    PluginInstallLimits limits = const PluginInstallLimits(),
  }) async {
    final result = await createPluginTestContext(limits: limits);
    directories.add(result.directory);
    return result;
  }

  Future<InstalledPlugin> install(
    PluginTestContext testContext, {
    Map<String, Object?>? manifest,
    Map<String, String> files = const {'assets/readme.txt': 'hello'},
  }) async {
    final package = await writePluginPackage(
      testContext.directory,
      manifest: manifest,
      files: files,
      fileName: 'source-${DateTime.now().microsecondsSinceEpoch}.ibuki',
    );
    final prepared = await testContext.manager.prepareInstall(
      FilePluginPackageSource(package),
    );
    return testContext.manager.installPrepared(prepared);
  }

  test('valid ZIP installs into private installed directory', () async {
    final testContext = await context();
    final plugin = await install(testContext);

    expect(plugin.enabled, true);
    expect(plugin.installedPath, contains(p.join('plugins', 'installed')));
    expect(
      File(p.join(plugin.installedPath, 'manifest.json')).existsSync(),
      true,
    );
    expect(
      File(p.join(plugin.installedPath, 'assets', 'readme.txt')).existsSync(),
      true,
    );
  });

  test('a generated no-code fixture installs as a foundation plugin', () async {
    final testContext = await context();
    final package = await writePluginPackage(
      testContext.directory,
      manifest: pluginManifest(id: 'dev.ibuki.hello', name: 'Hello Ibuki'),
    );
    final prepared = await testContext.manager.prepareInstall(
      FilePluginPackageSource(package),
    );
    final plugin = await testContext.manager.installPrepared(prepared);
    expect(plugin.id, 'dev.ibuki.hello');
    expect(plugin.manifest.name, 'Hello Ibuki');
    expect(plugin.manifest.capabilities, ['demo']);
  });

  test('missing manifest is rejected and installing temp is cleaned', () async {
    final testContext = await context();
    final package = await writePluginPackage(
      testContext.directory,
      includeManifest: false,
    );

    await expectLater(
      testContext.manager.prepareInstall(FilePluginPackageSource(package)),
      throwsA(
        isA<PluginException>().having(
          (error) => error.category,
          'category',
          PluginErrorCategory.missingManifest,
        ),
      ),
    );
    final installing = Directory(
      p.join(testContext.directory.path, 'plugins', '.installing'),
    );
    expect(await installing.list().isEmpty, true);
  });

  test('malformed manifest in ZIP is rejected', () async {
    final testContext = await context();
    final package = await writePluginPackage(
      testContext.directory,
      rawManifest: '{bad',
    );
    await expectLater(
      testContext.manager.prepareInstall(FilePluginPackageSource(package)),
      throwsA(isA<PluginException>()),
    );
  });

  test('corrupted ZIP is rejected', () async {
    final testContext = await context();
    final file = File(p.join(testContext.directory.path, 'broken.ibuki'));
    await file.writeAsBytes([0x50, 0x4b, 0x03, 0x04, 1, 2, 3]);
    await expectLater(
      testContext.manager.prepareInstall(FilePluginPackageSource(file)),
      throwsA(
        isA<PluginException>().having(
          (error) => error.category,
          'category',
          PluginErrorCategory.invalidArchive,
        ),
      ),
    );
  });

  test('non ZIP .ibuki is rejected by magic bytes', () async {
    final testContext = await context();
    final file = File(p.join(testContext.directory.path, 'fake.ibuki'));
    await file.writeAsString('not a zip');
    await expectLater(
      testContext.manager.prepareInstall(FilePluginPackageSource(file)),
      throwsA(isA<PluginException>()),
    );
  });

  test('wrong extension is rejected even when content is ZIP', () async {
    final testContext = await context();
    final package = await writePluginPackage(
      testContext.directory,
      fileName: 'plugin.zip',
    );
    await expectLater(
      testContext.manager.prepareInstall(FilePluginPackageSource(package)),
      throwsA(
        isA<PluginException>().having(
          (error) => error.category,
          'category',
          PluginErrorCategory.invalidExtension,
        ),
      ),
    );
  });

  test('ZIP traversal is rejected and cannot write outside staging', () async {
    final testContext = await context();
    final package = await writePluginPackage(
      testContext.directory,
      files: const {'../escape.txt': 'unsafe'},
    );
    await expectLater(
      testContext.manager.prepareInstall(FilePluginPackageSource(package)),
      throwsA(
        isA<PluginException>().having(
          (error) => error.category,
          'category',
          PluginErrorCategory.unsafeArchivePath,
        ),
      ),
    );
    expect(
      File(p.join(testContext.directory.path, 'escape.txt')).existsSync(),
      false,
    );
  });

  test('symbolic links are rejected', () async {
    final testContext = await context();
    final link = ArchiveFile.string('assets/link', '../outside')..mode = 0xa1ff;
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('manifest.json', jsonEncode(pluginManifest())),
      )
      ..addFile(link);
    final package = File(p.join(testContext.directory.path, 'link.ibuki'));
    final encoded = ZipEncoder().encodeBytes(archive);
    for (var index = 0; index < encoded.length - 6; index++) {
      if (encoded[index] == 0x50 &&
          encoded[index + 1] == 0x4b &&
          encoded[index + 2] == 0x01 &&
          encoded[index + 3] == 0x02) {
        encoded[index + 5] = 3;
      }
    }
    await package.writeAsBytes(encoded);
    await expectLater(
      testContext.manager.prepareInstall(FilePluginPackageSource(package)),
      throwsA(isA<PluginException>()),
    );
  });

  test('package size limit rejects without OOM', () async {
    final testContext = await context(
      limits: const PluginInstallLimits(maxPackageBytes: 20),
    );
    final package = await writePluginPackage(testContext.directory);
    await expectLater(
      testContext.manager.prepareInstall(FilePluginPackageSource(package)),
      throwsA(
        isA<PluginException>().having(
          (error) => error.category,
          'category',
          PluginErrorCategory.packageTooLarge,
        ),
      ),
    );
  });

  test('single file and extracted total limits are enforced', () async {
    final testContext = await context(
      limits: const PluginInstallLimits(
        maxSingleFileBytes: 10,
        maxExtractedBytes: 40,
      ),
    );
    final package = await writePluginPackage(
      testContext.directory,
      files: const {'assets/large.txt': '01234567890'},
    );
    await expectLater(
      testContext.manager.prepareInstall(FilePluginPackageSource(package)),
      throwsA(isA<PluginException>()),
    );
  });

  test('archive entry count limit is enforced', () async {
    final testContext = await context(
      limits: const PluginInstallLimits(maxEntries: 2),
    );
    final package = await writePluginPackage(
      testContext.directory,
      files: const {'one.txt': '1', 'two.txt': '2'},
    );
    await expectLater(
      testContext.manager.prepareInstall(FilePluginPackageSource(package)),
      throwsA(isA<PluginException>()),
    );
  });

  test('minimum app version is enforced', () async {
    final testContext = await context();
    final package = await writePluginPackage(
      testContext.directory,
      manifest: pluginManifest(minIbukiVersion: '9.0.0'),
    );
    await expectLater(
      testContext.manager.prepareInstall(FilePluginPackageSource(package)),
      throwsA(
        isA<PluginException>().having(
          (error) => error.category,
          'category',
          PluginErrorCategory.incompatibleAppVersion,
        ),
      ),
    );
  });

  test('duplicate same-version install is rejected', () async {
    final testContext = await context();
    await install(testContext);
    final package = await writePluginPackage(
      testContext.directory,
      fileName: 'duplicate.ibuki',
    );
    await expectLater(
      testContext.manager.prepareInstall(FilePluginPackageSource(package)),
      throwsA(
        isA<PluginException>().having(
          (error) => error.category,
          'category',
          PluginErrorCategory.duplicateInstall,
        ),
      ),
    );
  });

  test('update replaces install files and retains enabled state', () async {
    final testContext = await context();
    await install(testContext);
    await testContext.manager.disablePlugin('dev.ibuki.test');
    final updated = await install(
      testContext,
      manifest: pluginManifest(version: '2.0.0'),
      files: const {'assets/v2.txt': 'version two'},
    );

    expect(updated.manifest.version, '2.0.0');
    expect(updated.enabled, false);
    expect(
      File(p.join(updated.installedPath, 'assets', 'v2.txt')).existsSync(),
      true,
    );
    expect(
      File(p.join(updated.installedPath, 'assets', 'readme.txt')).existsSync(),
      false,
    );
  });

  test('failed update keeps the old plugin intact', () async {
    final testContext = await context();
    final old = await install(testContext);
    final oldManifest = File(p.join(old.installedPath, 'manifest.json'));
    final package = await writePluginPackage(
      testContext.directory,
      manifest: pluginManifest(version: '2.0.0'),
      fileName: 'update.ibuki',
    );
    final prepared = await testContext.manager.prepareInstall(
      FilePluginPackageSource(package),
    );
    await File(prepared.packagePath).writeAsString('corrupted after preview');

    await expectLater(
      testContext.manager.installPrepared(prepared),
      throwsA(isA<PluginException>()),
    );
    expect(oldManifest.existsSync(), true);
    expect(
      (await testContext.registry.getPlugin(old.id))?.manifest.version,
      '1.0.0',
    );
  });

  test('enable and disable persist in registry', () async {
    final testContext = await context();
    final plugin = await install(testContext);
    await testContext.manager.disablePlugin(plugin.id);
    expect((await testContext.registry.getPlugin(plugin.id))?.enabled, false);
    await testContext.manager.enablePlugin(plugin.id);
    expect((await testContext.registry.getPlugin(plugin.id))?.enabled, true);
  });

  test('restart load retains plugin state', () async {
    final testContext = await context();
    final plugin = await install(testContext);
    await testContext.manager.disablePlugin(plugin.id);
    final secondManager = PluginManager(
      registry: testContext.registry,
      applicationSupportDirectory: testContext.directory,
      picker: FakePluginPicker(),
    );
    final loaded = await secondManager.loadEnabledPlugins();
    expect(loaded.single.id, plugin.id);
    expect(loaded.single.enabled, false);
  });

  test('missing plugin directory is marked broken without throwing', () async {
    final testContext = await context();
    final plugin = await install(testContext);
    await Directory(plugin.installedPath).delete(recursive: true);

    final loaded = await testContext.manager.loadEnabledPlugins();
    expect(loaded.single.status, InstalledPluginStatus.broken);
  });

  test(
    'one broken plugin does not prevent another plugin from loading',
    () async {
      final testContext = await context();
      final first = await install(testContext);
      final second = await install(
        testContext,
        manifest: pluginManifest(id: 'dev.ibuki.second', name: 'Second'),
      );
      await Directory(first.installedPath).delete(recursive: true);

      final loaded = await testContext.manager.loadEnabledPlugins();
      expect(loaded.where((item) => item.id == first.id).single.isBroken, true);
      expect(
        loaded.where((item) => item.id == second.id).single.isBroken,
        false,
      );
    },
  );

  test('unknown files and capabilities are retained', () async {
    final testContext = await context();
    final plugin = await install(
      testContext,
      manifest: pluginManifest(capabilities: const ['future.magic']),
      files: const {
        'future/new-api.json': '{}',
        'scripts/main.future': 'opaque',
      },
    );
    expect(plugin.manifest.capabilities, contains('future.magic'));
    expect(
      File(p.join(plugin.installedPath, 'future', 'new-api.json')).existsSync(),
      true,
    );
    expect(
      File(p.join(plugin.installedPath, 'scripts', 'main.future')).existsSync(),
      true,
    );
  });

  test('plugin data is separate and survives update', () async {
    final testContext = await context();
    final plugin = await install(testContext);
    final dataFile = File(
      p.join(
        testContext.manager.pluginDataRoot.path,
        plugin.id,
        'user-data.txt',
      ),
    );
    await dataFile.writeAsString('keep me');
    await install(testContext, manifest: pluginManifest(version: '2.0.0'));
    expect(await dataFile.readAsString(), 'keep me');
  });

  test(
    'uninstall removes install and registry but keeps plugin data',
    () async {
      final testContext = await context();
      final plugin = await install(testContext);
      final dataDirectory = Directory(
        p.join(testContext.manager.pluginDataRoot.path, plugin.id),
      );
      await testContext.manager.uninstallPlugin(plugin.id);
      expect(Directory(plugin.installedPath).existsSync(), false);
      expect(await testContext.registry.getPlugin(plugin.id), isNull);
      expect(dataDirectory.existsSync(), true);
    },
  );

  test('uninstall can explicitly delete plugin data', () async {
    final testContext = await context();
    final plugin = await install(testContext);
    final dataDirectory = Directory(
      p.join(testContext.manager.pluginDataRoot.path, plugin.id),
    );
    await testContext.manager.uninstallPlugin(
      plugin.id,
      dataPolicy: PluginDataPolicy.delete,
    );
    expect(dataDirectory.existsSync(), false);
  });

  test(
    'file picker cancel returns null without creating install state',
    () async {
      final testContext = await context();
      expect(await testContext.manager.pickAndPrepareInstall(), isNull);
      expect(testContext.picker.calls, 1);
      expect(await testContext.registry.listPlugins(), isEmpty);
    },
  );

  test('discarding install preview cleans its temporary directory', () async {
    final testContext = await context();
    final package = await writePluginPackage(testContext.directory);
    final prepared = await testContext.manager.prepareInstall(
      FilePluginPackageSource(package),
    );
    expect(Directory(prepared.operationDirectory).existsSync(), true);
    await testContext.manager.discardPrepared(prepared);
    expect(Directory(prepared.operationDirectory).existsSync(), false);
  });

  test('startup cleans abandoned installing directories', () async {
    final testContext = await context();
    final abandoned = Directory(
      p.join(testContext.directory.path, 'plugins', '.installing', 'abandoned'),
    );
    await abandoned.create(recursive: true);
    await File(p.join(abandoned.path, 'partial')).writeAsString('partial');
    await testContext.manager.loadEnabledPlugins();
    expect(abandoned.existsSync(), false);
  });

  test(
    'lifecycle receives install enable disable start and uninstall',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ibuki_plugin_lifecycle_',
      );
      directories.add(directory);
      final registry = InMemoryPluginRegistry();
      final lifecycle = _RecordingLifecycle();
      var operation = 0;
      final manager = PluginManager(
        registry: registry,
        applicationSupportDirectory: directory,
        picker: FakePluginPicker(),
        lifecycle: lifecycle,
        operationId: () => 'lifecycle-${operation++}',
      );
      final package = await writePluginPackage(directory);
      final prepared = await manager.prepareInstall(
        FilePluginPackageSource(package),
      );
      final plugin = await manager.installPrepared(prepared);
      await manager.disablePlugin(plugin.id);
      await manager.enablePlugin(plugin.id);
      await manager.loadEnabledPlugins();
      await manager.uninstallPlugin(plugin.id);
      expect(lifecycle.events, [
        'install',
        'enable',
        'disable',
        'enable',
        'start',
        'uninstall',
      ]);
    },
  );
}

class _RecordingLifecycle implements PluginLifecycle {
  final List<String> events = [];

  @override
  Future<void> onAppStart(InstalledPlugin plugin) async => events.add('start');

  @override
  Future<void> onDisable(InstalledPlugin plugin) async => events.add('disable');

  @override
  Future<void> onEnable(InstalledPlugin plugin) async => events.add('enable');

  @override
  Future<void> onInstall(InstalledPlugin plugin) async => events.add('install');

  @override
  Future<void> onUninstall(InstalledPlugin plugin) async =>
      events.add('uninstall');
}
