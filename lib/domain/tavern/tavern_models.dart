enum TavernParticipantKind { persona, character, system, tool, external }

enum TavernTurnRole { player, character, narrator, system, tool }

enum TavernAlternativeOrigin { manual, generated, imported }

enum TavernContentKind {
  text,
  reasoning,
  reasoningSummary,
  reasoningUnavailable,
  toolCall,
  toolResult,
  attachment,
  event,
  unknown,
}

enum TavernGenerationStatus {
  queued,
  preparing,
  running,
  streaming,
  cancelled,
  failed,
  completed,
}

enum TavernGenerationType {
  normal,
  regenerate,
  alternative,
  continueTurn,
  impersonate,
  group,
  quiet,
}

class TavernSession {
  const TavernSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.activeStoryLineId,
    this.worldAssetType,
    this.worldAssetId,
    this.personaType,
    this.personaId,
    this.runtimeConfigId,
    this.metadata = const {},
    this.archivedAt,
    this.deletedAt,
  });
  final String id, title;
  final DateTime createdAt, updatedAt;
  final String? activeStoryLineId,
      worldAssetType,
      worldAssetId,
      personaType,
      personaId,
      runtimeConfigId;
  final Map<String, Object?> metadata;
  final DateTime? archivedAt, deletedAt;
}

class TavernParticipant {
  const TavernParticipant({
    required this.id,
    required this.sessionId,
    required this.kind,
    required this.position,
    this.entityId,
    this.displayName = '',
    this.metadata = const {},
  });
  final String id, sessionId;
  final TavernParticipantKind kind;
  final String? entityId;
  final String displayName;
  final int position;
  final Map<String, Object?> metadata;
}

class TavernStoryLine {
  const TavernStoryLine({
    required this.id,
    required this.sessionId,
    required this.name,
    required this.position,
    required this.createdAt,
    this.parentId,
    this.originTurnId,
    this.originAlternativeId,
    this.archivedAt,
    this.metadata = const {},
  });
  final String id, sessionId, name;
  final int position;
  final DateTime createdAt;
  final String? parentId, originTurnId, originAlternativeId;
  final DateTime? archivedAt;
  final Map<String, Object?> metadata;
}

class TavernTurn {
  const TavernTurn({
    required this.id,
    required this.sessionId,
    required this.storyLineId,
    required this.position,
    required this.participantId,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
    this.selectedAlternativeId,
    this.editedAt,
    this.metadata = const {},
  });
  final String id, sessionId, storyLineId, participantId;
  final int position;
  final TavernTurnRole role;
  final DateTime createdAt, updatedAt;
  final String? selectedAlternativeId;
  final DateTime? editedAt;
  final Map<String, Object?> metadata;
}

class TavernAlternative {
  const TavernAlternative({
    required this.id,
    required this.turnId,
    required this.position,
    required this.origin,
    required this.createdAt,
    this.editedAt,
    this.metadata = const {},
  });
  final String id, turnId;
  final int position;
  final TavernAlternativeOrigin origin;
  final DateTime createdAt;
  final DateTime? editedAt;
  final Map<String, Object?> metadata;
}

class TavernContentPart {
  const TavernContentPart({
    required this.id,
    required this.alternativeId,
    required this.position,
    required this.kind,
    required this.createdAt,
    this.text,
    this.toolName,
    this.toolCallId,
    this.arguments,
    this.result,
    this.error,
    this.assetReference,
    this.mimeType,
    this.generationAttemptId,
    this.unknownKind,
    this.metadata = const {},
  });
  final String id, alternativeId;
  final int position;
  final TavernContentKind kind;
  final DateTime createdAt;
  final String? text, toolName, toolCallId, error, assetReference, mimeType;
  final String? generationAttemptId, unknownKind;
  final Map<String, Object?>? arguments, result;
  final Map<String, Object?> metadata;

  void validate() {
    switch (kind) {
      case TavernContentKind.text:
      case TavernContentKind.reasoning:
      case TavernContentKind.reasoningSummary:
      case TavernContentKind.event:
        if (text == null) throw ArgumentError('Text content is required.');
      case TavernContentKind.reasoningUnavailable:
        break;
      case TavernContentKind.toolCall:
        if (toolName == null || toolCallId == null || arguments == null) {
          throw ArgumentError('Tool invocation fields are required.');
        }
      case TavernContentKind.toolResult:
        if (toolCallId == null || (result == null && error == null)) {
          throw ArgumentError('Tool result fields are required.');
        }
      case TavernContentKind.attachment:
        if (assetReference == null || mimeType == null) {
          throw ArgumentError('Attachment fields are required.');
        }
      case TavernContentKind.unknown:
        if (unknownKind == null || unknownKind!.isEmpty) {
          throw ArgumentError('An unknown content kind needs its source name.');
        }
    }
  }
}

class TavernGenerationAttempt {
  const TavernGenerationAttempt({
    required this.id,
    required this.sessionId,
    required this.storyLineId,
    required this.turnId,
    required this.alternativeId,
    required this.position,
    required this.status,
    required this.type,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    this.failureReason,
    this.cancelReason,
    this.providerReference,
    this.modelReference,
    this.hasPartialContent = false,
    this.metadata = const {},
  });
  final String id, sessionId, storyLineId, turnId, alternativeId;
  final int position;
  final TavernGenerationStatus status;
  final TavernGenerationType type;
  final DateTime createdAt;
  final DateTime? startedAt, endedAt;
  final String? failureReason, cancelReason, providerReference, modelReference;
  final bool hasPartialContent;
  final Map<String, Object?> metadata;
}

class TavernTurnProjection {
  const TavernTurnProjection({
    required this.turn,
    required this.selectedAlternative,
    required this.alternatives,
    required this.selectedParts,
  });
  final TavernTurn turn;
  final TavernAlternative selectedAlternative;
  final List<TavernAlternative> alternatives;
  final List<TavernContentPart> selectedParts;

  List<TavernContentPart> get visibleParts => selectedParts
      .where(
        (part) =>
            part.kind == TavernContentKind.text ||
            part.kind == TavernContentKind.attachment ||
            part.kind == TavernContentKind.event,
      )
      .toList(growable: false);
}

class TavernTranscriptProjection {
  const TavernTranscriptProjection({
    required this.session,
    required this.storyLine,
    required this.turns,
  });
  final TavernSession session;
  final TavernStoryLine storyLine;
  final List<TavernTurnProjection> turns;
}

class TavernStorySummary {
  const TavernStorySummary({
    required this.session,
    required this.participants,
    this.excerpt = '',
  });
  final TavernSession session;
  final List<TavernParticipant> participants;
  final String excerpt;
}

List<TavernContentPart> selectTavernContentParts(
  List<TavernContentPart> parts,
  List<TavernGenerationAttempt> attempts,
) {
  final ordered = [...attempts]
    ..sort((a, b) => a.position.compareTo(b.position));
  final selectedAttemptIds = <String>{};
  for (final attempt in ordered) {
    if (attempt.status != TavernGenerationStatus.completed) continue;
    if (attempt.type == TavernGenerationType.continueTurn &&
        selectedAttemptIds.isNotEmpty) {
      selectedAttemptIds.add(attempt.id);
    } else {
      selectedAttemptIds
        ..clear()
        ..add(attempt.id);
    }
  }
  return parts
      .where(
        (part) =>
            part.generationAttemptId == null ||
            selectedAttemptIds.contains(part.generationAttemptId),
      )
      .toList(growable: false)
    ..sort((a, b) => a.position.compareTo(b.position));
}
