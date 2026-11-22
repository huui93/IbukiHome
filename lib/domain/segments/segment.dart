import '../common/entity_metadata.dart';

class Segment {
  const Segment({
    required this.metadata,
    required this.projectId,
    required this.orderIndex,
    required this.content,
  });

  /// Shared entity metadata used by all storage backends.
  final EntityMetadata metadata;

  /// Owning project identifier.
  final String projectId;

  /// Stable manuscript order within a project.
  final int orderIndex;

  /// Plain segment text. Rich rendering is intentionally outside the model.
  final String content;

  String get id => metadata.id;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;
  int get revision => metadata.revision;
  DateTime? get deletedAt => metadata.deletedAt;

  Segment copyWith({
    EntityMetadata? metadata,
    String? projectId,
    int? orderIndex,
    String? content,
  }) {
    return Segment(
      metadata: metadata ?? this.metadata,
      projectId: projectId ?? this.projectId,
      orderIndex: orderIndex ?? this.orderIndex,
      content: content ?? this.content,
    );
  }

  Map<String, Object?> toJson() {
    return {
      ...metadata.toJson(),
      'project_id': projectId,
      'order_index': orderIndex,
      'content': content,
    };
  }

  factory Segment.fromJson(Map<String, dynamic> json) {
    const modelName = 'Segment';
    return Segment(
      metadata: EntityMetadata.fromJson(json, modelName: modelName),
      projectId: readRequiredString(json, 'project_id', modelName),
      orderIndex: readRequiredInt(json, 'order_index', modelName),
      content: readRequiredString(json, 'content', modelName),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Segment &&
        metadata == other.metadata &&
        projectId == other.projectId &&
        orderIndex == other.orderIndex &&
        content == other.content;
  }

  @override
  int get hashCode => Object.hash(metadata, projectId, orderIndex, content);
}
