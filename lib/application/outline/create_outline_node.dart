import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/outline_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/outline/outline_node.dart';

class CreateOutlineNode {
  const CreateOutlineNode(this._projects, this._outlines);

  final ProjectRepository _projects;
  final OutlineRepository _outlines;

  Future<OutlineNode> call({
    required String projectId,
    required String title,
    required String summary,
    required String id,
    required DateTime nowUtc,
  }) async {
    final project = await _projects.getProject(projectId);
    if (project.deletedAt != null) {
      throw const DataConflictException(
        'Deleted projects cannot create outline nodes.',
      );
    }
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw const DataFormatException('Outline title cannot be empty.');
    }
    final active = await _outlines.listOutlineNodes(projectId);
    final nextOrder = active.isEmpty
        ? 0
        : active
                  .map((item) => item.orderIndex)
                  .reduce((left, right) => left > right ? left : right) +
              1;
    final now = nowUtc.toUtc();
    final node = OutlineNode(
      metadata: EntityMetadata(
        id: id,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      ),
      projectId: projectId,
      title: normalizedTitle,
      summary: summary.trim(),
      orderIndex: nextOrder,
      status: OutlineNodeStatus.planned,
    );
    await _outlines.upsertOutlineNode(node);
    return node;
  }
}
