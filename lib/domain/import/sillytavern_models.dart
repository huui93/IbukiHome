import 'dart:typed_data';

enum SillyTavernAssetKind { characterCard, lorebook, persona, promptPreset }

enum SillyTavernExtensionKind {
  dataOnly,
  promptRelated,
  uiRelated,
  scriptLike,
  networkRelated,
  unknown,
}

class SillyTavernCharacterBookEntry {
  const SillyTavernCharacterBookEntry({
    required this.id,
    required this.title,
    required this.content,
    required this.keys,
    required this.secondaryKeys,
    required this.enabled,
    required this.constant,
    required this.selective,
    required this.order,
    required this.position,
    required this.probability,
    required this.unsupported,
  });

  final String id;
  final String title;
  final String content;
  final List<String> keys;
  final List<String> secondaryKeys;
  final bool enabled;
  final bool constant;
  final bool selective;
  final int order;
  final String position;
  final double probability;
  final Map<String, Object?> unsupported;
}

class SillyTavernCharacterBook {
  const SillyTavernCharacterBook({
    required this.name,
    required this.entries,
    required this.unsupported,
  });

  final String name;
  final List<SillyTavernCharacterBookEntry> entries;
  final Map<String, Object?> unsupported;
}

class SillyTavernCharacterCardData {
  const SillyTavernCharacterCardData({
    required this.name,
    required this.description,
    required this.personality,
    required this.scenario,
    required this.firstMessage,
    required this.exampleMessages,
    required this.creatorNotes,
    required this.systemPrompt,
    required this.postHistoryInstructions,
    required this.alternateGreetings,
    required this.tags,
    required this.creator,
    required this.characterVersion,
    required this.extensions,
    required this.characterBook,
  });

  final String name;
  final String description;
  final String personality;
  final String scenario;
  final String firstMessage;
  final String exampleMessages;
  final String creatorNotes;
  final String systemPrompt;
  final String postHistoryInstructions;
  final List<String> alternateGreetings;
  final List<String> tags;
  final String creator;
  final String characterVersion;
  final Map<String, Object?> extensions;
  final SillyTavernCharacterBook? characterBook;
}

class SillyTavernLorebookData {
  const SillyTavernLorebookData({required this.name, required this.entries});

  final String name;
  final List<SillyTavernCharacterBookEntry> entries;
}

class SillyTavernPersonaData {
  const SillyTavernPersonaData({
    required this.name,
    required this.description,
    required this.avatarReference,
    required this.promptIdentity,
  });

  final String name;
  final String description;
  final String? avatarReference;
  final String promptIdentity;
}

class SillyTavernPromptPresetData {
  const SillyTavernPromptPresetData({
    required this.name,
    required this.mainPrompt,
    required this.postHistoryInstructions,
    required this.authorsNote,
    required this.generationParameters,
  });

  final String name;
  final String mainPrompt;
  final String postHistoryInstructions;
  final String authorsNote;
  final Map<String, Object?> generationParameters;
}

class SillyTavernExtensionSummary {
  const SillyTavernExtensionSummary({
    required this.key,
    required this.kind,
    required this.encodedChars,
    required this.scriptLike,
    required this.remoteReference,
    required this.secretLike,
  });

  final String key;
  final SillyTavernExtensionKind kind;
  final int encodedChars;
  final bool scriptLike;
  final bool remoteReference;
  final bool secretLike;
}

class SillyTavernSecurityReport {
  const SillyTavernSecurityReport({
    this.scriptLikePaths = const [],
    this.remoteReferencePaths = const [],
    this.secretLikePaths = const [],
  });

  final List<String> scriptLikePaths;
  final List<String> remoteReferencePaths;
  final List<String> secretLikePaths;

  List<String> get flags => List.unmodifiable([
    if (scriptLikePaths.isNotEmpty) 'script_like_content',
    if (remoteReferencePaths.isNotEmpty) 'remote_resource_reference',
    if (secretLikePaths.isNotEmpty) 'secret_like_content_redacted',
  ]);
}

class SillyTavernParsedAsset {
  const SillyTavernParsedAsset({
    required this.kind,
    required this.sourceFormat,
    required this.sourceVersion,
    required this.displayName,
    required this.normalizedPayload,
    required this.unsupportedPayload,
    required this.security,
    required this.warnings,
    required this.extensionSummaries,
    this.characterCard,
    this.lorebook,
    this.persona,
    this.promptPreset,
  });

  final SillyTavernAssetKind kind;
  final String sourceFormat;
  final String sourceVersion;
  final String displayName;
  final Map<String, Object?> normalizedPayload;
  final Map<String, Object?> unsupportedPayload;
  final SillyTavernSecurityReport security;
  final List<String> warnings;
  final List<SillyTavernExtensionSummary> extensionSummaries;
  final SillyTavernCharacterCardData? characterCard;
  final SillyTavernLorebookData? lorebook;
  final SillyTavernPersonaData? persona;
  final SillyTavernPromptPresetData? promptPreset;
}

class SillyTavernImportInspection {
  const SillyTavernImportInspection({
    required this.fileName,
    required this.sourceSha256,
    required this.sourceBytes,
    required this.asset,
    required this.existingPayloadIds,
    required this.imageBytes,
  });

  final String fileName;
  final String sourceSha256;
  final Uint8List sourceBytes;
  final SillyTavernParsedAsset asset;
  final List<String> existingPayloadIds;
  final Uint8List? imageBytes;

  bool get isDuplicate => existingPayloadIds.isNotEmpty;
}
