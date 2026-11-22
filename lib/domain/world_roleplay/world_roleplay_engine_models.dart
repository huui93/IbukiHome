import '../common/entity_metadata.dart';
import 'world_roleplay_models.dart';

const worldPluginPromptLayerMarker = '{{IBUKI_WORLD_PLUGIN_PROMPT_LAYER}}';

enum WorldTurnStatus {
  pending,
  directing,
  generating,
  committing,
  completed,
  failed,
  cancelled,
}

enum WorldKnowledgeVisibility { public, directorOnly, private }

enum WorldEngineErrorCategory {
  directorError,
  loreActivationError,
  speakerSelectionError,
  characterGenerationError,
  narrationError,
  mutationParseError,
  mutationValidationError,
  mutationSaveError,
  memoryExtractionError,
  timelineExtractionError,
  transportInterrupted,
  providerError,
  busy,
  cancelled,
}

class WorldEngineException implements Exception {
  const WorldEngineException(this.category, this.message, {this.detail});

  final WorldEngineErrorCategory category;
  final String message;
  final String? detail;

  @override
  String toString() => 'WorldEngineException(${category.name}): $message';
}

class WorldTurn extends WorldRoleplayEntity {
  const WorldTurn({
    required super.entity,
    required this.worldSessionId,
    required this.branchId,
    required this.userFeedEntryId,
    this.directorDecision = const {},
    this.selectedSpeakerIds = const [],
    this.generatedFeedEntryIds = const [],
    this.mutationProposal = const {},
    this.status = WorldTurnStatus.pending,
    this.completedAt,
    this.errorCategory,
    super.metadata = const {},
  });

  final String worldSessionId;
  final String branchId;
  final String userFeedEntryId;
  final Map<String, Object?> directorDecision;
  final List<String> selectedSpeakerIds;
  final List<String> generatedFeedEntryIds;
  final Map<String, Object?> mutationProposal;
  final WorldTurnStatus status;
  final DateTime? completedAt;
  final WorldEngineErrorCategory? errorCategory;

  WorldTurn copyWith({
    EntityMetadata? entity,
    Map<String, Object?>? directorDecision,
    List<String>? selectedSpeakerIds,
    List<String>? generatedFeedEntryIds,
    Map<String, Object?>? mutationProposal,
    WorldTurnStatus? status,
    DateTime? completedAt,
    WorldEngineErrorCategory? errorCategory,
    Map<String, Object?>? metadata,
  }) {
    return WorldTurn(
      entity: entity ?? this.entity,
      worldSessionId: worldSessionId,
      branchId: branchId,
      userFeedEntryId: userFeedEntryId,
      directorDecision: directorDecision ?? this.directorDecision,
      selectedSpeakerIds: selectedSpeakerIds ?? this.selectedSpeakerIds,
      generatedFeedEntryIds:
          generatedFeedEntryIds ?? this.generatedFeedEntryIds,
      mutationProposal: mutationProposal ?? this.mutationProposal,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
      errorCategory: errorCategory ?? this.errorCategory,
      metadata: metadata ?? this.metadata,
    );
  }
}

class WorldDirectorDecision {
  const WorldDirectorDecision({
    required this.intentSummary,
    required this.narrationNeeded,
    this.candidateSpeakerIds = const [],
    this.preferredSpeakerIds = const [],
    this.loreQueryTerms = const [],
    this.mutationProposal = const WorldMutationProposal(),
    this.shouldRemember = false,
    this.timelineSignificant = false,
    this.notes = '',
  });

  final String intentSummary;
  final bool narrationNeeded;
  final List<String> candidateSpeakerIds;
  final List<String> preferredSpeakerIds;
  final List<String> loreQueryTerms;
  final WorldMutationProposal mutationProposal;
  final bool shouldRemember;
  final bool timelineSignificant;
  final String notes;

  factory WorldDirectorDecision.fromJson(Map<String, Object?> json) {
    return WorldDirectorDecision(
      intentSummary: _string(json, 'intentSummary'),
      narrationNeeded: _bool(json, 'narrationNeeded'),
      candidateSpeakerIds: _strings(json, 'candidateSpeakerIds'),
      preferredSpeakerIds: _strings(json, 'preferredSpeakerIds'),
      loreQueryTerms: _strings(json, 'loreQueryTerms'),
      mutationProposal: json['mutationProposal'] == null
          ? const WorldMutationProposal()
          : WorldMutationProposal.fromJson(_map(json, 'mutationProposal')),
      shouldRemember: _optionalBool(json, 'shouldRemember'),
      timelineSignificant: _optionalBool(json, 'timelineSignificant'),
      notes: _optionalString(json, 'notes'),
    );
  }

  Map<String, Object?> toJson() => {
    'intentSummary': intentSummary,
    'narrationNeeded': narrationNeeded,
    'candidateSpeakerIds': candidateSpeakerIds,
    'preferredSpeakerIds': preferredSpeakerIds,
    'loreQueryTerms': loreQueryTerms,
    'mutationProposal': mutationProposal.toJson(),
    'shouldRemember': shouldRemember,
    'timelineSignificant': timelineSignificant,
    'notes': notes,
  };
}

