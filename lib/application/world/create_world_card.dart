import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/world_repository.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/world/world_card.dart';

class CreateWorldCard {
  const CreateWorldCard(this._projects, this._worldCards);

  final ProjectRepository _projects;
  final WorldRepository _worldCards;

  Future<WorldCard> call({
    required String projectId,
    required String title,
    required String content,
    required String id,
    required DateTime nowUtc,
  }) async {
    final project = await _projects.getProject(projectId);
    if (project.deletedAt != null) {
      throw const DataConflictException('项目已删除，不能新建世界观卡。');
    }
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw const DataFormatException('世界观标题不能为空。');
    }
    final active = await _worldCards.listWorldCards(projectId);
    final nextOrder = active.isEmpty
        ? 0
        : active
                  .map((card) => card.sortOrder)
                  .reduce((left, right) => left > right ? left : right) +
              1;
    final now = nowUtc.toUtc();
    final card = WorldCard(
      metadata: EntityMetadata(
        id: id,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      ),
      projectId: projectId,
      title: normalizedTitle,
      content: content,
      sortOrder: nextOrder,
    );
    await _worldCards.upsertWorldCard(card);
    return card;
  }
}
