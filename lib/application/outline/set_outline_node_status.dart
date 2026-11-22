import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/outline_repository.dart';
import '../../domain/outline/outline_node.dart';

class SetOutlineNodeStatus {
  const SetOutlineNodeStatus(this._outlines);

  final OutlineRepository _outlines;

  Future<List<OutlineNode>> call({
    required String projectId,
    required String outlineNodeId,
    required OutlineNodeStatus status,
    required DateTime nowUtc,
  }) async {
    final stored = await _outlines.getOutlineNode(outlineNodeId);
    if (stored.projectId != projectId || stored.deletedAt != null) {
      throw const DataConflictException(
        'Outline node is unavailable for this project.',
      );
    }
    await _outlines.setOutlineNodeStatus(
      id: outlineNodeId,
      status: status,
      updatedAt: nowUtc.toUtc(),
    );
    return _outlines.listOutlineNodes(projectId);
  }
}
