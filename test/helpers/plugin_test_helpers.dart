import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:ibukihome/application/plugins/plugin_manager.dart';
import 'package:ibukihome/application/plugins/plugin_package_picker.dart';
import 'package:ibukihome/data/memory/in_memory_plugin_registry.dart';

Map<String, Object?> pluginManifest({
  String id = 'dev.ibuki.test',
  String name = 'Test Plugin',
  String version = '1.0.0',
  int manifestVersion = 1,
  String? minIbukiVersion = '1.0.0',
  List<String> permissions = const [],
  List<String> capabilities = const ['demo'],
  Map<String, Object?> metadata = const {},
}) {
  final result = <String, Object?>{
    'manifestVersion': manifestVersion,
    'id': id,
    'name': name,
    'version': version,
    'author': 'IbukiHome',
    'description': 'Test plugin',
    'entry': null,
    'permissions': permissions,
    'capabilities': capabilities,
    'metadata': metadata,
  };
  if (minIbukiVersion != null) {
    result['minIbukiVersion'] = minIbukiVersion;
  }
  return result;
}

Future<File> writePluginPackage(
  Directory directory, {
  Map<String, Object?>? manifest,
  bool includeManifest = true,
  String? rawManifest,
  Map<String, String> files = const {'assets/readme.txt': 'hello'},
  String fileName = 'plugin.ibuki',
}) async {
  final archive = Archive();
  if (includeManifest) {
    archive.addFile(
      ArchiveFile.string(
        'manifest.json',
        rawManifest ?? jsonEncode(manifest ?? pluginManifest()),
      ),
    );
  }
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(ZipEncoder().encodeBytes(archive), flush: true);
  return file;
}

class FakePluginPicker implements PluginPackagePicker {
  FakePluginPicker([this.source]);

  PluginPackageSource? source;
  int calls = 0;

  @override
  Future<PluginPackageSource?> pickPlugin() async {
    calls += 1;
    return source;
  }
}

class PluginTestContext {
  PluginTestContext({
    required this.directory,
    required this.registry,
    required this.picker,
    required this.manager,
  });

  final Directory directory;
  final InMemoryPluginRegistry registry;
  final FakePluginPicker picker;
  final PluginManager manager;
}

Future<PluginTestContext> createPluginTestContext({
  PluginInstallLimits limits = const PluginInstallLimits(),
  PluginPackageSource? source,
}) async {
  final directory = await Directory.systemTemp.createTemp('ibuki_plugin_test_');
  final registry = InMemoryPluginRegistry();
  final picker = FakePluginPicker(source);
  var operation = 0;
  final manager = PluginManager(
    registry: registry,
    applicationSupportDirectory: directory,
    picker: picker,
    limits: limits,
    operationId: () => 'operation-${operation++}',
    now: () => DateTime.utc(2026, 8, 26, 12),
  );
  return PluginTestContext(
    directory: directory,
    registry: registry,
    picker: picker,
    manager: manager,
  );
}
