import '../../domain/outline/outline_node.dart';
import '../repositories/outline_repository.dart';
import '../repositories/invalidatable_read_cache.dart';
import 'repository_cache_metrics.dart';

class CachedOutlineRepository
    implements OutlineRepository, InvalidatableReadCache {
  CachedOutlineRepository(this.delegate);

  final OutlineRepository delegate;
  final metrics = RepositoryCacheMetrics();
  final Map<String, OutlineNode> _entities = {};
  final Map<(String, bool), List<OutlineNode>> _lists = {};

  int get retainedEntryCount => _entities.length;

  @override
  void invalidateAll() {
    _entities.clear();
    _lists.clear();
  }

  @override
  Future<List<OutlineNode>> listOutlineNodes(
    String projectId, {
    bool includeDeleted = false,
  }) async {
    final key = (projectId, includeDeleted);
    final cached = _lists[key];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final items = await delegate.listOutlineNodes(
      projectId,
      includeDeleted: includeDeleted,
    );
    _entities.addEntries(items.map((item) => MapEntry(item.id, item)));
    return _lists[key] = List.unmodifiable(items);
  }

  @override
  Future<OutlineNode> getOutlineNode(String id) async {
    final cached = _entities[id];
    if (cached != null) {
      metrics.cacheHits += 1;
      return cached;
    }
    metrics.delegateReads += 1;
    final item = await delegate.getOutlineNode(id);
    _entities[id] = item;
    return item;
  }

  @override
  Future<void> upsertOutlineNode(OutlineNode node) async {
    await delegate.upsertOutlineNode(node);
    metrics.writes += 1;
    _store(node);
  }

  @override
  Future<void> softDeleteOutlineNode(String id, DateTime deletedAt) async {
    final current = await getOutlineNode(id);
    if (current.deletedAt != null) return;
    await delegate.softDeleteOutlineNode(id, deletedAt);
    metrics.writes += 1;
    final at = deletedAt.toUtc();
    _store(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: at,
          revision: current.revision + 1,
          deletedAt: at,
        ),
      ),
    );
  }

  @override
  Future<void> reorderOutlineNodes({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  }) async {
    final current = await listOutlineNodes(projectId);
    await delegate.reorderOutlineNodes(
      projectId: projectId,
      orderedIds: orderedIds,
      updatedAt: updatedAt,
    );
    metrics.writes += 1;
    final byId = {for (final node in current) node.id: node};
    final at = updatedAt.toUtc();
    for (var index = 0; index < orderedIds.length; index += 1) {
      final node = byId[orderedIds[index]]!;
      if (node.orderIndex == index) continue;
      _store(
        node.copyWith(
          metadata: node.metadata.copyWith(
            updatedAt: at,
            revision: node.revision + 1,
          ),
          orderIndex: index,
        ),
      );
    }
  }

  @override
  Future<void> setOutlineNodeStatus({
    required String id,
    required OutlineNodeStatus status,
    required DateTime updatedAt,
  }) async {
    final target = await getOutlineNode(id);
    if (target.deletedAt != null || target.status == status) return;
    await listOutlineNodes(target.projectId);
    await delegate.setOutlineNodeStatus(
      id: id,
      status: status,
      updatedAt: updatedAt,
    );
    metrics.writes += 1;
    final at = updatedAt.toUtc();
    if (status == OutlineNodeStatus.current) {
      for (final node in _entities.values.where(
        (item) =>
            item.projectId == target.projectId &&
            item.id != target.id &&
            item.deletedAt == null &&
            item.status == OutlineNodeStatus.current,
      )) {
        _store(
          node.copyWith(
            metadata: node.metadata.copyWith(
              updatedAt: at,
              revision: node.revision + 1,
            ),
            status: OutlineNodeStatus.planned,
          ),
        );
      }
    }
    _store(
      target.copyWith(
        metadata: target.metadata.copyWith(
          updatedAt: at,
          revision: target.revision + 1,
        ),
        status: status,
      ),
    );
  }

  void _store(OutlineNode node) {
    _entities[node.id] = node;
    final keys = _lists.keys
        .where((key) => key.$1 == node.projectId)
        .toList(growable: false);
    for (final key in keys) {
      final items = [..._lists[key]!]
        ..removeWhere((item) => item.id == node.id);
      if (key.$2 || node.deletedAt == null) items.add(node);
      items.sort(_compareOutlineNodes);
      _lists[key] = List.unmodifiable(items);
    }
  }
}

int _compareOutlineNodes(OutlineNode left, OutlineNode right) {
  final order = left.orderIndex.compareTo(right.orderIndex);
  return order != 0 ? order : left.id.compareTo(right.id);
}
