import 'dart:io';

import 'package:file_picker/file_picker.dart';

abstract class SillyTavernImportSource {
  String get fileName;
  Future<int> length();
  Stream<List<int>> openRead();
}

class FileSillyTavernImportSource implements SillyTavernImportSource {
  FileSillyTavernImportSource(this.file, {String? fileName})
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

abstract class SillyTavernImportPicker {
  Future<SillyTavernImportSource?> pick();
}

class SafSillyTavernImportPicker implements SillyTavernImportPicker {
  const SafSillyTavernImportPicker();

  @override
  Future<SillyTavernImportSource?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'json'],
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return _PlatformImportSource(result.files.single);
  }
}

class _PlatformImportSource implements SillyTavernImportSource {
  const _PlatformImportSource(this.file);

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
    if (bytes != null) return Stream.value(bytes);
    throw StateError('所选文件没有可读取内容。');
  }
}
