import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/memory/in_memory_novel_plugin_repository.dart';
import '../../data/repositories/novel_plugin_repository.dart';
import '../../data/repositories/invalidatable_read_cache.dart';
import '../../domain/plugins/installed_plugin.dart';
import '../../domain/projects/novel_story_branch.dart';
import '../providers/repository_providers.dart';
import '../projects/novel_output_limits_providers.dart';
import '../ai/ai_output_preferences.dart';
import '../ai/ai_runtime_providers.dart';
import '../ai/ai_settings_controller.dart';
import '../tavern/provider/tavern_model_profile_store.dart';
import '../import/sillytavern_import_providers.dart';
import '../world_roleplay/world_roleplay_providers.dart';
import 'novel_plugin_host.dart';
import 'novel_plugin_memory.dart';
import 'novel_plugin_sources.dart';
import 'plugin_providers.dart';
import 'novel_plugin_bundle.dart';
import 'novel_plugin_scope_store.dart';

final novelPluginRepositoryProvider = Provider<NovelPluginRepository>(
  (ref) => InMemoryNovelPluginRepository(
    projects: ref.watch(projectRepositoryProvider),
    segments: ref.watch(segmentRepositoryProvider),
    characters: ref.watch(characterRepositoryProvider),
    world: ref.watch(worldRepositoryProvider),
    outlines: ref.watch(outlineRepositoryProvider),
    plugins: ref.watch(pluginRegistryProvider),
    storage: ref.watch(pluginStorageRepositoryProvider),
    outputLimits: ref.watch(novelOutputLimitsRepositoryProvider),
  ),
);

final novelPluginScopeStoreProvider = Provider<NovelPluginScopeStore>((ref) {
  final store = NovelPluginScopeStore(
    repository: ref.watch(novelPluginRepositoryProvider),
    storage: ref.watch(pluginStorageRepositoryProvider),
  );
  ref.onDispose(store.dispose);
  return store;
});

final _novelPluginServicesProvider =
    Provider<({NovelPluginHost host, NovelPluginMemory memory})>((ref) {
      late final NovelPluginMemory memory;
      final host = NovelPluginHost(
        registry: ref.watch(pluginRegistryProvider),
        repository: ref.watch(novelPluginRepositoryProvider),
        scopes: ref.watch(novelPluginScopeStoreProvider),
        sources: NovelPluginSources(
          ref.watch(compatibilityImportRepositoryProvider),
          ref.watch(worldRoleplayRepositoryProvider),
        ),
        scheduleMemory: (id) => memory.schedule(id),
        cancelMemory: (id) => memory.cancel(id),
        modelLimits: (model) => TavernModelProfileStore(
          ref.read(aiSecureValueStoreProvider),
        ).savedLimits(model.providerConfigId, model.model),
        streamingPreference: () async {
          try {
            return await ref.read(aiOutputPreferencesProvider.future);
          } catch (_) {
            return true;
          }
        },
      );
      memory = NovelPluginMemory(
        host: host,
        runtime: ref.watch(aiGenerationServiceProvider),
        models: ref.watch(novelAiModelResolverProvider),
        requests: ref.watch(aiRequestCoordinatorProvider),
      );
      ref.onDispose(() {
        memory.dispose();
        host.dispose();
      });
      return (host: host, memory: memory);
    });

final novelPluginHostProvider = Provider(
  (ref) => ref.watch(_novelPluginServicesProvider).host,
);
final novelPluginMemoryProvider = Provider(
  (ref) => ref.watch(_novelPluginServicesProvider).memory,
);

final novelPluginEventsProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(novelPluginHostProvider).events,
);

final novelPluginChangesProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(novelPluginScopeStoreProvider).changes,
);

final novelStoryBranchProvider = FutureProvider.autoDispose
    .family<NovelStoryBranch, String>((ref, id) {
      ref.watch(repositoryRevisionsProvider.select((r) => r.projects));
      ref.watch(
        novelPluginEventsProvider.select(
          (e) => e.value?.projectId == id && e.value?.type == 'end' ? e : null,
        ),
      );
      return ref.watch(novelPluginRepositoryProvider).branch(id);
    });

final novelBoundPluginProvider = FutureProvider.autoDispose
    .family<InstalledPlugin?, String>((ref, id) async {
      ref.watch(novelPluginChangesProvider);
      ref.watch(repositoryRevisionsProvider.select((r) => r.projects));
      final plugins = await ref.watch(installedPluginsProvider.future);
      final scopes = ref.watch(novelPluginScopeStoreProvider);
      for (final plugin in plugins.where(NovelPluginBundleLoader.supports)) {
        if ((await scopes.resolve(plugin, id)).enabled) return plugin;
      }
      return null;
    });

final novelReplyViewProvider = FutureProvider.autoDispose
    .family<Map<String, Object?>?, ({String id, String hash})>(
      (ref, source) => ref
          .watch(novelPluginRepositoryProvider)
          .replyView(source.id, source.hash),
    );

/// Branch transactions write several repositories atomically beneath the caches.
void invalidateNovelBranchCaches(WidgetRef ref) {
  for (final repository in <Object>[
    ref.read(projectRepositoryProvider),
    ref.read(segmentRepositoryProvider),
    ref.read(characterRepositoryProvider),
    ref.read(worldRepositoryProvider),
    ref.read(outlineRepositoryProvider),
  ]) {
    if (repository case InvalidatableReadCache cache) cache.invalidateAll();
  }
  notifyRepositoryChanged(
    ref,
    areas: const [
      RepositoryDataArea.projects,
      RepositoryDataArea.segments,
      RepositoryDataArea.characters,
      RepositoryDataArea.worlds,
      RepositoryDataArea.outlines,
    ],
  );
}
