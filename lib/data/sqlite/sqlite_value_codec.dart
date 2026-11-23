import 'dart:convert';

import '../../core/errors/data_exceptions.dart';
import '../../domain/characters/character_card.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_image.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/chat/chat_persona.dart';
import '../../domain/chat/chat_preset_message.dart';
import '../../domain/chat/chat_message_role.dart';
import '../../domain/chat/chat_session.dart';
import '../../domain/chat/chat_memory_entry.dart';
import '../../domain/chat/conversation_summary.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/memory/memory_generation_status.dart';
import '../../domain/memory/novel_summary_chunk.dart';
import '../../domain/memory/story_memory_digest.dart';
import '../../domain/outline/outline_node.dart';
import '../../domain/projects/project.dart';
import '../../domain/segments/segment.dart';
import '../../domain/segments/segment_revision.dart';
import '../../domain/world/world_card.dart';

typedef SqlRow = Map<String, Object?>;

Map<String, Object?> metadataToSql(EntityMetadata metadata) {
  return {
    'id': metadata.id,
    'created_at': dateTimeToJson(metadata.createdAt),
    'updated_at': dateTimeToJson(metadata.updatedAt),
    'revision': metadata.revision,
    'deleted_at': metadata.deletedAt == null
        ? null
        : dateTimeToJson(metadata.deletedAt!),
  };
}

EntityMetadata metadataFromSql(SqlRow row, String modelName) {
  return EntityMetadata(
    id: _requiredString(row, 'id', modelName),
    createdAt: _requiredDateTime(row, 'created_at', modelName),
    updatedAt: _requiredDateTime(row, 'updated_at', modelName),
    revision: _requiredInt(row, 'revision', modelName),
    deletedAt: _optionalDateTime(row, 'deleted_at', modelName),
  );
}

Map<String, Object?> projectToSql(Project project) {
  return {
    ...metadataToSql(project.metadata),
    'title': project.title,
    'description': project.description,
    'system_prompt': project.systemPrompt,
    'ai_provider_config_id': project.aiProviderConfigId,
    'ai_model': project.aiModel,
  };
}

Project projectFromSql(SqlRow row) {
  const modelName = 'Project';
  return Project(
    metadata: metadataFromSql(row, modelName),
    title: _requiredString(row, 'title', modelName),
    description: _requiredString(row, 'description', modelName),
    systemPrompt: _requiredString(row, 'system_prompt', modelName),
    aiProviderConfigId: _optionalString(
      row,
      'ai_provider_config_id',
      modelName,
    ),
    aiModel: _optionalString(row, 'ai_model', modelName),
  );
}

Map<String, Object?> outlineNodeToSql(OutlineNode node) {
  return {
    ...metadataToSql(node.metadata),
    'project_id': node.projectId,
    'title': node.title,
    'summary': node.summary,
    'order_index': node.orderIndex,
    'status': node.status.jsonValue,
  };
}

OutlineNode outlineNodeFromSql(SqlRow row) {
  const modelName = 'OutlineNode';
  return OutlineNode(
    metadata: metadataFromSql(row, modelName),
    projectId: _requiredString(row, 'project_id', modelName),
    title: _requiredString(row, 'title', modelName),
    summary: _requiredString(row, 'summary', modelName),
    orderIndex: _requiredInt(row, 'order_index', modelName),
    status: OutlineNodeStatus.fromJson(
      _requiredString(row, 'status', modelName),
    ),
  );
}

Map<String, Object?> segmentToSql(Segment segment) {
  return {
    ...metadataToSql(segment.metadata),
    'project_id': segment.projectId,
    'order_index': segment.orderIndex,
    'content': segment.content,
  };
}

Segment segmentFromSql(SqlRow row) {
  const modelName = 'Segment';
  return Segment(
    metadata: metadataFromSql(row, modelName),
    projectId: _requiredString(row, 'project_id', modelName),
    orderIndex: _requiredInt(row, 'order_index', modelName),
    content: _requiredString(row, 'content', modelName),
  );
}

