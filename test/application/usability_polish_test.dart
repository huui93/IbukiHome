import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/application/ai/ai_model_resolver.dart';
import 'package:ibukihome/application/ai/card_completion.dart';
import 'package:ibukihome/application/ai/character_reference_lookup.dart';
import 'package:ibukihome/application/ai/novel_context_loader.dart';
import 'package:ibukihome/application/ai/novel_outline_context.dart';
import 'package:ibukihome/application/ai/novel_prompt_builder.dart';
import 'package:ibukihome/application/memory/novel_memory_context.dart';
import 'package:ibukihome/application/ai/save_ai_model_binding.dart';
import 'package:ibukihome/application/chat/create_chat_session.dart';
import 'package:ibukihome/application/chat/open_persona_chat.dart';
import 'package:ibukihome/application/memory/chat_memory_service.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/core/network/ai_provider_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_character_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_memory_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_persona_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/data/memory/in_memory_outline_repository.dart';
import 'package:ibukihome/data/memory/in_memory_segment_repository.dart';
import 'package:ibukihome/data/memory/in_memory_world_repository.dart';
import 'package:ibukihome/domain/ai/ai_default_selection.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import 'package:ibukihome/domain/chat/chat_memory_entry.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';

void main() {
  group('multi-session chat', () {
    test('new chat always creates while continue reuses latest', () async {
      final fixture = _Fixture();
      final first = await fixture.opener.createNew(
        personaId: 'persona',
        newSessionId: 's1',
        nowUtc: _now,
      );
      final second = await fixture.opener.createNew(
        personaId: 'persona',
        newSessionId: 's2',
        nowUtc: _now.add(const Duration(minutes: 1)),
      );
      final continued = await fixture.opener.continueLatest(
        personaId: 'persona',
        newSessionId: 'unused',
        nowUtc: _now,
      );
      expect(first.id, 's1');
      expect(second.id, 's2');
      expect(continued.id, 's2');
      expect(
        await fixture.chats.listSessions(personaId: 'persona'),
        hasLength(4),
      );
    });

    test('manual memories are session isolated', () async {
      final fixture = _Fixture();
      await fixture.memory.saveManual(
        personaId: 'persona',
        sessionId: 'session-a',
        category: ChatMemoryCategory.relationship,
        content: 'A only',
        pinned: true,
        nowUtc: _now,
      );
      final a = await fixture.memory.loadContext(
        personaId: 'persona',
        sessionId: 'session-a',
      );
      final b = await fixture.memory.loadContext(
        personaId: 'persona',
        sessionId: 'session-b',
      );
      expect(a.pinned.single.content, 'A only');
      expect(b.pinned, isEmpty);
    });
  });

  group('scoped AI model', () {
    test(
      'project override persists and resolves above global default',
      () async {
        final fixture = _Fixture();
        await SaveProjectAiBinding(fixture.projects)(
          projectId: 'project',
          providerConfigId: 'gemini',
          model: 'gemini-long',
          nowUtc: _now,
        );
        final resolved = await fixture.resolver.resolveForProject('project');
        expect(resolved.providerConfigId, 'gemini');
        expect(resolved.model, 'gemini-long');
        expect(resolved.source, AiModelSelectionSource.projectOverride);
      },
    );

    test('session override does not leak to another session', () async {
      final fixture = _Fixture();
      await SaveChatSessionAiBinding(fixture.chats)(
        sessionId: 'session-a',
        providerConfigId: 'gemini',
        model: 'gemini-long',
        nowUtc: _now,
      );
      expect(
        (await fixture.resolver.resolveForChatSession('session-a')).source,
        AiModelSelectionSource.sessionOverride,
      );
      expect(
        (await fixture.resolver.resolveForChatSession('session-b')).source,
        AiModelSelectionSource.globalDefault,
      );
    });

    test(
      'project can switch repeatedly between default and overrides',
      () async {
        final fixture = _Fixture();
        final save = SaveProjectAiBinding(fixture.projects);

        await save(
          projectId: 'project',
          providerConfigId: 'gemini',
          model: 'gemini-long',
          nowUtc: _now,
        );
        expect(
          (await fixture.resolver.resolveForProject(
            'project',
          )).providerConfigId,
          'gemini',
        );
        await save(
          projectId: 'project',
          providerConfigId: null,
          model: null,
          nowUtc: _now.add(const Duration(minutes: 1)),
        );
        expect(
          (await fixture.resolver.resolveForProject(
            'project',
          )).providerConfigId,
          'deepseek',
        );
        await save(
          projectId: 'project',
          providerConfigId: 'deepseek',
          model: 'deepseek-explicit',
          nowUtc: _now.add(const Duration(minutes: 2)),
        );
        final explicit = await fixture.resolver.resolveForProject('project');
        expect(explicit.providerConfigId, 'deepseek');
        expect(explicit.model, 'deepseek-explicit');
        expect(explicit.source, AiModelSelectionSource.projectOverride);
      },
    );

    test('session bindings remain isolated across repeated switches', () async {
      final fixture = _Fixture();
      final save = SaveChatSessionAiBinding(fixture.chats);
      await save(
        sessionId: 'session-a',
        providerConfigId: 'gemini',
        model: 'gemini-long',
        nowUtc: _now,
      );
      await save(
        sessionId: 'session-b',
        providerConfigId: 'deepseek',
        model: 'deepseek-session',
        nowUtc: _now,
      );

      expect(
        (await fixture.resolver.resolveForChatSession('session-a')).model,
        'gemini-long',
      );
      expect(
        (await fixture.resolver.resolveForChatSession('session-b')).model,
        'deepseek-session',
      );
      await save(
        sessionId: 'session-a',
        providerConfigId: null,
        model: null,
        nowUtc: _now.add(const Duration(minutes: 1)),
      );
      expect(
        (await fixture.resolver.resolveForChatSession('session-a')).source,
        AiModelSelectionSource.globalDefault,
      );
      expect(
        (await fixture.resolver.resolveForChatSession('session-b')).model,
        'deepseek-session',
      );
    });
  });

  group('card completion JSON', () {
    test('card prompt accepts a project without outline nodes', () async {
      final fixture = _Fixture();
      final service = CardCompletionService(
        contextLoader: NovelContextLoader(
          projects: fixture.projects,
          segments: InMemorySegmentRepository(fixture.store),
          characters: fixture.characters,
          worlds: InMemoryWorldRepository(fixture.store),
          outlines: InMemoryOutlineRepository(fixture.store),
        ),
        runtime: fixture.runtime,
        modelResolver: fixture.resolver,
      );
      final card = CharacterCard(
        metadata: _metadata('character'),
        projectId: 'project',
        name: '林雾',
        content: '',
        sortOrder: 0,
      );
      fixture.store.putCharacter(card);
      fixture.runtime.generated =
          '{"suggestions":[{"field":"content","value":"谨慎",'
          '"reason":"测试","inferred":false}]}';

      final values = await service.completeCharacter(
        card: card,
        mode: CardCompletionMode.fillBlank,
        instruction: '',
        requestId: 'request',
      );

      expect(values.single.suggestedValue, '谨慎');
    });

    test('ignores unknown fields and preserves inferred marker', () {
      final values = parseCardCompletionSuggestions(
        '{"suggestions":['
        '{"field":"content","value":"安静谨慎","reason":"正文动作","inferred":false},'
        '{"field":"deletedAt","value":"x","reason":"x","inferred":false},'
        '{"field":"name","value":"小雨","reason":"暗示","inferred":true}'
        ']}',
        current: const {'name': '', 'content': ''},
        allowedFields: const {'name', 'content'},
      );
      expect(values, hasLength(2));
      expect(values.last.inferred, isTrue);
      expect(values.map((item) => item.field), isNot(contains('deletedAt')));
    });

    test('rejects invalid JSON instead of changing a card', () {
      expect(
        () => parseCardCompletionSuggestions(
          'not-json',
          current: const {'name': '', 'content': ''},
          allowedFields: const {'name', 'content'},
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('parses fenced Gemini JSON with surrounding explanation', () {
      final values = parseCardCompletionSuggestions(
        '整理结果如下：\n```json\n'
        '{"suggestions":[{"field":"content","suggestedValue":"银白长发",'
        '"reason":"模型知识","source":"modelKnowledge","inferred":false}]}'
        '\n```\n请确认后应用。',
        current: const {'content': ''},
        allowedFields: const {'content'},
      );
      expect(values.single.suggestedValue, '银白长发');
      expect(values.single.source, CardSuggestionSource.modelKnowledge);
    });

    test('skips unrelated JSON before the suggestions object', () {
      final values = parseCardCompletionSuggestions(
        '{"status":"draft"}\n'
        '{"suggestions":[{"field":"content","value":"可靠",'
        '"reason":"正文依据","source":"storyEvidence","inferred":false}]}',
        current: const {'content': ''},
        allowedFields: const {'content'},
      );
      expect(values.single.suggestedValue, '可靠');
    });

    test('rejects a copied placeholder field instead of writing it', () {
      expect(
        () => parseCardCompletionSuggestions(
          '{"suggestions":[{"field":"白名单字段名","value":"内容",'
          '"reason":"无效字段","source":"creativeDraft","inferred":false}]}',
          current: const {'name': '', 'content': ''},
          allowedFields: const {'name', 'content'},
        ),
        throwsA(isA<AiProviderInvalidResponseException>()),
      );
    });

    test('fanfic prompt gives author changes priority over canon', () {
      final fixture = _Fixture();
      final prompt = const CharacterCardCompletionPromptBuilder().build(
        context: _context(fixture),
        card: CharacterCard(
          metadata: _metadata('fanfic'),
          projectId: 'project',
          name: '测试角色',
          content: '冷静、寡言，长期穿白色大衣。',
          sortOrder: 0,
          mode: CharacterCardMode.fanfic,
          sourceWorkTitle: '测试原作',
          sourceCharacterName: '测试角色',
          sourceVersionHint: '通常形态',
          fanficAdaptationNotes: '本世界线性格更安静，服装改为白色大衣。',
        ),
        mode: CardCompletionMode.canonReference,
        instruction: '',
      );
      expect(prompt, contains('作者当前角色卡 > 作者二创设定'));
      expect(prompt, contains('本世界线性格更安静'));
      expect(prompt, contains('没有真实参考证据时'));
      expect(prompt, contains('field 只允许从 name、content 中选择'));
      expect(prompt, isNot(contains('白名单字段名')));
    });

    test('novel prompt keeps adaptation above model canon knowledge', () {
      final card = CharacterCard(
        metadata: _metadata('fanfic'),
        projectId: 'project',
        name: '测试角色',
        content: '当前卡：冷静寡言，穿白色大衣。',
        sortOrder: 0,
        mode: CharacterCardMode.fanfic,
        sourceWorkTitle: '测试原作',
        sourceCharacterName: '测试角色',
        fanficAdaptationNotes: '二创：不使用原作红色服装。',
      );
      final prompt = const NovelPromptBuilder().buildContinue(
        project: _project(),
        segments: const [],
        characters: [card],
        worldCards: const [],
        instruction: '',
      );
      expect(prompt.systemPrompt, contains('作者当前角色卡，最高优先级'));
      expect(prompt.systemPrompt, contains('二创设定 / 与原作不同之处'));
      expect(prompt.systemPrompt, contains('不得用模型对原作的记忆覆盖'));
    });

    test(
      'model knowledge cannot masquerade as verified canon evidence',
      () async {
        final fixture = _Fixture();
        final service = CardCompletionService(
          contextLoader: NovelContextLoader(
            projects: fixture.projects,
            segments: InMemorySegmentRepository(fixture.store),
            characters: fixture.characters,
            worlds: InMemoryWorldRepository(fixture.store),
            outlines: InMemoryOutlineRepository(fixture.store),
          ),
          runtime: fixture.runtime,
          modelResolver: fixture.resolver,
        );
        final card = CharacterCard(
          metadata: _metadata('fanfic'),
          projectId: 'project',
          name: '测试角色',
          content: '',
          sortOrder: 0,
          mode: CharacterCardMode.fanfic,
          sourceWorkTitle: '测试原作',
          sourceCharacterName: '测试角色',
        );
        fixture.runtime.generated =
            '{"suggestions":[{"field":"content","value":"参考内容",'
            '"reason":"模型知识","source":"canonReference","inferred":false}]}';
        final values = await service.completeCharacter(
          card: card,
          mode: CardCompletionMode.canonReference,
          instruction: '',
          requestId: 'request',
        );
        expect(values.single.source, CardSuggestionSource.modelKnowledge);
      },
    );

    test('verified reference evidence remains canon reference', () async {
      final fixture = _Fixture();
      final service = CardCompletionService(
        contextLoader: NovelContextLoader(
          projects: fixture.projects,
          segments: InMemorySegmentRepository(fixture.store),
          characters: fixture.characters,
          worlds: InMemoryWorldRepository(fixture.store),
          outlines: InMemoryOutlineRepository(fixture.store),
        ),
        runtime: fixture.runtime,
        modelResolver: fixture.resolver,
        referenceLookup: const _ReferenceLookup(),
      );
      final card = CharacterCard(
        metadata: _metadata('fanfic'),
        projectId: 'project',
        name: '测试角色',
        content: '',
        sortOrder: 0,
        mode: CharacterCardMode.fanfic,
        sourceWorkTitle: '测试原作',
        sourceCharacterName: '测试角色',
      );
      fixture.runtime.generated =
          '{"suggestions":[{"field":"content","value":"已核对内容",'
          '"reason":"来源","source":"canonReference","inferred":false}]}';
      final values = await service.completeCharacter(
        card: card,
        mode: CardCompletionMode.canonReference,
        instruction: '',
        requestId: 'request',
      );
      expect(values.single.source, CardSuggestionSource.canonReference);
    });

    test('inferred suggestion remains lowest trust even with source field', () {
      final values = parseCardCompletionSuggestions(
        '{"suggestions":[{"field":"content","value":"推测",'
        '"reason":"不确定","source":"storyEvidence","inferred":true}]}',
        current: const {'content': ''},
        allowedFields: const {'content'},
      );
      expect(values.single.source, CardSuggestionSource.inferred);
    });
  });
}

NovelAiContext _context(_Fixture fixture) => NovelAiContext(
  project: _project(),
  segments: const [],
  characters: const [],
  worldCards: const [],
  outline: const NovelOutlineContext(),
  memory: const NovelMemoryContext(),
);

class _ReferenceLookup implements CharacterReferenceLookupService {
  const _ReferenceLookup();

  @override
  Future<List<CharacterReferenceEvidence>> lookup({
    required String workTitle,
    required String characterName,
    required String versionHint,
  }) async => const [
    CharacterReferenceEvidence(
      title: '可验证参考',
      sourceType: CharacterReferenceSourceType.webEvidence,
      sourceUrl: 'https://example.test/reference',
      summary: '参考摘要',
      confidence: 0.9,
    ),
  ];
}

class _Fixture {
  _Fixture() {
    store.putProject(_project());
    store.putChatPersona(_persona());
    store.putChatSession(_session('session-a'));
    store.putChatSession(_session('session-b'));
    create = CreateChatSession(chats, personas);
    opener = OpenPersonaChat(personas, chats, create);
    memory = ChatMemoryService(
      memories: memories,
      chats: chats,
      personas: personas,
      runtime: runtime,
      ids: EntityIdGenerator(),
    );
    resolver = AiModelResolver(
      projects: projects,
      chats: chats,
      runtime: runtime,
    );
  }

  final store = InMemoryIbukiStore();
  late final projects = InMemoryProjectRepository(store);
  late final chats = InMemoryChatRepository(store);
  late final characters = InMemoryCharacterRepository(store);
  late final personas = InMemoryChatPersonaRepository(store);
  late final memories = InMemoryChatMemoryRepository(store);
  final runtime = _Runtime();
  late final CreateChatSession create;
  late final OpenPersonaChat opener;
  late final ChatMemoryService memory;
  late final AiModelResolver resolver;
}

class _Runtime implements AiDetailedGenerationRuntime {
  String generated = '';
  AiResolvedProvider _resolved(String provider, String model) =>
      AiResolvedProvider(
        config: AiProviderConfig(
          id: provider,
          type: provider == 'gemini'
              ? AiProviderType.gemini
              : AiProviderType.deepseek,
          displayName: provider,
          baseUrl: 'https://example.test',
          apiKeyRef: 'secure.$provider',
          selectedModel: model,
          enabled: true,
          connectionStatus: AiProviderConnectionStatus.connected,
          availableModels: [model],
          createdAtUtc: _now,
          updatedAtUtc: _now,
        ),
        selection: AiDefaultSelection(
          providerId: provider,
          modelId: model,
          updatedAtUtc: _now,
        ),
      );

  @override
  Future<AiResolvedProvider> resolveDefault() async =>
      _resolved('deepseek', 'deepseek-default');

  @override
  Future<AiResolvedProvider> resolveSelection({
    String? providerConfigId,
    String? model,
  }) async => providerConfigId == null
      ? resolveDefault()
      : _resolved(providerConfigId, model!);

  @override
  Future<String> generate(AiGenerationRequest request, {cancellation}) async =>
      generated;

  @override
  Stream<String> stream(AiGenerationRequest request, {cancellation}) =>
      const Stream.empty();

  @override
  Stream<AiStreamEvent> streamEvents(
    AiGenerationRequest request, {
    cancellation,
  }) => const Stream.empty();
}

Project _project() =>
    Project(metadata: _metadata('project'), title: '作品', description: '');

ChatPersona _persona() => ChatPersona(
  metadata: _metadata('persona'),
  name: '伊吹',
  descriptionMode: ChatPersonaDescriptionMode.simple,
  shortDescription: '亲近用户',
  speakingStyle: '自然',
);

ChatSession _session(String id) => ChatSession(
  metadata: _metadata(id),
  projectId: null,
  personaId: 'persona',
  title: id,
);

EntityMetadata _metadata(String id) =>
    EntityMetadata(id: id, createdAt: _now, updatedAt: _now, revision: 1);

final _now = DateTime.utc(2026, 8, 13, 12);
