import 'dart:io';

import '../../domain/backup/backup_models.dart';
import '../common/entity_id_generator.dart';
import 'backup_archive_codec.dart';
import 'backup_contracts.dart';

class BackupService {
  BackupService({
    required this.store,
    required this.assets,
    required this.codec,
    required this.operationGuard,
    this.appVersion = '1.0.0',
    this.schemaVersion = 15,
  });

  final BackupSnapshotStore store;
  final BackupAssetStore assets;
  final BackupArchiveCodec codec;
  final BackupOperationGuard operationGuard;
  final String appVersion;
  final int schemaVersion;

  Future<PreparedBackup> prepareBackup() async {
    if (await operationGuard.hasActiveAiOperation) {
      throw const BackupException(
        'active_ai_operation',
        '请先停止正在进行的生成，再创建完整备份。',
      );
    }
    final snapshot = await store.buildSnapshot();
    final preview = await codec.preview(
      snapshot,
      appVersion: appVersion,
      schemaVersion: schemaVersion,
    );
    return PreparedBackup(snapshot: snapshot, preview: preview);
  }

  Future<BackupPreview> writePreparedBackup(
    PreparedBackup prepared,
    File destination, {
    void Function(BackupProgress progress)? onProgress,
    BackupCancellationToken? cancellation,
  }) async {
    if (await operationGuard.hasActiveAiOperation) {
      throw const BackupException(
        'active_ai_operation',
        '当前出现了新的生成任务，请先停止后重试备份。',
      );
    }
    return codec.write(
      snapshot: prepared.snapshot,
      destination: destination,
      appVersion: appVersion,
      schemaVersion: schemaVersion,
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }

  Future<BackupPreview> createBackup(
    File destination, {
    void Function(BackupProgress progress)? onProgress,
    BackupCancellationToken? cancellation,
  }) async {
    final prepared = await prepareBackup();
    return writePreparedBackup(
      prepared,
      destination,
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }

  Future<({DecodedBackupArchive archive, Directory staging})> inspect(
    File source, {
    void Function(BackupProgress progress)? onProgress,
    BackupCancellationToken? cancellation,
  }) async {
    final staging = await assets.createStagingDirectory(
      EntityIdGenerator().nextId('restore'),
    );
    try {
      final archive = await codec.read(
        source: source,
        staging: staging,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      return (archive: archive, staging: staging);
    } catch (_) {
      await assets.discard(staging);
      rethrow;
    }
  }

  Future<void> discardInspection(
    ({DecodedBackupArchive archive, Directory staging}) inspection,
  ) {
    return assets.discard(inspection.staging);
  }

  Future<void> restore(
    ({DecodedBackupArchive archive, Directory staging}) inspection, {
    required BackupRestoreMode mode,
    void Function(BackupProgress progress)? onProgress,
    BackupCancellationToken? cancellation,
  }) async {
    if (await operationGuard.hasActiveAiOperation) {
      throw const BackupException('active_ai_operation', '请先停止正在进行的生成，再恢复备份。');
    }
    Map<String, String> promoted = const {};
    try {
      cancellation?.throwIfCancelled();
      onProgress?.call(const BackupProgress('正在恢复资源', 0, 1));
      promoted = await assets.promoteRestoredAssets(
        inspection.staging,
        inspection.archive.preview.manifest.assets,
        cancellation: cancellation,
      );
      cancellation?.throwIfCancelled();
      await store.restore(
        inspection.archive.snapshot,
        mode: mode,
        restoredAssets: promoted,
        cancellation: cancellation,
      );
      onProgress?.call(const BackupProgress('恢复完成', 1, 1));
    } catch (_) {
      for (final path in promoted.values) {
        final root = File(path).parent.parent;
        if (await root.exists()) await root.delete(recursive: true);
      }
      rethrow;
    } finally {
      await assets.discard(inspection.staging);
    }
  }
}
