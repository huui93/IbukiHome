import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ai/ai_settings_controller.dart';
import '../providers/repository_providers.dart';
import '../world_roleplay/world_roleplay_providers.dart';
import '../security/secure_value_store.dart';
import '../../domain/tavern/tavern_models.dart';
import 'tavern_execution_providers.dart';
import 'tavern_story_service.dart';
import 'tavern_presentation_controller.dart';

final tavernStoryServiceProvider = Provider<TavernStoryService>(
  (ref) => TavernStoryService(
    repository: ref.watch(tavernRepositoryProvider),
    characters: ref.watch(characterRepositoryProvider),
    worlds: ref.watch(worldRoleplayRepositoryProvider),
    worldCards: ref.watch(worldRepositoryProvider),
    projects: ref.watch(projectRepositoryProvider),
    configs: ref.watch(aiProviderConfigRepositoryProvider),
    profiles: ref.watch(tavernModelProfilesProvider),
    ids: ref.watch(entityIdGeneratorProvider),
    clock: ref.watch(utcClockProvider),
  ),
);
final tavernAssetsProvider = FutureProvider<TavernAssetCatalog>(
  (ref) => ref.watch(tavernStoryServiceProvider).loadAssets(),
);
final tavernStoriesProvider =
    FutureProvider.family<List<TavernStorySummary>, bool>(
      (ref, archived) => ref
          .watch(tavernRepositoryProvider)
          .listStorySummaries(archived: archived),
    );
final tavernTraceCacheProvider = Provider((ref) => TavernTraceCache());
final tavernSessionControllerProvider = Provider.autoDispose
    .family<TavernSessionController, String>((ref, id) {
      final value = TavernSessionController(
        sessionId: id,
        service: ref.watch(tavernStoryServiceProvider),
        owner: ref.watch(tavernExecutionProvider),
        traces: ref.watch(tavernTraceCacheProvider),
      );
      ref.onDispose(value.dispose);
      return value;
    });
final tavernReadingStoreProvider = Provider(
  (ref) => TavernReadingStore(ref.watch(aiSecureValueStoreProvider)),
);

class TavernReadingAnchor {
  const TavernReadingAnchor({
    required this.turnId,
    required this.y,
    required this.following,
    this.pixelHint = 0,
  });
  final String? turnId;
  final double y, pixelHint;
  final bool following;
  Map<String, Object?> toJson() => {
    'turn': turnId,
    'y': y,
    'following': following,
    'hint': pixelHint,
  };
}

class TavernReadingStore {
  TavernReadingStore(this.store);
  final SecureValueStore store;
  final _cache = <String, TavernReadingAnchor>{};
  String _key(String session, String line) =>
      'tavern.reading.v1.$session.$line';
  Future<TavernReadingAnchor?> load(String session, String line) async {
    final key = _key(session, line);
    if (_cache.containsKey(key)) return _cache[key];
    final raw = await store.read(key);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map;
      return _cache[key] = TavernReadingAnchor(
        turnId: j['turn'] as String?,
        y: (j['y'] as num).toDouble(),
        following: j['following'] == true,
        pixelHint: (j['hint'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    String session,
    String line,
    TavernReadingAnchor anchor,
  ) async {
    final key = _key(session, line);
    _cache[key] = anchor;
    await store.write(key, jsonEncode(anchor.toJson()));
  }
}
