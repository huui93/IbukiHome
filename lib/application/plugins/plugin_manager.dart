import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/plugin_exceptions.dart';
import '../../data/repositories/plugin_registry.dart';
import '../../data/repositories/plugin_storage_repository.dart';
import '../../domain/plugins/ibuki_plugin_manifest.dart';
import '../../domain/plugins/installed_plugin.dart';
import 'plugin_package_picker.dart';
import 'ibuki_hook_bus.dart';
import 'plugin_runtime.dart';

class PluginInstallLimits {
  const PluginInstallLimits({
    this.maxPackageBytes = 150 * 1024 * 1024,
    this.maxSingleFileBytes = 75 * 1024 * 1024,
    this.maxExtractedBytes = 400 * 1024 * 1024,
    this.maxEntries = 4096,
    this.maxManifestBytes = 1024 * 1024,
  });

  final int maxPackageBytes;
  final int maxSingleFileBytes;
  final int maxExtractedBytes;
  final int maxEntries;
  final int maxManifestBytes;
}

enum PluginDataPolicy { keep, delete }

class PreparedPluginInstall {
  const PreparedPluginInstall({
    required this.manifest,
    required this.sourceFileName,
    required this.packagePath,
    required this.operationDirectory,
    required this.packageSize,
    required this.extractedSize,
    required this.isUpdate,
    this.existingPlugin,
  });

  final IbukiPluginManifest manifest;
  final String sourceFileName;
  final String packagePath;
  final String operationDirectory;
  final int packageSize;
  final int extractedSize;
  final bool isUpdate;
  final InstalledPlugin? existingPlugin;
}

class PluginManager {
  PluginManager({
    required this.registry,
    required this.applicationSupportDirectory,
    required this.picker,
    this.runtime = const NoExecutablePluginRuntime(),
    this.lifecycle = const NoopPluginLifecycle(),
    this.storageRepository,
    IbukiHookBus? hookBus,
    this.applicationVersion = '1.1.0',
    this.limits = const PluginInstallLimits(),
    DateTime Function()? now,
    String Function()? operationId,
  }) : hookBus = hookBus ?? IbukiHookBus(),
       _now = now ?? DateTime.now,
       _operationId = operationId ?? _defaultOperationId;

  final PluginRegistry registry;
  final Directory applicationSupportDirectory;
  final PluginPackagePicker picker;
  final PluginRuntime runtime;
  final PluginLifecycle lifecycle;
  final PluginStorageRepository? storageRepository;
  final IbukiHookBus hookBus;
  final String applicationVersion;
  final PluginInstallLimits limits;
  final DateTime Function() _now;
  final String Function() _operationId;

  Directory get _pluginsRoot =>
      Directory(p.join(applicationSupportDirectory.path, 'plugins'));
  Directory get _installedRoot =>
      Directory(p.join(_pluginsRoot.path, 'installed'));
  Directory get _installingRoot =>
      Directory(p.join(_pluginsRoot.path, '.installing'));
  Directory get _backupRoot => Directory(p.join(_pluginsRoot.path, '.backup'));
  Directory get pluginDataRoot =>
      Directory(p.join(applicationSupportDirectory.path, 'plugin_data'));

  Future<List<InstalledPlugin>> getInstalledPlugins() => registry.listPlugins();

  Future<InstalledPlugin?> getPlugin(String id) => registry.getPlugin(id);

  Future<PreparedPluginInstall?> pickAndPrepareInstall() async {
    final source = await picker.pickPlugin();
    if (source == null) return null;
    return prepareInstall(source);
  }

