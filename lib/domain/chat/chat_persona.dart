import '../common/entity_metadata.dart';
import 'chat_preset_message.dart';

enum ChatPersonaDescriptionMode {
  simple,
  detailed;

  String get jsonValue => name;

  static ChatPersonaDescriptionMode fromJson(String value) {
    return ChatPersonaDescriptionMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ChatPersonaDescriptionMode.simple,
    );
  }
}

const Object _unsetAvatarReference = Object();

class ChatPersona {
  const ChatPersona({
    required this.metadata,
    required this.name,
    required this.descriptionMode,
    required this.shortDescription,
    required this.speakingStyle,
    this.avatarReference,
    this.personaPrompt,
    this.presetMessages = const [],
    this.coreIdentity = '',
    this.personality = '',
    this.background = '',
    this.relationshipToUser = '',
    this.behaviorHabits = '',
    this.preferences = '',
    this.scenario = '',
    this.notes = '',
    this.autoMemoryEnabled = true,
    this.useLongTermMemory = true,
  });

  final EntityMetadata metadata;
  final String name;
  final String? personaPrompt;
  final List<ChatPresetMessage> presetMessages;
  final String? avatarReference;
  final ChatPersonaDescriptionMode descriptionMode;
  final String shortDescription;
  final String speakingStyle;
  final String coreIdentity;
  final String personality;
  final String background;
  final String relationshipToUser;
  final String behaviorHabits;
  final String preferences;
  final String scenario;
  final String notes;
  final bool autoMemoryEnabled;
  final bool useLongTermMemory;

  String get id => metadata.id;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;
  int get revision => metadata.revision;
  DateTime? get deletedAt => metadata.deletedAt;
  bool get isDetailed => descriptionMode == ChatPersonaDescriptionMode.detailed;

  /// Old fields remain readable until a user saves the unified editor.
  String get unifiedPrompt =>
      personaPrompt ??
      [
        shortDescription,
        if (speakingStyle.trim().isNotEmpty) '说话方式：$speakingStyle',
        if (coreIdentity.trim().isNotEmpty) '核心身份：$coreIdentity',
        if (personality.trim().isNotEmpty) '性格：$personality',
        if (background.trim().isNotEmpty) '背景：$background',
        if (relationshipToUser.trim().isNotEmpty) '与用户的关系：$relationshipToUser',
        if (behaviorHabits.trim().isNotEmpty) '行为习惯：$behaviorHabits',
        if (preferences.trim().isNotEmpty) '喜好：$preferences',
        if (scenario.trim().isNotEmpty) '情境：$scenario',
        if (notes.trim().isNotEmpty) '补充：$notes',
      ].where((text) => text.trim().isNotEmpty).join('\n\n');

  ChatPersona copyWith({
    EntityMetadata? metadata,
    String? name,
    Object? personaPrompt = _unsetAvatarReference,
    List<ChatPresetMessage>? presetMessages,
    Object? avatarReference = _unsetAvatarReference,
    ChatPersonaDescriptionMode? descriptionMode,
    String? shortDescription,
    String? speakingStyle,
    String? coreIdentity,
    String? personality,
    String? background,
    String? relationshipToUser,
    String? behaviorHabits,
    String? preferences,
    String? scenario,
    String? notes,
    bool? autoMemoryEnabled,
    bool? useLongTermMemory,
  }) {
    return ChatPersona(
      metadata: metadata ?? this.metadata,
      name: name ?? this.name,
      personaPrompt: personaPrompt == _unsetAvatarReference
          ? this.personaPrompt
          : personaPrompt as String?,
      presetMessages: presetMessages ?? this.presetMessages,
      avatarReference: avatarReference == _unsetAvatarReference
          ? this.avatarReference
          : avatarReference as String?,
      descriptionMode: descriptionMode ?? this.descriptionMode,
      shortDescription: shortDescription ?? this.shortDescription,
      speakingStyle: speakingStyle ?? this.speakingStyle,
      coreIdentity: coreIdentity ?? this.coreIdentity,
      personality: personality ?? this.personality,
      background: background ?? this.background,
      relationshipToUser: relationshipToUser ?? this.relationshipToUser,
      behaviorHabits: behaviorHabits ?? this.behaviorHabits,
      preferences: preferences ?? this.preferences,
      scenario: scenario ?? this.scenario,
      notes: notes ?? this.notes,
      autoMemoryEnabled: autoMemoryEnabled ?? this.autoMemoryEnabled,
      useLongTermMemory: useLongTermMemory ?? this.useLongTermMemory,
    );
  }

