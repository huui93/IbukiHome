import '../common/entity_metadata.dart';

const worldBookLibraryOwnerId = '__ibuki_world_book_library__';

const Object _unsetWorldValue = Object();

abstract class WorldRoleplayEntity {
  const WorldRoleplayEntity({required this.entity, required this.metadata});

  final EntityMetadata entity;
  final Map<String, Object?> metadata;

  String get id => entity.id;
  DateTime get createdAt => entity.createdAt;
  DateTime get updatedAt => entity.updatedAt;
  int get revision => entity.revision;
}

enum WorldSpeakerMode { natural, manual, sequence }

class RoleplayWorld extends WorldRoleplayEntity {
  const RoleplayWorld({
    required super.entity,
    required this.name,
    this.description = '',
    this.defaultSessionId,
    super.metadata = const {},
  });

  final String name;
  final String description;
  final String? defaultSessionId;

  RoleplayWorld copyWith({
    EntityMetadata? entity,
    String? name,
    String? description,
    Object? defaultSessionId = _unsetWorldValue,
    Map<String, Object?>? metadata,
  }) {
    return RoleplayWorld(
      entity: entity ?? this.entity,
      name: name ?? this.name,
      description: description ?? this.description,
      defaultSessionId: defaultSessionId == _unsetWorldValue
          ? this.defaultSessionId
          : defaultSessionId as String?,
      metadata: metadata ?? this.metadata,
    );
  }
}

class WorldSession extends WorldRoleplayEntity {
  const WorldSession({
    required super.entity,
    required this.worldId,
    required this.name,
    this.currentPlayerInstanceId,
    this.currentSceneId,
    this.currentBranchId,
    this.worldTime = '',
    this.aiProviderConfigId,
    this.aiModel,
    this.loreContextBudget = 1800,
    this.speakerMode = WorldSpeakerMode.natural,
    super.metadata = const {},
  });

  final String worldId;
  final String name;
  final String? currentPlayerInstanceId;
  final String? currentSceneId;
  final String? currentBranchId;
  final String worldTime;
  final String? aiProviderConfigId;
  final String? aiModel;
  final int loreContextBudget;
  final WorldSpeakerMode speakerMode;

  WorldSession copyWith({
    EntityMetadata? entity,
    String? worldId,
    String? name,
    Object? currentPlayerInstanceId = _unsetWorldValue,
    Object? currentSceneId = _unsetWorldValue,
    Object? currentBranchId = _unsetWorldValue,
    String? worldTime,
    Object? aiProviderConfigId = _unsetWorldValue,
    Object? aiModel = _unsetWorldValue,
    int? loreContextBudget,
    WorldSpeakerMode? speakerMode,
    Map<String, Object?>? metadata,
  }) {
    return WorldSession(
      entity: entity ?? this.entity,
      worldId: worldId ?? this.worldId,
      name: name ?? this.name,
      currentPlayerInstanceId: currentPlayerInstanceId == _unsetWorldValue
          ? this.currentPlayerInstanceId
          : currentPlayerInstanceId as String?,
      currentSceneId: currentSceneId == _unsetWorldValue
          ? this.currentSceneId
          : currentSceneId as String?,
      currentBranchId: currentBranchId == _unsetWorldValue
          ? this.currentBranchId
          : currentBranchId as String?,
      worldTime: worldTime ?? this.worldTime,
      aiProviderConfigId: aiProviderConfigId == _unsetWorldValue
          ? this.aiProviderConfigId
          : aiProviderConfigId as String?,
      aiModel: aiModel == _unsetWorldValue ? this.aiModel : aiModel as String?,
      loreContextBudget: loreContextBudget ?? this.loreContextBudget,
      speakerMode: speakerMode ?? this.speakerMode,
      metadata: metadata ?? this.metadata,
    );
  }
}

class WorldBook extends WorldRoleplayEntity {
  const WorldBook({
    required super.entity,
    this.worldId,
    required this.name,
    this.isPrimary = false,
    super.metadata = const {},
  });

  final String? worldId;
  final String name;
  final bool isPrimary;

