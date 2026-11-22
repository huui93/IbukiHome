import 'dto_readers.dart';

class ProjectSummaryDto {
  const ProjectSummaryDto({
    required this.id,
    required this.title,
    required this.description,
    required this.updatedAt,
    required this.revision,
    required this.segmentCount,
  });

  final String id;
  final String title;
  final String description;
  final DateTime updatedAt;
  final int revision;
  final int segmentCount;

  factory ProjectSummaryDto.fromJson(Map<String, dynamic> json) {
    return ProjectSummaryDto(
      id: readRequiredString(json, 'id', 'ProjectSummary'),
      title: readRequiredString(json, 'title', 'ProjectSummary'),
      description: readRequiredString(json, 'description', 'ProjectSummary'),
      updatedAt: readRequiredUtcDate(json, 'updated_at', 'ProjectSummary'),
      revision: readRequiredInt(json, 'revision', 'ProjectSummary'),
      segmentCount: readRequiredInt(json, 'segment_count', 'ProjectSummary'),
    );
  }
}
