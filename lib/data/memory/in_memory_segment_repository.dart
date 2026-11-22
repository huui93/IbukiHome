import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/segment_repository.dart';
import '../../domain/segments/segment.dart';
import '../../domain/segments/segment_revision.dart';
import 'in_memory_ibuki_store.dart';

class InMemorySegmentRepository implements SegmentRepository {
  InMemorySegmentRepository(this.store);

  final InMemoryIbukiStore store;

  @override
  Future<List<Segment>> listSegments(
    String projectId, {
    bool includeDeleted = false,
  }) async {
    final items =
        store.segments.where((segment) {
          return segment.projectId == projectId &&
              (includeDeleted || segment.deletedAt == null);
        }).toList()..sort((left, right) {
          final order = left.orderIndex.compareTo(right.orderIndex);
          if (order != 0) {
            return order;
          }
          final time = left.createdAt.compareTo(right.createdAt);
          return time != 0 ? time : left.id.compareTo(right.id);
        });
    return List.unmodifiable(items);
  }

  @override
  Future<Segment> getSegment(String id) async {
    final segment = store.segment(id);
    if (segment == null) {
      throw EntityNotFoundException('Segment', id);
    }
    return segment;
  }

  @override
  Future<void> upsertSegment(Segment segment) async {
    _requireProject(segment.projectId);
    _requireWritableProject(segment.projectId);
    final existing = store.segment(segment.id);
    if (existing != null && existing.projectId != segment.projectId) {
      throw DataConflictException(
        'Segment ${segment.id} cannot move between projects.',
      );
    }
    store.putSegment(segment);
  }

  @override
  Future<void> softDeleteSegment(String id, DateTime deletedAt) async {
    final segment = await getSegment(id);
    await softDeleteAndReorder(
      projectId: segment.projectId,
      segmentId: id,
      deletedAt: deletedAt,
    );
  }

  @override
  Future<void> restoreSegment(String id, DateTime updatedAt) async {
    final segment = await getSegment(id);
    await restoreAndReorder(
      projectId: segment.projectId,
      segmentId: id,
      restoredAt: updatedAt,
    );
  }

  @override
  Future<List<SegmentRevision>> listRevisions(String segmentId) async {
    final items =
        store.segmentRevisions.where((revision) {
          return revision.segmentId == segmentId && revision.deletedAt == null;
        }).toList()..sort((left, right) {
          final revision = left.revisionNumber.compareTo(right.revisionNumber);
          if (revision != 0) {
            return revision;
          }
          final time = left.createdAt.compareTo(right.createdAt);
          return time != 0 ? time : left.id.compareTo(right.id);
        });
    return List.unmodifiable(items);
  }

  @override
  Future<SegmentRevision> getRevision(String id) async {
    final revision = store.segmentRevision(id);
    if (revision == null) {
      throw EntityNotFoundException('SegmentRevision', id);
    }
    return revision;
  }

  @override
  Future<void> appendRevision(SegmentRevision revision) async {
    _validateRevisionCanBeAppended(revision);
    store.putSegmentRevision(revision);
  }

  @override
  Future<Segment> insertSegmentAt({
    required Segment segment,
    required String anchorSegmentId,
    required SegmentInsertPosition position,
  }) async {
    _requireProject(segment.projectId);
    if (store.hasSegment(segment.id)) {
      throw DuplicateEntityException('Segment', segment.id);
    }
    final anchor = await getSegment(anchorSegmentId);
    if (anchor.projectId != segment.projectId) {
      throw const DataConflictException('插入锚点不属于当前项目。');
    }
    if (anchor.deletedAt != null) {
      throw const DataConflictException('已删除段落不能作为插入锚点。');
    }

    final active = await listSegments(segment.projectId);
    final anchorIndex = active.indexWhere((item) => item.id == anchor.id);
    if (anchorIndex < 0) {
      throw EntityNotFoundException('Segment', anchorSegmentId);
    }
    final insertionIndex =
        anchorIndex + (position == SegmentInsertPosition.after ? 1 : 0);
    final updatedAt = segment.updatedAt.toUtc();
    for (var index = insertionIndex; index < active.length; index += 1) {
      final current = active[index];
      store.putSegment(
        current.copyWith(
          metadata: current.metadata.copyWith(
            updatedAt: updatedAt,
            revision: current.revision + 1,
          ),
          orderIndex: index + 1,
        ),
      );
    }
    final inserted = segment.copyWith(orderIndex: insertionIndex);
    store.putSegment(inserted);
    return inserted;
  }

  @override
  Future<void> reorderSegments({
    required String projectId,
    required List<String> orderedIds,
    required DateTime updatedAt,
  }) async {
    _requireProject(projectId);
    final active = await listSegments(projectId);
    _validateOrderedIds(active, orderedIds);
    final updatedUtc = updatedAt.toUtc();
    for (var index = 0; index < orderedIds.length; index += 1) {
      final current = store.segment(orderedIds[index])!;
      if (current.orderIndex == index) {
        continue;
      }
      store.putSegment(
        current.copyWith(
          metadata: current.metadata.copyWith(
            updatedAt: updatedUtc,
            revision: current.revision + 1,
          ),
          orderIndex: index,
        ),
      );
    }
  }

