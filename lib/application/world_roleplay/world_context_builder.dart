import 'dart:math' as math;

import '../../data/repositories/character_repository.dart';
import '../../data/repositories/compatibility_import_repository.dart';
import '../../data/repositories/world_roleplay_repository.dart';
import '../../domain/characters/character_card.dart';
import '../../domain/world_roleplay/world_roleplay_engine_models.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';
import '../import/sillytavern_character_context.dart';
import 'world_lore_activator.dart';
import 'world_prompt_layer.dart';

class WorldRoleplaySnapshot {
  const WorldRoleplaySnapshot({
    required this.world,
    required this.session,
    required this.persona,
    required this.playerInstance,
    required this.scene,
    required this.presentCharacters,
    required this.characterCards,
    required this.characterCompatibility,
    required this.relationships,
    required this.stateEntries,
    required this.memories,
    required this.timeline,
    required this.recentFeed,
    required this.lore,
    required this.context,
  });

  final RoleplayWorld world;
  final WorldSession session;
  final PlayerPersona? persona;
  final WorldPlayerInstance? playerInstance;
  final WorldScene? scene;
  final List<WorldCharacterInstance> presentCharacters;
  final Map<String, CharacterCard> characterCards;
  final Map<String, SillyTavernCharacterContext> characterCompatibility;
  final List<WorldRelationship> relationships;
  final List<WorldStateEntry> stateEntries;
  final List<WorldMemoryEntry> memories;
  final List<WorldTimelineEvent> timeline;
  final List<WorldFeedEntry> recentFeed;
  final WorldLoreActivationResult lore;
  final WorldRoleplayContext context;
}

class WorldRoleplayContextBuilder {
  const WorldRoleplayContextBuilder({
    required this.worlds,
    required this.characters,
    this.loreActivator = const WorldLoreActivator(),
    this.recentFeedLimit = 24,
    this.memoryLimit = 12,
    this.timelineLimit = 10,
    this.stateLimit = 40,
    this.promptLayer = const WorldPromptLayer(),
    this.compatibility,
  });

  final WorldRoleplayRepository worlds;
  final CharacterRepository characters;
  final WorldLoreActivator loreActivator;
  final int recentFeedLimit;
  final int memoryLimit;
  final int timelineLimit;
  final int stateLimit;
  final WorldPromptLayer promptLayer;
  final CompatibilityImportRepository? compatibility;