  Map<String, Object?> toJson() => {
    ...metadata.toJson(),
    'name': name,
    'persona_prompt': personaPrompt,
    'preset_messages': presetMessages
        .map((pair) => pair.toJson())
        .toList(growable: false),
    'avatar_reference': avatarReference,
    'description_mode': descriptionMode.jsonValue,
    'short_description': shortDescription,
    'speaking_style': speakingStyle,
    'core_identity': coreIdentity,
    'personality': personality,
    'background': background,
    'relationship_to_user': relationshipToUser,
    'behavior_habits': behaviorHabits,
    'preferences': preferences,
    'scenario': scenario,
    'notes': notes,
    'auto_memory_enabled': autoMemoryEnabled,
    'use_long_term_memory': useLongTermMemory,
  };

  factory ChatPersona.fromJson(Map<String, dynamic> json) {
    const modelName = 'ChatPersona';
    return ChatPersona(
      metadata: EntityMetadata.fromJson(json, modelName: modelName),
      name: readRequiredString(json, 'name', modelName),
      personaPrompt: readOptionalNullableString(
        json,
        'persona_prompt',
        modelName,
      ),
      presetMessages: ChatPresetMessage.parseList(json['preset_messages']),
      avatarReference: readOptionalNullableString(
        json,
        'avatar_reference',
        modelName,
      ),
      descriptionMode: ChatPersonaDescriptionMode.fromJson(
        readOptionalString(
          json,
          'description_mode',
          modelName,
          defaultValue: 'simple',
        ),
      ),
      shortDescription: readOptionalString(
        json,
        'short_description',
        modelName,
      ),
      speakingStyle: readOptionalString(json, 'speaking_style', modelName),
      coreIdentity: readOptionalString(json, 'core_identity', modelName),
      personality: readOptionalString(json, 'personality', modelName),
      background: readOptionalString(json, 'background', modelName),
      relationshipToUser: readOptionalString(
        json,
        'relationship_to_user',
        modelName,
      ),
      behaviorHabits: readOptionalString(json, 'behavior_habits', modelName),
      preferences: readOptionalString(json, 'preferences', modelName),
      scenario: readOptionalString(json, 'scenario', modelName),
      notes: readOptionalString(json, 'notes', modelName),
      autoMemoryEnabled: readOptionalBool(
        json,
        'auto_memory_enabled',
        modelName,
        defaultValue: true,
      ),
      useLongTermMemory: readOptionalBool(
        json,
        'use_long_term_memory',
        modelName,
        defaultValue: true,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatPersona &&
      metadata == other.metadata &&
      name == other.name &&
      personaPrompt == other.personaPrompt &&
      presetMessages.length == other.presetMessages.length &&
      presetMessages.indexed.every(
        (entry) => entry.$2 == other.presetMessages[entry.$1],
      ) &&
      avatarReference == other.avatarReference &&
      descriptionMode == other.descriptionMode &&
      shortDescription == other.shortDescription &&
      speakingStyle == other.speakingStyle &&
      coreIdentity == other.coreIdentity &&
      personality == other.personality &&
      background == other.background &&
      relationshipToUser == other.relationshipToUser &&
      behaviorHabits == other.behaviorHabits &&
      preferences == other.preferences &&
      scenario == other.scenario &&
      notes == other.notes &&
      autoMemoryEnabled == other.autoMemoryEnabled &&
      useLongTermMemory == other.useLongTermMemory;

  @override
  int get hashCode => Object.hash(
    metadata,
    name,
    personaPrompt,
    Object.hashAll(presetMessages),
    avatarReference,
    descriptionMode,
    shortDescription,
    speakingStyle,
    coreIdentity,
    personality,
    background,
    relationshipToUser,
    behaviorHabits,
    preferences,
    scenario,
    notes,
    autoMemoryEnabled,
    useLongTermMemory,
  );
}
