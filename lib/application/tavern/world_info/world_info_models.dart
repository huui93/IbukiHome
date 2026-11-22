import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../prompt/prompt_models.dart';

enum WorldInfoSelectiveLogic { andAny, andAll, notAny, notAll }

enum WorldInfoGenerationType { normal, regenerate, continueTurn }

enum WorldInfoAdditionalScanSource {
  characterDescription,
  characterPersonality,
  scenario,
  personaDescription,
  characterNote,
  creatorNotes,
}

enum WorldInfoActivationReason {
  activatedConstant,
  activatedPrimary,
  activatedRecursive,
  activatedSticky,
  disabled,
  scopeMismatch,
  generationMismatch,
  manualOnly,
  recursionOnly,
  recursionExcluded,
  primaryNotMatched,
  secondaryNotMatched,
  delayPending,
  cooldown,
  probabilityFailed,
  groupLost,
  recursionGuard,
}

typedef WorldInfoEntryId = (String bookId, String entryId);

class WorldInfoEntry {
  const WorldInfoEntry({
    required this.bookId,
    required this.entryId,
    required this.title,
    required this.content,
    this.bookEnabled = true,
    this.enabled = true,
    this.primaryKeys = const [],
    this.secondaryKeys = const [],
    this.selectiveLogic = WorldInfoSelectiveLogic.andAny,
    this.constant = false,
    this.manualOnly = false,
    this.probabilityPercent = 100,
    this.priority = 0,
    this.order = 0,
    this.groups = const [],
    this.groupWeight = 100,
    this.prioritizeGroup = false,
    this.scoreGroup = false,
    this.excludeRecursion = false,
    this.preventRecursion = false,
    this.recursionOnly = false,
    this.stickyMessages = 0,
    this.cooldownMessages = 0,
    this.delayMessages = 0,
    this.scanDepth,
    this.caseSensitive = false,
    this.wholeWords = true,
    this.worldIds = const {},
    this.characterIds = const {},
    this.personaIds = const {},
    this.characterTags = const {},
    this.excludeCharacterFilter = false,
    this.additionalScanSources = const {},
    this.generationTypes = const {},
    this.placement = const PromptPlacement(PromptPlacementKind.beforeHistory),
    this.role = PromptRoleIntent.context,
  });

  final String bookId, entryId, title, content;
  final bool bookEnabled, enabled, constant, manualOnly;
  final bool prioritizeGroup, scoreGroup;
  final bool excludeRecursion, preventRecursion, recursionOnly;
  final bool caseSensitive, wholeWords;
  final List<String> primaryKeys, secondaryKeys, groups;
  final WorldInfoSelectiveLogic selectiveLogic;
  final int probabilityPercent, priority, order, groupWeight;
  final int stickyMessages, cooldownMessages, delayMessages;
  final int? scanDepth;
  final Set<String> worldIds, characterIds, personaIds;
  final Set<String> characterTags;
  final bool excludeCharacterFilter;
  final Set<WorldInfoAdditionalScanSource> additionalScanSources;
  final Set<WorldInfoGenerationType> generationTypes;
  final PromptPlacement placement;
  final PromptRoleIntent role;

  WorldInfoEntryId get identity => (bookId, entryId);
  String get sourceId =>
      'worldInfo:${Uri.encodeComponent(bookId)}:${Uri.encodeComponent(entryId)}';

  int get definitionSignature =>
      int.parse(definitionFingerprint.substring(0, 15), radix: 16);
  String get definitionFingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            title,
            bookEnabled,
            enabled,
            content,
            primaryKeys,
            secondaryKeys,
            selectiveLogic.name,
            constant,
            manualOnly,
            probabilityPercent,
            priority,
            order,
            groups,
            groupWeight,
            prioritizeGroup,
            scoreGroup,
            excludeRecursion,
            preventRecursion,
            recursionOnly,
            stickyMessages,
            cooldownMessages,
            delayMessages,
            scanDepth,
            caseSensitive,
            wholeWords,
            placement.kind.name,
            placement.depth,
            role.name,
            worldIds.toList()..sort(),
            characterIds.toList()..sort(),
            personaIds.toList()..sort(),
            characterTags.toList()..sort(),
            excludeCharacterFilter,
            additionalScanSources.map((e) => e.name).toList()..sort(),
            generationTypes.map((e) => e.name).toList()..sort(),
          ]),
        ),
      )
      .toString();
}

