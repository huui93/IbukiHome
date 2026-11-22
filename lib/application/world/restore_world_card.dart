import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/world_repository.dart';
import '../../domain/world/world_card.dart';

class RestoreWorldCard {
  const RestoreWorldCard(this._worldCards);

  final WorldRepository _worldCards;

  Future<WorldCard> call({
    required String projectId,
    required String worldCardId,
    required DateTime nowUtc,
  }) async {
    final stored = await _worldCards.getWorldCard(worldCardId);
    if (stored.projectId != projectId) {
      throw const DataConflictException('世界观卡不属于当前项目。');
    }
    if (stored.deletedAt == null) {
      return stored;
    }
    await _worldCards.restoreWorldCard(worldCardId, nowUtc.toUtc());
    return _worldCards.getWorldCard(worldCardId);
  }
}