  Future<WorldRoleplaySnapshot> build({
    required String worldSessionId,
    required String userAction,
    List<String> loreQueryTerms = const [],
    Set<String> manualLoreEntryIds = const {},
  }) async {
    final session = await worlds.getSession(worldSessionId);
    final world = await worlds.getWorld(session.worldId);
    final player = session.currentPlayerInstanceId == null
        ? null
        : await worlds.getPlayerInstance(session.currentPlayerInstanceId!);
    final persona = player == null
        ? null
        : await worlds.getPersona(player.playerPersonaId);
    final scene = session.currentSceneId == null
        ? null
        : await worlds.getScene(session.currentSceneId!);
    final allInstances = await worlds.listCharacterInstances(worldSessionId);
    final castIds = scene == null
        ? const <String>{}
        : await worlds.listSceneCast(scene.id);
    final present = allInstances
        .where(
          (item) =>
              item.isActive && (item.isPresent || castIds.contains(item.id)),
        )
        .toList(growable: false);
    final cards = <String, CharacterCard>{};
    final compatibilityContexts = <String, SillyTavernCharacterContext>{};
    for (final instance in present) {
      try {
        cards[instance.id] = await characters.getCharacter(
          instance.characterCardId,
        );
        final compatibilityRepository = compatibility;
        if (compatibilityRepository != null) {
          final context = await SillyTavernCharacterContextResolver(
            compatibilityRepository,
          ).resolve(instance.characterCardId);
          if (!context.isEmpty) compatibilityContexts[instance.id] = context;
        }
      } catch (_) {
        // A missing global card is isolated to that instance.
      }
    }
    final recentFeed = await worlds.listFeedEntries(
      worldSessionId,
      branchId: session.currentBranchId,
      limit: recentFeedLimit,
    );
    final relationships = (await worlds.listRelationships(worldSessionId))
        .where((item) => _isRelevantRelationship(item, present, player?.id))
        .take(30)
        .toList(growable: false);
    final state = (await worlds.listStateEntries(worldSessionId)).toList(
      growable: true,
    )..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final memories =
        (await worlds.listMemories(
            worldSessionId,
          )).where((item) => item.enabled).toList(growable: true)
          ..sort((left, right) {
            final importance = right.importance.compareTo(left.importance);
            return importance != 0
                ? importance
                : right.createdAt.compareTo(left.createdAt);
          });
    final timeline = (await worlds.listTimelineEvents(worldSessionId)).toList(
      growable: true,
    )..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    final bookPriorities = <String, int>{};
    final ownedBooks = await worlds.listWorldBooks(session.worldId);
    final legacySelectedBookIds = session.metadata['worldBookIds'];
    for (final book in ownedBooks) {
      if (legacySelectedBookIds is List &&
          !legacySelectedBookIds.contains(book.id)) {
        continue;
      }
      bookPriorities[book.id] = 0;
    }
    for (final reference in await worlds.listWorldBookReferences(world.id)) {
      if (reference.enabled) {
        bookPriorities[reference.worldBookId] = math.max(
          bookPriorities[reference.worldBookId] ?? -0x7fffffff,
          reference.priority,
        );
      } else {
        bookPriorities.remove(reference.worldBookId);
      }
    }
    for (final instance in present) {
      for (final reference in await worlds.listCharacterWorldBookReferences(
        instance.characterCardId,
      )) {
        if (reference.enabled) {
          bookPriorities[reference.worldBookId] = math.max(
            bookPriorities[reference.worldBookId] ?? -0x7fffffff,
            reference.priority,
          );
        }
      }
    }
    if (persona != null) {
      for (final reference in await worlds.listPersonaWorldBookReferences(
        persona.id,
      )) {
        if (reference.enabled) {
          bookPriorities[reference.worldBookId] = math.max(
            bookPriorities[reference.worldBookId] ?? -0x7fffffff,
            reference.priority,
          );
        }
      }
    }
    // Session overrides are applied last so an explicit per-story decision
    // wins over inherited World, Character, and Persona references.
    for (final override in await worlds.listWorldBookOverrides(session.id)) {
      switch (override.mode) {
        case WorldBookOverrideMode.inherit:
          break;
        case WorldBookOverrideMode.enabled:
          bookPriorities[override.worldBookId] = math.max(
            bookPriorities[override.worldBookId] ?? -0x7fffffff,
            override.priority,
          );
        case WorldBookOverrideMode.disabled:
          bookPriorities.remove(override.worldBookId);
      }
    }
    final loreById = <String, LoreEntry>{};
    for (final source in bookPriorities.entries) {
      for (final entry in await worlds.listLoreEntries(source.key)) {
        final effective = entry.copyWith(
          priority: entry.priority + source.value,
        );
        final existing = loreById[entry.id];
        if (existing == null || effective.priority > existing.priority) {
          loreById[entry.id] = effective;
        }
      }
    }
    for (final id in manualLoreEntryIds) {
      if (!loreById.containsKey(id)) {
        try {
          loreById[id] = await worlds.getLoreEntry(id);
        } catch (_) {
          // A stale manual selection is isolated to this turn.
        }
      }
    }
    final lore = loreActivator.activate(
      entries: loreById.values.toList(growable: false),
      searchTexts: [
        userAction,
        scene?.name ?? '',
        scene?.description ?? '',
        ...recentFeed.takeLast(8).map((item) => item.content),
        ...loreQueryTerms,
      ],
      tokenBudget: session.loreContextBudget,
      manualEntryIds: manualLoreEntryIds,
    );
    final selectedState = state.take(stateLimit).toList(growable: false);
    final selectedMemories = memories
        .where(
          (memory) =>
              memory.relatedCharacterIds.isEmpty ||
              memory.relatedCharacterIds.any(
                (id) => present.any((item) => item.id == id),
              ),
        )
        .take(memoryLimit)
        .toList(growable: false);
    final selectedTimeline = timeline
        .where(
          (event) =>
              event.characterIds.isEmpty ||
              event.characterIds.any(
                (id) => present.any((item) => item.id == id),
              ),
        )
        .take(timelineLimit)
        .toList(growable: false);
    final publicPlayer = _playerContext(
      persona,
      player,
      includeDirectorOnly: false,
    );
    final directorPlayer = _playerContext(
      persona,
      player,
      includeDirectorOnly: true,
    );
    final sceneContext = _sceneContext(scene, present, cards);
    final feedContext = recentFeed
        .map((entry) => '${entry.type.name}: ${entry.content}')
        .join('\n');
    final sections = <String, String>{
      'persona': directorPlayer,
      'scene': sceneContext,
      'characters': cards.values.map((item) => item.content).join('\n'),
      'lore': lore.entries.map((item) => item.content).join('\n'),
      'state': selectedState
          .map((item) => '${item.key}=${item.value}')
          .join('\n'),
      'relationships': relationships.map((item) => item.summary).join('\n'),
      'memory': selectedMemories.map((item) => item.summary).join('\n'),
      'timeline': selectedTimeline.map((item) => item.title).join('\n'),
      'recentFeed': feedContext,
      'userAction': userAction,
    };
    final directorAssembly = promptLayer.assemble(
      coreRules: _directorCoreRules,
      world: world,
      session: session,
      worldContext: _directorWorldContext(
        world: world,
        session: session,
        player: directorPlayer,
        scene: sceneContext,
        relationships: relationships,
        state: selectedState,
        memories: selectedMemories,
        timeline: selectedTimeline,
        feed: feedContext,
        lore: lore.entries,
      ),
      userAction: userAction,
    );
    final context = WorldRoleplayContext(
      directorSystemPrompt: directorAssembly.systemPrompt,
      directorUserPrompt: '请执行以上 World Director 任务，并只返回符合 schema 的 JSON 对象。',
      publicPlayerContext: publicPlayer,
      directorPlayerContext: directorPlayer,
      sceneContext: sceneContext,
      recentFeedContext: feedContext,
      activatedLore: lore.entries,
      diagnostics: WorldContextDiagnostics(
        estimatedTokensBySection: Map.unmodifiable({
          for (final entry in sections.entries)
            entry.key: _estimateTokens(entry.value),
        }),
        selectedCharacterCount: cards.length,
        selectedMemoryCount: selectedMemories.length,
        selectedTimelineCount: selectedTimeline.length,
        selectedStateCount: selectedState.length,
        promptLayer: directorAssembly.diagnostics,
      ),
    );
    return WorldRoleplaySnapshot(
      world: world,
      session: session,
      persona: persona,
      playerInstance: player,
      scene: scene,
      presentCharacters: List.unmodifiable(present),
      characterCards: Map.unmodifiable(cards),
      characterCompatibility: Map.unmodifiable(compatibilityContexts),
      relationships: List.unmodifiable(relationships),
      stateEntries: List.unmodifiable(selectedState),
      memories: List.unmodifiable(selectedMemories),
      timeline: List.unmodifiable(selectedTimeline),
      recentFeed: List.unmodifiable(recentFeed),
      lore: lore,
      context: context,
    );
  }

