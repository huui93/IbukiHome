import '../common/entity_metadata.dart';

class WorldCard {
  const WorldCard({
    required this.metadata,
    required this.projectId,
    required this.title,
    required this.content,
    required this.sortOrder,
  });

  /// Shared entity metadata used by all storage backends.
  final EntityMetadata metadata;

  /// Owning project identifier.
  final String projectId;

  /// World-card title.
  final String title;

  /// Consolidated world-setting text compatible with desktop stable fields.
  final String content;

  /// Stable display order within a project.
  final int sortOrder;

  String get id => metadata.id;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;
  int get revision => metadata.revision;
  DateTime? get deletedAt => metadata.deletedAt;

  WorldCard copyWith({
    EntityMetadata? metadata,
    String? projectId,
    String? title,
    String? content,
    int? sortOrder,
  }) {
    return WorldCard(
      metadata: metadata ?? this.metadata,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      content: content ?? this.content,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, Object?> toJson() {
    return {
      ...metadata.toJson(),
      'project_id': projectId,
      'title': title,
      'content': content,
      'sort_order': sortOrder,
    };
  }

  factory WorldCard.fromJson(Map<String, dynamic> json) {
    const modelName = 'WorldCard';
    return WorldCard(
      metadata: EntityMetadata.fromJson(json, modelName: modelName),
      projectId: readRequiredString(json, 'project_id', modelName),
      title: readRequiredString(json, 'title', modelName),
      content: readOptionalString(json, 'content', modelName),
      sortOrder: readRequiredInt(json, 'sort_order', modelName),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorldCard &&
        metadata == other.metadata &&
        projectId == other.projectId &&
        title == other.title &&
        content == other.content &&
        sortOrder == other.sortOrder;
  }

  @override
  int get hashCode =>
      Object.hash(metadata, projectId, title, content, sortOrder);
}
