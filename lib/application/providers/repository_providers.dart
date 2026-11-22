import '../plugins/novel_plugin_providers.dart';
import '../projects/novel_output_limits_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/common/entity_id_generator.dart';
import '../../application/common/utc_clock.dart';
import '../../application/ai/ai_runtime_providers.dart';
import '../../application/ai/ai_model_resolver.dart';
import '../../application/ai/auto_story_runner.dart';
import '../../application/ai/chat_prompt_builder.dart';
import '../../application/ai/generate_chat_reply.dart';
import '../../application/ai/generate_next_segment.dart';
import '../../application/ai/novel_context_loader.dart';
import '../../application/ai/novel_prompt_builder.dart';
import '../../application/ai/segment_ai_drafts.dart';
import '../../application/ai/save_ai_model_binding.dart';
import '../../application/ai/card_completion.dart';
import '../../application/ai/character_reference_lookup.dart';
import '../../application/memory/chat_memory_service.dart';
import '../../domain/chat/chat_memory_state.dart';
import '../../application/plugins/plugin_providers.dart';
import '../../application/plugins/ibuki_plugin_ai.dart';
import '../../application/memory/novel_memory_invalidator.dart';
import '../../application/memory/novel_memory_service.dart';
import '../../application/chat/create_chat_session.dart';
import '../../application/chat/create_chat_persona.dart';
import '../../application/chat/list_chat_messages.dart';
import '../../application/chat/list_chat_sessions.dart';
import '../../application/chat/open_persona_chat.dart';
import '../../application/chat/restore_chat_persona.dart';
import '../../application/chat/save_chat_persona.dart';
import '../../application/chat/soft_delete_chat_persona.dart';
import '../../application/chat/rename_chat_session.dart';
import '../../application/chat/restore_chat_session.dart';
import '../../application/chat/send_chat_message.dart';
import '../../application/chat/chat_controls_providers.dart';
import '../chat/recognize_chat_image.dart';
import '../chat/chat_vision_preferences.dart';
import '../../application/chat/soft_delete_chat_session.dart';
import '../../application/characters/create_character_card.dart';
import '../../application/characters/reorder_character_cards.dart';
import '../../application/characters/restore_character_card.dart';
import '../../application/characters/save_character_card.dart';
import '../../application/characters/soft_delete_character_card.dart';
import '../../application/projects/create_project.dart';
import '../../application/projects/save_project_system_prompt.dart';
import '../../application/outline/create_outline_node.dart';
import '../../application/outline/reorder_outline_nodes.dart';
import '../../application/outline/save_outline_node.dart';
import '../../application/outline/set_outline_node_status.dart';
import '../../application/outline/soft_delete_outline_node.dart';
import '../../application/segments/create_segment.dart';
import '../../application/segments/insert_segment.dart';
import '../../application/segments/list_segment_revisions.dart';
import '../../application/segments/reorder_segments.dart';
import '../../application/segments/restore_segment.dart';
import '../../application/segments/restore_segment_revision.dart';
import '../../application/segments/soft_delete_segment.dart';
import '../../application/world/create_world_card.dart';
import '../../application/world/reorder_world_cards.dart';
import '../../application/world/restore_world_card.dart';
import '../../application/world/save_world_card.dart';
import '../../application/world/soft_delete_world_card.dart';
import '../../application/world_roleplay/world_roleplay_providers.dart';
import '../../data/memory/in_memory_character_repository.dart';
import '../../data/memory/in_memory_chat_repository.dart';
import '../../data/memory/in_memory_chat_persona_repository.dart';
import '../../data/memory/in_memory_ibuki_store.dart';
import '../../data/memory/in_memory_project_repository.dart';
import '../../data/memory/in_memory_outline_repository.dart';
import '../../data/memory/in_memory_novel_memory_repository.dart';
import '../../data/memory/in_memory_reader_repository.dart';
import '../../data/memory/in_memory_chat_memory_repository.dart';
import '../../data/memory/in_memory_segment_repository.dart';
import '../../data/memory/in_memory_world_repository.dart';
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/chat_persona_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/outline_repository.dart';
import '../../data/repositories/novel_memory_repository.dart';
import '../../data/repositories/reader_repository.dart';
import '../../data/repositories/chat_memory_repository.dart';
import '../../data/repositories/segment_repository.dart';
import '../../data/repositories/world_repository.dart';
import '../../domain/projects/project.dart';
import '../../domain/outline/outline_node.dart';
import '../../domain/characters/character_card.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_session.dart';
import '../../domain/chat/chat_persona.dart';
import '../../domain/chat/chat_memory_entry.dart';
import '../../domain/chat/conversation_summary.dart';
import '../../domain/memory/novel_summary_chunk.dart';
import '../../domain/memory/story_memory_digest.dart';
import '../../domain/reader/reader_preferences.dart';
import '../../domain/segments/segment.dart';
import '../../domain/segments/segment_revision.dart';
import '../../domain/world/world_card.dart';
import '../segments/save_segment.dart';

final entityIdGeneratorProvider = Provider<EntityIdGenerator>((ref) {
  return EntityIdGenerator();
});