Map<String, Object?> segmentRevisionToSql(SegmentRevision revision) {
  return {
    ...metadataToSql(revision.metadata),
    'project_id': revision.projectId,
    'segment_id': revision.segmentId,
    'revision_number': revision.revisionNumber,
    'content': revision.content,
    'note': revision.note,
    'user_instruction': revision.userInstruction,
    'mode': revision.mode,
  };
}

SegmentRevision segmentRevisionFromSql(SqlRow row) {
  const modelName = 'SegmentRevision';
  return SegmentRevision(
    metadata: metadataFromSql(row, modelName),
    projectId: _requiredString(row, 'project_id', modelName),
    segmentId: _requiredString(row, 'segment_id', modelName),
    revisionNumber: _requiredInt(row, 'revision_number', modelName),
    content: _requiredString(row, 'content', modelName),
    note: _requiredString(row, 'note', modelName),
    userInstruction: _requiredString(row, 'user_instruction', modelName),
    mode: _requiredString(row, 'mode', modelName),
  );
}

Map<String, Object?> characterCardToSql(CharacterCard character) {
  return {
    ...metadataToSql(character.metadata),
    'project_id': character.projectId,
    'name': character.name,
    'content': character.content,
    'mode': character.mode?.name,
    'source_work_title': character.sourceWorkTitle,
    'source_character_name': character.sourceCharacterName,
    'source_version_hint': character.sourceVersionHint,
    'fanfic_adaptation_notes': character.fanficAdaptationNotes,
    'original_idea': character.originalIdea,
    'avatar_reference': character.avatarReference,
    'source_format': character.sourceFormat,
    'compatibility_payload_id': character.compatibilityPayloadId,
    'sort_order': character.sortOrder,
  };
}

CharacterCard characterCardFromSql(SqlRow row) {
  const modelName = 'CharacterCard';
  return CharacterCard(
    metadata: metadataFromSql(row, modelName),
    projectId: _requiredString(row, 'project_id', modelName),
    name: _requiredString(row, 'name', modelName),
    content: _requiredString(row, 'content', modelName),
    mode: switch (row['mode']) {
      'fanfic' => CharacterCardMode.fanfic,
      'original' => CharacterCardMode.original,
      _ => null,
    },
    sourceWorkTitle: _optionalString(row, 'source_work_title', modelName) ?? '',
    sourceCharacterName:
        _optionalString(row, 'source_character_name', modelName) ?? '',
    sourceVersionHint:
        _optionalString(row, 'source_version_hint', modelName) ?? '',
    fanficAdaptationNotes:
        _optionalString(row, 'fanfic_adaptation_notes', modelName) ?? '',
    originalIdea: _optionalString(row, 'original_idea', modelName) ?? '',
    avatarReference: _optionalString(row, 'avatar_reference', modelName),
    sourceFormat: _optionalString(row, 'source_format', modelName) ?? '',
    compatibilityPayloadId: _optionalString(
      row,
      'compatibility_payload_id',
      modelName,
    ),
    sortOrder: _requiredInt(row, 'sort_order', modelName),
  );
}

Map<String, Object?> worldCardToSql(WorldCard card) {
  return {
    ...metadataToSql(card.metadata),
    'project_id': card.projectId,
    'title': card.title,
    'content': card.content,
    'sort_order': card.sortOrder,
  };
}

WorldCard worldCardFromSql(SqlRow row) {
  const modelName = 'WorldCard';
  return WorldCard(
    metadata: metadataFromSql(row, modelName),
    projectId: _requiredString(row, 'project_id', modelName),
    title: _requiredString(row, 'title', modelName),
    content: _requiredString(row, 'content', modelName),
    sortOrder: _requiredInt(row, 'sort_order', modelName),
  );
}

Map<String, Object?> chatSessionToSql(ChatSession session) {
  return {
    ...metadataToSql(session.metadata),
    'project_id': session.projectId,
    'character_id': session.characterId,
    'persona_id': session.personaId,
    'ai_provider_config_id': session.aiProviderConfigId,
    'ai_model': session.aiModel,
    'title': session.title,
  };
}