  WorldBook copyWith({
    EntityMetadata? entity,
    Object? worldId = _unsetWorldValue,
    String? name,
    bool? isPrimary,
    Map<String, Object?>? metadata,
  }) {
    return WorldBook(
      entity: entity ?? this.entity,
      worldId: worldId == _unsetWorldValue ? this.worldId : worldId as String?,
      name: name ?? this.name,
      isPrimary: isPrimary ?? this.isPrimary,
      metadata: metadata ?? this.metadata,
    );
  }
}

enum WorldBookOverrideMode { inherit, enabled, disabled }

class WorldWorldBookReference extends WorldRoleplayEntity {
  const WorldWorldBookReference({
    required super.entity,
    required this.worldId,
    required this.worldBookId,
    this.enabled = true,
    this.priority = 0,
    super.metadata = const {},
  });

  final String worldId;
  final String worldBookId;
  final bool enabled;
  final int priority;

  WorldWorldBookReference copyWith({
    EntityMetadata? entity,
    bool? enabled,
    int? priority,
    Map<String, Object?>? metadata,
  }) => WorldWorldBookReference(
    entity: entity ?? this.entity,
    worldId: worldId,
    worldBookId: worldBookId,
    enabled: enabled ?? this.enabled,
    priority: priority ?? this.priority,
    metadata: metadata ?? this.metadata,
  );
}

class WorldSessionWorldBookOverride extends WorldRoleplayEntity {
  const WorldSessionWorldBookOverride({
    required super.entity,
    required this.worldSessionId,
    required this.worldBookId,
    this.mode = WorldBookOverrideMode.inherit,
    this.priority = 0,
    super.metadata = const {},
  });

  final String worldSessionId;
  final String worldBookId;
  final WorldBookOverrideMode mode;
  final int priority;

  WorldSessionWorldBookOverride copyWith({
    EntityMetadata? entity,
    WorldBookOverrideMode? mode,
    int? priority,
    Map<String, Object?>? metadata,
  }) => WorldSessionWorldBookOverride(
    entity: entity ?? this.entity,
    worldSessionId: worldSessionId,
    worldBookId: worldBookId,
    mode: mode ?? this.mode,
    priority: priority ?? this.priority,
    metadata: metadata ?? this.metadata,
  );
}

class EntityWorldBookReference extends WorldRoleplayEntity {
  const EntityWorldBookReference({
    required super.entity,
    required this.entityId,
    required this.worldBookId,
    this.enabled = true,
    this.priority = 0,
    super.metadata = const {},
  });

  final String entityId;
  final String worldBookId;
  final bool enabled;
  final int priority;

  EntityWorldBookReference copyWith({
    EntityMetadata? entity,
    bool? enabled,
    int? priority,
    Map<String, Object?>? metadata,
  }) => EntityWorldBookReference(
    entity: entity ?? this.entity,
    entityId: entityId,
    worldBookId: worldBookId,
    enabled: enabled ?? this.enabled,
    priority: priority ?? this.priority,
    metadata: metadata ?? this.metadata,
  );
}

enum LoreActivationMode { always, keyword, manual }

class LoreEntry extends WorldRoleplayEntity {
  const LoreEntry({
    required super.entity,
    required this.worldBookId,
    required this.title,
    required this.content,
    this.keywords = const [],
    this.secondaryKeywords = const [],
    this.enabled = true,
    this.priority = 0,
    this.activationMode = LoreActivationMode.keyword,
    this.insertionPosition = 'context',
    this.probability = 1,
    this.scope = 'world',
    this.tokenBudgetHint,
    this.sourceWorldCardId,
    super.metadata = const {},
  });

  final String worldBookId;
  final String title;
  final String content;
  final List<String> keywords;
  final List<String> secondaryKeywords;
  final bool enabled;
  final int priority;
  final LoreActivationMode activationMode;
  final String insertionPosition;
  final double probability;
  final String scope;
  final int? tokenBudgetHint;
  final String? sourceWorldCardId;

  bool get isPinned => metadata['pinned'] == true;

