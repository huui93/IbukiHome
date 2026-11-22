import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/backup/backup_archive_codec.dart';
import 'package:ibukihome/application/backup/backup_contracts.dart';
import 'package:ibukihome/application/backup/backup_service.dart';
import 'package:ibukihome/domain/backup/backup_models.dart';

void main() {
  test('active AI operation blocks snapshot creation', () async {
    final root = await Directory.systemTemp.createTemp('backup-active-');
    final store = _FakeStore();
    final service = BackupService(
      store: store,
      assets: _FakeAssets(root),
      codec: BackupArchiveCodec(applicationSupportDirectory: root),
      operationGuard: const _Guard(true),
    );
    try {
      await expectLater(
        service.prepareBackup(),
        throwsA(
          isA<BackupException>().having(
            (error) => error.code,
            'code',
            'active_ai_operation',
          ),
        ),
      );
      expect(store.snapshotCalls, 0);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('database failure removes promoted assets and staging', () async {
    final root = await Directory.systemTemp.createTemp('backup-rollback-');
    final staging = Directory('${root.path}/staging')..createSync();
    final promoted = File('${root.path}/promoted/op/asset/avatar.png')
      ..createSync(recursive: true)
      ..writeAsStringSync('asset');
    final assets = _FakeAssets(root, promotedPath: promoted.path);
    final service = BackupService(
      store: _FakeStore(failRestore: true),
      assets: assets,
      codec: BackupArchiveCodec(applicationSupportDirectory: root),
      operationGuard: const _Guard(false),
    );
    final manifest = IbukiBackupManifest(
      createdAt: DateTime.utc(2026),
      appVersion: 'test',
      schemaVersion: 12,
      collections: const [],
      assets: const [
        BackupAssetManifest(
          id: 'asset',
          archivePath: 'assets/asset/avatar.png',
          fileName: 'avatar.png',
          bytes: 5,
          sha256: 'digest',
        ),
      ],
      security: const {},
    );
    final decoded = DecodedBackupArchive(
      preview: BackupPreview(manifest: manifest, checksum: 'digest'),
      snapshot: const BackupSnapshot(collections: {}),
      assetDirectory: staging,
    );
    try {
      await expectLater(
        service.restore((
          archive: decoded,
          staging: staging,
        ), mode: BackupRestoreMode.merge),
        throwsStateError,
      );
      expect(await Directory('${root.path}/promoted/op').exists(), isFalse);
      expect(await staging.exists(), isFalse);
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test(
    'cancelled restore does not write the database and clears staging',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'backup-cancel-restore-',
      );
      final staging = Directory('${root.path}/staging')
        ..createSync(recursive: true);
      final store = _FakeStore();
      final service = BackupService(
        store: store,
        assets: _FakeAssets(root),
        codec: BackupArchiveCodec(applicationSupportDirectory: root),
        operationGuard: const _Guard(false),
      );
      final inspection = (
        archive: DecodedBackupArchive(
          preview: BackupPreview(
            manifest: IbukiBackupManifest(
              createdAt: DateTime.utc(2026),
              appVersion: 'test',
              schemaVersion: 12,
              collections: const [],
              assets: const [],
              security: const {},
            ),
            checksum: '',
          ),
          snapshot: const BackupSnapshot(collections: {}),
          assetDirectory: staging,
        ),
        staging: staging,
      );
      final cancellation = BackupCancellationToken()..cancel();
      try {
        await expectLater(
          service.restore(
            inspection,
            mode: BackupRestoreMode.merge,
            cancellation: cancellation,
          ),
          throwsA(
            isA<BackupException>().having(
              (error) => error.code,
              'code',
              'cancelled',
            ),
          ),
        );
        expect(store.restoreCalls, 0);
        expect(await staging.exists(), isFalse);
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );
}

class _Guard implements BackupOperationGuard {
  const _Guard(this.value);
  final bool value;
  @override
  Future<bool> get hasActiveAiOperation async => value;
}

class _FakeStore implements BackupSnapshotStore {
  _FakeStore({this.failRestore = false});
  final bool failRestore;
  int snapshotCalls = 0;
  int restoreCalls = 0;

  @override
  Future<BackupSnapshot> buildSnapshot() async {
    snapshotCalls += 1;
    return const BackupSnapshot(collections: {});
  }

  @override
  Future<bool> hasUserData() async => false;

  @override
  Future<void> restore(
    BackupSnapshot snapshot, {
    required BackupRestoreMode mode,
    required Map<String, String> restoredAssets,
    BackupCancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    restoreCalls += 1;
    if (failRestore) throw StateError('database failure');
  }
}

class _FakeAssets implements BackupAssetStore {
  _FakeAssets(this.root, {this.promotedPath});
  final Directory root;
  final String? promotedPath;

  @override
  Future<Directory> createStagingDirectory(String operationId) async {
    return Directory('${root.path}/$operationId')..createSync(recursive: true);
  }

  @override
  Future<void> discard(Directory staging) async {
    if (await staging.exists()) await staging.delete(recursive: true);
  }

  @override
  Future<Map<String, String>> promoteRestoredAssets(
    Directory staging,
    List<BackupAssetManifest> assets, {
    BackupCancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    return promotedPath == null ? const {} : {'asset': promotedPath!};
  }
}