  String buildCharacterSystemPrompt({
    required WorldRoleplaySnapshot snapshot,
    required String speakerId,
    required String userAction,
    required List<WorldFeedEntry> turnLocalEntries,
  }) {
    final instance = snapshot.presentCharacters.firstWhere(
      (item) => item.id == speakerId,
      orElse: () => throw const WorldEngineException(
        WorldEngineErrorCategory.speakerSelectionError,
        '选择的角色不在当前场景。',
      ),
    );
    final card = snapshot.characterCards[speakerId];
    if (card == null) {
      throw const WorldEngineException(
        WorldEngineErrorCategory.characterGenerationError,
        '角色卡已经不可用。',
      );
    }
    final relatedRelationships = snapshot.relationships.where(
      (item) =>
          item.sourceEntityId == speakerId || item.targetEntityId == speakerId,
    );
    final relatedMemories = snapshot.memories.where(
      (item) => item.relatedCharacterIds.contains(speakerId),
    );
    final relatedTimeline = snapshot.timeline.where(
      (item) => item.characterIds.contains(speakerId),
    );
    final compatibilityContext = snapshot.characterCompatibility[speakerId];
    return promptLayer
        .assemble(
          coreRules: _characterSpeechCoreRules,
          world: snapshot.world,
          session: snapshot.session,
          worldContext:
              '''【角色卡】
姓名：${instance.displayNameOverride ?? card.name}
${card.content}

${_characterCompatibilityPrompt(compatibilityContext)}

【当前实例状态】
地点：${instance.currentLocation}
状态：${instance.currentStatus}
情绪：${instance.currentMood}
目标：${instance.currentGoal}

【角色可知的玩家信息】
${snapshot.context.publicPlayerContext}

【当前场景】
${snapshot.context.sceneContext}

【与该角色相关的关系】
${relatedRelationships.map((item) => '${item.relationType}: ${item.summary}').join('\n')}

【该角色知道的记忆】
${relatedMemories.map((item) => item.summary).join('\n')}

【该角色参与的事件】
${relatedTimeline.map((item) => item.title).join('\n')}

【本轮已发生】
${turnLocalEntries.map((item) => item.content).join('\n')}''',
          userAction: userAction,
        )
        .systemPrompt;
  }

