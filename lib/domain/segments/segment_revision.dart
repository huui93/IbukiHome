import '../common/entity_metadata.dart';

class SegmentRevision {
  const SegmentRevision({
    required this.metadata,
    required this.projectId,
    required this.segmentId,
    required this.revisionNumber,
    required this.content,
    required this.note,
    required this.userInstruction,
    required this.mode,
  });

  /// Shared entity metadata used by all storage backends.
  final EntityMetadata metadata;

  /// Owning project identifier.
  final String projectId;

  /// Segment identifier that this revision snapshots.
  final String segmentId;

  /// Segment revision number represented by this snapshot.
  final int revisionNumber;

  /// Historical segment content.
  final String content;

  /// Optional human note for why the revision was created.
  final String note;

  /// Optional instruction that caused the change.
  final String userInstruction;

  /// Operation mode, such as edit, rewrite, restore or insert.
  final String mode;

  String get id => metadata.id;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;
  int get revision => metadata.revision;
  DateTime? get deletedAt => metadata.deletedAt;

  SegmentRevision copyWith({
    EntityMetadata? metadata,
    String? projectId,
    String? segmentId,
    int? revisionNumber,
    String? content,
    String? note,
    String? userInstruction,
    String? mode,
  }) {
    return SegmentRevision(
      metadata: metadata ?? this.metadata,
      projectId: projectId ?? this.projectId,
      segmentId: segmentId ?? this.segmentId,
      revisionNumber: revisionNumber ?? this.revisionNumber,
      content: content ?? this.content,
      note: note ?? this.note,
      userInstruction: userInstruction ?? this.userInstruction,
      mode: mode ?? this.mode,
    );
  }

  Map<String, Object?> toJson() {
    return {
      ...metadata.toJson(),
      'project_id': projectId,
      'segment_id': segmentId,
      'revision_number': revisionNumber,
      'content': content,
      'note': note,
      'user_instruction': userInstruction,
      'mode': mode,
    };
  }

  factory SegmentRevision.fromJson(Map<String, dynamic> json) {
    const modelName = 'SegmentRevision';
    return SegmentRevision(
      metadata: EntityMetadata.fromJson(json, modelName: modelName),
      projectId: readRequiredString(json, 'project_id', modelName),
      segmentId: readRequiredString(json, 'segment_id', modelName),
      revisionNumber: readRequiredInt(json, 'revision_number', modelName),
      content: readRequiredString(json, 'content', modelName),
      note: readOptionalString(json, 'note', modelName),
      userInstruction: readOptionalString(json, 'user_instruction', modelName),
      mode: readOptionalString(json, 'mode', modelName),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SegmentRevision &&
        metadata == other.metadata &&
        projectId == other.projectId &&
        segmentId == other.segmentId &&
        revisionNumber == other.revisionNumber &&
        content == other.content &&
        note == other.note &&
        userInstruction == other.userInstruction &&
        mode == other.mode;
  }

  @override
  int get hashCode => Object.hash(
    metadata,
    projectId,
    segmentId,
    revisionNumber,
    content,
    note,
    userInstruction,
    mode,
  );
}
