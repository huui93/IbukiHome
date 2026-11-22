import '../../domain/outline/outline_node.dart';

abstract class OutlineRepository {
  Future<List<OutlineNode>> listOutlineNodes(
    String projectId, {
    bool includeDeleted = false,
  });

  Future<OutlineNode> getOutlineNode(String id);

  Future<void> upsertOutlineNode(OutlineNode node);

  Future<void> softDeleteOutlineNode(String id, DateTime deletedAt);

  Future<void> reorderOutlineNodes({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  });

  /// Changes status atomically. Selecting current demotes any previous current
  /// node to planned so the project always has at most one current node.
  Future<void> setOutlineNodeStatus({
    required String id,
    required OutlineNodeStatus status,
    required DateTime updatedAt,
  });
}