ChatSession chatSessionFromSql(SqlRow row) {
  const modelName = 'ChatSession';
  return ChatSession(
    metadata: metadataFromSql(row, modelName),
    projectId: _optionalString(row, 'project_id', modelName),
    characterId: _optionalString(row, 'character_id', modelName),
    personaId: _optionalString(row, 'persona_id', modelName),
    aiProviderConfigId: _optionalString(
      row,
      'ai_provider_config_id',
      modelName,
    ),
    aiModel: _optionalString(row, 'ai_model', modelName),
    title: _requiredString(row, 'title', modelName),
  );
}

Map<String, Object?> chatPersonaToSql(ChatPersona persona) {
  return {
    ...metadataToSql(persona.metadata),
    'name': persona.name,
    'persona_prompt': persona.personaPrompt,
    'preset_messages_json': jsonEncode(
      persona.presetMessages.map((pair) => pair.toJson()).toList(),
    ),
    'avatar_reference': persona.avatarReference,
    'description_mode': persona.descriptionMode.jsonValue,
    'short_description': persona.shortDescription,
    'speaking_style': persona.speakingStyle,
    'core_identity': persona.coreIdentity,
    'personality': persona.personality,
    'background': persona.background,
    'relationship_to_user': persona.relationshipToUser,
    'behavior_habits': persona.behaviorHabits,
    'preferences': persona.preferences,
    'scenario': persona.scenario,
    'notes': persona.notes,
    'auto_memory_enabled': persona.autoMemoryEnabled ? 1 : 0,
    'use_long_term_memory': persona.useLongTermMemory ? 1 : 0,
  };
}

ChatPersona chatPersonaFromSql(SqlRow row) {
  const modelName = 'ChatPersona';
  return ChatPersona(
    metadata: metadataFromSql(row, modelName),
    name: _requiredString(row, 'name', modelName),
    personaPrompt: _optionalString(row, 'persona_prompt', modelName),
    presetMessages: ChatPresetMessage.parseList(
      jsonDecode((row['preset_messages_json'] as String?) ?? '[]'),
    ),
    avatarReference: _optionalString(row, 'avatar_reference', modelName),
    descriptionMode: ChatPersonaDescriptionMode.fromJson(
      _requiredString(row, 'description_mode', modelName),
    ),
    shortDescription: _requiredString(row, 'short_description', modelName),
    speakingStyle: _requiredString(row, 'speaking_style', modelName),
    coreIdentity: _requiredString(row, 'core_identity', modelName),
    personality: _requiredString(row, 'personality', modelName),
    background: _requiredString(row, 'background', modelName),
    relationshipToUser: _requiredString(row, 'relationship_to_user', modelName),
    behaviorHabits: _requiredString(row, 'behavior_habits', modelName),
    preferences: _requiredString(row, 'preferences', modelName),
    scenario: _requiredString(row, 'scenario', modelName),
    notes: _requiredString(row, 'notes', modelName),
    autoMemoryEnabled: _requiredBool(row, 'auto_memory_enabled', modelName),
    useLongTermMemory: _requiredBool(row, 'use_long_term_memory', modelName),
  );
}

Map<String, Object?> novelSummaryChunkToSql(NovelSummaryChunk chunk) => {
  ...metadataToSql(chunk.metadata),
  'project_id': chunk.projectId,
  'source_start_order': chunk.sourceStartOrder,
  'source_end_order': chunk.sourceEndOrder,
  'source_start_segment_id': chunk.sourceStartSegmentId,
  'source_end_segment_id': chunk.sourceEndSegmentId,
  'summary': chunk.summary,
  'source_fingerprint': chunk.sourceFingerprint,
  'status': chunk.status.jsonValue,
  'provider': chunk.provider,
  'model': chunk.model,
};

