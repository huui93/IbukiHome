import '../common/entity_metadata.dart';

enum ChatMemoryCategory {
  userFact,
  preference,
  relationship,
  sharedEvent,
  ongoingMatter,
  other;

  String get jsonValue => name;

  static ChatMemoryCategory fromJson(String value) {
    return ChatMemoryCategory.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ChatMemoryCategory.other,
    );
  }
}

enum ChatMemoryOrigin {
  auto,
  manual;

  String get jsonValue => name;

  static ChatMemoryOrigin fromJson(String value) {
    return ChatMemoryOrigin.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ChatMemoryOrigin.manual,
    );
  }
}

const Object _unsetMemoryString = Object();

class ChatMemoryEntry {
  const ChatMemoryEntry({
    required this.metadata,
    required this.personaId,
    this.sessionId,
    required this.category,
    required this.content,
    required this.origin,
    this.isPinned = false,
    this.isUserEdited = false,
    this.sourceSessionId,
    this.sourceStartMessageId,
    this.sourceEndMessageId,
    this.topic = '',
    this.sourceFingerprint = '',
  });

  final EntityMetadata metadata;
  final String personaId;
  final String? sessionId;
  final ChatMemoryCategory category;
  final String content;
  final ChatMemoryOrigin origin;
  final bool isPinned;
  final bool isUserEdited;
  final String? sourceSessionId;
  final String? sourceStartMessageId;
  final String? sourceEndMessageId;
  final String topic;
  final String sourceFingerprint;

  String get id => metadata.id;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;
  int get revision => metadata.revision;
  DateTime? get deletedAt => metadata.deletedAt;
  bool get isProtected => isPinned || isUserEdited;

  ChatMemoryEntry copyWith({
    EntityMetadata? metadata,
    ChatMemoryCategory? category,
    String? content,
    ChatMemoryOrigin? origin,
    bool? isPinned,
    bool? isUserEdited,
    String? topic,
    String? sourceFingerprint,
    Object? sourceSessionId = _unsetMemoryString,
    Object? sessionId = _unsetMemoryString,
    Object? sourceStartMessageId = _unsetMemoryString,
    Object? sourceEndMessageId = _unsetMemoryString,
  }) {
    return ChatMemoryEntry(
      metadata: metadata ?? this.metadata,
      personaId: personaId,
      sessionId: sessionId == _unsetMemoryString
          ? this.sessionId
          : sessionId as String?,
      category: category ?? this.category,
      content: content ?? this.content,
      origin: origin ?? this.origin,
      isPinned: isPinned ?? this.isPinned,
      isUserEdited: isUserEdited ?? this.isUserEdited,
      topic: topic ?? this.topic,
      sourceFingerprint: sourceFingerprint ?? this.sourceFingerprint,
      sourceSessionId: sourceSessionId == _unsetMemoryString
          ? this.sourceSessionId
          : sourceSessionId as String?,
      sourceStartMessageId: sourceStartMessageId == _unsetMemoryString
          ? this.sourceStartMessageId
          : sourceStartMessageId as String?,
      sourceEndMessageId: sourceEndMessageId == _unsetMemoryString
          ? this.sourceEndMessageId
          : sourceEndMessageId as String?,
    );
  }
}