  LoreEntry copyWith({
    EntityMetadata? entity,
    String? worldBookId,
    String? title,
    String? content,
    List<String>? keywords,
    List<String>? secondaryKeywords,
    bool? enabled,
    int? priority,
    LoreActivationMode? activationMode,
    String? insertionPosition,
    double? probability,
    String? scope,
    Object? tokenBudgetHint = _unsetWorldValue,
    Object? sourceWorldCardId = _unsetWorldValue,
    Map<String, Object?>? metadata,
  }) {
    return LoreEntry(
      entity: entity ?? this.entity,
      worldBookId: worldBookId ?? this.worldBookId,
      title: title ?? this.title,
      content: content ?? this.content,
      keywords: keywords ?? this.keywords,
      secondaryKeywords: secondaryKeywords ?? this.secondaryKeywords,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      activationMode: activationMode ?? this.activationMode,
      insertionPosition: insertionPosition ?? this.insertionPosition,
      probability: probability ?? this.probability,
      scope: scope ?? this.scope,
      tokenBudgetHint: tokenBudgetHint == _unsetWorldValue
          ? this.tokenBudgetHint
          : tokenBudgetHint as int?,
      sourceWorldCardId: sourceWorldCardId == _unsetWorldValue
          ? this.sourceWorldCardId
          : sourceWorldCardId as String?,
      metadata: metadata ?? this.metadata,
    );
  }
}

class PlayerPersona extends WorldRoleplayEntity {
  const PlayerPersona({
    required super.entity,
    required this.worldId,
    required this.name,
    this.description = '',
    this.appearance = '',
    this.background = '',
    this.notes = '',
    this.avatarReference,
    super.metadata = const {},
  });

  final String worldId;
  final String name;
  final String description;
  final String appearance;
  final String background;
  final String notes;
  final String? avatarReference;

  PlayerPersona copyWith({
    EntityMetadata? entity,
    String? worldId,
    String? name,
    String? description,
    String? appearance,
    String? background,
    String? notes,
    Object? avatarReference = _unsetWorldValue,
    Map<String, Object?>? metadata,
  }) {
    return PlayerPersona(
      entity: entity ?? this.entity,
      worldId: worldId ?? this.worldId,
      name: name ?? this.name,
      description: description ?? this.description,
      appearance: appearance ?? this.appearance,
      background: background ?? this.background,
      notes: notes ?? this.notes,
      avatarReference: avatarReference == _unsetWorldValue
          ? this.avatarReference
          : avatarReference as String?,
      metadata: metadata ?? this.metadata,
    );
  }
}

class WorldPlayerInstance extends WorldRoleplayEntity {
  const WorldPlayerInstance({
    required super.entity,
    required this.worldSessionId,
    required this.playerPersonaId,
    this.displayNameOverride,
    this.currentLocation = '',
    this.currentStatus = '',
    this.currentMood = '',
    this.currentGoal = '',
    this.isActive = true,
    this.lastActiveAt,
    super.metadata = const {},
  });

  final String worldSessionId;
  final String playerPersonaId;
  final String? displayNameOverride;
  final String currentLocation;
  final String currentStatus;
  final String currentMood;
  final String currentGoal;
  final bool isActive;
  final DateTime? lastActiveAt;

  WorldPlayerInstance copyWith({
    EntityMetadata? entity,
    String? worldSessionId,
    String? playerPersonaId,
    Object? displayNameOverride = _unsetWorldValue,
    String? currentLocation,
    String? currentStatus,
    String? currentMood,
    String? currentGoal,
    bool? isActive,
    Object? lastActiveAt = _unsetWorldValue,
    Map<String, Object?>? metadata,
  }) {
    return WorldPlayerInstance(
      entity: entity ?? this.entity,
      worldSessionId: worldSessionId ?? this.worldSessionId,
      playerPersonaId: playerPersonaId ?? this.playerPersonaId,
      displayNameOverride: displayNameOverride == _unsetWorldValue
          ? this.displayNameOverride
          : displayNameOverride as String?,
      currentLocation: currentLocation ?? this.currentLocation,
      currentStatus: currentStatus ?? this.currentStatus,
      currentMood: currentMood ?? this.currentMood,
      currentGoal: currentGoal ?? this.currentGoal,
      isActive: isActive ?? this.isActive,
      lastActiveAt: lastActiveAt == _unsetWorldValue
          ? this.lastActiveAt
          : lastActiveAt as DateTime?,
      metadata: metadata ?? this.metadata,
    );
  }
}