final utcClockProvider = Provider<UtcClock>((ref) {
  return const UtcClock();
});

final inMemoryIbukiStoreProvider = Provider<InMemoryIbukiStore>((ref) {
  return InMemoryIbukiStore();
});

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  final store = ref.watch(inMemoryIbukiStoreProvider);
  return InMemoryProjectRepository(store);
});

final outlineRepositoryProvider = Provider<OutlineRepository>((ref) {
  return InMemoryOutlineRepository(ref.watch(inMemoryIbukiStoreProvider));
});

final segmentRepositoryProvider = Provider<SegmentRepository>((ref) {
  final store = ref.watch(inMemoryIbukiStoreProvider);
  return InMemorySegmentRepository(store);
});

final characterRepositoryProvider = Provider<CharacterRepository>((ref) {
  final store = ref.watch(inMemoryIbukiStoreProvider);
  return InMemoryCharacterRepository(store);
});

final worldRepositoryProvider = Provider<WorldRepository>((ref) {
  final store = ref.watch(inMemoryIbukiStoreProvider);
  return InMemoryWorldRepository(store);
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final store = ref.watch(inMemoryIbukiStoreProvider);
  return InMemoryChatRepository(store);
});

final chatPersonaRepositoryProvider = Provider<ChatPersonaRepository>((ref) {
  return InMemoryChatPersonaRepository(ref.watch(inMemoryIbukiStoreProvider));
});

final novelMemoryRepositoryProvider = Provider<NovelMemoryRepository>((ref) {
  return InMemoryNovelMemoryRepository(ref.watch(inMemoryIbukiStoreProvider));
});

final readerRepositoryProvider = Provider<ReaderRepository>((ref) {
  return InMemoryReaderRepository(ref.watch(inMemoryIbukiStoreProvider));
});

final chatMemoryRepositoryProvider = Provider<ChatMemoryRepository>((ref) {
  return InMemoryChatMemoryRepository(ref.watch(inMemoryIbukiStoreProvider));
});

final novelMemoryInvalidatorProvider = Provider<NovelMemoryInvalidator>((ref) {
  return NovelMemoryInvalidator(ref.watch(novelMemoryRepositoryProvider));
});

final aiModelResolverProvider = Provider<AiModelResolver>((ref) {
  return AiModelResolver(
    projects: ref.watch(projectRepositoryProvider),
    chats: ref.watch(chatRepositoryProvider),
    worlds: ref.watch(worldRoleplayRepositoryProvider),
    runtime: ref.watch(aiGenerationServiceProvider),
  );
});

final novelAiModelResolverProvider = Provider<AiModelResolver>((ref) {
  return AiModelResolver(
    projects: ref.watch(projectRepositoryProvider),
    runtime: ref.watch(aiGenerationServiceProvider),
  );
});

final chatAiModelResolverProvider = Provider<AiModelResolver>((ref) {
  return AiModelResolver(
    chats: ref.watch(chatRepositoryProvider),
    runtime: ref.watch(aiGenerationServiceProvider),
  );
});

final ibukiPluginAiProvider = Provider<CoreIbukiPluginAi>((ref) {
  final host = CoreIbukiPluginAi(
    runtime: ref.watch(aiGenerationServiceProvider),
    modelResolver: ref.watch(aiModelResolverProvider),
    hooks: ref.watch(ibukiHookBusProvider),
  );
  ref.onDispose(host.dispose);
  return host;
});

final saveProjectAiBindingProvider = Provider<SaveProjectAiBinding>((ref) {
  return SaveProjectAiBinding(ref.watch(projectRepositoryProvider));
});

final saveChatSessionAiBindingProvider = Provider<SaveChatSessionAiBinding>((
  ref,
) {
  return SaveChatSessionAiBinding(ref.watch(chatRepositoryProvider));
});

final saveWorldSessionAiBindingProvider = Provider<SaveWorldSessionAiBinding>((
  ref,
) {
  return SaveWorldSessionAiBinding(ref.watch(worldRoleplayRepositoryProvider));
});

final characterReferenceLookupProvider =
    Provider<CharacterReferenceLookupService>((ref) {
      return const NoopCharacterReferenceLookupService();
    });

final cardCompletionServiceProvider = Provider<CardCompletionService>((ref) {
  return CardCompletionService(
    contextLoader: ref.watch(novelContextLoaderProvider),
    runtime: ref.watch(aiGenerationServiceProvider),
    modelResolver: ref.watch(novelAiModelResolverProvider),
    referenceLookup: ref.watch(characterReferenceLookupProvider),
  );
});

final projectAiLabelProvider = FutureProvider.family<String?, String>((
  ref,
  projectId,
) async {
  _watchProjects(ref);
  final project = await ref
      .watch(projectRepositoryProvider)
      .getProject(projectId);
  if (project.aiProviderConfigId == null) {
    return ref.watch(defaultAiLabelProvider.future);
  }
  try {
    return (await ref
            .watch(novelAiModelResolverProvider)
            .resolveForProject(projectId))
        .displayLabel;
  } catch (_) {
    return '此项目选择的 AI 当前不可用';
  }
});

