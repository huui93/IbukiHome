import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/ai_provider_config_repository.dart';
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/tavern_repository.dart';
import '../../data/repositories/world_repository.dart';
import '../../data/repositories/world_roleplay_repository.dart';
import '../../domain/ai/ai_provider_config.dart';
import '../../domain/characters/character_card.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/projects/project.dart';
import '../../domain/tavern/tavern_models.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';
import '../common/entity_id_generator.dart';
import '../common/utc_clock.dart';
import 'provider/tavern_model_profile_store.dart';
import 'provider/tavern_provider_models.dart';

class TavernWorldChoice {
  const TavernWorldChoice(this.type, this.id, this.name, this.description);
  final String type, id, name, description;
  String get key => '$type:$id';
}

class TavernAssetCatalog {
  const TavernAssetCatalog({
    required this.characters,
    required this.worlds,
    required this.personas,
    required this.books,
  });
  final List<CharacterCard> characters;
  final List<TavernWorldChoice> worlds;
  final List<PlayerPersona> personas;
  final List<WorldBook> books;
}

class TavernStoryDraft {
  const TavernStoryDraft({
    required this.title,
    required this.characterIds,
    this.personaId,
    this.personaName = '',
    this.personaDescription = '',
    this.world,
    this.bookIds = const {},
    this.sceneName = '初始场景',
    this.sceneDescription = '',
    this.timeText = '',
    this.binding = const {},
  });
  final String title,
      personaName,
      personaDescription,
      sceneName,
      sceneDescription,
      timeText;
  final String? personaId;
  final TavernWorldChoice? world;
  final Set<String> characterIds, bookIds;
  final Map<String, Object?> binding;
}

TavernSession editTavernSession(
  TavernSession old, {
  String? title,
  Map<String, Object?>? metadata,
  DateTime? now,
}) => TavernSession(
  id: old.id,
  title: title ?? old.title,
  createdAt: old.createdAt,
  updatedAt: now ?? old.updatedAt,
  activeStoryLineId: old.activeStoryLineId,
  worldAssetType: old.worldAssetType,
  worldAssetId: old.worldAssetId,
  personaType: old.personaType,
  personaId: old.personaId,
  runtimeConfigId: old.runtimeConfigId,
  metadata: metadata ?? old.metadata,
  archivedAt: old.archivedAt,
  deletedAt: old.deletedAt,
);

class TavernStoryService {
  const TavernStoryService({
    required this.repository,
    required this.characters,
    required this.worlds,
    required this.worldCards,
    required this.projects,
    required this.configs,
    required this.profiles,
    required this.ids,
    this.clock = const UtcClock(),
  });
  final TavernRepository repository;
  final CharacterRepository characters;
  final WorldRoleplayRepository worlds;
  final WorldRepository worldCards;
  final ProjectRepository projects;
  final AiProviderConfigRepository configs;
  final TavernModelProfileStore profiles;
  final EntityIdGenerator ids;
  final UtcClock clock;

  EntityMetadata _entity(String prefix) => EntityMetadata(
    id: ids.nextId(prefix),
    createdAt: clock.now(),
    updatedAt: clock.now(),
    revision: 1,
  );

  Future<TavernAssetCatalog> loadAssets() async {
    final cards = <CharacterCard>[],
        places = <TavernWorldChoice>[],
        personas = <PlayerPersona>[];
    for (final project in await projects.listProjects()) {
      cards.addAll(await characters.listCharacters(project.id));
      places.addAll(
        (await worldCards.listWorldCards(
          project.id,
        )).map((w) => TavernWorldChoice('worldCard', w.id, w.title, w.content)),
      );
    }
    for (final world in await worlds.listWorlds()) {
      places.add(
        TavernWorldChoice(
          'roleplayWorld',
          world.id,
          world.name,
          world.description,
        ),
      );
      personas.addAll(await worlds.listPersonas(world.id));
    }
    personas.addAll(await worlds.listPersonas(worldBookLibraryOwnerId));
    return TavernAssetCatalog(
      characters: List.unmodifiable(cards),
      worlds: List.unmodifiable(places),
      personas: List.unmodifiable(personas),
      books: List.unmodifiable(await worlds.listWorldBookLibrary()),
    );
  }