class WorldCharacterInstance extends WorldRoleplayEntity {
  const WorldCharacterInstance({
    required super.entity,
    required this.worldSessionId,
    required this.characterCardId,
    this.displayNameOverride,
    this.currentLocation = '',
    this.currentStatus = '',
    this.currentMood = '',
    this.currentGoal = '',
    this.isPresent = false,
    this.isActive = true,
    this.lastActiveAt,
    super.metadata = const {},
  });

  final String worldSessionId;
  final String characterCardId;
  final String? displayNameOverride;
  final String currentLocation;
  final String currentStatus;
  final String currentMood;
  final String currentGoal;
  final bool isPresent;
  final bool isActive;
  final DateTime? lastActiveAt;

  WorldCharacterInstance copyWith({
    EntityMetadata? entity,
    String? worldSessionId,
    String? characterCardId,
    Object? displayNameOverride = _unsetWorldValue,
    String? currentLocation,
    String? currentStatus,
    String? currentMood,
    String? currentGoal,
    bool? isPresent,
    bool? isActive,
    Object? lastActiveAt = _unsetWorldValue,
    Map<String, Object?>? metadata,
  }) {
    return WorldCharacterInstance(
      entity: entity ?? this.entity,
      worldSessionId: worldSessionId ?? this.worldSessionId,
      characterCardId: characterCardId ?? this.characterCardId,
      displayNameOverride: displayNameOverride == _unsetWorldValue
          ? this.displayNameOverride
          : displayNameOverride as String?,
      currentLocation: currentLocation ?? this.currentLocation,
      currentStatus: currentStatus ?? this.currentStatus,
      currentMood: currentMood ?? this.currentMood,
      currentGoal: currentGoal ?? this.currentGoal,
      isPresent: isPresent ?? this.isPresent,
      isActive: isActive ?? this.isActive,
      lastActiveAt: lastActiveAt == _unsetWorldValue
          ? this.lastActiveAt
          : lastActiveAt as DateTime?,
      metadata: metadata ?? this.metadata,
    );
  }
}

class WorldScene extends WorldRoleplayEntity {
  const WorldScene({
    required super.entity,
    required this.worldSessionId,
    required this.name,
    this.description = '',
    this.location = '',
    this.timeText = '',
    this.weather = '',
    this.atmosphere = '',
    this.currentEvent = '',
    this.notes = '',
    super.metadata = const {},
  });

  final String worldSessionId;
  final String name;
  final String description;
  final String location;
  final String timeText;
  final String weather;
  final String atmosphere;
  final String currentEvent;
  final String notes;

  WorldScene copyWith({
    EntityMetadata? entity,
    String? worldSessionId,
    String? name,
    String? description,
    String? location,
    String? timeText,
    String? weather,
    String? atmosphere,
    String? currentEvent,
    String? notes,
    Map<String, Object?>? metadata,
  }) {
    return WorldScene(
      entity: entity ?? this.entity,
      worldSessionId: worldSessionId ?? this.worldSessionId,
      name: name ?? this.name,
      description: description ?? this.description,
      location: location ?? this.location,
      timeText: timeText ?? this.timeText,
      weather: weather ?? this.weather,
      atmosphere: atmosphere ?? this.atmosphere,
      currentEvent: currentEvent ?? this.currentEvent,
      notes: notes ?? this.notes,
      metadata: metadata ?? this.metadata,
    );
  }
}

class WorldStateEntry extends WorldRoleplayEntity {
  const WorldStateEntry({
    required super.entity,
    required this.worldSessionId,
    required this.key,
    required this.value,
    this.category = 'general',
    this.source = 'manual',
    super.metadata = const {},
  });

  final String worldSessionId;
  final String key;
  final Object? value;
  final String category;
  final String source;

  WorldStateEntry copyWith({
    EntityMetadata? entity,
    String? worldSessionId,
    String? key,
    Object? value = _unsetWorldValue,
    String? category,
    String? source,
    Map<String, Object?>? metadata,
  }) {
    return WorldStateEntry(
      entity: entity ?? this.entity,
      worldSessionId: worldSessionId ?? this.worldSessionId,
      key: key ?? this.key,
      value: value == _unsetWorldValue ? this.value : value,
      category: category ?? this.category,
      source: source ?? this.source,
      metadata: metadata ?? this.metadata,
    );
  }
}

