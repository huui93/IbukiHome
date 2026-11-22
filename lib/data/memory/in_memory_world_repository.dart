import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/world_repository.dart';
import '../../domain/world/world_card.dart';
import 'in_memory_ibuki_store.dart';

class InMemoryWorldRepository implements WorldRepository {
  InMemoryWorldRepository(this.store);

  final InMemoryIbukiStore store;

  @override
  Future<List<WorldCard>> listWorldCards(
    String projectId, {
    bool includeDeleted = false,
  }) async {
    final items =
        store.worldCards.where((card) {
          return card.projectId == projectId &&
              (includeDeleted || card.deletedAt == null);
        }).toList()..sort((left, right) {
          final order = left.sortOrder.compareTo(right.sortOrder);
          if (order != 0) {
            return order;
          }
          final time = left.updatedAt.compareTo(right.updatedAt);
          return time != 0 ? time : left.id.compareTo(right.id);
        });
    return List.unmodifiable(items);
  }

  @override
  Future<WorldCard> getWorldCard(String id) async {
    final card = store.worldCard(id);
    if (card == null) {
      throw EntityNotFoundException('WorldCard', id);
    }
    return card;
  }

  @override
  Future<void> upsertWorldCard(WorldCard card) async {
    _requireProject(card.projectId);
    final existing = store.worldCard(card.id);
    if (existing != null && existing.projectId != card.projectId) {
      throw DataConflictException(
        'WorldCard ${card.id} cannot move between projects.',
      );
    }
    store.putWorldCard(card);
  }

  @override
  Future<void> softDeleteWorldCard(String id, DateTime deletedAt) async {
    final card = await getWorldCard(id);
    final deletedUtc = deletedAt.toUtc();
    store.putWorldCard(
      card.copyWith(
        metadata: card.metadata.copyWith(
          updatedAt: deletedUtc,
          revision: card.revision + 1,
          deletedAt: deletedUtc,
        ),
      ),
    );
  }

  @override
  Future<void> restoreWorldCard(String id, DateTime updatedAt) async {
    final card = await getWorldCard(id);
    final updatedUtc = updatedAt.toUtc();
    store.putWorldCard(
      card.copyWith(
        metadata: card.metadata.copyWith(
          updatedAt: updatedUtc,
          revision: card.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  @override
  Future<void> reorderWorldCards({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  }) async {
    _requireProject(projectId);
    final active = await listWorldCards(projectId);
    _validateOrderedIds(active, orderedIds);
    final updatedUtc = updatedAt.toUtc();
    for (var index = 0; index < orderedIds.length; index += 1) {
      final card = store.worldCard(orderedIds[index])!;
      if (card.sortOrder == index) {
        continue;
      }
      store.putWorldCard(
        card.copyWith(
          metadata: card.metadata.copyWith(
            updatedAt: updatedUtc,
            revision: card.revision + 1,
          ),
          sortOrder: index,
        ),
      );
    }
  }

  void _validateOrderedIds(List<WorldCard> active, List<String> orderedIds) {
    final expected = active.map((item) => item.id).toSet();
    final provided = orderedIds.toSet();
    if (orderedIds.length != provided.length ||
        expected.length != provided.length ||
        !expected.containsAll(provided)) {
      throw const DataConflictException('世界观排序必须包含当前项目的全部有效卡片，且不能重复。');
    }
  }

  void _requireProject(String projectId) {
    if (!store.hasProject(projectId)) {
      throw EntityNotFoundException('Project', projectId);
    }
  }
}
