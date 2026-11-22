import '../../core/errors/data_exceptions.dart';
import '../../domain/outline/outline_node.dart';
import '../repositories/outline_repository.dart';
import 'in_memory_ibuki_store.dart';

class InMemoryOutlineRepository implements OutlineRepository {
  InMemoryOutlineRepository(this.store);

  final InMemoryIbukiStore store;

  @override
  Future<List<OutlineNode>> listOutlineNodes(
    String projectId, {
    bool includeDeleted = false,
  }) async {
    final nodes = store.outlineNodes.where((node) {
      return node.projectId == projectId &&
          (includeDeleted || node.deletedAt == null);
    }).toList()..sort(_compareOutlineNodes);
    return List.unmodifiable(nodes);
  }

  @override
  Future<OutlineNode> getOutlineNode(String id) async {
    final node = store.outlineNode(id);
    if (node == null) throw EntityNotFoundException('OutlineNode', id);
    return node;
  }

  @override
  Future<void> upsertOutlineNode(OutlineNode node) async {
    _requireProject(node.projectId);
    final existing = store.outlineNode(node.id);
    if (existing != null && existing.projectId != node.projectId) {
      throw const DataConflictException(
        'Outline nodes cannot move between projects.',
      );
    }
    if (node.status == OutlineNodeStatus.current && node.deletedAt == null) {
      final current = store.outlineNodes.where(
        (item) =>
            item.projectId == node.projectId &&
            item.id != node.id &&
            item.deletedAt == null &&
            item.status == OutlineNodeStatus.current,
      );
      if (current.isNotEmpty) {
        throw const DataConflictException(
          'A project can only have one current outline node.',
        );
      }
    }
    store.putOutlineNode(node);
  }

  @override
  Future<void> softDeleteOutlineNode(String id, DateTime deletedAt) async {
    final node = await getOutlineNode(id);
    if (node.deletedAt != null) return;
    final at = deletedAt.toUtc();
    store.putOutlineNode(
      node.copyWith(
        metadata: node.metadata.copyWith(
          updatedAt: at,
          revision: node.revision + 1,
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
    _requireProject(projectId);
    final active = await listOutlineNodes(projectId);
    _validateOrderedIds(active.map((item) => item.id).toList(), orderedIds);
    final at = updatedAt.toUtc();
    for (var index = 0; index < orderedIds.length; index += 1) {
      final node = store.outlineNode(orderedIds[index])!;
      if (node.orderIndex == index) continue;
      store.putOutlineNode(
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
    final at = updatedAt.toUtc();
    if (status == OutlineNodeStatus.current) {
      for (final node in store.outlineNodes.where(
        (item) =>
            item.projectId == target.projectId &&
            item.id != target.id &&
            item.deletedAt == null &&
            item.status == OutlineNodeStatus.current,
      )) {
        store.putOutlineNode(
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
    store.putOutlineNode(
      target.copyWith(
        metadata: target.metadata.copyWith(
          updatedAt: at,
          revision: target.revision + 1,
        ),
        status: status,
      ),
    );
  }

  void _requireProject(String projectId) {
    if (!store.hasProject(projectId)) {
      throw EntityNotFoundException('Project', projectId);
    }
  }
}

int _compareOutlineNodes(OutlineNode left, OutlineNode right) {
  final order = left.orderIndex.compareTo(right.orderIndex);
  return order != 0 ? order : left.id.compareTo(right.id);
}

void _validateOrderedIds(List<String> activeIds, List<String> orderedIds) {
  final expected = activeIds.toSet();
  final provided = orderedIds.toSet();
  if (orderedIds.length != provided.length ||
      expected.length != provided.length ||
      !expected.containsAll(provided)) {
    throw const DataConflictException(
      'Outline ordering must include every active node exactly once.',
    );
  }
}
