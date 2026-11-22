import '../../domain/world/world_card.dart';

abstract class WorldRepository {
  Future<List<WorldCard>> listWorldCards(
    String projectId, {
    bool includeDeleted = false,
  });

  Future<WorldCard> getWorldCard(String id);

  Future<void> upsertWorldCard(WorldCard card);

  Future<void> softDeleteWorldCard(String id, DateTime deletedAt);

  Future<void> restoreWorldCard(String id, DateTime updatedAt);

  Future<void> reorderWorldCards({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  });
}
