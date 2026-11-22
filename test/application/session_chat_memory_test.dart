import 'dart:async';
import 'package:ibukihome/data/ai/ai_provider_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/memory/chat_memory_service.dart';
import 'package:ibukihome/application/memory/local_chat_memory_search.dart';
import 'package:ibukihome/application/memory/source_fingerprint.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_chat_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_persona_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_memory_repository.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/chat/chat_memory_entry.dart';
import 'package:ibukihome/domain/chat/chat_memory_state.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';

void main() {
  test(
    'same persona sessions have independent settings and saved memories',
    () async {
      final f = Fixture();
      await f.save('a', '用户喜欢乌龙茶');
      await f.save('b', '用户喜欢咖啡');
      await f.service.updateSettings('a', savedEnabled: false);
      expect((await f.service.settings('a')).historyEnabled, isFalse);
      expect((await f.service.settings('b')).savedEnabled, isTrue);
      expect(
        (await f.service.loadContext(
          personaId: 'p',
          sessionId: 'a',
          query: '喜欢',
        )).isEmpty,
        isTrue,
      );
      final b = await f.service.loadContext(
        personaId: 'p',
        sessionId: 'b',
        query: '喜欢',
      );
      expect(b.recent.single.content, '用户喜欢咖啡');
      expect(b.sources.every((s) => s.sessionId == 'b'), isTrue);
      expect(await f.repo.listEntriesForSession('a'), hasLength(1));
    },
  );
  test(
    'persona defaults are copied once, never used as a shared live switch',
    () async {
      final f = Fixture();
      await f.service.settings('a');
      f.store.putChatPersona(
        f.store.chatPersona('p')!.copyWith(useLongTermMemory: false),
      );
      expect((await f.service.settings('a')).savedEnabled, isTrue);
      expect((await f.service.settings('b')).savedEnabled, isFalse);
    },
  );
  test('scope mismatches and unspecific manual memory are rejected', () async {
    final f = Fixture();
    final entry = await f.save('a', '乌龙茶');
    expect(
      f.service.loadContext(personaId: 'other', sessionId: 'a'),
      throwsA(isA<DataConflictException>()),
    );
    expect(
      f.service.saveManual(
        personaId: 'p',
        sessionId: 'b',
        entryId: entry.id,
        category: entry.category,
        content: '移动记忆',
        pinned: false,
        nowUtc: now,
      ),
      throwsA(isA<DataConflictException>()),
    );
    expect(
      f.service.saveManual(
        personaId: 'p',
        category: entry.category,
        content: '无归属',
        pinned: false,
        nowUtc: now,
      ),
      throwsA(isA<DataConflictException>()),
    );
  });
  test(
    'Chinese retrieval selects relevant older messages with a strict budget',
    () async {
      final f = Fixture(count: 50);
      f.store.putChatMessage(message(0, content: '约定周末去杭州看展览'));
      final context = await f.service.loadContext(
        personaId: 'p',
        sessionId: 'a',
        query: '杭州展览',
      );
      expect(context.history.any((s) => s.id == 'm0'), isTrue);
      expect(context.history.any((s) => s.id == 'm49'), isFalse);
      expect(
        context.sources.fold<int>(0, (sum, s) => sum + s.content.length),
        lessThanOrEqualTo(6000),
      );
      final sources = [
        for (var i = 0; i < 100; i++)
          ChatMemorySource(
            kind: ChatMemorySourceKind.saved,
            id: '$i',
            sessionId: i == 99 ? 'b' : 'a',
            content: '杭州展览${'资料' * 1000}',
            updatedAt: now,
          ),
      ];
      final results = const LocalChatMemorySearch().search(
        sessionId: 'a',
        query: '杭州',
        documents: sources,
        characterBudget: 1600,
      );
      expect(results.every((s) => s.sessionId == 'a'), isTrue);
      expect(
        results.fold<int>(0, (n, s) => n + s.content.length),
        lessThanOrEqualTo(1600),
      );
    },
  );
  test(
    'unrelated query does not dump recent ordinary memories into prompt',
    () async {
      final f = Fixture();
      await f.save('a', '用户喜欢乌龙茶');
      expect(
        (await f.service.loadContext(
          personaId: 'p',
          sessionId: 'a',
          query: '量子物理',
        )).isEmpty,
        isTrue,
      );
      expect(f.runtime.requests, isEmpty);
    },
  );
  test(
    'manual history search is local and still works while reference is off',
    () async {
      final f = Fixture(count: 2);
      f.store.putChatMessage(message(0, content: '周末杭州展览'));
      await f.service.updateSettings('a', savedEnabled: false);
      expect((await f.service.search('a', '杭州')).single.id, 'm0');
      expect(await f.service.search('b', '杭州'), isEmpty);
      expect(f.runtime.requests, isEmpty);
    },
  );
  test('pause stops reads and model calls while preserving raw chat', () async {
    final f = Fixture(count: 8);
    await f.save('a', '用户喜欢乌龙茶');
    await f.service.updateSettings('a', paused: true);
    expect(
      (await f.service.loadContext(personaId: 'p', sessionId: 'a')).isEmpty,
      isTrue,
    );
    expect(
      await f.service.organize('a'),
      ChatMemoryOrganizationResult.disabled,
    );
    expect(f.runtime.requests, isEmpty);
    expect(f.store.chatMessages, hasLength(8));
  });
  test(
    'summary and automatic note reject source edits and deletions',
    () async {
      final f = Fixture(
        count: 50,
        outputs: [
          '杭州展览摘要',
          '[{"category":"sharedEvent","content":"周末杭州展览","topic":"展览约定"}]',
        ],
      );
      expect(
        await f.service.organize('a'),
        ChatMemoryOrganizationResult.completed,
      );
      expect(
        (await f.service.loadContext(
          personaId: 'p',
          sessionId: 'a',
          query: '杭州',
        )).sources,
        isNotEmpty,
      );
      final old = f.store.chatMessage('m0')!;
      f.store.putChatMessage(
        old.copyWith(
          content: '更正内容',
          metadata: old.metadata.copyWith(revision: 2),
        ),
      );
      final invalidated = await f.service.loadContext(
        personaId: 'p',
        sessionId: 'a',
        query: '杭州',
      );
      expect(invalidated.sources, isEmpty);
      expect((await f.service.settings('a')).overview, isEmpty);
    },
  );
  test(
    'turning memory off rejects an in-flight organization transaction',
    () async {
      final gate = Completer<void>();
      final f = Fixture(
        count: 8,
        outputs: ['摘要', '[{"content":"用户喜欢茶"}]'],
        gate: gate,
      );
      final job = f.service.organize('a');
      await f.runtime.started.future;
      await f.service.updateSettings('a', savedEnabled: false);
      gate.complete();
      expect(await job, ChatMemoryOrganizationResult.changed);
      expect(await f.repo.listEntriesForSession('a'), isEmpty);
      expect(await f.repo.listSummaries('a'), isEmpty);
    },
  );
  test(
    'forgetting during organization does not resurrect deleted memory',
    () async {
      final gate = Completer<void>();
      final f = Fixture(
        count: 8,
        outputs: ['茶的摘要', '[{"content":"用户喜欢乌龙茶"}]'],
        gate: gate,
      );
      final entry = await f.save('a', '用户喜欢乌龙茶');
      final job = f.service.organize('a');
      await f.runtime.started.future;
      await f.service.forget('a', source(entry), deleteSaved: true);
      gate.complete();
      expect(await job, ChatMemoryOrganizationResult.changed);
      expect(await f.repo.listEntriesForSession('a'), isEmpty);
      expect(
        (await f.service.loadContext(
          personaId: 'p',
          sessionId: 'a',
          query: '乌龙茶',
        )).isEmpty,
        isTrue,
      );
      await f.service.restore('a', entry.id);
      expect(
        (await f.service.loadContext(
          personaId: 'p',
          sessionId: 'a',
          query: '乌龙茶',
        )).recent,
        hasLength(1),
      );
    },
  );
  test(
    'failed extraction retains cursor and can be retried without losing batch',
    () async {
      final f = Fixture(count: 8, outputs: ['摘要', 'bad-json', '摘要重试', '[]']);
      expect(
        await f.service.organize('a'),
        ChatMemoryOrganizationResult.failed,
      );
      expect((await f.service.settings('a')).cursor, isNull);
      expect(
        await f.service.organize('a'),
        ChatMemoryOrganizationResult.completed,
      );
      expect((await f.service.settings('a')).cursor, 'm7');
      expect(await f.repo.listSummaries('a'), hasLength(1));
    },
  );
  test(
    'automatic correction replaces a topic and cannot overwrite manual facts',
    () async {
      final f = Fixture(
        count: 8,
        outputs: [
          '摘要',
          '[{"category":"preference","content":"用户喜欢咖啡","topic":"饮品"}]',
          '摘要2',
          '[{"content":"用户改喝水","topic":"饮品"}]',
        ],
      );
      await f.repo.upsertEntry(
        ChatMemoryEntry(
          metadata: meta('auto'),
          personaId: 'p',
          sessionId: 'a',
          category: ChatMemoryCategory.preference,
          content: '用户喜欢茶',
          origin: ChatMemoryOrigin.auto,
          topic: '饮品',
        ),
      );
      expect(
        await f.service.organize('a'),
        ChatMemoryOrganizationResult.completed,
      );
      expect((await f.repo.listEntriesForSession('a')).single.id, 'auto');
      final fixed = (await f.repo.listEntriesForSession('a')).single;
      await f.service.saveManual(
        personaId: 'p',
        sessionId: 'a',
        category: fixed.category,
        content: '用户只喝热茶',
        pinned: true,
        nowUtc: now,
        entryId: fixed.id,
      );
      for (var i = 8; i < 16; i++) {
        f.store.putChatMessage(message(i));
      }
      await f.service.organize('a');
      expect((await f.repo.getEntry('auto')).content, '用户只喝热茶');
    },
  );
  test('clear affects only one session and retains messages', () async {
    final f = Fixture(count: 8);
    await f.save('a', '乌龙茶');
    await f.save('b', '咖啡');
    await f.service.clearAndDisable('a');
    expect(await f.repo.listEntriesForSession('a'), isEmpty);
    expect(await f.repo.listEntriesForSession('b'), hasLength(1));
    expect(f.store.chatMessages, hasLength(8));
    expect((await f.service.settings('a')).savedEnabled, isFalse);
    expect(
      await f.service.organize('a'),
      ChatMemoryOrganizationResult.disabled,
    );
  });
  test(
    'source references persist but changed content is not misreported',
    () async {
      final f = Fixture();
      final entry = await f.save('a', '乌龙茶');
      final context = await f.service.loadContext(
        personaId: 'p',
        sessionId: 'a',
        query: '乌龙茶',
      );
      f.store.putChatMessage(message(1));
      await f.service.recordUsage('a', 'm1', context);
      expect((await f.service.sourcesForReply('a', 'm1')).single.id, entry.id);
      expect(await f.service.sourcesForReply('b', 'm1'), isEmpty);
      await f.service.saveManual(
        personaId: 'p',
        sessionId: 'a',
        category: entry.category,
        content: '咖啡',
        pinned: false,
        nowUtc: now,
        entryId: entry.id,
      );
      expect(await f.service.sourcesForReply('a', 'm1'), isEmpty);
    },
  );
  test(
    'explicit remember is immediate, local, deduplicated and session scoped',
    () async {
      final f = Fixture();
      await f.service.applyUserInstruction('a', '记住：我的茶要少糖');
      await f.service.applyUserInstruction('a', '记住：我的茶要少糖');
      expect(
        (await f.repo.listEntriesForSession('a')).single.content,
        '我的茶要少糖',
      );
      expect(await f.repo.listEntriesForSession('b'), isEmpty);
      expect(f.runtime.requests, isEmpty);
    },
  );
  test('explicit forgetting does not delete an unrelated fact', () async {
    final f = Fixture();
    await f.save('a', '用户喜欢乌龙茶');
    await f.save('a', '用户喜欢爵士乐');
    await f.service.applyUserInstruction('a', '忘记乌龙茶');
    expect((await f.repo.listEntriesForSession('a')).single.content, '用户喜欢爵士乐');
  });
  test('source range fingerprints change when an interior row is deleted', () {
    final messages = List.generate(8, message);
    expect(
      fingerprintMessages(messages),
      isNot(fingerprintMessages(messages.where((m) => m.id != 'm3'))),
    );
  });
}