final chatSessionAiLabelProvider = FutureProvider.family<String?, String>((
  ref,
  sessionId,
) async {
  _watchChatSessions(ref);
  final session = await ref.watch(chatRepositoryProvider).getSession(sessionId);
  if (session.aiProviderConfigId == null) {
    return ref.watch(defaultAiLabelProvider.future);
  }
  try {
    return (await ref
            .watch(chatAiModelResolverProvider)
            .resolveForChatSession(sessionId))
        .displayLabel;
  } catch (_) {
    return '此聊天选择的 AI 当前不可用';
  }
});

final novelMemoryServiceProvider = Provider<NovelMemoryService>((ref) {
  return NovelMemoryService(
    repository: ref.watch(novelMemoryRepositoryProvider),
    segments: ref.watch(segmentRepositoryProvider),
    runtime: ref.watch(aiGenerationServiceProvider),
    ids: ref.watch(entityIdGeneratorProvider),
    modelResolver: ref.watch(novelAiModelResolverProvider),
  );
});

final chatMemoryServiceProvider = Provider<ChatMemoryService>((ref) {
  var alive = true;
  ref.onDispose(() => alive = false);
  return ChatMemoryService(
    memories: ref.watch(chatMemoryRepositoryProvider),
    chats: ref.watch(chatRepositoryProvider),
    personas: ref.watch(chatPersonaRepositoryProvider),
    runtime: ref.watch(aiGenerationServiceProvider),
    ids: ref.watch(entityIdGeneratorProvider),
    modelResolver: ref.watch(chatAiModelResolverProvider),
    usageTracker: ref.watch(chatUsageTrackerProvider),
    onChanged: () {
      if (alive) {
        ref.read(repositoryRevisionsProvider.notifier).bump(const [
          RepositoryDataArea.chatMemory,
        ]);
      }
    },
  );
});

final saveSegmentProvider = Provider<SaveSegment>((ref) {
  final segments = ref.watch(segmentRepositoryProvider);
  return SaveSegment(
    segments,
    ref.watch(novelMemoryInvalidatorProvider),
    (segment) => ref.read(novelPluginHostProvider).finalized(segment, 'edit'),
  );
});

final novelPromptBuilderProvider = Provider<NovelPromptBuilder>((ref) {
  return const NovelPromptBuilder(contextSegmentCount: 5);
});

final chatPromptBuilderProvider = Provider<ChatPromptBuilder>((ref) {
  return const ChatPromptBuilder(recentMessageLimit: 30);
});

final novelContextLoaderProvider = Provider<NovelContextLoader>((ref) {
  return NovelContextLoader(
    projects: ref.watch(projectRepositoryProvider),
    segments: ref.watch(segmentRepositoryProvider),
    characters: ref.watch(characterRepositoryProvider),
    worlds: ref.watch(worldRepositoryProvider),
    outlines: ref.watch(outlineRepositoryProvider),
    memories: ref.watch(novelMemoryRepositoryProvider),
  );
});

final segmentAiDraftRunnerProvider = Provider<SegmentAiDraftRunner>((ref) {
  return SegmentAiDraftRunner(
    contextLoader: ref.watch(novelContextLoaderProvider),
    promptBuilder: ref.watch(novelPromptBuilderProvider),
    runtime: ref.watch(aiGenerationServiceProvider),
    coordinator: ref.watch(aiRequestCoordinatorProvider),
    modelResolver: ref.watch(novelAiModelResolverProvider),
    outputLimits: ref.watch(novelOutputLimitsRepositoryProvider),
    promptPipeline: ref.watch(ibukiPromptPipelineProvider),
    novelPlugins: ref.watch(novelPluginHostProvider),
  );
});

final generateNextSegmentProvider = Provider<GenerateNextSegment>((ref) {
  return GenerateNextSegment(
    contextLoader: ref.watch(novelContextLoaderProvider),
    promptBuilder: ref.watch(novelPromptBuilderProvider),
    runtime: ref.watch(aiGenerationServiceProvider),
    coordinator: ref.watch(aiRequestCoordinatorProvider),
    createSegment: ref.watch(createSegmentProvider),
    memoryService: ref.watch(novelMemoryServiceProvider),
    modelResolver: ref.watch(novelAiModelResolverProvider),
    outputLimits: ref.watch(novelOutputLimitsRepositoryProvider),
    promptPipeline: ref.watch(ibukiPromptPipelineProvider),
    novelPlugins: ref.watch(novelPluginHostProvider),
  );
});

