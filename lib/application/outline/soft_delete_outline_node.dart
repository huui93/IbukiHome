import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/outline_repository.dart';

class SoftDeleteOutlineNode {
  const SoftDeleteOutlineNode(this._outlines);

  final OutlineRepository _outlines;

  Future<void> call({
    required String projectId,
    required String outlineNodeId,
    required DateTime nowUtc,
  }) async {
    final stored = await _outlines.getOutlineNode(outlineNodeId);
    if (stored.projectId != projectId) {
      throw const DataConflictException(
        'Outline node does not belong to this project.',
      );
    }
    if (stored.deletedAt != null) return;
    await _outlines.softDeleteOutlineNode(outlineNodeId, nowUtc.toUtc());
  }
}
