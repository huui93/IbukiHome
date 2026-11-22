import '../../../domain/common/entity_metadata.dart';
import '../../../domain/segments/segment.dart';
import '../dto/segment_dto.dart';

Segment segmentFromRemote(SegmentDto dto) {
  return Segment(
    metadata: EntityMetadata(
      id: dto.id,
      createdAt: dto.createdAt,
      updatedAt: dto.updatedAt,
      revision: dto.revision,
    ),
    projectId: dto.projectId,
    orderIndex: dto.orderIndex,
    content: dto.content,
  );
}
