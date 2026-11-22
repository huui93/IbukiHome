import '../../domain/outline/outline_node.dart';

class NovelOutlineContext {
  const NovelOutlineContext({
    this.recentCompleted,
    this.current,
    this.nextPlanned,
  });

  final OutlineNode? recentCompleted;
  final OutlineNode? current;
  final OutlineNode? nextPlanned;

  bool get isEmpty =>
      recentCompleted == null && current == null && nextPlanned == null;

  static NovelOutlineContext select(List<OutlineNode> nodes) {
    final active = nodes.where((item) => item.deletedAt == null).toList()
      ..sort((left, right) {
        final order = left.orderIndex.compareTo(right.orderIndex);
        return order != 0 ? order : left.id.compareTo(right.id);
      });
    if (active.isEmpty) return const NovelOutlineContext();

    final explicitCurrent = active.where(
      (item) => item.status == OutlineNodeStatus.current,
    );
    final planned = active.where(
      (item) => item.status == OutlineNodeStatus.planned,
    );
    final current = explicitCurrent.firstOrNull ?? planned.firstOrNull;

    OutlineNode? recentCompleted;
    final completed = active.where(
      (item) => item.status == OutlineNodeStatus.completed,
    );
    if (current == null) {
      recentCompleted = completed.lastOrNull;
    } else {
      recentCompleted = completed
          .where((item) => item.orderIndex < current.orderIndex)
          .lastOrNull;
    }

    OutlineNode? next;
    if (current != null) {
      next = planned
          .where(
            (item) =>
                item.id != current.id && item.orderIndex > current.orderIndex,
          )
          .firstOrNull;
    }
    return NovelOutlineContext(
      recentCompleted: recentCompleted,
      current: current,
      nextPlanned: next,
    );
  }
}
