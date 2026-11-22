import '../common/entity_metadata.dart';

const Object _unsetProjectAi = Object();

class Project {
  const Project({
    required this.metadata,
    required this.title,
    required this.description,
    this.systemPrompt = '',
    this.aiProviderConfigId,
    this.aiModel,
  });

  /// Shared entity metadata used by all storage backends.
  final EntityMetadata metadata;

  /// Human-readable project title.
  final String title;

  /// Stable project summary or direction text.
  final String description;

  /// Long-lived novel-generation guidance for this project only.
  final String systemPrompt;
  final String? aiProviderConfigId;
  final String? aiModel;

  String get id => metadata.id;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;
  int get revision => metadata.revision;
  DateTime? get deletedAt => metadata.deletedAt;

  Project copyWith({
    EntityMetadata? metadata,
    String? title,
    String? description,
    String? systemPrompt,
    Object? aiProviderConfigId = _unsetProjectAi,
    Object? aiModel = _unsetProjectAi,
  }) {
    return Project(
      metadata: metadata ?? this.metadata,
      title: title ?? this.title,
      description: description ?? this.description,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      aiProviderConfigId: aiProviderConfigId == _unsetProjectAi
          ? this.aiProviderConfigId
          : aiProviderConfigId as String?,
      aiModel: aiModel == _unsetProjectAi ? this.aiModel : aiModel as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      ...metadata.toJson(),
      'title': title,
      'description': description,
      'system_prompt': systemPrompt,
      'ai_provider_config_id': aiProviderConfigId,
      'ai_model': aiModel,
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    const modelName = 'Project';
    return Project(
      metadata: EntityMetadata.fromJson(json, modelName: modelName),
      title: readRequiredString(json, 'title', modelName),
      description: readOptionalString(json, 'description', modelName),
      systemPrompt: readOptionalString(json, 'system_prompt', modelName),
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
    return other is Project &&
        metadata == other.metadata &&
        title == other.title &&
        description == other.description &&
        systemPrompt == other.systemPrompt &&
        aiProviderConfigId == other.aiProviderConfigId &&
        aiModel == other.aiModel;
  }

  @override
  int get hashCode => Object.hash(
    metadata,
    title,
    description,
    systemPrompt,
    aiProviderConfigId,
    aiModel,
  );
}
