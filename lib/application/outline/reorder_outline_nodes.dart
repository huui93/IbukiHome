import '../../data/repositories/outline_repository.dart';
import '../../domain/outline/outline_node.dart';

class ReorderOutlineNodes {
  const ReorderOutlineNodes(this._outlines);

  final OutlineRepository _outlines;

  Future<List<OutlineNode>> call({
    required String projectId,
    required List<String> orderedIds,
    required DateTime nowUtc,
  }) async {
    await _outlines.reorderOutlineNodes(
      projectId: projectId,
      orderedIds: List.unmodifiable(orderedIds),
      updatedAt: nowUtc.toUtc(),
    );
    return _outlines.listOutlineNodes(projectId);
  }
}