class WorldRelationship extends WorldRoleplayEntity {
  const WorldRelationship({
    required super.entity,
    required this.worldSessionId,
    required this.sourceEntityType,
    required this.sourceEntityId,
    required this.targetEntityType,
    required this.targetEntityId,
    required this.relationType,
    this.summary = '',
    this.state = const {},
    super.metadata = const {},
  });

  final String worldSessionId;
  final String sourceEntityType;
  final String sourceEntityId;
  final String targetEntityType;
  final String targetEntityId;
  final String relationType;
  final String summary;
  final Map<String, Object?> state;

  WorldRelationship copyWith({
    EntityMetadata? entity,
    String? worldSessionId,
    String? sourceEntityType,
    String? sourceEntityId,
    String? targetEntityType,
    String? targetEntityId,
    String? relationType,
    String? summary,
    Map<String, Object?>? state,
    Map<String, Object?>? metadata,
  }) {
    return WorldRelationship(
      entity: entity ?? this.entity,
      worldSessionId: worldSessionId ?? this.worldSessionId,
      sourceEntityType: sourceEntityType ?? this.sourceEntityType,
      sourceEntityId: sourceEntityId ?? this.sourceEntityId,
      targetEntityType: targetEntityType ?? this.targetEntityType,
      targetEntityId: targetEntityId ?? this.targetEntityId,
      relationType: relationType ?? this.relationType,
      summary: summary ?? this.summary,
      state: state ?? this.state,
      metadata: metadata ?? this.metadata,
    );
  }
}

class WorldMemoryEntry extends WorldRoleplayEntity {
  const WorldMemoryEntry({
    required super.entity,
    required this.worldSessionId,
    required this.type,
    required this.summary,
    required this.content,
    this.importance = 0.5,
    this.relatedCharacterIds = const [],
    this.relatedSceneId,
    this.lastReferencedAt,
    this.enabled = true,
    super.metadata = const {},
  });

  final String worldSessionId;
  final String type;
  final String summary;
  final String content;
  final double importance;
  final List<String> relatedCharacterIds;
  final String? relatedSceneId;
  final DateTime? lastReferencedAt;
  final bool enabled;

  WorldMemoryEntry copyWith({
    EntityMetadata? entity,
    String? worldSessionId,
    String? type,
    String? summary,
    String? content,
    double? importance,
    List<String>? relatedCharacterIds,
    Object? relatedSceneId = _unsetWorldValue,
    Object? lastReferencedAt = _unsetWorldValue,
    bool? enabled,
    Map<String, Object?>? metadata,
  }) {
    return WorldMemoryEntry(
      entity: entity ?? this.entity,
      worldSessionId: worldSessionId ?? this.worldSessionId,
      type: type ?? this.type,
      summary: summary ?? this.summary,
      content: content ?? this.content,
      importance: importance ?? this.importance,
      relatedCharacterIds: relatedCharacterIds ?? this.relatedCharacterIds,
      relatedSceneId: relatedSceneId == _unsetWorldValue
          ? this.relatedSceneId
          : relatedSceneId as String?,
      lastReferencedAt: lastReferencedAt == _unsetWorldValue
          ? this.lastReferencedAt
          : lastReferencedAt as DateTime?,
      enabled: enabled ?? this.enabled,
      metadata: metadata ?? this.metadata,
    );
  }
}

class WorldTimelineEvent extends WorldRoleplayEntity {
  const WorldTimelineEvent({
    required super.entity,
    required this.worldSessionId,
    required this.title,
    required this.description,
    this.worldTime = '',
    this.sceneId,
    this.characterIds = const [],
    this.eventType = 'manual',
    this.importance = 0.5,
    super.metadata = const {},
  });

  final String worldSessionId;
  final String title;
  final String description;
  final String worldTime;
  final String? sceneId;
  final List<String> characterIds;
  final String eventType;
  final double importance;

  WorldTimelineEvent copyWith({
    EntityMetadata? entity,
    String? worldSessionId,
    String? title,
    String? description,
    String? worldTime,
    Object? sceneId = _unsetWorldValue,
    List<String>? characterIds,
    String? eventType,
    double? importance,
    Map<String, Object?>? metadata,
  }) {
    return WorldTimelineEvent(
      entity: entity ?? this.entity,
      worldSessionId: worldSessionId ?? this.worldSessionId,
      title: title ?? this.title,
      description: description ?? this.description,
      worldTime: worldTime ?? this.worldTime,
      sceneId: sceneId == _unsetWorldValue ? this.sceneId : sceneId as String?,
      characterIds: characterIds ?? this.characterIds,
      eventType: eventType ?? this.eventType,
      importance: importance ?? this.importance,
      metadata: metadata ?? this.metadata,
    );
  }
}

