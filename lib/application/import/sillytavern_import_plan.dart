import '../../domain/characters/character_card.dart';
import '../../domain/import/external_compatibility_payload.dart';
import '../../domain/import/sillytavern_models.dart';
import '../../domain/projects/project.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';

enum SillyTavernPersonaVisibility { public, directorOnly }

enum SillyTavernCharacterBookImportMode {
  preserveOnly,
  createNewWorldBook,
  existingWorldBook,
}

enum SillyTavernPromptImportMode { skip, append, replace }

// A user-confirmed preview awaiting the story's World selection. It owns no
// database rows or files until the normal Import Service executes its plan.
class SillyTavernStoryImport {
  const SillyTavernStoryImport({
    required this.inspection,
    required this.personaVisibility,
    this.allowDuplicateSource = false,
  });

  final SillyTavernImportInspection inspection;
  final SillyTavernPersonaVisibility personaVisibility;
  final bool allowDuplicateSource;
}

class SillyTavernImportDestination {
  const SillyTavernImportDestination({
    this.projectId,
    this.newProjectTitle,
    this.worldId,
    this.worldSessionId,
    this.worldBookId,
    this.characterBookMode = SillyTavernCharacterBookImportMode.preserveOnly,
    this.personaVisibility = SillyTavernPersonaVisibility.public,
    this.promptMode = SillyTavernPromptImportMode.skip,
    this.allowDuplicateSource = false,
    this.allowSameNameCopy = false,
  });

  final String? projectId;
  final String? newProjectTitle;
  final String? worldId;
  final String? worldSessionId;
  final String? worldBookId;
  final SillyTavernCharacterBookImportMode characterBookMode;
  final SillyTavernPersonaVisibility personaVisibility;
  final SillyTavernPromptImportMode promptMode;
  final bool allowDuplicateSource;
  final bool allowSameNameCopy;
}

class SillyTavernImportPlan {
  const SillyTavernImportPlan({
    required this.inspection,
    required this.destination,
    required this.payload,
    required this.warnings,
    required this.conflicts,
    this.project,
    this.character,
    this.worldBook,
    this.worldBookReference,
    this.characterBookReference,
    this.loreEntries = const [],
    this.persona,
    this.updatedWorld,
    this.updatedSession,
  });

  final SillyTavernImportInspection inspection;
  final SillyTavernImportDestination destination;
  final ExternalCompatibilityPayload payload;
  final List<String> warnings;
  final List<String> conflicts;
  final Project? project;
  final CharacterCard? character;
  final WorldBook? worldBook;
  final WorldWorldBookReference? worldBookReference;
  final EntityWorldBookReference? characterBookReference;
  final List<LoreEntry> loreEntries;
  final PlayerPersona? persona;
  final RoleplayWorld? updatedWorld;
  final WorldSession? updatedSession;

  bool get canImport => conflicts.isEmpty;
}

class SillyTavernImportResult {
  const SillyTavernImportResult({
    required this.payload,
    this.character,
    this.worldBook,
    this.worldBookReference,
    this.characterBookReference,
    this.persona,
  });

  final ExternalCompatibilityPayload payload;
  final CharacterCard? character;
  final WorldBook? worldBook;
  final WorldWorldBookReference? worldBookReference;
  final EntityWorldBookReference? characterBookReference;
  final PlayerPersona? persona;
}

class SillyTavernImportWrite {
  const SillyTavernImportWrite({
    required this.payload,
    this.project,
    this.character,
    this.worldBook,
    this.worldBookReference,
    this.characterBookReference,
    this.loreEntries = const [],
    this.persona,
    this.updatedWorld,
    this.updatedSession,
  });

  final ExternalCompatibilityPayload payload;
  final Project? project;
  final CharacterCard? character;
  final WorldBook? worldBook;
  final WorldWorldBookReference? worldBookReference;
  final EntityWorldBookReference? characterBookReference;
  final List<LoreEntry> loreEntries;
  final PlayerPersona? persona;
  final RoleplayWorld? updatedWorld;
  final WorldSession? updatedSession;
}