  @override
  Future<Segment> softDeleteAndReorder({
    required String projectId,
    required String segmentId,
    required DateTime deletedAt,
  }) async {
    _requireProject(projectId);
    final target = await getSegment(segmentId);
    if (target.projectId != projectId) {
      throw const DataConflictException('段落不属于当前项目。');
    }
    if (target.deletedAt != null) {
      return target;
    }

    final active = await listSegments(projectId);
    final deletedUtc = deletedAt.toUtc();
    final deleted = target.copyWith(
      metadata: target.metadata.copyWith(
        updatedAt: deletedUtc,
        revision: target.revision + 1,
        deletedAt: deletedUtc,
      ),
    );
    store.putSegment(deleted);
    var order = 0;
    for (final current in active) {
      if (current.id == segmentId) {
        continue;
      }
      if (current.orderIndex != order) {
        store.putSegment(
          current.copyWith(
            metadata: current.metadata.copyWith(
              updatedAt: deletedUtc,
              revision: current.revision + 1,
            ),
            orderIndex: order,
          ),
        );
      }
      order += 1;
    }
    return deleted;
  }

  @override
  Future<Segment> restoreAndReorder({
    required String projectId,
    required String segmentId,
    required DateTime restoredAt,
  }) async {
    _requireProject(projectId);
    final target = await getSegment(segmentId);
    if (target.projectId != projectId) {
      throw const DataConflictException('段落不属于当前项目。');
    }
    if (target.deletedAt == null) {
      return target;
    }

    final active = await listSegments(projectId);
    final insertionIndex = target.orderIndex.clamp(0, active.length).toInt();
    final restoredUtc = restoredAt.toUtc();
    for (var index = insertionIndex; index < active.length; index += 1) {
      final current = active[index];
      store.putSegment(
        current.copyWith(
          metadata: current.metadata.copyWith(
            updatedAt: restoredUtc,
            revision: current.revision + 1,
          ),
          orderIndex: index + 1,
        ),
      );
    }
    final restored = target.copyWith(
      metadata: target.metadata.copyWith(
        updatedAt: restoredUtc,
        revision: target.revision + 1,
        deletedAt: null,
      ),
      orderIndex: insertionIndex,
    );
    store.putSegment(restored);
    return restored;
  }

  @override
  Future<void> saveSegmentWithRevision({
    required Segment updatedSegment,
    required SegmentRevision revision,
  }) async {
    _requireWritableProject(updatedSegment.projectId);
    _validateRevisionCanBeAppended(revision);
    final current = store.segment(updatedSegment.id);
    if (current == null) {
      throw EntityNotFoundException('Segment', updatedSegment.id);
    }
    if (current.projectId != updatedSegment.projectId ||
        current.orderIndex != updatedSegment.orderIndex ||
        current.revision != revision.revisionNumber ||
        current.content != revision.content ||
        revision.segmentId != updatedSegment.id ||
        revision.projectId != updatedSegment.projectId) {
      throw DataConflictException(
        'Segment ${updatedSegment.id} and revision ${revision.id} do not match.',
      );
    }
    store.putSegmentRevision(revision);
    store.putSegment(updatedSegment);
  }

  void _validateRevisionCanBeAppended(SegmentRevision revision) {
    if (store.hasSegmentRevision(revision.id)) {
      throw DuplicateEntityException('SegmentRevision', revision.id);
    }
    final segment = store.segment(revision.segmentId);
    if (segment == null) {
      throw EntityNotFoundException('Segment', revision.segmentId);
    }
    if (segment.projectId != revision.projectId) {
      throw DataConflictException(
        'SegmentRevision ${revision.id} project does not match segment.',
      );
    }
    final numberAlreadyExists = store.segmentRevisions.any((existing) {
      return existing.segmentId == revision.segmentId &&
          existing.revisionNumber == revision.revisionNumber;
    });
    if (numberAlreadyExists) {
      throw DataConflictException(
        'SegmentRevision ${revision.segmentId}/${revision.revisionNumber} already exists.',
      );
    }
  }

  void _validateOrderedIds(List<Segment> active, List<String> orderedIds) {
    final expected = active.map((item) => item.id).toSet();
    final provided = orderedIds.toSet();
    if (orderedIds.length != provided.length ||
        expected.length != provided.length ||
        !expected.containsAll(provided)) {
      throw const DataConflictException('正文排序必须包含当前项目的全部有效段落，且不能重复。');
    }
  }

  void _requireProject(String projectId) {
    if (!store.hasProject(projectId)) {
      throw EntityNotFoundException('Project', projectId);
    }
  }

  void _requireWritableProject(String projectId) {
    _requireProject(projectId);
    if (store.project(projectId)!.deletedAt != null) {
      throw const DataConflictException('作品已删除，不能继续保存正文。');
    }
  }
}
