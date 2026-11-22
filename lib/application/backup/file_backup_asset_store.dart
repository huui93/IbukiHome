import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/backup/backup_models.dart';
import 'backup_contracts.dart';

class FileBackupAssetStore implements BackupAssetStore {
  FileBackupAssetStore(this.applicationSupportDirectory);
  final Directory applicationSupportDirectory;

  @override
  Future<Directory> createStagingDirectory(String operationId) async {
    final directory = Directory(
      p.join(
        applicationSupportDirectory.path,
        'backup',
        'restore-staging',
        operationId,
      ),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<Map<String, String>> promoteRestoredAssets(
    Directory staging,
    List<BackupAssetManifest> assets, {
    BackupCancellationToken? cancellation,
  }) async {
    if (assets.isEmpty) return const {};
    final operationId = p.basename(staging.path);
    final destination = Directory(
      p.join(applicationSupportDirectory.path, 'restored-assets', operationId),
    );
    await destination.create(recursive: true);
    final result = <String, String>{};
    try {
      for (final asset in assets) {
        cancellation?.throwIfCancelled();
        final source = File(
          p.joinAll([staging.path, ...p.posix.split(asset.archivePath)]),
        );
        final target = File(p.join(destination.path, asset.id, asset.fileName));
        await target.parent.create(recursive: true);
        await source.copy(target.path);
        result[asset.id] = target.path;
      }
      return result;
    } catch (_) {
      if (await destination.exists()) {
        await destination.delete(recursive: true);
      }
      rethrow;
    }
  }

  @override
  Future<void> discard(Directory staging) async {
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
