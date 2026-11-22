import 'dto_readers.dart';

class ProjectDetailDto {
  const ProjectDetailDto({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    required this.segmentCount,
  });

  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final int segmentCount;

  factory ProjectDetailDto.fromJson(Map<String, dynamic> json) {
    return ProjectDetailDto(
      id: readRequiredString(json, 'id', 'ProjectDetail'),
      title: readRequiredString(json, 'title', 'ProjectDetail'),
      description: readRequiredString(json, 'description', 'ProjectDetail'),
      createdAt: readRequiredUtcDate(json, 'created_at', 'ProjectDetail'),
      updatedAt: readRequiredUtcDate(json, 'updated_at', 'ProjectDetail'),
      revision: readRequiredInt(json, 'revision', 'ProjectDetail'),
      segmentCount: readRequiredInt(json, 'segment_count', 'ProjectDetail'),
    );
  }
}