  Future<PlayerPersona> createPersona(String name, String description) async {
    if (name.trim().isEmpty) throw ArgumentError('请输入我的角色名字。');
    try {
      await worlds.getWorld(worldBookLibraryOwnerId);
    } on EntityNotFoundException {
      await worlds.upsertWorld(
        RoleplayWorld(
          entity: EntityMetadata(
            id: worldBookLibraryOwnerId,
            createdAt: clock.now(),
            updatedAt: clock.now(),
            revision: 1,
          ),
          name: '世界书库',
          metadata: const {'library': true},
        ),
      );
    }
    final persona = PlayerPersona(
      entity: _entity('player_persona'),
      worldId: worldBookLibraryOwnerId,
      name: name.trim(),
      description: description.trim(),
      metadata: const {
        'knowledgeVisibility': {
          'name': 'public',
          'description': 'public',
          'appearance': 'public',
          'background': 'public',
          'notes': 'private',
        },
      },
    );
    await worlds.upsertPersona(persona);
    return persona;
  }

  Future<CharacterCard> createCharacter(String name, String content) async {
    if (name.trim().isEmpty) throw ArgumentError('请输入角色名字。');
    final existing = await projects.listProjects();
    late final String projectId;
    if (existing.isEmpty) {
      final project = Project(
        metadata: _entity('project'),
        title: '角色资源库',
        description: '我的角色卡',
      );
      await projects.upsertProject(project);
      projectId = project.id;
    } else {
      projectId = existing.first.id;
    }
    final card = CharacterCard(
      metadata: _entity('character'),
      projectId: projectId,
      name: name.trim(),
      content: content.trim(),
      sortOrder: (await characters.listCharacters(projectId)).length,
      mode: CharacterCardMode.original,
    );
    await characters.upsertCharacter(card);
    return card;
  }

  Future<TavernSession> createStory(TavernStoryDraft draft) async {
    if (draft.title.trim().isEmpty) throw ArgumentError('请输入故事名字。');
    final cast = <CharacterCard>[];
    for (final id in draft.characterIds) {
      final card = await characters.getCharacter(id);
      if (card.deletedAt != null) throw ArgumentError('所选角色已经删除。');
      cast.add(card);
    }
    if (draft.world?.type == 'worldCard') {
      final world = await worldCards.getWorldCard(draft.world!.id);
      if (world.deletedAt != null) throw ArgumentError('所选世界已经删除。');
    } else if (draft.world?.type == 'roleplayWorld') {
      await worlds.getWorld(draft.world!.id);
    } else if (draft.world != null) {
      throw ArgumentError('所选世界类型不受支持。');
    }
    for (final id in draft.bookIds) {
      await worlds.getWorldBook(id);
    }
    if (draft.binding.isNotEmpty) {
      await resolveBinding(draft.binding);
    }
    final persona = draft.personaId == null
        ? await createPersona(draft.personaName, draft.personaDescription)
        : await worlds.getPersona(draft.personaId!);
    final sessionId = ids.nextId('tavern_session'),
        lineId = ids.nextId('tavern_line');
    final participants = <TavernParticipant>[
      TavernParticipant(
        id: ids.nextId('tavern_player'),
        sessionId: sessionId,
        kind: TavernParticipantKind.persona,
        entityId: persona.id,
        displayName: persona.name,
        position: 0,
      ),
      for (var i = 0; i < cast.length; i++)
        TavernParticipant(
          id: ids.nextId('tavern_character'),
          sessionId: sessionId,
          kind: TavernParticipantKind.character,
          entityId: cast[i].id,
          displayName: cast[i].name,
          position: i + 1,
        ),
    ];
    return repository.createSession(
      TavernSession(
        id: sessionId,
        title: draft.title.trim(),
        createdAt: clock.now(),
        updatedAt: clock.now(),
        worldAssetType: draft.world?.type,
        worldAssetId: draft.world?.id,
        personaType: 'playerPersona',
        personaId: persona.id,
        metadata: {
          'tavernBindingV1': draft.binding,
          'tavernSceneV1': {
            'name': draft.sceneName.trim().isEmpty
                ? '初始场景'
                : draft.sceneName.trim(),
            'description': draft.sceneDescription.trim(),
            'timeText': draft.timeText.trim(),
          },
          'tavernBookReferencesV1': {
            for (final id in draft.bookIds)
              id: {'enabled': true, 'priority': 0},
          },
        },
      ),
      TavernStoryLine(
        id: lineId,
        sessionId: sessionId,
        name: '主线',
        position: 0,
        createdAt: clock.now(),
      ),
      participants: participants,
    );
  }

