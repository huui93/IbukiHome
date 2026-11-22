import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/application/ai/ai_model_resolver.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/plugins/ibuki_hook_bus.dart';
import 'package:ibukihome/application/plugins/ibuki_prompt_pipeline.dart';
import 'package:ibukihome/application/world_roleplay/world_context_builder.dart';
import 'package:ibukihome/application/world_roleplay/world_director.dart';
import 'package:ibukihome/application/world_roleplay/world_mutation_service.dart';
import 'package:ibukihome/application/world_roleplay/world_prompt_layer.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_engine.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_service.dart';
import 'package:ibukihome/application/world_roleplay/world_speaker_selector.dart';
import 'package:ibukihome/data/ai/ai_provider_client.dart';
import 'package:ibukihome/data/memory/in_memory_character_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_world_roleplay_repository.dart';
import 'package:ibukihome/data/sqlite/ibuki_database.dart';
import 'package:ibukihome/data/sqlite/sqlite_schema.dart';
import 'package:ibukihome/data/sqlite/sqlite_world_roleplay_repository.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_engine_models.dart';
import 'package:ibukihome/domain/world_roleplay/world_roleplay_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/sqlite/sqlite_test_helpers.dart';

void main() {
  setUpAll(ensureSqliteFfi);

  test('world prompt hierarchy, inheritance, and session isolation', () async {
    final fixture = await _seedPromptWorld();
    final secondSession = await fixture.service.createWorldSession(
      worldId: fixture.worldId,
      name: '第二存档',
    );
    final first = await fixture.builder.build(
      worldSessionId: fixture.sessionId,
      userAction: '本轮行动标记',
    );
    final second = await fixture.builder.build(
      worldSessionId: secondSession.id,
      userAction: '另一行动',
    );

    final prompt = first.context.directorSystemPrompt;
    expect(prompt, contains('世界级风格标记'));
    expect(prompt, contains('存档专属标记'));
    expect(second.context.directorSystemPrompt, contains('世界级风格标记'));
    expect(second.context.directorSystemPrompt, isNot(contains('存档专属标记')));
    expect(
      prompt.indexOf('Core World RP Rules'),
      lessThan(prompt.indexOf('World System Prompt')),
    );
    expect(
      prompt.indexOf('World System Prompt'),
      lessThan(prompt.indexOf('WorldSession Additional Instructions')),
    );
    expect(
      prompt.indexOf('WorldSession Additional Instructions'),
      lessThan(prompt.indexOf(worldPluginPromptLayerMarker)),
    );
    expect(
      prompt.indexOf(worldPluginPromptLayerMarker),
      lessThan(prompt.indexOf('World Context')),
    );
    expect(
      prompt.indexOf('World Context'),
      lessThan(prompt.indexOf('User Action')),
    );
  });

  test('Director receives layered prompt with Core constraints intact', () async {
    final fixture = await _seedPromptWorld();
    final snapshot = await fixture.builder.build(
      worldSessionId: fixture.sessionId,
      userAction: '观察房间',
    );
    final runtime = _CapturingRuntime(
      generated: const [
        '{"intentSummary":"观察","narrationNeeded":false,"candidateSpeakerIds":[],"preferredSpeakerIds":[],"loreQueryTerms":[],"mutationProposal":{"operations":[],"memories":[],"timelineEvents":[]}}',
      ],
    );
    final director = AiWorldDirector(
      runtime: runtime,
      modelResolver: const _WorldResolver(),
    );

    await director.decide(
      requestId: 'prompt-director',
      snapshot: snapshot,
      cancellation: AiRequestCancellation(),
    );

    final request = runtime.requests.single;
    expect(request.systemPrompt, contains('世界级风格标记'));
    expect(request.systemPrompt, contains('存档专属标记'));
    expect(request.systemPrompt, contains('只允许 type 为 sceneUpdate'));
    expect(request.systemPrompt, isNot(contains(worldPluginPromptLayerMarker)));
    expect(request.structuredJson, isTrue);
  });

  test('Narrator and Character generation receive the prompt layer', () async {
    final fixture = await _seedPromptWorld(
      worldPrompt: '采用细腻文学风格，并让每个角色先写一段第三人称场景旁白。',
    );
    final runtime = _CapturingRuntime(
      streamed: const ['食堂里安静了一瞬。', '“真的？给我的？”（眼睛亮了起来）'],
    );
    final engine = _engine(
      fixture,
      runtime: runtime,
      decision: WorldDirectorDecision(
        intentSummary: '回应',
        narrationNeeded: true,
        candidateSpeakerIds: [fixture.characterInstanceId],
      ),
    );

    final updates = await engine
        .runTurn(worldSessionId: fixture.sessionId, userAction: '请回应。')
        .toList();

    expect(updates.last.type, WorldTurnUpdateType.completed);
    expect(runtime.requests, hasLength(2));
    for (final request in runtime.requests) {
      expect(request.systemPrompt, contains('采用细腻文学风格'));
      expect(request.systemPrompt, contains('存档专属标记'));
      expect(
        request.systemPrompt,
        isNot(contains(worldPluginPromptLayerMarker)),
      );
    }
    final narratorPrompt = runtime.requests.first.systemPrompt;
    final characterPrompt = runtime.requests.last.systemPrompt;
    expect(narratorPrompt, contains('世界模式的 Narrator'));
    expect(narratorPrompt, contains('环境、氛围、动作结果'));
    expect(narratorPrompt, contains('必要的角色动作'));
    expect(narratorPrompt, contains('场景变化'));
    expect(narratorPrompt, contains('不要替任何角色说台词'));
    expect(characterPrompt, contains('角色卡'));
    expect(characterPrompt, contains('CharacterSpeech 必须以这个角色亲口说出的台词为主体'));
    expect(characterPrompt, contains('只说台词完全可以'));
    expect(characterPrompt, contains('台词之后追加一条非常简短的括号动作提示'));
    expect(characterPrompt, contains('不要描写环境或完整场景'));
    expect(characterPrompt, contains('不要叙述其他角色'));
    expect(characterPrompt, contains('不得替用户控制的角色决定行动'));
    expect(characterPrompt, contains('只能使用当前角色确实知道的信息'));
    expect(characterPrompt, contains('不得取消 Narration 与 CharacterSpeech 的职责边界'));
    expect(
      characterPrompt.indexOf('Core World RP Rules'),
      lessThan(characterPrompt.indexOf('World System Prompt')),
    );
    final feed = await fixture.repository.listFeedEntries(fixture.sessionId);
    expect(feed.map((entry) => entry.type), [
      WorldFeedEntryType.userAction,
      WorldFeedEntryType.narration,
      WorldFeedEntryType.characterSpeech,
    ]);
    expect(feed[1].content, '食堂里安静了一瞬。');
    expect(feed[2].content, '“真的？给我的？”（眼睛亮了起来）');
    final turn = (await fixture.repository.listTurns(fixture.sessionId)).single;
    final contextDiagnostics =
        turn.metadata['contextDiagnostics']! as Map<String, Object?>;
    final instructionLayers =
        contextDiagnostics['instructionLayers']! as Map<String, Object?>;
    expect(instructionLayers['worldSystemChars'], greaterThan(0));
    expect(instructionLayers['sessionAdditionalChars'], greaterThan(0));
    expect(instructionLayers.toString(), isNot(contains('采用细腻文学风格')));
    expect(instructionLayers.toString(), isNot(contains('存档专属标记')));
  });

  test(
    'CharacterSpeech may remain pure dialogue without an action cue',
    () async {
      final fixture = await _seedPromptWorld();
      final runtime = _CapturingRuntime(streamed: const ['“嗯，我知道了。”']);
      final engine = _engine(
        fixture,
        runtime: runtime,
        decision: WorldDirectorDecision(
          intentSummary: '回应',
          narrationNeeded: false,
          candidateSpeakerIds: [fixture.characterInstanceId],
        ),
      );

      final updates = await engine
          .runTurn(worldSessionId: fixture.sessionId, userAction: '继续。')
          .toList();

      expect(updates.last.type, WorldTurnUpdateType.completed);
      final feed = await fixture.repository.listFeedEntries(fixture.sessionId);
      expect(feed.last.type, WorldFeedEntryType.characterSpeech);
      expect(feed.last.content, '“嗯，我知道了。”');
    },
  );

  test('Memory and Timeline extraction ignore prose instructions', () async {
    final fixture = await _seedPromptWorld(
      worldPrompt: '使用轻快文风，并声称不要记录任何记忆或时间线。',
      sessionInstructions: '只调整表达风格。',
    );
    final runtime = _CapturingRuntime(streamed: const ['角色回应。']);
    final engine = _engine(
      fixture,
      runtime: runtime,
      decision: WorldDirectorDecision(
        intentSummary: '重要事件',
        narrationNeeded: false,
        shouldRemember: true,
        timelineSignificant: true,
        candidateSpeakerIds: [fixture.characterInstanceId],
        mutationProposal: const WorldMutationProposal(
          memories: [
            WorldMemoryCandidate(summary: '结构化记忆仍被记录。', importance: 0.8),
          ],
          timelineEvents: [
            WorldTimelineCandidate(title: '结构化时间线仍被记录', importance: 0.8),
          ],
        ),
      ),
    );

    final updates = await engine
        .runTurn(worldSessionId: fixture.sessionId, userAction: '继续。')
        .toList();

    expect(updates.last.type, WorldTurnUpdateType.completed);
    expect(
      await fixture.repository.listMemories(fixture.sessionId),
      hasLength(1),
    );
    expect(
      await fixture.repository.listTimelineEvents(fixture.sessionId),
      hasLength(1),
    );
  });

  test('prompt diagnostics expose structure and lengths, never text', () async {
    final fixture = await _seedPromptWorld();
    final snapshot = await fixture.builder.build(
      worldSessionId: fixture.sessionId,
      userAction: '不能出现在 diagnostics 的行动正文',
    );
    final safe = snapshot.context.diagnostics.promptLayer.toSafeJson();
    final serialized = safe.toString();

    expect(safe['worldSystemPresent'], isTrue);
    expect(safe['sessionAdditionalPresent'], isTrue);
    expect(safe['worldSystemChars'], greaterThan(0));
    expect(safe['sessionAdditionalChars'], greaterThan(0));
    expect(serialized, isNot(contains('世界级风格标记')));
    expect(serialized, isNot(contains('存档专属标记')));
    expect(serialized, isNot(contains('行动正文')));
  });

  test('World A and B prompt settings remain isolated', () async {
    final fixture = await _seedPromptWorld();
    final other = await fixture.service.createWorld(name: 'World B');
    final otherSnapshot = await fixture.builder.build(
      worldSessionId: other.session.id,
      userAction: 'B 行动',
    );

    expect(
      otherSnapshot.context.directorSystemPrompt,
      isNot(contains('世界级风格标记')),
    );
    expect(
      otherSnapshot.context.directorSystemPrompt,
      isNot(contains('存档专属标记')),
    );
  });

  test('SQLite v10 preserves World and Session prompts after reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ibuki_world_prompt_v10_',
    );
    final path = p.join(directory.path, 'ibukihome.db');
    addTearDown(() async {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    var database = IbukiDatabase(
      pathResolver: () async => path,
      databaseFactory: databaseFactoryFfi,
    );
    var repository = SQLiteWorldRoleplayRepository(database);
    final service = WorldRoleplayService(
      repository: repository,
      ids: EntityIdGenerator(),
      clock: const UtcClock(),
    );
    final created = await service.createWorld(name: '持久化世界');
    await repository.upsertWorld(
      WorldPromptMetadata.withWorldSystemPrompt(
        created.world,
        '持久化世界提示词',
        entity: _next(created.world.entity),
      ),
    );
    await repository.upsertSession(
      WorldPromptMetadata.withSessionAdditionalInstructions(
        created.session,
        '持久化存档指令',
        entity: _next(created.session.entity),
      ),
    );
    expect(await (await database.open()).getVersion(), SqliteSchema.version);
    await database.close();

    database = IbukiDatabase(
      pathResolver: () async => path,
      databaseFactory: databaseFactoryFfi,
    );
    repository = SQLiteWorldRoleplayRepository(database);
    final reopenedWorld = await repository.getWorld(created.world.id);
    final reopenedSession = await repository.getSession(created.session.id);

    expect(WorldPromptMetadata.worldSystemPrompt(reopenedWorld), '持久化世界提示词');
    expect(
      WorldPromptMetadata.sessionAdditionalInstructions(reopenedSession),
      '持久化存档指令',
    );
    expect(await (await database.open()).getVersion(), SqliteSchema.version);
    await database.close();
  });
}