NovelSummaryChunk novelSummaryChunkFromSql(SqlRow row) {
  const modelName = 'NovelSummaryChunk';
  return NovelSummaryChunk(
    metadata: metadataFromSql(row, modelName),
    projectId: _requiredString(row, 'project_id', modelName),
    sourceStartOrder: _requiredInt(row, 'source_start_order', modelName),
    sourceEndOrder: _requiredInt(row, 'source_end_order', modelName),
    sourceStartSegmentId: _requiredString(
      row,
      'source_start_segment_id',
      modelName,
    ),
    sourceEndSegmentId: _requiredString(
      row,
      'source_end_segment_id',
      modelName,
    ),
    summary: _requiredString(row, 'summary', modelName),
    sourceFingerprint: _requiredString(row, 'source_fingerprint', modelName),
    status: MemoryGenerationStatus.fromJson(
      _requiredString(row, 'status', modelName),
    ),
    provider: _optionalString(row, 'provider', modelName),
    model: _optionalString(row, 'model', modelName),
  );
}

Map<String, Object?> storyMemoryDigestToSql(StoryMemoryDigest digest) => {
  ...metadataToSql(digest.metadata),
  'project_id': digest.projectId,
  'content': digest.content,
  'source_through_order': digest.sourceThroughOrder,
  'source_fingerprint': digest.sourceFingerprint,
  'status': digest.status.jsonValue,
  'is_user_edited': digest.isUserEdited ? 1 : 0,
  'is_pinned': digest.isPinned ? 1 : 0,
  'provider': digest.provider,
  'model': digest.model,
};

StoryMemoryDigest storyMemoryDigestFromSql(SqlRow row) {
  const modelName = 'StoryMemoryDigest';
  return StoryMemoryDigest(
    metadata: metadataFromSql(row, modelName),
    projectId: _requiredString(row, 'project_id', modelName),
    content: _requiredString(row, 'content', modelName),
    sourceThroughOrder: _requiredInt(row, 'source_through_order', modelName),
    sourceFingerprint: _requiredString(row, 'source_fingerprint', modelName),
    status: MemoryGenerationStatus.fromJson(
      _requiredString(row, 'status', modelName),
    ),
    isUserEdited: _requiredBool(row, 'is_user_edited', modelName),
    isPinned: _requiredBool(row, 'is_pinned', modelName),
    provider: _optionalString(row, 'provider', modelName),
    model: _optionalString(row, 'model', modelName),
  );
}

Map<String, Object?> chatMemoryEntryToSql(ChatMemoryEntry entry) => {
  ...metadataToSql(entry.metadata),
  'persona_id': entry.personaId,
  'session_id': entry.sessionId,
  'category': entry.category.jsonValue,
  'content': entry.content,
  'origin': entry.origin.jsonValue,
  'topic': entry.topic,
  'source_fingerprint': entry.sourceFingerprint,
  'is_pinned': entry.isPinned ? 1 : 0,
  'is_user_edited': entry.isUserEdited ? 1 : 0,
  'source_session_id': entry.sourceSessionId,
  'source_start_message_id': entry.sourceStartMessageId,
  'source_end_message_id': entry.sourceEndMessageId,
};

ChatMemoryEntry chatMemoryEntryFromSql(SqlRow row) {
  const modelName = 'ChatMemoryEntry';
  return ChatMemoryEntry(
    metadata: metadataFromSql(row, modelName),
    personaId: _requiredString(row, 'persona_id', modelName),
    topic: _optionalString(row, 'topic', modelName) ?? '',
    sourceFingerprint:
        _optionalString(row, 'source_fingerprint', modelName) ?? '',
    sessionId: _optionalString(row, 'session_id', modelName),
    category: ChatMemoryCategory.fromJson(
      _requiredString(row, 'category', modelName),
    ),
    content: _requiredString(row, 'content', modelName),
    origin: ChatMemoryOrigin.fromJson(
      _requiredString(row, 'origin', modelName),
    ),
    isPinned: _requiredBool(row, 'is_pinned', modelName),
    isUserEdited: _requiredBool(row, 'is_user_edited', modelName),
    sourceSessionId: _optionalString(row, 'source_session_id', modelName),
    sourceStartMessageId: _optionalString(
      row,
      'source_start_message_id',
      modelName,
    ),
    sourceEndMessageId: _optionalString(
      row,
      'source_end_message_id',
      modelName,
    ),
  );
}