  Future<TavernProviderBinding> resolveBinding(
    Map<String, Object?> settings,
  ) async {
    final providerId = settings['providerId'], model = settings['model'];
    if (providerId is! String || model is! String || model.trim().isEmpty) {
      throw const TavernProviderFailure(TavernProviderErrorKind.unknownModel);
    }
    final config = await configs.getConfig(providerId);
    if (config == null || !config.enabled) {
      throw const TavernProviderFailure(TavernProviderErrorKind.unknownModel);
    }
    final base = await profiles.load(config, model);
    final old = base.capabilities;
    final continuation = settings['continuation'] as String?;
    final maxContext = settings['contextWindow'] as int? ?? old.contextWindow;
    final output = settings['outputTokens'] as int? ?? base.outputTokens;
    if (maxContext < 512 ||
        output < 1 ||
        output >= maxContext ||
        output > old.maximumOutput) {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.unsupportedCapability,
      );
    }
    return TavernProviderBinding(
      config: config,
      model: model,
      protocol: base.protocol,
      outputTokens: output,
      allowLocalHttp: settings['allowLocalHttp'] == true || base.allowLocalHttp,
      timeout: base.timeout,
      parameters: base.parameters,
      capabilities: TavernModelCapabilities(
        contextWindow: maxContext,
        maximumOutput: old.maximumOutput,
        systemRole: old.systemRole,
        developerRole: old.developerRole,
        streaming: old.streaming,
        streamUsage: old.streamUsage,
        reasoning: old.reasoning,
        continuation: continuation == 'instruction'
            ? TavernContinuation.instruction
            : old.continuation,
        toolCalling: old.toolCalling,
        multimodal: old.multimodal,
        tokenAccuracy: old.tokenAccuracy,
        allowedParameters: old.allowedParameters,
      ),
    );
  }

  Future<Map<String, Object?>> modelSettings(
    AiProviderConfig config,
    String model, {
    bool compatibleContinue = true,
    bool localHttp = false,
  }) async {
    final profile = await profiles.load(config, model);
    return {
      'providerId': config.id,
      'model': model,
      'contextWindow': profile.capabilities.contextWindow,
      'outputTokens': profile.outputTokens,
      'continuation': compatibleContinue
          ? 'instruction'
          : profile.capabilities.continuation.name,
      'allowLocalHttp': localHttp,
    };
  }

  Future<void> rename(String id, String title) async {
    if (title.trim().isEmpty) throw ArgumentError('请输入故事名字。');
    await repository.saveSession(
      editTavernSession(
        await repository.getSession(id),
        title: title.trim(),
        now: clock.now(),
      ),
    );
  }

  Future<void> saveSettings(String id, Map<String, Object?> settings) async {
    final refs = settings['tavernBookReferencesV1'];
    if (refs is Map) {
      for (final key in refs.keys) {
        await worlds.getWorldBook(key as String);
      }
    }
    final binding = settings['tavernBindingV1'];
    if (binding is Map && binding.isNotEmpty) {
      await resolveBinding(Map<String, Object?>.from(binding));
    }
    final session = await repository.getSession(id);
    await repository.saveSession(
      editTavernSession(
        session,
        metadata: {...session.metadata, ...settings},
        now: clock.now(),
      ),
    );
  }
}
