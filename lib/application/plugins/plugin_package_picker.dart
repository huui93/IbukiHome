import 'dart:io';

import 'package:file_picker/file_picker.dart';

abstract class PluginPackageSource {
  String get fileName;

  Future<int> length();

  Stream<List<int>> openRead();
}

class FilePluginPackageSource implements PluginPackageSource {
  FilePluginPackageSource(this.file, {String? fileName})
    : _fileName = fileName ?? file.uri.pathSegments.last;

  final File file;
  final String _fileName;

  @override
  String get fileName => _fileName;

  @override
  Future<int> length() => file.length();

  @override
  Stream<List<int>> openRead() => file.openRead();
}

abstract class PluginPackagePicker {
  Future<PluginPackageSource?> pickPlugin();
}

class SafPluginPackagePicker implements PluginPackagePicker {
  const SafPluginPackagePicker();

  @override
  Future<PluginPackageSource?> pickPlugin() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['ibuki'],
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return _PlatformFilePluginPackageSource(result.files.single);
  }
}

class _PlatformFilePluginPackageSource implements PluginPackageSource {
  const _PlatformFilePluginPackageSource(this.file);

  final PlatformFile file;

  @override
  String get fileName => file.name;

  @override
  Future<int> length() async => file.size;

  @override
  Stream<List<int>> openRead() {
    final stream = file.readStream;
    if (stream != null) return stream;
    final path = file.path;
    if (path != null) return File(path).openRead();
    final bytes = file.bytes;
    if (bytes != null) return Stream<List<int>>.value(bytes);
    throw StateError('Selected plugin has no readable content.');
  }
}