final autoStoryRunnerProvider = Provider<AutoStoryRunner>((ref) {
  final generateNext = ref.watch(generateNextSegmentProvider);
  final ids = ref.watch(entityIdGeneratorProvider);
  final clock = ref.watch(utcClockProvider);
  final runner = AutoStoryRunner(
    generateSegment:
        ({
          required projectId,
          required userInstruction,
          required selectedCharacterIds,
          required selectedWorldCardIds,
          required requestId,
          required segmentId,
          required nowUtc,
        }) => generateNext(
          projectId: projectId,
          userInstruction: userInstruction,
          selectedCharacterIds: selectedCharacterIds,
          selectedWorldCardIds: selectedWorldCardIds,
          requestId: requestId,
          segmentId: segmentId,
          nowUtc: nowUtc,
        ),
    cancelGeneration: generateNext.cancel,
    nextId: ids.nextId,
    now: clock.now,
  );
  ref.onDispose(runner.dispose);
  return runner;
});

final rewriteSegmentProvider = Provider<RewriteSegment>((ref) {
  return RewriteSegment(
    ref.watch(segmentAiDraftRunnerProvider),
    ref.watch(segmentRepositoryProvider),
    ref.watch(saveSegmentProvider),
  );
});

final modifySegmentWithInstructionProvider =
    Provider<ModifySegmentWithInstruction>((ref) {
      return ModifySegmentWithInstruction(
        ref.watch(segmentAiDraftRunnerProvider),
        ref.watch(segmentRepositoryProvider),
        ref.watch(saveSegmentProvider),
      );
    });

final selectionModifySegmentProvider = Provider<SelectionModifySegment>((ref) {
  return SelectionModifySegment(
    ref.watch(segmentAiDraftRunnerProvider),
    ref.watch(segmentRepositoryProvider),
    ref.watch(saveSegmentProvider),
  );
});

final generateChatReplyProvider = Provider<GenerateChatReply>((ref) {
  return GenerateChatReply(
    imageRecognizer: RecognizeChatImage(
      chats: ref.watch(chatRepositoryProvider),
      runtime: ref.watch(aiGenerationServiceProvider),
      selection: () => ref.read(chatVisionPreferencesProvider.future),
      modelResolver: ref.watch(chatAiModelResolverProvider),
      usageTracker: ref.watch(chatUsageTrackerProvider),
    ),
    chats: ref.watch(chatRepositoryProvider),
    personas: ref.watch(chatPersonaRepositoryProvider),
    promptBuilder: ref.watch(chatPromptBuilderProvider),
    runtime: ref.watch(aiGenerationServiceProvider),
    coordinator: ref.watch(aiRequestCoordinatorProvider),
    memoryService: ref.watch(chatMemoryServiceProvider),
    modelResolver: ref.watch(chatAiModelResolverProvider),
    promptPipeline: ref.watch(ibukiPromptPipelineProvider),
    controls: ref.watch(chatControlsRepositoryProvider),
    usageTracker: ref.watch(chatUsageTrackerProvider),
  );
});

final createProjectProvider = Provider<CreateProject>((ref) {
  final projects = ref.watch(projectRepositoryProvider);
  return CreateProject(projects);
});

final saveProjectSystemPromptProvider = Provider<SaveProjectSystemPrompt>((
  ref,
) {
  return SaveProjectSystemPrompt(ref.watch(projectRepositoryProvider));
});

final createOutlineNodeProvider = Provider<CreateOutlineNode>((ref) {
  return CreateOutlineNode(
    ref.watch(projectRepositoryProvider),
    ref.watch(outlineRepositoryProvider),
  );
});

final saveOutlineNodeProvider = Provider<SaveOutlineNode>((ref) {
  return SaveOutlineNode(ref.watch(outlineRepositoryProvider));
});

final softDeleteOutlineNodeProvider = Provider<SoftDeleteOutlineNode>((ref) {
  return SoftDeleteOutlineNode(ref.watch(outlineRepositoryProvider));
});

final reorderOutlineNodesProvider = Provider<ReorderOutlineNodes>((ref) {
  return ReorderOutlineNodes(ref.watch(outlineRepositoryProvider));
});

final setOutlineNodeStatusProvider = Provider<SetOutlineNodeStatus>((ref) {
  return SetOutlineNodeStatus(ref.watch(outlineRepositoryProvider));
});

final createSegmentProvider = Provider<CreateSegment>((ref) {
  final projects = ref.watch(projectRepositoryProvider);
  final segments = ref.watch(segmentRepositoryProvider);
  return CreateSegment(
    projects,
    segments,
    (segment) => ref.read(novelPluginHostProvider).finalized(segment, 'send'),
  );
});

final createChatSessionProvider = Provider<CreateChatSession>((ref) {
  return CreateChatSession(
    ref.watch(chatRepositoryProvider),
    ref.watch(chatPersonaRepositoryProvider),
  );
});

final createChatPersonaProvider = Provider<CreateChatPersona>((ref) {
  return CreateChatPersona(ref.watch(chatPersonaRepositoryProvider));
});

final saveChatPersonaProvider = Provider<SaveChatPersona>((ref) {
  return SaveChatPersona(ref.watch(chatPersonaRepositoryProvider));
});

final softDeleteChatPersonaProvider = Provider<SoftDeleteChatPersona>((ref) {
  return SoftDeleteChatPersona(ref.watch(chatPersonaRepositoryProvider));
});

final restoreChatPersonaProvider = Provider<RestoreChatPersona>((ref) {
  return RestoreChatPersona(ref.watch(chatPersonaRepositoryProvider));
});