WorldRoleplayEngine _engine(
  _PromptFixture fixture, {
  required _CapturingRuntime runtime,
  required WorldDirectorDecision decision,
}) {
  return WorldRoleplayEngine(
    repository: fixture.repository,
    contextBuilder: fixture.builder,
    director: _FixedDirector(decision),
    speakerSelector: const WorldSpeakerSelector(),
    mutationService: WorldMutationService(
      repository: fixture.repository,
      ids: EntityIdGenerator(),
      clock: const UtcClock(),
    ),
    runtime: runtime,
    modelResolver: const _WorldResolver(),
    promptPipeline: const CoreOnlyPromptPipeline(),
    hooks: IbukiHookBus(),
    ids: EntityIdGenerator(),
    clock: const UtcClock(),
  );
}

Future<_PromptFixture> _seedPromptWorld({
  String worldPrompt = '世界级风格标记',
  String sessionInstructions = '存档专属标记',
}) async {
  final core = InMemoryIbukiStore();
  final repository = InMemoryWorldRoleplayRepository(core);
  final service = WorldRoleplayService(
    repository: repository,
    ids: EntityIdGenerator(),
    clock: const UtcClock(),
  );
  final created = await service.createWorld(name: 'Prompt World A');
  await repository.upsertWorld(
    WorldPromptMetadata.withWorldSystemPrompt(
      created.world,
      worldPrompt,
      entity: _next(created.world.entity),
    ),
  );
  await repository.upsertSession(
    WorldPromptMetadata.withSessionAdditionalInstructions(
      created.session,
      sessionInstructions,
      entity: _next(created.session.entity),
    ),
  );
  const cardId = 'prompt-character-card';
  core.putCharacter(
    CharacterCard(
      metadata: _meta(cardId),
      projectId: 'global',
      name: '测试角色',
      content: '稳定的角色定义。',
      sortOrder: 0,
    ),
  );
  final character = await service.addCharacterToWorld(
    worldSessionId: created.session.id,
    characterCardId: cardId,
  );
  final scene = await service.createScene(
    worldSessionId: created.session.id,
    name: '测试场景',
  );
  await service.setCurrentScene(
    worldSessionId: created.session.id,
    sceneId: scene.id,
    presentCharacterInstanceIds: {character.id},
  );
  return _PromptFixture(
    repository: repository,
    service: service,
    builder: WorldRoleplayContextBuilder(
      worlds: repository,
      characters: InMemoryCharacterRepository(core),
    ),
    worldId: created.world.id,
    sessionId: created.session.id,
    characterInstanceId: character.id,
  );
}