Map<String, Object?> conversationSummaryToSql(ConversationSummary summary) => {
  ...metadataToSql(summary.metadata),
  'session_id': summary.sessionId,
  'source_start_message_id': summary.sourceStartMessageId,
  'source_end_message_id': summary.sourceEndMessageId,
  'summary': summary.summary,
  'source_fingerprint': summary.sourceFingerprint,
  'status': summary.status.jsonValue,
};

ConversationSummary conversationSummaryFromSql(SqlRow row) {
  const modelName = 'ConversationSummary';
  return ConversationSummary(
    metadata: metadataFromSql(row, modelName),
    sessionId: _requiredString(row, 'session_id', modelName),
    sourceStartMessageId: _requiredString(
      row,
      'source_start_message_id',
      modelName,
    ),
    sourceEndMessageId: _requiredString(
      row,
      'source_end_message_id',
      modelName,
    ),
    summary: _requiredString(row, 'summary', modelName),
    sourceFingerprint: _requiredString(row, 'source_fingerprint', modelName),
    status: MemoryGenerationStatus.fromJson(
      _requiredString(row, 'status', modelName),
    ),
  );
}

Map<String, Object?> chatMessageToSql(ChatMessage message) {
  return {
    ...metadataToSql(message.metadata),
    'session_id': message.sessionId,
    'project_id': message.projectId,
    'role': message.role.jsonValue,
    'content': message.content,
    'finish_reason': message.finishReason?.name,
    'image_json': message.image == null
        ? null
        : jsonEncode(message.image!.toJson()),
  };
}

ChatMessage chatMessageFromSql(SqlRow row, {bool deferImageDecoding = false}) {
  const modelName = 'ChatMessage';
  return ChatMessage(
    metadata: metadataFromSql(row, modelName),
    sessionId: _requiredString(row, 'session_id', modelName),
    projectId: _optionalString(row, 'project_id', modelName),
    role: ChatMessageRole.fromJson(_requiredString(row, 'role', modelName)),
    content: _requiredString(row, 'content', modelName),
    finishReason: _optionalFinishReason(row, 'finish_reason', modelName),
    hasImage: row['has_image'] == 1,
    image: row['image_json'] == null
        ? null
        : ChatImage.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(row['image_json'] as String) as Map,
            ),
            deferDecoding: deferImageDecoding,
          ),
  );
}

AiFinishReason? _optionalFinishReason(
  SqlRow row,
  String key,
  String modelName,
) {
  final value = _optionalString(row, key, modelName);
  if (value == null) return null;
  return AiFinishReason.values.firstWhere(
    (item) => item.name == value,
    orElse: () => AiFinishReason.unknown,
  );
}

String _requiredString(SqlRow row, String key, String modelName) {
  final value = row[key];
  if (value is String) {
    return value;
  }
  throw DataFormatException('$modelName.$key must be a string.');
}

String? _optionalString(SqlRow row, String key, String modelName) {
  final value = row[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw DataFormatException('$modelName.$key must be a string when present.');
}

int _requiredInt(SqlRow row, String key, String modelName) {
  final value = row[key];
  if (value is int) {
    return value;
  }
  throw DataFormatException('$modelName.$key must be an integer.');
}

bool _requiredBool(SqlRow row, String key, String modelName) {
  final value = row[key];
  if (value is int && (value == 0 || value == 1)) return value == 1;
  throw DataFormatException('$modelName.$key must be a SQLite boolean.');
}

DateTime _requiredDateTime(SqlRow row, String key, String modelName) {
  final value = _requiredString(row, key, modelName);
  return _parseUtc(value, '$modelName.$key');
}

DateTime? _optionalDateTime(SqlRow row, String key, String modelName) {
  final value = row[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw DataFormatException('$modelName.$key must be a string when present.');
  }
  return _parseUtc(value, '$modelName.$key');
}

DateTime _parseUtc(String value, String fieldName) {
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw DataFormatException('$fieldName must be a valid ISO 8601 date.');
  }
}
