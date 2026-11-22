import '../common/entity_metadata.dart';
import '../memory/memory_generation_status.dart';

class ConversationSummary {
  const ConversationSummary({
    required this.metadata,
    required this.sessionId,
    required this.sourceStartMessageId,
    required this.sourceEndMessageId,
    required this.summary,
    required this.sourceFingerprint,
    required this.status,
  });

  final EntityMetadata metadata;
  final String sessionId;
  final String sourceStartMessageId;
  final String sourceEndMessageId;
  final String summary;
  final String sourceFingerprint;
  final MemoryGenerationStatus status;

  String get id => metadata.id;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;
  int get revision => metadata.revision;

  ConversationSummary copyWith({
    EntityMetadata? metadata,
    String? summary,
    String? sourceFingerprint,
    MemoryGenerationStatus? status,
  }) {
    return ConversationSummary(
      metadata: metadata ?? this.metadata,
      sessionId: sessionId,
      sourceStartMessageId: sourceStartMessageId,
      sourceEndMessageId: sourceEndMessageId,
      summary: summary ?? this.summary,
      sourceFingerprint: sourceFingerprint ?? this.sourceFingerprint,
      status: status ?? this.status,
    );
  }
}