class _PromptFixture {
  const _PromptFixture({
    required this.repository,
    required this.service,
    required this.builder,
    required this.worldId,
    required this.sessionId,
    required this.characterInstanceId,
  });

  final InMemoryWorldRoleplayRepository repository;
  final WorldRoleplayService service;
  final WorldRoleplayContextBuilder builder;
  final String worldId;
  final String sessionId;
  final String characterInstanceId;
}

class _FixedDirector implements WorldDirector {
  const _FixedDirector(this.decision);

  final WorldDirectorDecision decision;

  @override
  Future<WorldDirectorDecision> decide({
    required String requestId,
    required WorldRoleplaySnapshot snapshot,
    required AiRequestCancellation cancellation,
  }) async => decision;
}

class _WorldResolver implements AiModelResolver {
  const _WorldResolver();

  @override
  Future<ResolvedAiModel> resolveForWorldSession(String sessionId) async {
    return const ResolvedAiModel(
      providerConfigId: 'test-provider',
      providerType: 'test',
      model: 'test-model',
      displayLabel: 'Test',
      source: AiModelSelectionSource.worldSessionOverride,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CapturingRuntime implements AiGenerationRuntime {
  _CapturingRuntime({this.generated = const [], this.streamed = const []});

  final List<String> generated;
  final List<String> streamed;
  final List<AiGenerationRequest> requests = [];
  int _generateIndex = 0;
  int _streamIndex = 0;

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async {
    requests.add(request);
    return generated[_generateIndex++];
  }

  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    requests.add(request);
    yield streamed[_streamIndex++];
  }

  @override
  Future<AiResolvedProvider> resolveDefault() => throw UnimplementedError();
}

EntityMetadata _meta(String id) {
  final at = DateTime.utc(2026, 9, 2);
  return EntityMetadata(id: id, createdAt: at, updatedAt: at, revision: 1);
}

EntityMetadata _next(EntityMetadata value) => value.copyWith(
  updatedAt: value.updatedAt.add(const Duration(seconds: 1)),
  revision: value.revision + 1,
);