enum WorldMutationType {
  sceneUpdate,
  stateSet,
  stateRemove,
  characterUpdate,
  playerUpdate,
  sceneCastAdd,
  sceneCastRemove,
  relationshipUpsert,
  worldTimeUpdate,
}

class WorldMutationOperation {
  const WorldMutationOperation({
    required this.type,
    this.entityId,
    this.values = const {},
  });

  final WorldMutationType type;
  final String? entityId;
  final Map<String, Object?> values;

  factory WorldMutationOperation.fromJson(Map<String, Object?> json) {
    final typeName = _string(json, 'type');
    final type = WorldMutationType.values
        .where((value) => value.name == typeName)
        .firstOrNull;
    if (type == null) {
      throw const WorldEngineException(
        WorldEngineErrorCategory.mutationParseError,
        '世界变化包含不支持的操作。',
      );
    }
    return WorldMutationOperation(
      type: type,
      entityId: _optionalString(json, 'entityId').nullIfEmpty,
      values: json['values'] == null ? const {} : _map(json, 'values'),
    );
  }

  Map<String, Object?> toJson() => {
    'type': type.name,
    'entityId': entityId,
    'values': values,
  };
}

class WorldMemoryCandidate {
  const WorldMemoryCandidate({
    required this.summary,
    this.content = '',
    this.type = 'event',
    this.importance = 0.5,
    this.relatedCharacterIds = const [],
  });

  final String summary;
  final String content;
  final String type;
  final double importance;
  final List<String> relatedCharacterIds;

  factory WorldMemoryCandidate.fromJson(Map<String, Object?> json) {
    return WorldMemoryCandidate(
      summary: _string(json, 'summary'),
      content: _optionalString(json, 'content'),
      type: _optionalString(json, 'type').nullIfEmpty ?? 'event',
      importance: _number(json, 'importance', fallback: 0.5).clamp(0, 1),
      relatedCharacterIds: _strings(json, 'relatedCharacterIds'),
    );
  }

  Map<String, Object?> toJson() => {
    'summary': summary,
    'content': content,
    'type': type,
    'importance': importance,
    'relatedCharacterIds': relatedCharacterIds,
  };
}

class WorldTimelineCandidate {
  const WorldTimelineCandidate({
    required this.title,
    this.description = '',
    this.eventType = 'worldTurn',
    this.importance = 0.5,
    this.characterIds = const [],
  });

  final String title;
  final String description;
  final String eventType;
  final double importance;
  final List<String> characterIds;

  factory WorldTimelineCandidate.fromJson(Map<String, Object?> json) {
    return WorldTimelineCandidate(
      title: _string(json, 'title'),
      description: _optionalString(json, 'description'),
      eventType: _optionalString(json, 'eventType').nullIfEmpty ?? 'worldTurn',
      importance: _number(json, 'importance', fallback: 0.5).clamp(0, 1),
      characterIds: _strings(json, 'characterIds'),
    );
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'description': description,
    'eventType': eventType,
    'importance': importance,
    'characterIds': characterIds,
  };
}

class WorldMutationProposal {
  const WorldMutationProposal({
    this.operations = const [],
    this.memories = const [],
    this.timelineEvents = const [],
  });

  final List<WorldMutationOperation> operations;
  final List<WorldMemoryCandidate> memories;
  final List<WorldTimelineCandidate> timelineEvents;

