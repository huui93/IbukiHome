import '../common/entity_metadata.dart';
import '../ai/ai_generation.dart';
import 'chat_message_role.dart';
import 'chat_image.dart';

const Object _unsetFinishReason = Object();

const Object _unsetProjectId = Object();

class ChatMessage {
  const ChatMessage({
    required this.metadata,
    required this.sessionId,
    required this.projectId,
    required this.role,
    required this.content,
    this.finishReason,
    this.image,
  });

  /// Shared entity metadata used by all storage backends.
  final EntityMetadata metadata;

  /// Owning chat-session identifier.
  final String sessionId;

  /// Optional owning project. Null follows the session as an unbound chat.
  final String? projectId;

  /// User, assistant or system message role.
  final ChatMessageRole role;

  /// Plain message content.
  final String content;
  final AiFinishReason? finishReason;
  final ChatImage? image;

  String get id => metadata.id;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;
  int get revision => metadata.revision;
  DateTime? get deletedAt => metadata.deletedAt;

  ChatMessage copyWith({
    EntityMetadata? metadata,
    String? sessionId,
    Object? projectId = _unsetProjectId,
    ChatMessageRole? role,
    String? content,
    ChatImage? image,
    Object? finishReason = _unsetFinishReason,
  }) {
    return ChatMessage(
      metadata: metadata ?? this.metadata,
      sessionId: sessionId ?? this.sessionId,
      projectId: projectId == _unsetProjectId
          ? this.projectId
          : projectId as String?,
      role: role ?? this.role,
      content: content ?? this.content,
      image: image ?? this.image,
      finishReason: finishReason == _unsetFinishReason
          ? this.finishReason
          : finishReason as AiFinishReason?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      ...metadata.toJson(),
      'session_id': sessionId,
      'project_id': projectId,
      'role': role.jsonValue,
      'content': content,
      'finish_reason': finishReason?.name,
      if (image != null) 'image': image!.toJson(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    const modelName = 'ChatMessage';
    return ChatMessage(
      metadata: EntityMetadata.fromJson(json, modelName: modelName),
      sessionId: readRequiredString(json, 'session_id', modelName),
      projectId: readOptionalNullableString(json, 'project_id', modelName),
      role: ChatMessageRole.fromJson(json['role']),
      content: readRequiredString(json, 'content', modelName),
      finishReason: _finishReasonFromJson(json['finish_reason']),
      image: json['image'] == null
          ? null
          : ChatImage.fromJson(Map<String, dynamic>.from(json['image'] as Map)),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChatMessage &&
        metadata == other.metadata &&
        sessionId == other.sessionId &&
        projectId == other.projectId &&
        role == other.role &&
        content == other.content &&
        finishReason == other.finishReason &&
        image == other.image;
  }

  @override
  int get hashCode => Object.hash(
    metadata,
    sessionId,
    projectId,
    role,
    content,
    finishReason,
    image,
  );
}

AiFinishReason? _finishReasonFromJson(Object? value) {
  if (value is! String || value.isEmpty) return null;
  for (final item in AiFinishReason.values) {
    if (item.name == value) return item;
  }
  return AiFinishReason.unknown;
}
