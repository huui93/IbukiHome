import '../../data/repositories/world_repository.dart';
import '../../domain/world/world_card.dart';

class ReorderWorldCards {
  const ReorderWorldCards(this._worldCards);

  final WorldRepository _worldCards;

  Future<List<WorldCard>> call({
    required String projectId,
    required List<String> orderedIds,
    required DateTime nowUtc,
  }) async {
    await _worldCards.reorderWorldCards(
      projectId: projectId,
      orderedIds: List.unmodifiable(orderedIds),
      updatedAt: nowUtc.toUtc(),
    );
    return _worldCards.listWorldCards(projectId);
  }
}