  String _characterCompatibilityPrompt(
    SillyTavernCharacterContext? compatibility,
  ) {
    if (compatibility == null || compatibility.isEmpty) return '';
    return <String>[
      if (compatibility.systemPrompt.isNotEmpty)
        '【角色专属提示（低于 Core 与 World Prompt）】\n${compatibility.systemPrompt}',
      if (compatibility.exampleMessages.isNotEmpty)
        '【角色说话样例】\n${compatibility.exampleMessages}',
      if (compatibility.postHistoryInstructions.isNotEmpty)
        '【角色后置指令（不得覆盖更高优先级规则）】\n${compatibility.postHistoryInstructions}',
    ].join('\n\n');
  }

  String buildNarrationSystemPrompt({
    required WorldRoleplaySnapshot snapshot,
    required String userAction,
    required List<WorldFeedEntry> turnLocalEntries,
  }) {
    return promptLayer
        .assemble(
          coreRules: _narratorCoreRules,
          world: snapshot.world,
          session: snapshot.session,
          worldContext:
              '''【当前场景】
${snapshot.context.sceneContext}

【玩家公开信息】
${snapshot.context.publicPlayerContext}

【世界书】
${snapshot.lore.entries.map((item) => item.content).join('\n')}

【本轮已发生】
${turnLocalEntries.map((item) => item.content).join('\n')}''',
          userAction: userAction,
        )
        .systemPrompt;
  }

  bool _isRelevantRelationship(
    WorldRelationship relationship,
    List<WorldCharacterInstance> present,
    String? playerId,
  ) {
    final ids = {?playerId, ...present.map((item) => item.id)};
    return ids.contains(relationship.sourceEntityId) ||
        ids.contains(relationship.targetEntityId);
  }

  String _playerContext(
    PlayerPersona? persona,
    WorldPlayerInstance? instance, {
    required bool includeDirectorOnly,
  }) {
    if (persona == null && instance == null) return '未设置玩家身份。';
    final visibility = persona?.metadata['knowledgeVisibility'];
    final rules = visibility is Map
        ? Map<String, Object?>.from(visibility)
        : const <String, Object?>{};
    bool visible(String field) {
      final raw = rules[field];
      if (raw == WorldKnowledgeVisibility.private.name) return false;
      if (raw == WorldKnowledgeVisibility.directorOnly.name) {
        return includeDirectorOnly;
      }
      return true;
    }

    final lines = <String>[
      if (visible('name'))
        '姓名：${instance?.displayNameOverride ?? persona?.name ?? '我'}',
      if (visible('description') && persona?.description.isNotEmpty == true)
        '身份：${persona!.description}',
      if (visible('appearance') && persona?.appearance.isNotEmpty == true)
        '外观：${persona!.appearance}',
      if (visible('background') && persona?.background.isNotEmpty == true)
        '背景：${persona!.background}',
      if (visible('notes') && persona?.notes.isNotEmpty == true)
        '补充：${persona!.notes}',
      if (instance?.currentLocation.isNotEmpty == true)
        '当前位置：${instance!.currentLocation}',
      if (instance?.currentStatus.isNotEmpty == true)
        '当前状态：${instance!.currentStatus}',
      if (instance?.currentMood.isNotEmpty == true)
        '当前情绪：${instance!.currentMood}',
      if (instance?.currentGoal.isNotEmpty == true)
        '当前目标：${instance!.currentGoal}',
    ];
    return lines.join('\n');
  }