final openPersonaChatProvider = Provider<OpenPersonaChat>((ref) {
  return OpenPersonaChat(
    ref.watch(chatPersonaRepositoryProvider),
    ref.watch(chatRepositoryProvider),
    ref.watch(createChatSessionProvider),
  );
});

final renameChatSessionProvider = Provider<RenameChatSession>((ref) {
  return RenameChatSession(ref.watch(chatRepositoryProvider));
});

final softDeleteChatSessionProvider = Provider<SoftDeleteChatSession>((ref) {
  return SoftDeleteChatSession(ref.watch(chatRepositoryProvider));
});

final restoreChatSessionProvider = Provider<RestoreChatSession>((ref) {
  return RestoreChatSession(ref.watch(chatRepositoryProvider));
});

final sendChatMessageProvider = Provider<SendChatMessage>((ref) {
  return SendChatMessage(ref.watch(chatRepositoryProvider));
});

final listChatSessionsProvider = Provider<ListChatSessions>((ref) {
  return ListChatSessions(ref.watch(chatRepositoryProvider));
});

final listChatMessagesProvider = Provider<ListChatMessages>((ref) {
  return ListChatMessages(ref.watch(chatRepositoryProvider));
});

final insertSegmentProvider = Provider<InsertSegment>((ref) {
  return InsertSegment(
    ref.watch(projectRepositoryProvider),
    ref.watch(segmentRepositoryProvider),
    ref.watch(novelMemoryInvalidatorProvider),
    (segment) => ref.read(novelPluginHostProvider).finalized(segment, 'insert'),
  );
});

final reorderSegmentsProvider = Provider<ReorderSegments>((ref) {
  return ReorderSegments(
    ref.watch(projectRepositoryProvider),
    ref.watch(segmentRepositoryProvider),
    ref.watch(novelMemoryInvalidatorProvider),
  );
});

final softDeleteSegmentProvider = Provider<SoftDeleteSegment>((ref) {
  return SoftDeleteSegment(
    ref.watch(projectRepositoryProvider),
    ref.watch(segmentRepositoryProvider),
    ref.watch(novelMemoryInvalidatorProvider),
    (segment) => ref.read(novelPluginHostProvider).finalized(segment, 'delete'),
  );
});

final restoreSegmentProvider = Provider<RestoreSegment>((ref) {
  return RestoreSegment(
    ref.watch(projectRepositoryProvider),
    ref.watch(segmentRepositoryProvider),
    ref.watch(novelMemoryInvalidatorProvider),
    (segment) =>
        ref.read(novelPluginHostProvider).finalized(segment, 'restore'),
  );
});

final listSegmentRevisionsProvider = Provider<ListSegmentRevisions>((ref) {
  return ListSegmentRevisions(ref.watch(segmentRepositoryProvider));
});

final restoreSegmentRevisionProvider = Provider<RestoreSegmentRevision>((ref) {
  return RestoreSegmentRevision(
    ref.watch(projectRepositoryProvider),
    ref.watch(segmentRepositoryProvider),
    ref.watch(novelMemoryInvalidatorProvider),
  );
});

final createCharacterCardProvider = Provider<CreateCharacterCard>((ref) {
  return CreateCharacterCard(
    ref.watch(projectRepositoryProvider),
    ref.watch(characterRepositoryProvider),
  );
});

final saveCharacterCardProvider = Provider<SaveCharacterCard>((ref) {
  return SaveCharacterCard(ref.watch(characterRepositoryProvider));
});

final softDeleteCharacterCardProvider = Provider<SoftDeleteCharacterCard>((
  ref,
) {
  return SoftDeleteCharacterCard(ref.watch(characterRepositoryProvider));
});

final restoreCharacterCardProvider = Provider<RestoreCharacterCard>((ref) {
  return RestoreCharacterCard(ref.watch(characterRepositoryProvider));
});

final reorderCharacterCardsProvider = Provider<ReorderCharacterCards>((ref) {
  return ReorderCharacterCards(ref.watch(characterRepositoryProvider));
});

final createWorldCardProvider = Provider<CreateWorldCard>((ref) {
  return CreateWorldCard(
    ref.watch(projectRepositoryProvider),
    ref.watch(worldRepositoryProvider),
  );
});

final saveWorldCardProvider = Provider<SaveWorldCard>((ref) {
  return SaveWorldCard(ref.watch(worldRepositoryProvider));
});

final softDeleteWorldCardProvider = Provider<SoftDeleteWorldCard>((ref) {
  return SoftDeleteWorldCard(ref.watch(worldRepositoryProvider));
});

final restoreWorldCardProvider = Provider<RestoreWorldCard>((ref) {
  return RestoreWorldCard(ref.watch(worldRepositoryProvider));
});

final reorderWorldCardsProvider = Provider<ReorderWorldCards>((ref) {
  return ReorderWorldCards(ref.watch(worldRepositoryProvider));
});