  factory WorldMutationProposal.fromJson(Map<String, Object?> json) {
    return WorldMutationProposal(
      operations: _objects(json, 'operations', WorldMutationOperation.fromJson),
      memories: _objects(json, 'memories', WorldMemoryCandidate.fromJson),
      timelineEvents: _objects(
        json,
        'timelineEvents',
        WorldTimelineCandidate.fromJson,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'operations': operations.map((value) => value.toJson()).toList(),
    'memories': memories.map((value) => value.toJson()).toList(),
    'timelineEvents': timelineEvents.map((value) => value.toJson()).toList(),
  };
}

class WorldMutationCommit {
  const WorldMutationCommit({
    required this.worldSessionId,
    required this.turn,
    this.session,
    this.scene,
    this.sceneCast,
    this.characterInstances = const [],
    this.playerInstance,
    this.stateUpserts = const [],
    this.stateDeleteIds = const [],
    this.relationshipUpserts = const [],
    this.memories = const [],
    this.timelineEvents = const [],
  });

  final String worldSessionId;
  final WorldTurn turn;
  final WorldSession? session;
  final WorldScene? scene;
  final Set<String>? sceneCast;
  final List<WorldCharacterInstance> characterInstances;
  final WorldPlayerInstance? playerInstance;
  final List<WorldStateEntry> stateUpserts;
  final List<String> stateDeleteIds;
  final List<WorldRelationship> relationshipUpserts;
  final List<WorldMemoryEntry> memories;
  final List<WorldTimelineEvent> timelineEvents;
}

class WorldLoreActivationDiagnostics {
  const WorldLoreActivationDiagnostics({
    required this.candidateLoreCount,
    required this.activatedLoreCount,
    required this.selectedLoreCount,
    required this.estimatedTokens,
  });

  final int candidateLoreCount;
  final int activatedLoreCount;
  final int selectedLoreCount;
  final int estimatedTokens;
}

class WorldLoreActivationResult {
  const WorldLoreActivationResult({
    required this.entries,
    required this.diagnostics,
  });

  final List<LoreEntry> entries;
  final WorldLoreActivationDiagnostics diagnostics;
}

class WorldPromptDiagnostics {
  const WorldPromptDiagnostics({
    required this.worldSystemPromptPresent,
    required this.worldSystemPromptChars,
    required this.sessionAdditionalInstructionsPresent,
    required this.sessionAdditionalInstructionsChars,
    required this.pipelineStages,
  });

  final bool worldSystemPromptPresent;
  final int worldSystemPromptChars;
  final bool sessionAdditionalInstructionsPresent;
  final int sessionAdditionalInstructionsChars;
  final List<String> pipelineStages;

  Map<String, Object?> toSafeJson() => {
    'worldSystemPresent': worldSystemPromptPresent,
    'worldSystemChars': worldSystemPromptChars,
    'sessionAdditionalPresent': sessionAdditionalInstructionsPresent,
    'sessionAdditionalChars': sessionAdditionalInstructionsChars,
    'stages': pipelineStages,
  };
}

class WorldContextDiagnostics {
  const WorldContextDiagnostics({
    required this.estimatedTokensBySection,
    required this.selectedCharacterCount,
    required this.selectedMemoryCount,
    required this.selectedTimelineCount,
    required this.selectedStateCount,
    required this.promptLayer,
  });

  final Map<String, int> estimatedTokensBySection;
  final int selectedCharacterCount;
  final int selectedMemoryCount;
  final int selectedTimelineCount;
  final int selectedStateCount;
  final WorldPromptDiagnostics promptLayer;
}

class WorldRoleplayContext {
  const WorldRoleplayContext({
    required this.directorSystemPrompt,
    required this.directorUserPrompt,
    required this.publicPlayerContext,
    required this.directorPlayerContext,
    required this.sceneContext,
    required this.recentFeedContext,
    required this.diagnostics,
    this.activatedLore = const [],
  });

  final String directorSystemPrompt;
  final String directorUserPrompt;
  final String publicPlayerContext;
  final String directorPlayerContext;
  final String sceneContext;
  final String recentFeedContext;
  final WorldContextDiagnostics diagnostics;
  final List<LoreEntry> activatedLore;
}

class WorldSpeakerSelection {
  const WorldSpeakerSelection({required this.speakerIds, required this.mode});

  final List<String> speakerIds;
  final WorldSpeakerMode mode;
}

enum WorldTurnUpdateType {
  status,
  feedEntry,
  streaming,
  completed,
  failed,
  cancelled,
}

class WorldTurnUpdate {
  const WorldTurnUpdate({
    required this.turnId,
    required this.type,
    required this.status,
    this.feedEntry,
    this.streamingContent = '',
    this.activeSpeakerId,
    this.error,
  });

  final String turnId;
  final WorldTurnUpdateType type;
  final WorldTurnStatus status;
  final WorldFeedEntry? feedEntry;
  final String streamingContent;
  final String? activeSpeakerId;
  final WorldEngineException? error;
}

Map<String, Object?> _map(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw WorldEngineException(
      WorldEngineErrorCategory.directorError,
      '世界导演字段 $key 格式无效。',
    );
  }
  return Map.unmodifiable(Map<String, Object?>.from(value));
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw WorldEngineException(
      WorldEngineErrorCategory.directorError,
      '世界导演字段 $key 格式无效。',
    );
  }
  return value.trim();
}

String _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return '';
  if (value is! String) {
    throw WorldEngineException(
      WorldEngineErrorCategory.directorError,
      '世界导演字段 $key 格式无效。',
    );
  }
  return value.trim();
}

bool _bool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw WorldEngineException(
    WorldEngineErrorCategory.directorError,
    '世界导演字段 $key 格式无效。',
  );
}

bool _optionalBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return false;
  if (value is bool) return value;
  throw WorldEngineException(
    WorldEngineErrorCategory.directorError,
    '世界导演字段 $key 格式无效。',
  );
}

double _number(
  Map<String, Object?> json,
  String key, {
  required double fallback,
}) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is num && value.isFinite) return value.toDouble();
  throw WorldEngineException(
    WorldEngineErrorCategory.directorError,
    '世界导演字段 $key 格式无效。',
  );
}

List<String> _strings(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List || value.any((item) => item is! String)) {
    throw WorldEngineException(
      WorldEngineErrorCategory.directorError,
      '世界导演字段 $key 格式无效。',
    );
  }
  return List.unmodifiable(
    value
        .cast<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty),
  );
}

List<T> _objects<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, Object?>) parser,
) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List || value.any((item) => item is! Map)) {
    throw WorldEngineException(
      WorldEngineErrorCategory.directorError,
      '世界导演字段 $key 格式无效。',
    );
  }
  return List.unmodifiable(
    value.map((item) => parser(Map<String, Object?>.from(item as Map))),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

extension _NullIfEmpty on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
