import '../common/entity_metadata.dart';

enum OutlineNodeStatus {
  planned,
  current,
  completed;

  String get jsonValue => name;

  static OutlineNodeStatus fromJson(String value) {
    return OutlineNodeStatus.values.firstWhere(
      (item) => item.jsonValue == value,
      orElse: () => throw const FormatException('Invalid outline status.'),
    );
  }
}

class OutlineNode {
  const OutlineNode({
    required this.metadata,
    required this.projectId,
    required this.title,
    required this.summary,
    required this.orderIndex,
    required this.status,
  });

  final EntityMetadata metadata;
  final String projectId;
  final String title;
  final String summary;
  final int orderIndex;
  final OutlineNodeStatus status;

  String get id => metadata.id;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;
  int get revision => metadata.revision;
  DateTime? get deletedAt => metadata.deletedAt;

  OutlineNode copyWith({
    EntityMetadata? metadata,
    String? projectId,
    String? title,
    String? summary,
    int? orderIndex,
    OutlineNodeStatus? status,
  }) {
    return OutlineNode(
      metadata: metadata ?? this.metadata,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      orderIndex: orderIndex ?? this.orderIndex,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toJson() {
    return {
      ...metadata.toJson(),
      'project_id': projectId,
      'title': title,
      'summary': summary,
      'order_index': orderIndex,
      'status': status.jsonValue,
    };
  }

  factory OutlineNode.fromJson(Map<String, dynamic> json) {
    const modelName = 'OutlineNode';
    return OutlineNode(
      metadata: EntityMetadata.fromJson(json, modelName: modelName),
      projectId: readRequiredString(json, 'project_id', modelName),
      title: readRequiredString(json, 'title', modelName),
      summary: readOptionalString(json, 'summary', modelName),
      orderIndex: readRequiredInt(json, 'order_index', modelName),
      status: OutlineNodeStatus.fromJson(
        readRequiredString(json, 'status', modelName),
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OutlineNode &&
        metadata == other.metadata &&
        projectId == other.projectId &&
        title == other.title &&
        summary == other.summary &&
        orderIndex == other.orderIndex &&
        status == other.status;
  }

  @override
  int get hashCode {
    return Object.hash(metadata, projectId, title, summary, orderIndex, status);
  }
}