enum RepositoryDataArea {
  projects,
  outlines,
  segments,
  characters,
  worlds,
  chatSessions,
  chatMessages,
  chatPersonas,
  novelMemory,
  reader,
  chatMemory,
}

final repositoryRevisionsProvider =
    NotifierProvider<RepositoryRevisionsController, RepositoryRevisions>(
      RepositoryRevisionsController.new,
    );

class RepositoryRevisions {
  const RepositoryRevisions({
    this.projects = 0,
    this.outlines = 0,
    this.segments = 0,
    this.characters = 0,
    this.worlds = 0,
    this.chatSessions = 0,
    this.chatMessages = 0,
    this.chatPersonas = 0,
    this.novelMemory = 0,
    this.reader = 0,
    this.chatMemory = 0,
  });

  final int projects;
  final int outlines;
  final int segments;
  final int characters;
  final int worlds;
  final int chatSessions;
  final int chatMessages;
  final int chatPersonas;
  final int novelMemory;
  final int reader;
  final int chatMemory;

  RepositoryRevisions bump(Set<RepositoryDataArea> areas) {
    return RepositoryRevisions(
      projects:
          projects + (areas.contains(RepositoryDataArea.projects) ? 1 : 0),
      outlines:
          outlines + (areas.contains(RepositoryDataArea.outlines) ? 1 : 0),
      segments:
          segments + (areas.contains(RepositoryDataArea.segments) ? 1 : 0),
      characters:
          characters + (areas.contains(RepositoryDataArea.characters) ? 1 : 0),
      worlds: worlds + (areas.contains(RepositoryDataArea.worlds) ? 1 : 0),
      chatSessions:
          chatSessions +
          (areas.contains(RepositoryDataArea.chatSessions) ? 1 : 0),
      chatMessages:
          chatMessages +
          (areas.contains(RepositoryDataArea.chatMessages) ? 1 : 0),
      chatPersonas:
          chatPersonas +
          (areas.contains(RepositoryDataArea.chatPersonas) ? 1 : 0),
      novelMemory:
          novelMemory +
          (areas.contains(RepositoryDataArea.novelMemory) ? 1 : 0),
      reader: reader + (areas.contains(RepositoryDataArea.reader) ? 1 : 0),
      chatMemory:
          chatMemory + (areas.contains(RepositoryDataArea.chatMemory) ? 1 : 0),
    );
  }
}

class RepositoryRevisionsController extends Notifier<RepositoryRevisions> {
  @override
  RepositoryRevisions build() => const RepositoryRevisions();

  void bump(Iterable<RepositoryDataArea> areas) {
    state = state.bump(areas.toSet());
  }
}

@Deprecated('Use repositoryRevisionsProvider with a scoped data area.')
final dataChangeTickProvider = NotifierProvider<DataChangeTickController, int>(
  DataChangeTickController.new,
);

@Deprecated('Use RepositoryRevisionsController.')
class DataChangeTickController extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state += 1;
    ref
        .read(repositoryRevisionsProvider.notifier)
        .bump(RepositoryDataArea.values);
  }
}

void notifyRepositoryChanged(
  WidgetRef ref, {
  Iterable<RepositoryDataArea> areas = RepositoryDataArea.values,
}) {
  final expandedAreas = areas.toSet();
  if (expandedAreas.contains(RepositoryDataArea.segments)) {
    expandedAreas.add(RepositoryDataArea.novelMemory);
  }
  if (expandedAreas.contains(RepositoryDataArea.chatMessages)) {
    expandedAreas.add(RepositoryDataArea.chatMemory);
  }
  ref.read(repositoryRevisionsProvider.notifier).bump(expandedAreas);
}

void _watchProjects(Ref ref) {
  ref.watch(repositoryRevisionsProvider.select((value) => value.projects));
}

void _watchOutlines(Ref ref) {
  ref.watch(repositoryRevisionsProvider.select((value) => value.outlines));
}

void _watchSegments(Ref ref) {
  ref.watch(repositoryRevisionsProvider.select((value) => value.segments));
}

void _watchCharacters(Ref ref) {
  ref.watch(repositoryRevisionsProvider.select((value) => value.characters));
}

void _watchWorlds(Ref ref) {
  ref.watch(repositoryRevisionsProvider.select((value) => value.worlds));
}

void _watchChatSessions(Ref ref) {
  ref.watch(repositoryRevisionsProvider.select((value) => value.chatSessions));
}

void _watchChatMessages(Ref ref) {
  ref.watch(repositoryRevisionsProvider.select((value) => value.chatMessages));
}

void _watchChatPersonas(Ref ref) {
  ref.watch(repositoryRevisionsProvider.select((value) => value.chatPersonas));
}

void _watchNovelMemory(Ref ref) {
  ref.watch(repositoryRevisionsProvider.select((value) => value.novelMemory));
}

void _watchReader(Ref ref) {
  ref.watch(repositoryRevisionsProvider.select((value) => value.reader));
}

void _watchChatMemory(Ref ref) {
  ref.watch(repositoryRevisionsProvider.select((value) => value.chatMemory));
}