class WorldInfoScanMessage {
  const WorldInfoScanMessage({required this.turnId, required this.text});
  final String turnId, text;
}

class WorldInfoActivationContext {
  const WorldInfoActivationContext({
    required this.sessionId,
    required this.storyLineId,
    required this.generationType,
    required this.messages,
    required this.historyMarker,
    this.worldId,
    this.characterIds = const {},
    this.characterTags = const {},
    this.additionalScanText = const {},
    this.personaId,
  });
  final String sessionId, storyLineId, historyMarker;
  final WorldInfoGenerationType generationType;
  final List<WorldInfoScanMessage> messages;
  final String? worldId, personaId;
  final Set<String> characterIds;
  final Set<String> characterTags;
  final Map<WorldInfoAdditionalScanSource, String> additionalScanText;
  int get messageCount => messages.length;
}

class WorldInfoSettings {
  const WorldInfoSettings({
    this.scanDepth = 20,
    this.maxRecursionPasses = 3,
    this.recursive = true,
  });
  final int scanDepth, maxRecursionPasses;
  final bool recursive;
}

class WorldInfoTimedState {
  const WorldInfoTimedState({
    required this.activatedAtMessage,
    required this.definitionSignature,
    this.definitionFingerprint,
  });
  final int activatedAtMessage, definitionSignature;
  final String? definitionFingerprint;
}

class WorldInfoRuntimeState {
  const WorldInfoRuntimeState({
    required this.sessionId,
    required this.storyLineId,
    this.observedMessageCount = 0,
    this.historyMarker = '',
    this.timed = const {},
  });
  final String sessionId, storyLineId, historyMarker;
  final int observedMessageCount;
  final Map<WorldInfoEntryId, WorldInfoTimedState> timed;

  WorldInfoRuntimeState forkAt({
    required String childStoryLineId,
    required int branchPointMessageCount,
    required String childHistoryMarker,
  }) {
    if (branchPointMessageCount < 0) {
      throw ArgumentError.value(branchPointMessageCount);
    }
    return WorldInfoRuntimeState(
      sessionId: sessionId,
      storyLineId: childStoryLineId,
      observedMessageCount: branchPointMessageCount,
      historyMarker: childHistoryMarker,
      timed: Map.unmodifiable({
        for (final item in timed.entries)
          if (item.value.activatedAtMessage <= branchPointMessageCount)
            item.key: item.value,
      }),
    );
  }
}

abstract class WorldInfoRandomSource {
  double sample(String key);
}

class SeededWorldInfoRandom implements WorldInfoRandomSource {
  const SeededWorldInfoRandom(this.seed);
  final int seed;

  @override
  double sample(String key) {
    var hash = 2166136261 ^ seed;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0xffffffff;
    }
    return hash / 0x100000000;
  }
}

class WorldInfoActivationDecision {
  const WorldInfoActivationDecision({
    required this.identity,
    required this.title,
    required this.active,
    required this.reason,
    this.pass,
    this.matchedPrimary = const [],
    this.matchedSecondary = const [],
    this.groupWinner,
    this.groupScore,
    this.groupSample,
    this.groupWeight,
    this.probabilitySample,
    this.recursionSource,
    this.stickyRemaining = 0,
    this.cooldownRemaining = 0,
    this.delayRemaining = 0,
  });
  final WorldInfoEntryId identity;
  final String title;
  final bool active;
  final WorldInfoActivationReason reason;
  final int? pass;
  final List<String> matchedPrimary, matchedSecondary;
  final WorldInfoEntryId? groupWinner, recursionSource;
  final int? groupScore;
  final double? groupSample;
  final int? groupWeight;
  final double? probabilitySample;
  final int stickyRemaining, cooldownRemaining, delayRemaining;
}

class WorldInfoActivationTrace {
  const WorldInfoActivationTrace(
    this.decisions, {
    this.recursionGuarded = const [],
  });
  final List<WorldInfoActivationDecision> decisions;
  final List<WorldInfoEntryId> recursionGuarded;
  int get checked => decisions.length;
  int get active => decisions.where((decision) => decision.active).length;
}

class WorldInfoActivationPlan {
  const WorldInfoActivationPlan({
    required this.activated,
    required this.promptSources,
    required this.trace,
    required this.nextState,
  });
  final List<WorldInfoEntryId> activated;
  final List<PromptSource> promptSources;
  final WorldInfoActivationTrace trace;
  final WorldInfoRuntimeState nextState;
}
