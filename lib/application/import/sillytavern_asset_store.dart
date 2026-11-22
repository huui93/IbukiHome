import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

abstract class SillyTavernImportAssetStore {
  Future<String> saveCharacterImage(String payloadId, Uint8List bytes);
  Future<void> deleteAsset(String path);
}

class FileSillyTavernImportAssetStore implements SillyTavernImportAssetStore {
  FileSillyTavernImportAssetStore(this.applicationSupportDirectory);

  final Directory applicationSupportDirectory;

  String get _root => p.normalize(
    p.absolute(
      p.join(applicationSupportDirectory.path, 'imports', 'sillytavern'),
    ),
  );

  Future<void> _validatePath(String path) async {
    if (!p.isWithin(_root, p.normalize(p.absolute(path)))) {
      throw const FileSystemException(
        'Import asset path is outside private storage.',
      );
    }
    var current = p.normalize(p.absolute(path));
    while (p.isWithin(_root, current) || current == _root) {
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FileSystemException(
          'Linked import asset paths are not allowed.',
        );
      }
      current = p.dirname(current);
    }
  }

  @override
  Future<String> saveCharacterImage(String payloadId, Uint8List bytes) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(payloadId)) {
      throw const FileSystemException('Invalid import asset identity.');
    }
    final root = Directory(_root);
    final temp = Directory(p.join(root.path, '.installing', payloadId));
    final target = Directory(p.join(root.path, 'assets', payloadId));
    await _validatePath(temp.path);
    await _validatePath(target.path);
    if (await target.exists() || await temp.exists()) {
      throw const FileSystemException('Import asset already exists.');
    }
    await temp.create(recursive: true);
    try {
      final staged = File(p.join(temp.path, 'avatar.png'));
      await staged.writeAsBytes(bytes, flush: true);
      await target.parent.create(recursive: true);
      await temp.rename(target.path);
      return p.join(target.path, 'avatar.png');
    } catch (_) {
      if (await temp.exists()) await temp.delete(recursive: true);
      rethrow;
    }
  }

  @override
  Future<void> deleteAsset(String path) async {
    await _validatePath(path);
    if (!p.isWithin(p.join(_root, 'assets'), p.normalize(p.absolute(path))) ||
        p.basename(path) != 'avatar.png') {
      throw const FileSystemException('Invalid import asset path.');
    }
    final file = File(path);
    if (await file.exists()) await file.delete();
    final parent = file.parent;
    if (await parent.exists() && await parent.list().isEmpty) {
      await parent.delete();
    }
  }
}

class InMemorySillyTavernImportAssetStore
    implements SillyTavernImportAssetStore {
  final Map<String, Uint8List> assets = {};

  @override
  Future<String> saveCharacterImage(String payloadId, Uint8List bytes) async {
    final path = 'memory://sillytavern/$payloadId/avatar.png';
    assets[path] = Uint8List.fromList(bytes);
    return path;
  }

  @override
  Future<void> deleteAsset(String path) async {
    assets.remove(path);
  }
}