final projectListProvider = FutureProvider<List<Project>>((ref) {
  _watchProjects(ref);
  return ref.watch(projectRepositoryProvider).listProjects();
});

final projectByIdProvider = FutureProvider.family<Project, String>((
  ref,
  projectId,
) {
  _watchProjects(ref);
  return ref.watch(projectRepositoryProvider).getProject(projectId);
});

final outlineListProvider = FutureProvider.family<List<OutlineNode>, String>((
  ref,
  projectId,
) {
  _watchOutlines(ref);
  return ref.watch(outlineRepositoryProvider).listOutlineNodes(projectId);
});

final chatSessionListProvider = FutureProvider<List<ChatSession>>((ref) {
  _watchChatSessions(ref);
  return ref.watch(listChatSessionsProvider)();
});

final deletedChatSessionListProvider = FutureProvider<List<ChatSession>>((ref) {
  _watchChatSessions(ref);
  return ref.watch(listChatSessionsProvider)(onlyDeleted: true);
});

final chatSessionByIdProvider = FutureProvider.family<ChatSession, String>((
  ref,
  sessionId,
) {
  _watchChatSessions(ref);
  return ref.watch(chatRepositoryProvider).getSession(sessionId);
});

final chatSessionsByCharacterProvider =
    FutureProvider.family<List<ChatSession>, String>((ref, characterId) {
      _watchChatSessions(ref);
      return ref
          .watch(chatRepositoryProvider)
          .listSessions(characterId: characterId);
    });

final chatSessionsByPersonaProvider =
    FutureProvider.family<List<ChatSession>, String>((ref, personaId) {
      _watchChatSessions(ref);
      return ref
          .watch(chatRepositoryProvider)
          .listSessions(personaId: personaId);
    });

final chatPersonaListProvider = FutureProvider<List<ChatPersona>>((ref) {
  _watchChatPersonas(ref);
  return ref.watch(chatPersonaRepositoryProvider).listPersonas();
});

final deletedChatPersonaListProvider = FutureProvider<List<ChatPersona>>((
  ref,
) async {
  _watchChatPersonas(ref);
  final items = await ref
      .watch(chatPersonaRepositoryProvider)
      .listPersonas(includeDeleted: true);
  return List.unmodifiable(items.where((item) => item.deletedAt != null));
});

final chatPersonaByIdProvider = FutureProvider.family<ChatPersona, String>((
  ref,
  personaId,
) {
  _watchChatPersonas(ref);
  return ref.watch(chatPersonaRepositoryProvider).getPersona(personaId);
});

final chatMessageListProvider =
    FutureProvider.family<List<ChatMessage>, String>((ref, sessionId) {
      _watchChatMessages(ref);
      return ref.watch(listChatMessagesProvider)(sessionId);
    });

final segmentListProvider = FutureProvider.family<List<Segment>, String>((
  ref,
  projectId,
) {
  _watchSegments(ref);
  return ref.watch(segmentRepositoryProvider).listSegments(projectId);
});

final deletedSegmentListProvider = FutureProvider.family<List<Segment>, String>(
  (ref, projectId) async {
    _watchSegments(ref);
    final all = await ref
        .watch(segmentRepositoryProvider)
        .listSegments(projectId, includeDeleted: true);
    return List.unmodifiable(all.where((segment) => segment.deletedAt != null));
  },
);

final segmentByIdProvider = FutureProvider.family<Segment, String>((
  ref,
  segmentId,
) {
  _watchSegments(ref);
  return ref.watch(segmentRepositoryProvider).getSegment(segmentId);
});

final segmentRevisionListProvider =
    FutureProvider.family<List<SegmentRevision>, String>((ref, segmentId) {
      _watchSegments(ref);
      return ref.watch(segmentRepositoryProvider).listRevisions(segmentId);
    });

final segmentRevisionCountProvider = FutureProvider.family<int, String>((
  ref,
  segmentId,
) async {
  final revisions = await ref.watch(
    segmentRevisionListProvider(segmentId).future,
  );
  return revisions.length;
});

final segmentHistoryProvider =
    FutureProvider.family<
      List<SegmentRevision>,
      ({String projectId, String segmentId})
    >((ref, query) {
      _watchSegments(ref);
      return ref.watch(listSegmentRevisionsProvider)(
        projectId: query.projectId,
        segmentId: query.segmentId,
      );
    });

final segmentRevisionByIdProvider =
    FutureProvider.family<SegmentRevision, String>((ref, revisionId) {
      _watchSegments(ref);
      return ref.watch(segmentRepositoryProvider).getRevision(revisionId);
    });

final characterListProvider =
    FutureProvider.family<List<CharacterCard>, String>((ref, projectId) {
      _watchCharacters(ref);
      return ref.watch(characterRepositoryProvider).listCharacters(projectId);
    });

final deletedCharacterListProvider =
    FutureProvider.family<List<CharacterCard>, String>((ref, projectId) async {
      _watchCharacters(ref);
      final all = await ref
          .watch(characterRepositoryProvider)
          .listCharacters(projectId, includeDeleted: true);
      return List.unmodifiable(
        all.where((character) => character.deletedAt != null),
      );
    });