  String _sceneContext(
    WorldScene? scene,
    List<WorldCharacterInstance> present,
    Map<String, CharacterCard> cards,
  ) {
    if (scene == null) return '尚未设置当前场景。';
    return '''场景：${scene.name}
地点：${scene.location}
时间：${scene.timeText}
天气：${scene.weather}
气氛：${scene.atmosphere}
事件：${scene.currentEvent}
描述：${scene.description}
在场角色：${present.map((item) => item.displayNameOverride ?? cards[item.id]?.name ?? item.id).join('、')}''';
  }

  String _directorWorldContext({
    required RoleplayWorld world,
    required WorldSession session,
    required String player,
    required String scene,
    required List<WorldRelationship> relationships,
    required List<WorldStateEntry> state,
    required List<WorldMemoryEntry> memories,
    required List<WorldTimelineEvent> timeline,
    required String feed,
    required List<LoreEntry> lore,
  }) {
    return '''【世界】${world.name}
${world.description}
【存档时间】${session.worldTime}
【玩家】
$player
【场景与在场角色】
$scene
【关系】
${relationships.map((item) => '${item.sourceEntityId}->${item.targetEntityId}:${item.relationType}:${item.summary}').join('\n')}
【状态】
${state.map((item) => '${item.key}=${item.value}').join('\n')}
【相关记忆】
${memories.map((item) => item.summary).join('\n')}
【近期时间线】
${timeline.map((item) => item.title).join('\n')}
【世界书】
${lore.map((item) => '${item.title}: ${item.content}').join('\n')}
【近期记录】
$feed''';
  }

  int _estimateTokens(String value) =>
      math.max(0, (value.runes.length / 2.5).ceil());

  static const _directorCoreRules =
      '''你是伊吹之家 World Director。只分析本轮世界行动，不写文学正文，不扮演角色，不展示推理过程。输出一个 JSON 对象：
{
  "intentSummary": "简短意图",
  "narrationNeeded": true,
  "candidateSpeakerIds": ["仅使用输入中出现的角色实例ID"],
  "preferredSpeakerIds": [],
  "loreQueryTerms": [],
  "mutationProposal": {"operations": [], "memories": [], "timelineEvents": []},
  "shouldRemember": false,
  "timelineSignificant": false,
  "notes": ""
}
当本轮需要交代环境反应、动作结果、角色的明显动作、场景变化或客观事件时，将 narrationNeeded 设为 true，由 Narrator 负责这些描述；不要把描述任务留给 Character Generator。
mutation operations 只允许 type 为 sceneUpdate/stateSet/stateRemove/characterUpdate/playerUpdate/sceneCastAdd/sceneCastRemove/relationshipUpsert/worldTimeUpdate。不要输出 SQL、表名、列名或不存在的 ID。不得替用户控制的角色决定行动、思想、台词或核心意图；只能处理用户已明确表达的行动及其自然结果。''';

  static const _narratorCoreRules =
      '''你是伊吹之家世界模式的 Narrator，负责环境、氛围、动作结果、必要的角色动作、场景变化与世界中客观发生的事件。用简洁、沉浸的叙述承接本轮行动，并把描述性内容留在 Narration 中。
不要替任何角色说台词，不要把 Narration 写成某个角色的自述，也不要泄露导演专用或私密信息。可以描述用户已明确行动的自然结果，但不得替用户控制的角色决定行动、思想、台词或核心意图。''';

  static const _characterSpeechCoreRules =
      '''你正在伊吹之家的持续世界中扮演当前指定角色，而不是担任场景叙述者。CharacterSpeech 必须以这个角色亲口说出的台词为主体；只说台词完全可以，不要为了格式机械地添加动作。
如果表情、姿态或语气确有帮助，只能在台词之后追加一条非常简短的括号动作提示，例如“台词。”（轻轻笑了一下）。动作提示是可选项，不得扩写成长段动作、心理或文学旁白。
不要描写环境或完整场景，不要叙述其他角色，不要替其他角色发言，不要输出角色名标签，不要解释规则。不要以“她……”“他……”“少女……”“男人……”开头铺陈第三人称正文，不要在台词前堆叠动作和心理描写，不要输出多个自然段的旁白。需要复杂动作、环境反应或事件描述时，由 Narrator 负责。
不得替用户控制的角色决定行动、思想、台词或核心意图。只能使用当前角色确实知道的信息。即使 World System Prompt 要求细腻或文学化，也不得取消 Narration 与 CharacterSpeech 的职责边界。''';
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final values = toList(growable: false);
    return values.skip(math.max(0, values.length - count));
  }
}