  Future<PreparedPluginInstall> prepareInstall(
    PluginPackageSource source,
  ) async {
    if (!source.fileName.toLowerCase().endsWith('.ibuki')) {
      throw const PluginException(
        PluginErrorCategory.invalidExtension,
        '请选择 .ibuki 插件包。',
      );
    }

    await _ensureRoots();
    final operationDirectory = Directory(
      p.join(_installingRoot.path, _operationId()),
    );
    await operationDirectory.create(recursive: true);
    final packageFile = File(p.join(operationDirectory.path, 'plugin.ibuki'));

    try {
      final declaredLength = await source.length();
      if (declaredLength > limits.maxPackageBytes) {
        throw const PluginException(
          PluginErrorCategory.packageTooLarge,
          '插件包过大。',
        );
      }
      final packageSize = await _copyPackage(source, packageFile);
      await _verifyZipMagic(packageFile);
      final inspection = _inspectArchive(packageFile);
      _verifyMinimumVersion(inspection.manifest);

      final existing = await registry.getPlugin(inspection.manifest.id);
      if (existing != null &&
          existing.manifest.version == inspection.manifest.version) {
        throw PluginException(
          PluginErrorCategory.duplicateInstall,
          '已安装此版本的“${inspection.manifest.name}”。',
        );
      }

      return PreparedPluginInstall(
        manifest: inspection.manifest,
        sourceFileName: source.fileName,
        packagePath: packageFile.path,
        operationDirectory: operationDirectory.path,
        packageSize: packageSize,
        extractedSize: inspection.extractedSize,
        isUpdate: existing != null,
        existingPlugin: existing,
      );
    } catch (_) {
      await _deleteDirectory(operationDirectory);
      rethrow;
    }
  }

  Future<InstalledPlugin> installPrepared(
    PreparedPluginInstall prepared,
  ) async {
    final operationDirectory = Directory(prepared.operationDirectory);
    if (!await operationDirectory.exists()) {
      throw const PluginException(
        PluginErrorCategory.installFailed,
        '插件安装临时文件已失效，请重新选择。',
      );
    }

    final extractedDirectory = Directory(
      p.join(operationDirectory.path, 'extracted'),
    );
    final finalDirectory = Directory(
      p.join(_installedRoot.path, prepared.manifest.id),
    );
    final backupDirectory = Directory(
      p.join(_backupRoot.path, '${prepared.manifest.id}-${_operationId()}'),
    );
    var oldMovedToBackup = false;
    var newMovedToFinal = false;

    try {
      await extractedDirectory.create(recursive: true);
      final inspection = await _extractAndVerify(
        File(prepared.packagePath),
        extractedDirectory,
      );
      if (inspection.manifest.id != prepared.manifest.id ||
          inspection.manifest.version != prepared.manifest.version) {
        throw const PluginException(
          PluginErrorCategory.invalidManifest,
          '插件包在安装期间发生变化。',
        );
      }

      if (await finalDirectory.exists()) {
        await backupDirectory.parent.create(recursive: true);
        await finalDirectory.rename(backupDirectory.path);
        oldMovedToBackup = true;
      }
      await extractedDirectory.rename(finalDirectory.path);
      newMovedToFinal = true;

      final now = _now().toUtc();
      final dataDirectory = Directory(
        p.join(pluginDataRoot.path, prepared.manifest.id),
      );
      final installed = InstalledPlugin(
        manifest: inspection.manifest,
        installedPath: finalDirectory.path,
        dataPath: dataDirectory.path,
        enabled:
            prepared.existingPlugin?.enabled ??
            !inspection.manifest.permissions.contains('core.service.override'),
        installedAt: prepared.existingPlugin?.installedAt ?? now,
        updatedAt: now,
        packageSize: prepared.packageSize,
        extractedSize: inspection.extractedSize,
      );
      await registry.upsertPlugin(installed);
      await dataDirectory.create(recursive: true);
      await lifecycle.onInstall(installed);

      if (installed.enabled) {
        await _loadRuntime(installed);
        await lifecycle.onEnable(installed);
        await hookBus.publish(IbukiHook.onPluginEnabled, {
          'pluginId': installed.id,
        });
      }
      if (oldMovedToBackup) await _deleteDirectory(backupDirectory);
      await _deleteDirectory(operationDirectory);
      return installed;
    } catch (error) {
      try {
        await runtime.unload(
          prepared.existingPlugin ??
              InstalledPlugin(
                manifest: prepared.manifest,
                installedPath: finalDirectory.path,
                dataPath: p.join(pluginDataRoot.path, prepared.manifest.id),
                enabled: false,
                installedAt: _now().toUtc(),
                updatedAt: _now().toUtc(),
              ),
        );
      } catch (_) {
        // Runtime cleanup is best-effort; package rollback still continues.
      }
      if (newMovedToFinal) await _deleteDirectory(finalDirectory);
      if (oldMovedToBackup && await backupDirectory.exists()) {
        await backupDirectory.rename(finalDirectory.path);
      }
      final existing = prepared.existingPlugin;
      if (existing != null) {
        try {
          await registry.upsertPlugin(existing);
          if (existing.enabled) await _loadRuntime(existing);
        } catch (_) {
          // The original installation files are restored even if registry repair fails.
        }
      } else {
        try {
          await registry.deletePlugin(prepared.manifest.id);
        } catch (_) {
          // A failed install must not keep a usable registry entry.
        }
      }
      await _deleteDirectory(operationDirectory);
      if (error is PluginException) rethrow;
      throw PluginException(
        prepared.isUpdate
            ? PluginErrorCategory.updateFailed
            : PluginErrorCategory.installFailed,
        prepared.isUpdate ? '插件更新失败，旧版本仍可使用。' : '插件安装失败。',
        detail: error.runtimeType.toString(),
      );
    }
  }

