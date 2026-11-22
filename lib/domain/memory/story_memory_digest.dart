import '../common/entity_metadata.dart';
import 'memory_generation_status.dart';

class StoryMemoryDigest {
  const StoryMemoryDigest({
    required this.metadata,
    required this.projectId,
    required this.content,
    required this.sourceThroughOrder,
    required this.sourceFingerprint,
    required this.status,
    this.isUserEdited = false,
    this.isPinned = false,
    this.provider,
    this.model,
  });

  final EntityMetadata metadata;
  final String projectId;
  final String content;
  final int sourceThroughOrder;
  final String sourceFingerprint;
  final MemoryGenerationStatus status;
  final bool isUserEdited;
  final bool isPinned;
  final String? provider;
  final String? model;

  String get id => metadata.id;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;
  int get revision => metadata.revision;
  bool get isProtected => isUserEdited || isPinned;

  StoryMemoryDigest copyWith({
    EntityMetadata? metadata,
    String? content,
    int? sourceThroughOrder,
    String? sourceFingerprint,
    MemoryGenerationStatus? status,
    bool? isUserEdited,
    bool? isPinned,
    String? provider,
    String? model,
  }) {
    return StoryMemoryDigest(
      metadata: metadata ?? this.metadata,
      projectId: projectId,
      content: content ?? this.content,
      sourceThroughOrder: sourceThroughOrder ?? this.sourceThroughOrder,
      sourceFingerprint: sourceFingerprint ?? this.sourceFingerprint,
      status: status ?? this.status,
      isUserEdited: isUserEdited ?? this.isUserEdited,
      isPinned: isPinned ?? this.isPinned,
      provider: provider ?? this.provider,
      model: model ?? this.model,
    );
  }
}
