import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/memory/in_memory_compatibility_import_repository.dart';
import '../../data/repositories/compatibility_import_repository.dart';
import '../../domain/import/external_compatibility_payload.dart';
import '../providers/repository_providers.dart';
import '../world_roleplay/world_roleplay_providers.dart';
import 'sillytavern_asset_store.dart';
import 'sillytavern_file_picker.dart';
import 'sillytavern_import_service.dart';

final compatibilityImportRepositoryProvider =
    Provider<CompatibilityImportRepository>((ref) {
      return InMemoryCompatibilityImportRepository(
        coreStore: ref.watch(inMemoryIbukiStoreProvider),
        worlds: ref.watch(worldRoleplayRepositoryProvider),
      );
    });

final sillyTavernImportAssetStoreProvider =
    Provider<SillyTavernImportAssetStore>((ref) {
      return InMemorySillyTavernImportAssetStore();
    });

final sillyTavernImportPickerProvider = Provider<SillyTavernImportPicker>((
  ref,
) {
  return const SafSillyTavernImportPicker();
});

final sillyTavernImportServiceProvider = Provider<SillyTavernImportService>((
  ref,
) {
  return SillyTavernImportService(
    repository: ref.watch(compatibilityImportRepositoryProvider),
    projects: ref.watch(projectRepositoryProvider),
    characters: ref.watch(characterRepositoryProvider),
    worlds: ref.watch(worldRoleplayRepositoryProvider),
    assets: ref.watch(sillyTavernImportAssetStoreProvider),
    ids: ref.watch(entityIdGeneratorProvider),
    clock: ref.watch(utcClockProvider),
  );
});

final sillyTavernImportRevisionProvider =
    NotifierProvider<SillyTavernImportRevisionController, int>(
      SillyTavernImportRevisionController.new,
    );

class SillyTavernImportRevisionController extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state += 1;
}

final compatibilityPayloadByIdProvider =
    FutureProvider.family<ExternalCompatibilityPayload, String>((ref, id) {
      ref.watch(sillyTavernImportRevisionProvider);
      return ref.watch(compatibilityImportRepositoryProvider).getPayload(id);
    });

final compatibilityPayloadListProvider =
    FutureProvider<List<ExternalCompatibilityPayload>>((ref) {
      ref.watch(sillyTavernImportRevisionProvider);
      return ref.watch(compatibilityImportRepositoryProvider).listPayloads();
    });

final compatibilityPayloadsForEntityProvider =
    FutureProvider.family<
      List<ExternalCompatibilityPayload>,
      ({String entityType, String entityId})
    >((ref, key) {
      ref.watch(sillyTavernImportRevisionProvider);
      return ref
          .watch(compatibilityImportRepositoryProvider)
          .listForEntity(key.entityType, key.entityId);
    });
