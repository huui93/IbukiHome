import 'dart:io';

import '../../domain/backup/backup_models.dart';

abstract class BackupSnapshotStore {
  Future<BackupSnapshot> buildSnapshot();
  Future<bool> hasUserData();
  Future<void> restore(
    BackupSnapshot snapshot, {
    required BackupRestoreMode mode,
    required Map<String, String> restoredAssets,
    BackupCancellationToken? cancellation,
  });
}

abstract class BackupAssetStore {
  Future<Directory> createStagingDirectory(String operationId);
  Future<Map<String, String>> promoteRestoredAssets(
    Directory staging,
    List<BackupAssetManifest> assets, {
    BackupCancellationToken? cancellation,
  });
  Future<void> discard(Directory staging);
}

abstract class BackupOperationGuard {
  Future<bool> get hasActiveAiOperation;
}

class NoActiveBackupOperationGuard implements BackupOperationGuard {
  const NoActiveBackupOperationGuard();
  @override
  Future<bool> get hasActiveAiOperation async => false;
}