  Future<void> discardPrepared(PreparedPluginInstall prepared) async {
    await _deleteDirectory(Directory(prepared.operationDirectory));
  }

  Future<void> enablePlugin(String id) => _setEnabled(id, true);

  Future<void> disablePlugin(String id) => _setEnabled(id, false);

  Future<void> _setEnabled(String id, bool enabled) async {
    final plugin = await registry.getPlugin(id);
    if (plugin == null) {
      throw PluginException(PluginErrorCategory.brokenPlugin, '找不到插件：$id。');
    }
    final updated = plugin.copyWith(
      enabled: enabled,
      updatedAt: _now().toUtc(),
    );
    if (enabled) {
      await _loadRuntime(updated);
      await registry.upsertPlugin(updated);
      await lifecycle.onEnable(updated);
      await hookBus.publish(IbukiHook.onPluginEnabled, {'pluginId': id});
    } else {
      await hookBus.publish(IbukiHook.onPluginDisabled, {'pluginId': id});
      try {
        await runtime.unload(updated);
      } catch (_) {
        // Disable must still remove registrations and persist the disabled state.
      } finally {
        hookBus.removePlugin(id);
      }
      await registry.upsertPlugin(updated);
      await lifecycle.onDisable(updated);
    }
  }

  Future<void> uninstallPlugin(
    String id, {
    PluginDataPolicy dataPolicy = PluginDataPolicy.keep,
  }) async {
    final plugin = await registry.getPlugin(id);
    if (plugin == null) return;
    await hookBus.publish(IbukiHook.onPluginDisabled, {'pluginId': id});
    try {
      await runtime.unload(plugin);
    } catch (_) {
      // Uninstall continues so a broken runtime cannot trap the plugin in Core.
    } finally {
      hookBus.removePlugin(id);
    }
    await lifecycle.onUninstall(plugin);
    await _deleteDirectory(Directory(plugin.installedPath));
    await registry.deletePlugin(id);
    if (dataPolicy == PluginDataPolicy.delete) {
      await _deleteDirectory(Directory(plugin.dataPath));
      await storageRepository?.clearPlugin(id);
    }
  }

  Future<List<InstalledPlugin>> loadEnabledPlugins() async {
    await _ensureRoots();
    await _cleanupInstallingDirectory();
    final plugins = await registry.listPlugins();
    final checked = <InstalledPlugin>[];
    for (final plugin in plugins) {
      var current = plugin;
      try {
        final directory = Directory(plugin.installedPath);
        final expectedPath = p.normalize(
          p.absolute(p.join(_installedRoot.path, plugin.id)),
        );
        if (p.normalize(p.absolute(directory.path)) != expectedPath) {
          throw const PluginException(
            PluginErrorCategory.brokenPlugin,
            '插件 Registry 中的安装路径无效。',
          );
        }
        final manifestFile = File(p.join(directory.path, 'manifest.json'));
        if (!await directory.exists() || !await manifestFile.exists()) {
          throw const PluginException(
            PluginErrorCategory.brokenPlugin,
            '插件安装文件缺失。',
          );
        }
        final manifest = IbukiPluginManifest.parse(
          await manifestFile.readAsString(),
        );
        if (manifest.id != plugin.id) {
          throw const PluginException(
            PluginErrorCategory.brokenPlugin,
            '插件 Manifest 与 Registry 不一致。',
          );
        }
        current = plugin.copyWith(
          manifest: manifest,
          status: InstalledPluginStatus.installed,
          clearErrorCategory: true,
        );
        if (current.dataPath.isEmpty) {
          current = current.copyWith(
            dataPath: p.join(pluginDataRoot.path, current.id),
          );
        }
        await Directory(current.dataPath).create(recursive: true);
        if (current.enabled) await _loadRuntime(current);
        if (current.enabled) await lifecycle.onAppStart(current);
      } catch (error) {
        current = plugin.copyWith(
          status: InstalledPluginStatus.broken,
          errorCategory: error is PluginException
              ? error.category.name
              : error.runtimeType.toString(),
        );
      }
      try {
        await registry.upsertPlugin(current);
      } catch (_) {
        // A corrupt registry row must not prevent other plugins or Core startup.
      }
      checked.add(current);
    }
    return List.unmodifiable(checked);
  }

