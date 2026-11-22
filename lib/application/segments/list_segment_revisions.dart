import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/segment_repository.dart';
import '../../domain/segments/segment_revision.dart';

class ListSegmentRevisions {
  const ListSegmentRevisions(this._segments);

  final SegmentRepository _segments;

  Future<List<SegmentRevision>> call({
    required String projectId,
    required String segmentId,
  }) async {
    final segment = await _segments.getSegment(segmentId);
    if (segment.projectId != projectId) {
      throw const DataConflictException('段落不属于当前项目。');
    }
    final revisions = await _segments.listRevisions(segmentId);
    final newestFirst = revisions.toList()
      ..sort((left, right) {
        final number = right.revisionNumber.compareTo(left.revisionNumber);
        if (number != 0) {
          return number;
        }
        final time = right.createdAt.compareTo(left.createdAt);
        return time != 0 ? time : right.id.compareTo(left.id);
      });
    return List.unmodifiable(newestFirst);
  }
}
