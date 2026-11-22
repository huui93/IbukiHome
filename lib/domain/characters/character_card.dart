import '../common/entity_metadata.dart';

enum CharacterCardMode { fanfic, original }

class CharacterCard {
  const CharacterCard({
    required this.metadata,
    required this.projectId,
    required this.name,
    required this.content,
    required this.sortOrder,
    this.mode,
    this.sourceWorkTitle = '',
    this.sourceCharacterName = '',
    this.sourceVersionHint = '',
    this.fanficAdaptationNotes = '',
    this.originalIdea = '',
    this.avatarReference,
    this.sourceFormat = '',
    this.compatibilityPayloadId,
  });

  /// Shared entity metadata used by all storage backends.
  final EntityMetadata metadata;

  /// Owning project identifier.
  final String projectId;

  /// Character display name.
  final String name;

  /// Consolidated character-card text compatible with desktop stable fields.
  final String content;

  /// Stable display order within a project.
  final int sortOrder;

  /// Null means a legacy card whose type has not been chosen by the user yet.
  final CharacterCardMode? mode;

  /// Lightweight source identity for fanfic cards. Empty for original/legacy.
  final String sourceWorkTitle;
  final String sourceCharacterName;
  final String sourceVersionHint;

  /// Author-owned changes that always take precedence over canon references.
  final String fanficAdaptationNotes;

  /// The user's starting idea for an original character.
  final String originalIdea;

  /// Optional local image used by imported cards. Core-created cards keep null.
  final String? avatarReference;

  /// Lightweight provenance only. Large compatibility data lives separately.
  final String sourceFormat;
  final String? compatibilityPayloadId;

  String get id => metadata.id;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;
  int get revision => metadata.revision;
  DateTime? get deletedAt => metadata.deletedAt;

  CharacterCard copyWith({
    EntityMetadata? metadata,
    String? projectId,
    String? name,
    String? content,
    int? sortOrder,
    CharacterCardMode? mode,
    String? sourceWorkTitle,
    String? sourceCharacterName,
    String? sourceVersionHint,
    String? fanficAdaptationNotes,
    String? originalIdea,
    Object? avatarReference = _unsetCharacterValue,
    String? sourceFormat,
    Object? compatibilityPayloadId = _unsetCharacterValue,
  }) {
    return CharacterCard(
      metadata: metadata ?? this.metadata,
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      content: content ?? this.content,
      sortOrder: sortOrder ?? this.sortOrder,
      mode: mode ?? this.mode,
      sourceWorkTitle: sourceWorkTitle ?? this.sourceWorkTitle,
      sourceCharacterName: sourceCharacterName ?? this.sourceCharacterName,
      sourceVersionHint: sourceVersionHint ?? this.sourceVersionHint,
      fanficAdaptationNotes:
          fanficAdaptationNotes ?? this.fanficAdaptationNotes,
      originalIdea: originalIdea ?? this.originalIdea,
      avatarReference: avatarReference == _unsetCharacterValue
          ? this.avatarReference
          : avatarReference as String?,
      sourceFormat: sourceFormat ?? this.sourceFormat,
      compatibilityPayloadId: compatibilityPayloadId == _unsetCharacterValue
          ? this.compatibilityPayloadId
          : compatibilityPayloadId as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      ...metadata.toJson(),
      'project_id': projectId,
      'name': name,
      'content': content,
      'sort_order': sortOrder,
      'mode': mode?.name,
      'source_work_title': sourceWorkTitle,
      'source_character_name': sourceCharacterName,
      'source_version_hint': sourceVersionHint,
      'fanfic_adaptation_notes': fanficAdaptationNotes,
      'original_idea': originalIdea,
      'avatar_reference': avatarReference,
      'source_format': sourceFormat,
      'compatibility_payload_id': compatibilityPayloadId,
    };
  }

  factory CharacterCard.fromJson(Map<String, dynamic> json) {
    const modelName = 'CharacterCard';
    return CharacterCard(
      metadata: EntityMetadata.fromJson(json, modelName: modelName),
      projectId: readRequiredString(json, 'project_id', modelName),
      name: readRequiredString(json, 'name', modelName),
      content: readOptionalString(json, 'content', modelName),
      sortOrder: readRequiredInt(json, 'sort_order', modelName),
      mode: _modeFromJson(json['mode']),
      sourceWorkTitle: readOptionalString(json, 'source_work_title', modelName),
      sourceCharacterName: readOptionalString(
        json,
        'source_character_name',
        modelName,
      ),
      sourceVersionHint: readOptionalString(
        json,
        'source_version_hint',
        modelName,
      ),
      fanficAdaptationNotes: readOptionalString(
        json,
        'fanfic_adaptation_notes',
        modelName,
      ),
      originalIdea: readOptionalString(json, 'original_idea', modelName),
      avatarReference: _nullableString(json['avatar_reference']),
      sourceFormat: readOptionalString(json, 'source_format', modelName),
      compatibilityPayloadId: _nullableString(json['compatibility_payload_id']),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CharacterCard &&
        metadata == other.metadata &&
        projectId == other.projectId &&
        name == other.name &&
        content == other.content &&
        sortOrder == other.sortOrder &&
        mode == other.mode &&
        sourceWorkTitle == other.sourceWorkTitle &&
        sourceCharacterName == other.sourceCharacterName &&
        sourceVersionHint == other.sourceVersionHint &&
        fanficAdaptationNotes == other.fanficAdaptationNotes &&
        originalIdea == other.originalIdea &&
        avatarReference == other.avatarReference &&
        sourceFormat == other.sourceFormat &&
        compatibilityPayloadId == other.compatibilityPayloadId;
  }

  @override
  int get hashCode => Object.hash(
    metadata,
    projectId,
    name,
    content,
    sortOrder,
    mode,
    sourceWorkTitle,
    sourceCharacterName,
    sourceVersionHint,
    fanficAdaptationNotes,
    originalIdea,
    avatarReference,
    sourceFormat,
    compatibilityPayloadId,
  );
}

const Object _unsetCharacterValue = Object();

String? _nullableString(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value;
}

CharacterCardMode? _modeFromJson(Object? value) => switch (value) {
  'fanfic' => CharacterCardMode.fanfic,
  'original' => CharacterCardMode.original,
  _ => null,
};