class WorldBranch extends WorldRoleplayEntity {
  const WorldBranch({
    required super.entity,
    required this.worldSessionId,
    required this.name,
    this.parentBranchId,
    this.branchPointMessageId,
    this.branchPointEventId,
    this.isCurrent = false,
    super.metadata = const {},
  });

  final String worldSessionId;
  final String name;
  final String? parentBranchId;
  final String? branchPointMessageId;
  final String? branchPointEventId;
  final bool isCurrent;

  WorldBranch copyWith({
    EntityMetadata? entity,
    String? worldSessionId,
    String? name,
    Object? parentBranchId = _unsetWorldValue,
    Object? branchPointMessageId = _unsetWorldValue,
    Object? branchPointEventId = _unsetWorldValue,
    bool? isCurrent,
    Map<String, Object?>? metadata,
  }) {
    return WorldBranch(
      entity: entity ?? this.entity,
      worldSessionId: worldSessionId ?? this.worldSessionId,
      name: name ?? this.name,
      parentBranchId: parentBranchId == _unsetWorldValue
          ? this.parentBranchId
          : parentBranchId as String?,
      branchPointMessageId: branchPointMessageId == _unsetWorldValue
          ? this.branchPointMessageId
          : branchPointMessageId as String?,
      branchPointEventId: branchPointEventId == _unsetWorldValue
          ? this.branchPointEventId
          : branchPointEventId as String?,
      isCurrent: isCurrent ?? this.isCurrent,
      metadata: metadata ?? this.metadata,
    );
  }
}

enum WorldFeedEntryType {
  userAction,
  characterSpeech,
  narration,
  systemEvent;

  static WorldFeedEntryType fromJson(String value) {
    return values.firstWhere(
      (item) => item.name == value,
      orElse: () => WorldFeedEntryType.systemEvent,
    );
  }
}

class WorldFeedEntry extends WorldRoleplayEntity {
  const WorldFeedEntry({
    required super.entity,
    required this.worldSessionId,
    required this.branchId,
    required this.type,
    required this.content,
    this.speakerCharacterInstanceId,
    super.metadata = const {},
  });

  final String worldSessionId;
  final String branchId;
  final WorldFeedEntryType type;
  final String? speakerCharacterInstanceId;
  final String content;

  WorldFeedEntry copyWith({
    EntityMetadata? entity,
    String? worldSessionId,
    String? branchId,
    WorldFeedEntryType? type,
    Object? speakerCharacterInstanceId = _unsetWorldValue,
    String? content,
    Map<String, Object?>? metadata,
  }) {
    return WorldFeedEntry(
      entity: entity ?? this.entity,
      worldSessionId: worldSessionId ?? this.worldSessionId,
      branchId: branchId ?? this.branchId,
      type: type ?? this.type,
      speakerCharacterInstanceId: speakerCharacterInstanceId == _unsetWorldValue
          ? this.speakerCharacterInstanceId
          : speakerCharacterInstanceId as String?,
      content: content ?? this.content,
      metadata: metadata ?? this.metadata,
    );
  }
}

class WorldDatabaseCounts {
  const WorldDatabaseCounts({
    this.characterInstances = 0,
    this.loreEntries = 0,
    this.personas = 0,
    this.playerInstances = 0,
    this.scenes = 0,
    this.stateEntries = 0,
    this.relationships = 0,
    this.memories = 0,
    this.timelineEvents = 0,
    this.branches = 0,
    this.feedEntries = 0,
    this.pluginBindings = 0,
  });

  final int characterInstances;
  final int loreEntries;
  final int personas;
  final int playerInstances;
  final int scenes;
  final int stateEntries;
  final int relationships;
  final int memories;
  final int timelineEvents;
  final int branches;
  final int feedEntries;
  final int pluginBindings;
}

class WorldSearchResult {
  const WorldSearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.preview,
  });

  final String type;
  final String id;
  final String title;
  final String preview;
}
