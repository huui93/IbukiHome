import '../projects/novel_output_limits_providers.dart';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/invalidatable_read_cache.dart';
import '../ai/ai_runtime_providers.dart';
import '../import/sillytavern_import_providers.dart';
import '../providers/repository_providers.dart';
import '../projects/novel_prompt_presets.dart';
import '../chat/chat_controls_providers.dart';
import '../world_roleplay/world_roleplay_providers.dart';
import 'backup_archive_codec.dart';
import 'backup_archive_picker.dart';
import 'backup_contracts.dart';
import 'backup_service.dart';

final backupSnapshotStoreProvider = Provider<BackupSnapshotStore>((ref) {
  throw StateError('BackupSnapshotStore must be configured by bootstrap.');
});

final backupAssetStoreProvider = Provider<BackupAssetStore>((ref) {
  throw StateError('BackupAssetStore must be configured by bootstrap.');
});

final backupArchiveCodecProvider = Provider<BackupArchiveCodec>((ref) {
  throw StateError('BackupArchiveCodec must be configured by bootstrap.');
});

final backupWorkingDirectoryProvider = Provider<Directory>((ref) {
  throw StateError('Backup working directory must be configured by bootstrap.');
});

final backupArchivePickerProvider = Provider<BackupArchivePicker>((ref) {
  return const SafBackupArchivePicker();
});

final backupOperationGuardProvider = Provider<BackupOperationGuard>((ref) {
  return AppBackupOperationGuard(ref);
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    store: ref.watch(backupSnapshotStoreProvider),
    assets: ref.watch(backupAssetStoreProvider),
    codec: ref.watch(backupArchiveCodecProvider),
    operationGuard: ref.watch(backupOperationGuardProvider),
  );
});

void notifyFullRestoreCompleted(WidgetRef ref) {
  for (final repository in <Object>[
    ref.read(projectRepositoryProvider),
    ref.read(outlineRepositoryProvider),
    ref.read(segmentRepositoryProvider),
    ref.read(characterRepositoryProvider),
    ref.read(worldRepositoryProvider),
    ref.read(chatRepositoryProvider),
    ref.read(chatPersonaRepositoryProvider),
    ref.read(novelMemoryRepositoryProvider),
    ref.read(readerRepositoryProvider),
    ref.read(chatMemoryRepositoryProvider),
  ]) {
    if (repository case InvalidatableReadCache cache) cache.invalidateAll();
  }
  ref.invalidate(projectListProvider);
  ref.invalidate(novelPromptPresetsProvider);
  ref.invalidate(novelOutputLimitsProvider);
  ref.invalidate(chatReasoningLevelProvider);
  ref.invalidate(chatSessionUsageProvider);
  ref.invalidate(chatSessionListProvider);
  ref.invalidate(chatPersonaListProvider);
  ref.read(worldRoleplayRevisionProvider.notifier).bump();
  ref.read(sillyTavernImportRevisionProvider.notifier).bump();
}

class AppBackupOperationGuard implements BackupOperationGuard {
  AppBackupOperationGuard(this.ref);
  final Ref ref;

  @override
  Future<bool> get hasActiveAiOperation async {
    return ref.read(aiRequestCoordinatorProvider).hasActiveRequests ||
        ref.read(worldRoleplayEngineProvider).hasActiveTurns ||
        ref.read(ibukiPluginAiProvider).activeRequestCount > 0;
  }
}
