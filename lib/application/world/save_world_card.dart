import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/world_repository.dart';
import '../../domain/world/world_card.dart';

class SaveWorldCard {
  const SaveWorldCard(this._worldCards);

  final WorldRepository _worldCards;

  Future<WorldCard> call({
    required String projectId,
    required String worldCardId,
    required String title,
    required String content,
    required DateTime nowUtc,
  }) async {
    final stored = await _worldCards.getWorldCard(worldCardId);
    if (stored.projectId != projectId) {
      throw const DataConflictException('世界观卡不属于当前项目。');
    }
    if (stored.deletedAt != null) {
      throw const DataConflictException('已删除的世界观卡不能编辑。');
    }
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw const DataFormatException('世界观标题不能为空。');
    }
    if (stored.title == normalizedTitle && stored.content == content) {
      return stored;
    }
    final updated = stored.copyWith(
      metadata: stored.metadata.copyWith(
        updatedAt: nowUtc.toUtc(),
        revision: stored.revision + 1,
      ),
      title: normalizedTitle,
      content: content,
    );
    await _worldCards.upsertWorldCard(updated);
    return updated;
  }
}