  Future<void> _loadRuntime(InstalledPlugin plugin) async {
    if (!runtime.supports(plugin.manifest)) {
      throw const PluginException(
        PluginErrorCategory.unsupportedRuntime,
        '此插件需要当前版本尚未支持的运行环境。',
      );
    }
    await runtime.load(plugin);
  }

  Future<int> _copyPackage(PluginPackageSource source, File destination) async {
    final sink = destination.openWrite();
    var written = 0;
    try {
      await for (final chunk in source.openRead()) {
        written += chunk.length;
        if (written > limits.maxPackageBytes) {
          throw const PluginException(
            PluginErrorCategory.packageTooLarge,
            '插件包过大。',
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
      return written;
    } finally {
      await sink.close();
    }
  }

  Future<void> _verifyZipMagic(File file) async {
    if (await file.length() < 22) {
      throw const PluginException(
        PluginErrorCategory.invalidArchive,
        '插件包已损坏或不完整。',
      );
    }
    final handle = await file.open();
    try {
      final bytes = await handle.read(4);
      final valid =
          bytes.length == 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4b &&
          ((bytes[2] == 0x03 && bytes[3] == 0x04) ||
              (bytes[2] == 0x05 && bytes[3] == 0x06) ||
              (bytes[2] == 0x07 && bytes[3] == 0x08));
      if (!valid) {
        throw const PluginException(
          PluginErrorCategory.invalidArchive,
          '所选文件不是有效的 ZIP 插件包。',
        );
      }
    } finally {
      await handle.close();
    }
  }

  _ArchiveInspection _inspectArchive(File file) {
    InputFileStream? input;
    try {
      input = InputFileStream(file.path);
      final archive = ZipDecoder().decodeStream(input, verify: true);
      return _validateArchive(archive);
    } on PluginException {
      rethrow;
    } catch (error) {
      throw PluginException(
        PluginErrorCategory.invalidArchive,
        '插件包已损坏或不是有效 ZIP。',
        detail: error.runtimeType.toString(),
      );
    } finally {
      input?.closeSync();
    }
  }

  Future<_ArchiveInspection> _extractAndVerify(
    File file,
    Directory destination,
  ) async {
    InputFileStream? input;
    try {
      input = InputFileStream(file.path);
      final archive = ZipDecoder().decodeStream(input, verify: true);
      final inspection = _validateArchive(archive);
      final root = p.normalize(p.absolute(destination.path));
      for (final entry in archive) {
        final relative = _safeEntryPath(entry.name);
        final outputPath = p.normalize(p.absolute(p.join(root, relative)));
        if (!p.isWithin(root, outputPath)) {
          throw const PluginException(
            PluginErrorCategory.unsafeArchivePath,
            '插件包包含不安全的文件路径。',
          );
        }
        if (entry.isDirectory) {
          await Directory(outputPath).create(recursive: true);
          continue;
        }
        await Directory(p.dirname(outputPath)).create(recursive: true);
        final output = OutputFileStream(outputPath);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
      }
      final installedManifest = IbukiPluginManifest.parse(
        await File(p.join(root, 'manifest.json')).readAsString(),
      );
      return _ArchiveInspection(installedManifest, inspection.extractedSize);
    } on PluginException {
      rethrow;
    } catch (error) {
      throw PluginException(
        PluginErrorCategory.invalidArchive,
        '插件包解压失败。',
        detail: error.runtimeType.toString(),
      );
    } finally {
      input?.closeSync();
    }
  }

  _ArchiveInspection _validateArchive(Archive archive) {
    if (archive.length > limits.maxEntries) {
      throw const PluginException(
        PluginErrorCategory.packageTooLarge,
        '插件包包含的文件数量过多。',
      );
    }
    final paths = <String>{};
    ArchiveFile? manifestEntry;
    var totalSize = 0;
    for (final entry in archive) {
      final safePath = _safeEntryPath(entry.name);
      final canonical = safePath.toLowerCase();
      if (!paths.add(canonical)) {
        throw const PluginException(
          PluginErrorCategory.invalidArchive,
          '插件包包含重复文件路径。',
        );
      }
      if (entry.isSymbolicLink) {
        throw const PluginException(
          PluginErrorCategory.unsafeArchivePath,
          '插件包不能包含符号链接。',
        );
      }
      if (entry.size > limits.maxSingleFileBytes) {
        throw const PluginException(
          PluginErrorCategory.packageTooLarge,
          '插件包中的单个文件过大。',
        );
      }
      if (entry.isFile) totalSize += entry.size;
      if (totalSize > limits.maxExtractedBytes) {
        throw const PluginException(
          PluginErrorCategory.packageTooLarge,
          '插件包解压后的总体积过大。',
        );
      }
      if (safePath == 'manifest.json' && entry.isFile) {
        manifestEntry = entry;
      }
    }
    if (manifestEntry == null) {
      throw const PluginException(
        PluginErrorCategory.missingManifest,
        '插件包根目录缺少 manifest.json。',
      );
    }
    if (manifestEntry.size > limits.maxManifestBytes) {
      throw const PluginException(
        PluginErrorCategory.packageTooLarge,
        '插件 Manifest 过大。',
      );
    }
    final bytes = manifestEntry.readBytes();
    if (bytes == null) {
      throw const PluginException(
        PluginErrorCategory.malformedManifest,
        '无法读取 manifest.json。',
      );
    }
    final manifest = IbukiPluginManifest.parse(utf8.decode(bytes));
    return _ArchiveInspection(manifest, totalSize);
  }

  String _safeEntryPath(String rawPath) {
    if (rawPath.isEmpty || rawPath.codeUnits.any((code) => code == 0)) {
      throw const PluginException(
        PluginErrorCategory.unsafeArchivePath,
        '插件包包含无效文件路径。',
      );
    }
    final normalized = rawPath.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) {
      throw const PluginException(
        PluginErrorCategory.unsafeArchivePath,
        '插件包包含绝对文件路径。',
      );
    }
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final parts = trimmed.split('/');
    if (parts.isEmpty ||
        parts.any(
          (part) =>
              part.isEmpty || part == '.' || part == '..' || part.contains(':'),
        )) {
      throw const PluginException(
        PluginErrorCategory.unsafeArchivePath,
        '插件包包含路径穿越或不安全路径。',
      );
    }
    return p.joinAll(parts);
  }

  void _verifyMinimumVersion(IbukiPluginManifest manifest) {
    final minimum = manifest.minIbukiVersion;
    if (minimum == null) return;
    if (_compareVersions(applicationVersion, minimum) < 0) {
      throw PluginException(
        PluginErrorCategory.incompatibleAppVersion,
        '此插件需要伊吹之家 $minimum 或更高版本。',
      );
    }
  }

  Future<void> _ensureRoots() async {
    await Future.wait([
      _installedRoot.create(recursive: true),
      _installingRoot.create(recursive: true),
      _backupRoot.create(recursive: true),
      pluginDataRoot.create(recursive: true),
    ]);
  }

  Future<void> _cleanupInstallingDirectory() async {
    await for (final entity in _installingRoot.list(followLinks: false)) {
      if (entity is Directory) {
        await _deleteDirectory(entity);
      } else if (entity is File) {
        await entity.delete();
      }
    }
  }

  Future<void> _deleteDirectory(Directory directory) async {
    final root = p.normalize(p.absolute(applicationSupportDirectory.path));
    final target = p.normalize(p.absolute(directory.path));
    if (!p.isWithin(root, target)) {
      throw StateError('Refusing to delete outside application support.');
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  static int _compareVersions(String left, String right) {
    List<int> parts(String value) {
      final clean = value.split('+').first.split('-').first;
      return clean.split('.').map((item) => int.tryParse(item) ?? 0).toList();
    }

    final a = parts(left);
    final b = parts(right);
    final length = max(a.length, b.length);
    for (var index = 0; index < length; index++) {
      final av = index < a.length ? a[index] : 0;
      final bv = index < b.length ? b[index] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static String _defaultOperationId() {
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return '${DateTime.now().microsecondsSinceEpoch}-$random';
  }
}

class _ArchiveInspection {
  const _ArchiveInspection(this.manifest, this.extractedSize);

  final IbukiPluginManifest manifest;
  final int extractedSize;
}
