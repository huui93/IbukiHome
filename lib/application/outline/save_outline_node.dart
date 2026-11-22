import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/outline_repository.dart';
import '../../domain/outline/outline_node.dart';

class SaveOutlineNode {
  const SaveOutlineNode(this._outlines);

  final OutlineRepository _outlines;

  Future<OutlineNode> call({
    required String projectId,
    required String outlineNodeId,
    required String title,
    required String summary,
    required DateTime nowUtc,
  }) async {
    final stored = await _outlines.getOutlineNode(outlineNodeId);
    if (stored.projectId != projectId || stored.deletedAt != null) {
      throw const DataConflictException(
        'Outline node is unavailable for this project.',
      );
    }
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw const DataFormatException('Outline title cannot be empty.');
    }
    final normalizedSummary = summary.trim();
    if (stored.title == normalizedTitle &&
        stored.summary == normalizedSummary) {
      return stored;
    }
    final updated = stored.copyWith(
      metadata: stored.metadata.copyWith(
        updatedAt: nowUtc.toUtc(),
        revision: stored.revision + 1,
      ),
      title: normalizedTitle,
      summary: normalizedSummary,
    );
    await _outlines.upsertOutlineNode(updated);
    return updated;
  }
}
