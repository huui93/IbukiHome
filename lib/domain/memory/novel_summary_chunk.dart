import '../common/entity_metadata.dart';
import 'memory_generation_status.dart';

class NovelSummaryChunk {
  const NovelSummaryChunk({
    required this.metadata,
    required this.projectId,
    required this.sourceStartOrder,
    required this.sourceEndOrder,
    required this.sourceStartSegmentId,
    required this.sourceEndSegmentId,
    required this.summary,
    required this.sourceFingerprint,
    required this.status,
    this.provider,
    this.model,
  });

  final EntityMetadata metadata;
  final String projectId;
  final int sourceStartOrder;
  final int sourceEndOrder;
  final String sourceStartSegmentId;
  final String sourceEndSegmentId;
  final String summary;
  final String sourceFingerprint;
  final MemoryGenerationStatus status;
  final String? provider;
  final String? model;

  String get id => metadata.id;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;
  int get revision => metadata.revision;

  NovelSummaryChunk copyWith({
    EntityMetadata? metadata,
    String? summary,
    String? sourceFingerprint,
    MemoryGenerationStatus? status,
    String? provider,
    String? model,
  }) {
    return NovelSummaryChunk(
      metadata: metadata ?? this.metadata,
      projectId: projectId,
      sourceStartOrder: sourceStartOrder,
      sourceEndOrder: sourceEndOrder,
      sourceStartSegmentId: sourceStartSegmentId,
      sourceEndSegmentId: sourceEndSegmentId,
      summary: summary ?? this.summary,
      sourceFingerprint: sourceFingerprint ?? this.sourceFingerprint,
      status: status ?? this.status,
      provider: provider ?? this.provider,
      model: model ?? this.model,
    );
  }
}