final characterByIdProvider = FutureProvider.family<CharacterCard, String>((
  ref,
  characterId,
) {
  _watchCharacters(ref);
  return ref.watch(characterRepositoryProvider).getCharacter(characterId);
});

final worldCardListProvider = FutureProvider.family<List<WorldCard>, String>((
  ref,
  projectId,
) {
  _watchWorlds(ref);
  return ref.watch(worldRepositoryProvider).listWorldCards(projectId);
});

final deletedWorldCardListProvider =
    FutureProvider.family<List<WorldCard>, String>((ref, projectId) async {
      _watchWorlds(ref);
      final all = await ref
          .watch(worldRepositoryProvider)
          .listWorldCards(projectId, includeDeleted: true);
      return List.unmodifiable(all.where((card) => card.deletedAt != null));
    });

final worldCardByIdProvider = FutureProvider.family<WorldCard, String>((
  ref,
  worldCardId,
) {
  _watchWorlds(ref);
  return ref.watch(worldRepositoryProvider).getWorldCard(worldCardId);
});

final novelSummaryChunkListProvider =
    FutureProvider.family<List<NovelSummaryChunk>, String>((ref, projectId) {
      _watchNovelMemory(ref);
      return ref.watch(novelMemoryRepositoryProvider).listChunks(projectId);
    });

final storyMemoryDigestProvider =
    FutureProvider.family<StoryMemoryDigest?, String>((ref, projectId) {
      _watchNovelMemory(ref);
      return ref.watch(novelMemoryRepositoryProvider).getDigest(projectId);
    });

final readerPreferencesProvider =
    FutureProvider.family<ReaderPreferences, String>((ref, projectId) {
      _watchReader(ref);
      return ref.watch(readerRepositoryProvider).loadPreferences(projectId);
    });

final readerProgressProvider = FutureProvider.family<ReaderProgress, String>((
  ref,
  projectId,
) {
  _watchReader(ref);
  return ref.watch(readerRepositoryProvider).loadProgress(projectId);
});

final chatMemoryEntryListProvider =
    FutureProvider.family<List<ChatMemoryEntry>, String>((ref, personaId) {
      _watchChatMemory(ref);
      return ref.watch(chatMemoryRepositoryProvider).listEntries(personaId);
    });

final chatMemoryStateProvider = FutureProvider.family<ChatMemoryState, String>((
  ref,
  sessionId,
) {
  _watchChatMemory(ref);
  return ref.watch(chatMemoryServiceProvider).settings(sessionId);
});

final chatReplyMemorySourcesProvider =
    FutureProvider.family<List<ChatMemorySource>, (String, String)>((ref, ids) {
      _watchChatMemory(ref);
      _watchChatMessages(ref);
      return ref
          .watch(chatMemoryServiceProvider)
          .sourcesForReply(ids.$1, ids.$2);
    });

final deletedChatMemoryEntryListProvider =
    FutureProvider.family<List<ChatMemoryEntry>, String>((ref, personaId) {
      _watchChatMemory(ref);
      return ref
          .watch(chatMemoryRepositoryProvider)
          .listEntries(personaId, includeDeleted: true)
          .then(
            (items) => List.unmodifiable(
              items.where((item) => item.deletedAt != null),
            ),
          );
    });

final deletedChatSessionsByPersonaProvider =
    FutureProvider.family<List<ChatSession>, String>((ref, personaId) async {
      _watchChatSessions(ref);
      final items = await ref
          .watch(chatRepositoryProvider)
          .listSessions(personaId: personaId, includeDeleted: true);
      return List.unmodifiable(items.where((item) => item.deletedAt != null));
    });

final chatMemoryEntryListForSessionProvider =
    FutureProvider.family<List<ChatMemoryEntry>, String>((ref, sessionId) {
      _watchChatMemory(ref);
      return ref
          .watch(chatMemoryRepositoryProvider)
          .listEntriesForSession(sessionId);
    });

final deletedChatMemoryEntryListForSessionProvider =
    FutureProvider.family<List<ChatMemoryEntry>, String>((ref, sessionId) {
      _watchChatMemory(ref);
      return ref
          .watch(chatMemoryRepositoryProvider)
          .listEntriesForSession(sessionId, includeDeleted: true)
          .then(
            (items) => List.unmodifiable(
              items.where((item) => item.deletedAt != null),
            ),
          );
    });

final legacyChatMemoryEntryListProvider =
    FutureProvider.family<List<ChatMemoryEntry>, String>((ref, personaId) {
      _watchChatMemory(ref);
      return ref
          .watch(chatMemoryRepositoryProvider)
          .listEntries(personaId, includeDeleted: true)
          .then(
            (items) => List.unmodifiable(
              items.where((item) => item.sessionId == null),
            ),
          );
    });

final conversationSummaryListProvider =
    FutureProvider.family<List<ConversationSummary>, String>((ref, sessionId) {
      _watchChatMemory(ref);
      return ref.watch(chatMemoryRepositoryProvider).listSummaries(sessionId);
    });
