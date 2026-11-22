import 'dto_readers.dart';

class SegmentDto {
  const SegmentDto({
    required this.id,
    required this.projectId,
    required this.orderIndex,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
  });

  final String id;
  final String projectId;
  final int orderIndex;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;

  factory SegmentDto.fromJson(Map<String, dynamic> json) {
    return SegmentDto(
      id: readRequiredString(json, 'id', 'Segment'),
      projectId: readRequiredString(json, 'project_id', 'Segment'),
      orderIndex: readRequiredInt(json, 'order_index', 'Segment'),
      content: readRequiredString(json, 'content', 'Segment'),
      createdAt: readRequiredUtcDate(json, 'created_at', 'Segment'),
      updatedAt: readRequiredUtcDate(json, 'updated_at', 'Segment'),
      revision: readRequiredInt(json, 'revision', 'Segment'),
    );
  }
}
