import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../domain/backup/backup_models.dart';
import '../common/entity_id_generator.dart';

abstract class BackupArchivePicker {
  Future<File?> pickForRestore(Directory temporaryDirectory);
  Future<bool> save(File source, String suggestedName);
}

class SafBackupArchivePicker implements BackupArchivePicker {
  const SafBackupArchivePicker();

  static const _channel = MethodChannel('com.ibuki.ibukihome/archive');

  @override
  Future<File?> pickForRestore(Directory temporaryDirectory) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ibukibackup'],
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final selected = result.files.single;
    await temporaryDirectory.create(recursive: true);
    final target = File(
      p.join(
        temporaryDirectory.path,
        '${EntityIdGenerator().nextId('picked')}.ibukibackup',
      ),
    );
    final stream = selected.readStream;
    if (stream != null) {
      final sink = target.openWrite();
      try {
        await sink.addStream(stream);
      } finally {
        await sink.close();
      }
      return target;
    }
    if (selected.path != null) {
      await File(selected.path!).copy(target.path);
      return target;
    }
    throw const BackupException('picker_read_failed', '无法读取所选备份。');
  }

  @override
  Future<bool> save(File source, String suggestedName) async {
    if (Platform.isAndroid) {
      final saved = await _channel.invokeMethod<bool>('saveArchive', {
        'sourcePath': source.path,
        'fileName': suggestedName,
      });
      return saved ?? false;
    }
    final target = await FilePicker.platform.saveFile(
      dialogTitle: '保存伊吹之家完整备份',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: const ['ibukibackup'],
    );
    if (target == null) return false;
    await source.copy(target);
    return true;
  }
}