final now = DateTime.utc(2026, 11, 21);
EntityMetadata meta(String id) =>
    EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);
ChatMessage message(int i, {String? content}) => ChatMessage(
  metadata: meta('m$i').copyWith(createdAt: now.add(Duration(seconds: i))),
  sessionId: 'a',
  projectId: null,
  role: i.isEven ? ChatMessageRole.user : ChatMessageRole.assistant,
  content: content ?? '普通对话第 $i 条',
);
ChatMemorySource source(ChatMemoryEntry entry) => ChatMemorySource(
  kind: ChatMemorySourceKind.saved,
  id: entry.id,
  sessionId: entry.sessionId!,
  content: entry.content,
  updatedAt: entry.updatedAt,
);

class Fixture {
  Fixture({
    int count = 0,
    List<String> outputs = const [],
    Completer<void>? gate,
  }) : runtime = Runtime(outputs, gate) {
    store.putChatPersona(
      ChatPersona(
        metadata: meta('p'),
        name: '人格',
        descriptionMode: ChatPersonaDescriptionMode.simple,
        shortDescription: '',
        speakingStyle: '',
      ),
    );
    for (final id in ['a', 'b']) {
      store.putChatSession(
        ChatSession(
          metadata: meta(id),
          personaId: 'p',
          projectId: null,
          title: id,
        ),
      );
    }
    for (var i = 0; i < count; i++) {
      store.putChatMessage(message(i));
    }
    repo = InMemoryChatMemoryRepository(store);
    service = ChatMemoryService(
      memories: repo,
      chats: InMemoryChatRepository(store),
      personas: InMemoryChatPersonaRepository(store),
      runtime: runtime,
      ids: EntityIdGenerator(),
    );
  }
  final store = InMemoryIbukiStore();
  final Runtime runtime;
  late final InMemoryChatMemoryRepository repo;
  late final ChatMemoryService service;
  Future<ChatMemoryEntry> save(String sessionId, String text) =>
      service.saveManual(
        personaId: 'p',
        sessionId: sessionId,
        category: ChatMemoryCategory.preference,
        content: text,
        pinned: false,
        nowUtc: now,
      );
}

class Runtime implements AiGenerationRuntime {
  Runtime(List<String> outputs, this.gate) : outputs = [...outputs];
  final List<String> outputs;
  final Completer<void>? gate;
  final started = Completer<void>();
  final requests = <AiGenerationRequest>[];
  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async {
    requests.add(request);
    if (!started.isCompleted) started.complete();
    await gate?.future;
    if (outputs.isEmpty) throw StateError('No mock output');
    return outputs.removeAt(0);
  }

  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    yield await generate(request, cancellation: cancellation);
  }

  @override
  Future<AiResolvedProvider> resolveDefault() => throw UnimplementedError();
}
