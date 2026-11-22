import '../common/entity_metadata.dart';

const Object _unsetProjectId = Object();
const Object _unsetCharacterId = Object();
const Object _unsetPersonaId = Object();
const Object _unsetSessionAi = Object();

class ChatSession {
  const ChatSession({
    required this.metadata,
    required this.projectId,
    required this.title,
    this.characterId,
    this.personaId,
    this.aiProviderConfigId,
    this.aiModel,
  });

  /// Shared entity metadata used by all storage backends.
  final EntityMetadata metadata;

  /// Optional owning project. Null means an unbound general conversation.
  final String? projectId;

  /// Optional primary character used by the conversation UI.
  ///
  /// Null preserves legacy sessions that predate character-based chat.
  final String? characterId;

  /// Primary chat persona. New conversations use this independent entity.
  /// Character ID remains only for migrated legacy compatibility.
  final String? personaId;
  final String? aiProviderConfigId;
  final String? aiModel;

  /// Conversation title.
  final String title;

  String get id => metadata.id;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;
  int get revision => metadata.revision;
  DateTime? get deletedAt => metadata.deletedAt;

  ChatSession copyWith({
    EntityMetadata? metadata,
    Object? projectId = _unsetProjectId,
    Object? characterId = _unsetCharacterId,
    Object? personaId = _unsetPersonaId,
    String? title,
    Object? aiProviderConfigId = _unsetSessionAi,
    Object? aiModel = _unsetSessionAi,
  }) {
    return ChatSession(
      metadata: metadata ?? this.metadata,
      projectId: projectId == _unsetProjectId
          ? this.projectId
          : projectId as String?,
      characterId: characterId == _unsetCharacterId
          ? this.characterId
          : characterId as String?,
      personaId: personaId == _unsetPersonaId
          ? this.personaId
          : personaId as String?,
      title: title ?? this.title,
      aiProviderConfigId: aiProviderConfigId == _unsetSessionAi
          ? this.aiProviderConfigId
          : aiProviderConfigId as String?,
      aiModel: aiModel == _unsetSessionAi ? this.aiModel : aiModel as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      ...metadata.toJson(),
      'project_id': projectId,
      'character_id': characterId,
      'persona_id': personaId,
      'title': title,
      'ai_provider_config_id': aiProviderConfigId,
      'ai_model': aiModel,
    };
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    const modelName = 'ChatSession';
    return ChatSession(
      metadata: EntityMetadata.fromJson(json, modelName: modelName),
      projectId: readOptionalNullableString(json, 'project_id', modelName),
      characterId: readOptionalNullableString(json, 'character_id', modelName),
      personaId: readOptionalNullableString(json, 'persona_id', modelName),
      title: readRequiredString(json, 'title', modelName),
      aiProviderConfigId: readOptionalNullableString(
        json,
        'ai_provider_config_id',
        modelName,
      ),
      aiModel: readOptionalNullableString(json, 'ai_model', modelName),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChatSession &&
        metadata == other.metadata &&
        projectId == other.projectId &&
        characterId == other.characterId &&
        personaId == other.personaId &&
        title == other.title &&
        aiProviderConfigId == other.aiProviderConfigId &&
        aiModel == other.aiModel;
  }

  @override
  int get hashCode => Object.hash(
    metadata,
    projectId,
    characterId,
    personaId,
    title,
    aiProviderConfigId,
    aiModel,
  );
}
