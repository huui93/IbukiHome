import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/application/ai/chat_prompt_builder.dart';
import 'package:ibukihome/application/ai/novel_prompt_builder.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/memory/chat_memory_context.dart';
import 'package:ibukihome/application/memory/chat_memory_extractor.dart';
import 'package:ibukihome/application/memory/chat_memory_service.dart';
import 'package:ibukihome/application/memory/long_context_policy.dart';
import 'package:ibukihome/application/memory/novel_memory_context.dart';
import 'package:ibukihome/application/memory/novel_memory_invalidator.dart';
import 'package:ibukihome/application/memory/novel_memory_service.dart';
import 'package:ibukihome/application/memory/source_fingerprint.dart';
import 'package:ibukihome/data/ai/ai_provider_client.dart';
import 'package:ibukihome/data/memory/in_memory_chat_memory_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_persona_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_novel_memory_repository.dart';
import 'package:ibukihome/data/memory/in_memory_segment_repository.dart';
import 'package:ibukihome/domain/ai/ai_default_selection.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import 'package:ibukihome/domain/chat/chat_memory_entry.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/chat/conversation_summary.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/memory/memory_generation_status.dart';
import 'package:ibukihome/domain/memory/novel_summary_chunk.dart';
import 'package:ibukihome/domain/memory/story_memory_digest.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/segments/segment.dart';

void main() {
  group('novel long context', () {
    test('SummaryChunk create keeps source range', () {
      final chunk = _chunk('chunk-1', start: 0, end: 19);
      expect(chunk.projectId, 'project-1');
      expect(chunk.sourceStartOrder, 0);
      expect(chunk.sourceEndOrder, 19);
    });

    test('SummaryChunk persists in repository', () async {
      final fixture = _NovelFixture.empty();
      await fixture.memories.upsertChunk(_chunk('chunk-1'));
      expect((await fixture.memories.getChunk('chunk-1'))?.summary, '摘要 1');
    });

    test('segment fingerprint is stable', () {
      final segments = [_segment(0), _segment(1)];
      expect(fingerprintSegments(segments), fingerprintSegments(segments));
    });

    test('segment fingerprint changes with content', () {
      final original = [_segment(0)];
      final changed = [_segment(0).copyWith(content: 'changed')];
      expect(
        fingerprintSegments(original),
        isNot(fingerprintSegments(changed)),
      );
    });

    test('valid, stale and failed states remain distinct', () {
      expect(
        MemoryGenerationStatus.values,
        contains(MemoryGenerationStatus.valid),
      );
      expect(
        MemoryGenerationStatus.values,
        contains(MemoryGenerationStatus.stale),
      );
      expect(
        MemoryGenerationStatus.values,
        contains(MemoryGenerationStatus.failed),
      );
    });

    test('chunk threshold is centralized at twenty segments', () {
      expect(NovelMemoryPolicy.chunkSegmentCount, 20);
    });

    test('recent raw window is not compressed', () async {
      final fixture = _NovelFixture.withSegments(
        30,
        outputs: ['chunk', 'digest'],
      );
      await fixture.service.refresh('project-1');
      final chunk = (await fixture.memories.listChunks('project-1')).single;
      expect(chunk.sourceEndOrder, 19);
      expect(chunk.sourceEndSegmentId, 'segment-19');
    });

    test('old complete range automatically enters a chunk', () async {
      final fixture = _NovelFixture.withSegments(
        30,
        outputs: ['chunk', 'digest'],
      );
      await fixture.service.refresh('project-1');
      expect(await fixture.memories.listChunks('project-1'), hasLength(1));
    });

    test('incomplete old range does not call AI', () async {
      final fixture = _NovelFixture.withSegments(29, outputs: const []);
      await fixture.service.refresh('project-1');
      expect(fixture.runtime.requests, isEmpty);
    });

    test('two old ranges are summarized sequentially', () async {
      final fixture = _NovelFixture.withSegments(
        50,
        outputs: ['chunk-a', 'chunk-b', 'digest'],
      );
      await fixture.service.refresh('project-1');
      final chunks = await fixture.memories.listChunks('project-1');
      expect(chunks.map((item) => item.summary), ['chunk-a', 'chunk-b']);
      expect(fixture.runtime.maxConcurrent, 1);
    });

    test('segment edit marks covering chunk stale', () async {
      final fixture = _NovelFixture.empty();
      await fixture.memories.upsertChunk(_chunk('chunk-1'));
      await fixture.invalidator.invalidateFromOrder(
        projectId: 'project-1',
        fromOrder: 4,
        nowUtc: _later,
      );
      expect(
        (await fixture.memories.getChunk('chunk-1'))?.status,
        MemoryGenerationStatus.stale,
      );
    });

    test('rewrite invalidates the same content range', () async {
      final fixture = _NovelFixture.empty();
      await fixture.memories.upsertChunk(_chunk('chunk-1'));
      await fixture.invalidator.invalidateFromOrder(
        projectId: 'project-1',
        fromOrder: 10,
        nowUtc: _later,
      );
      expect((await fixture.memories.getChunk('chunk-1'))?.revision, 2);
    });

    test('modify invalidates digest', () async {
      final fixture = _NovelFixture.empty();
      await fixture.memories.upsertDigest(_digest());
      await fixture.invalidator.invalidateFromOrder(
        projectId: 'project-1',
        fromOrder: 1,
        nowUtc: _later,
      );
      expect(
        (await fixture.memories.getDigest('project-1'))?.status,
        MemoryGenerationStatus.stale,
      );
    });

    test(
      'revision restore preserves summary text while marking stale',
      () async {
        final fixture = _NovelFixture.empty();
        await fixture.memories.upsertChunk(_chunk('chunk-1'));
        await fixture.invalidator.invalidateFromOrder(
          projectId: 'project-1',
          fromOrder: 0,
          nowUtc: _later,
        );
        final chunk = await fixture.memories.getChunk('chunk-1');
        expect(chunk?.summary, '摘要 1');
        expect(chunk?.status, MemoryGenerationStatus.stale);
      },
    );

    test('insert removes chunks from affected chunk boundary', () async {
      final fixture = _NovelFixture.empty();
      await fixture.memories.upsertChunk(_chunk('a', start: 0, end: 19));
      await fixture.memories.upsertChunk(_chunk('b', start: 20, end: 39));
      await fixture.invalidator.invalidateStructureFromOrder(
        projectId: 'project-1',
        fromOrder: 24,
        nowUtc: _later,
      );
      expect(
        (await fixture.memories.listChunks('project-1')).map((e) => e.id),
        ['a'],
      );
    });

    test('delete rebuild starts at affected chunk boundary', () async {
      final fixture = _NovelFixture.empty();
      await fixture.memories.upsertChunk(_chunk('a', start: 0, end: 19));
      await fixture.memories.upsertChunk(_chunk('b', start: 20, end: 39));
      await fixture.invalidator.invalidateStructureFromOrder(
        projectId: 'project-1',
        fromOrder: 3,
        nowUtc: _later,
      );
      expect(await fixture.memories.listChunks('project-1'), isEmpty);
    });

    test(
      'restore marks digest stale without deleting original segments',
      () async {
        final fixture = _NovelFixture.withSegments(30, outputs: const []);
        await fixture.memories.upsertDigest(_digest());
        await fixture.invalidator.invalidateStructureFromOrder(
          projectId: 'project-1',
          fromOrder: 5,
          nowUtc: _later,
        );
        expect(await fixture.segments.listSegments('project-1'), hasLength(30));
        expect(
          (await fixture.memories.getDigest('project-1'))?.status,
          MemoryGenerationStatus.stale,
        );
      },
    );

    test('reorder only removes affected and later chunks', () async {
      final fixture = _NovelFixture.empty();
      for (var i = 0; i < 3; i++) {
        await fixture.memories.upsertChunk(
          _chunk('c$i', start: i * 20, end: i * 20 + 19),
        );
      }
      await fixture.invalidator.invalidateStructureFromOrder(
        projectId: 'project-1',
        fromOrder: 21,
        nowUtc: _later,
      );
      expect(
        (await fixture.memories.listChunks('project-1')).map((e) => e.id),
        ['c0'],
      );
    });

    test('digest is created from valid chunks', () async {
      final fixture = _NovelFixture.withSegments(
        30,
        outputs: ['chunk', 'digest'],
      );
      await fixture.service.refresh('project-1');
      expect(
        (await fixture.memories.getDigest('project-1'))?.content,
        'digest',
      );
    });

    test('digest updates when chunk fingerprint changes', () async {
      final fixture = _NovelFixture.withSegments(
        30,
        outputs: ['first', 'digest-1'],
      );
      await fixture.service.refresh('project-1');
      fixture.runtime.outputs.addAll(['second', 'digest-2']);
      fixture.store.putSegment(
        _segment(0).copyWith(
          metadata: _metadata('segment-0', revision: 2, updatedAt: _later),
          content: 'updated old fact',
        ),
      );
      await fixture.service.refresh('project-1');
      expect(
        (await fixture.memories.getDigest('project-1'))?.content,
        'digest-2',
      );
    });

    test('digest can be marked stale independently', () async {
      final fixture = _NovelFixture.empty();
      await fixture.memories.upsertDigest(_digest());
      await fixture.invalidator.invalidateFromOrder(
        projectId: 'project-1',
        fromOrder: 100,
        nowUtc: _later,
      );
      expect(
        (await fixture.memories.getDigest('project-1'))?.status,
        MemoryGenerationStatus.stale,
      );
    });

    test('user edited digest is protected from automatic overwrite', () async {
      final fixture = _NovelFixture.withSegments(
        30,
        outputs: ['chunk', 'ignored-digest'],
      );
      await fixture.service.saveUserDigest(
        projectId: 'project-1',
        content: '人工长期事实',
        pinned: true,
        nowUtc: _now,
      );
      await fixture.service.refresh('project-1');
      expect(
        (await fixture.memories.getDigest('project-1'))?.content,
        '人工长期事实',
      );
      expect(fixture.runtime.requests, hasLength(1));
    });

    test('NovelPrompt contains digest before character context', () {
      final prompt = const NovelPromptBuilder().buildContinue(
        project: _project(),
        segments: [_segment(29)],
        characters: const [],
        worldCards: const [],
        instruction: '继续',
        memory: NovelMemoryContext(digest: _digest()),
      );
      expect(prompt.systemPrompt, contains('长期事实'));
      expect(
        prompt.systemPrompt.indexOf('长期事实'),
        lessThan(prompt.systemPrompt.indexOf('本次参考角色卡')),
      );
    });

    test('NovelPrompt contains recent chunk summaries', () {
      final prompt = const NovelPromptBuilder().buildContinue(
        project: _project(),
        segments: [_segment(29)],
        characters: const [],
        worldCards: const [],
        instruction: '',
        memory: NovelMemoryContext(recentChunks: [_chunk('chunk-1')]),
      );
      expect(prompt.systemPrompt, contains('往事摘要'));
      expect(prompt.systemPrompt, contains('摘要 1'));
    });

    test('NovelPrompt always keeps recent raw segments', () {
      final segments = List.generate(30, _segment);
      final prompt = const NovelPromptBuilder(contextSegmentCount: 5)
          .buildContinue(
            project: _project(),
            segments: segments,
            characters: const [],
            worldCards: const [],
            instruction: '',
            memory: NovelMemoryContext(digest: _digest()),
          );
      expect(prompt.userPrompt, contains('正文 29'));
      expect(prompt.userPrompt, isNot(contains('正文 1')));
    });

    test('pending unsummarized tail stays in raw novel context', () {
      final segments = List.generate(41, _segment);
      final prompt = const NovelPromptBuilder(contextSegmentCount: 5)
          .buildContinue(
            project: _project(),
            segments: segments,
            characters: const [],
            worldCards: const [],
            instruction: '',
            memory: NovelMemoryContext(
              recentChunks: [_chunk('chunk-1', start: 0, end: 19)],
              rawSegmentStartOrder: 20,
            ),
          );
      expect(prompt.userPrompt, contains('正文 20'));
      expect(prompt.userPrompt, contains('正文 40'));
      expect(prompt.userPrompt, isNot(contains('正文 19')));
    });

    test('raw novel fallback stays bounded when no summary is usable', () {
      expect(
        calculateNovelRawStartOrder(
          segmentCount: 1000,
          summarizedChunks: const [],
        ),
        1000 - NovelMemoryPolicy.maxRawSegmentCount,
      );
    });

    test('context only keeps the most recent summary chunks', () async {
      final fixture = _NovelFixture.empty();
      for (var i = 0; i < 6; i++) {
        await fixture.memories.upsertChunk(
          _chunk('c$i', start: i * 20, end: i * 20 + 19, summary: 'summary-$i'),
        );
      }
      final context = await fixture.service.loadContext('project-1');
      expect(context.recentChunks, hasLength(3));
      expect(context.recentChunks.first.summary, 'summary-3');
    });

    test('summary failure does not modify source manuscript', () async {
      final fixture = _NovelFixture.withSegments(
        30,
        outputs: const [],
        fail: true,
      );
      await fixture.service.refresh('project-1');
      expect(await fixture.segments.listSegments('project-1'), hasLength(30));
      expect(
        (await fixture.memories.listChunks('project-1')).single.status,
        MemoryGenerationStatus.failed,
      );
    });

    test(
      'failed refresh retains a previous summary as fallback context',
      () async {
        final fixture = _NovelFixture.empty();
        await fixture.memories.upsertChunk(
          _chunk('chunk-1').copyWith(status: MemoryGenerationStatus.failed),
        );
        final context = await fixture.service.loadContext('project-1');
        expect(context.recentChunks.single.summary, '摘要 1');
      },
    );

    test('same project refresh has one in-flight job', () async {
      final gate = Completer<void>();
      final fixture = _NovelFixture.withSegments(
        30,
        outputs: ['chunk', 'digest'],
        gate: gate,
      );
      final first = fixture.service.refresh('project-1');
      final second = fixture.service.refresh('project-1');
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future.wait([first, second]);
      expect(fixture.runtime.requests, hasLength(2));
      expect(fixture.runtime.maxConcurrent, 1);
    });

    test('project memories remain isolated', () async {
      final fixture = _NovelFixture.empty();
      await fixture.memories.upsertChunk(_chunk('a'));
      await fixture.memories.upsertChunk(_chunk('b', projectId: 'project-2'));
      expect(await fixture.memories.listChunks('project-1'), hasLength(1));
      expect(await fixture.memories.listChunks('project-2'), hasLength(1));
    });
  });

  group('chat long-term memory', () {
    test('manual memory can be created', () async {
      final fixture = _ChatFixture.withMessages(0);
      final entry = await fixture.service.saveManual(
        personaId: 'persona-1',
        sessionId: 'session-1',
        category: ChatMemoryCategory.userFact,
        content: '用户希望被称作小铃',
        pinned: false,
        nowUtc: _now,
      );
      expect(
        (await fixture.memories.getEntry(entry.id)).content,
        contains('小铃'),
      );
    });

    test('manual memory edit is user protected', () async {
      final fixture = _ChatFixture.withMessages(0);
      final first = await fixture.service.saveManual(
        personaId: 'persona-1',
        sessionId: 'session-1',
        category: ChatMemoryCategory.other,
        content: '旧内容',
        pinned: false,
        nowUtc: _now,
      );
      final edited = await fixture.service.saveManual(
        personaId: 'persona-1',
        sessionId: 'session-1',
        category: ChatMemoryCategory.preference,
        content: '新内容',
        pinned: true,
        nowUtc: _later,
        entryId: first.id,
      );
      expect(edited.isUserEdited, isTrue);
      expect(edited.isPinned, isTrue);
      expect(edited.revision, 2);
    });

    test('memory soft delete hides it from normal listing', () async {
      final fixture = _ChatFixture.withMessages(0);
      final entry = await fixture.service.saveManual(
        personaId: 'persona-1',
        sessionId: 'session-1',
        category: ChatMemoryCategory.other,
        content: 'delete me',
        pinned: false,
        nowUtc: _now,
      );
      await fixture.memories.softDeleteEntry(entry.id, _later);
      expect(await fixture.memories.listEntries('persona-1'), isEmpty);
    });

    test('deleted memory can be restored', () async {
      final fixture = _ChatFixture.withMessages(0);
      final entry = await fixture.service.saveManual(
        personaId: 'persona-1',
        sessionId: 'session-1',
        category: ChatMemoryCategory.other,
        content: 'restore me',
        pinned: false,
        nowUtc: _now,
      );
      await fixture.memories.softDeleteEntry(entry.id, _later);
      await fixture.memories.restoreEntry(
        entry.id,
        _later.add(const Duration(minutes: 1)),
      );
      expect(await fixture.memories.listEntries('persona-1'), hasLength(1));
    });

    test('pinned and unpinned state can be edited', () async {
      final fixture = _ChatFixture.withMessages(0);
      final entry = await fixture.service.saveManual(
        personaId: 'persona-1',
        sessionId: 'session-1',
        category: ChatMemoryCategory.preference,
        content: '不喜欢苦咖啡',
        pinned: true,
        nowUtc: _now,
      );
      final updated = await fixture.service.saveManual(
        personaId: 'persona-1',
        sessionId: 'session-1',
        category: entry.category,
        content: entry.content,
        pinned: false,
        nowUtc: _later,
        entryId: entry.id,
      );
      expect(updated.isPinned, isFalse);
    });

    test('personas have isolated memory', () async {
      final fixture = _ChatFixture.withMessages(0);
      await fixture.memories.upsertEntry(_memory('m1', personaId: 'persona-1'));
      await fixture.memories.upsertEntry(_memory('m2', personaId: 'persona-2'));
      expect(await fixture.memories.listEntries('persona-1'), hasLength(1));
    });

    test('multiple sessions keep memory isolated under one persona', () async {
      final fixture = _ChatFixture.withMessages(0);
      await fixture.memories.upsertEntry(_memory('m1', sessionId: 'session-1'));
      final one = await fixture.service.loadContext(
        personaId: 'persona-1',
        sessionId: 'session-1',
      );
      final two = await fixture.service.loadContext(
        personaId: 'persona-1',
        sessionId: 'session-2',
      );
      expect(one.recent.single.content, '长期记忆内容');
      expect(two.recent, isEmpty);
    });

    test('deleted memory is excluded from prompt context', () async {
      final fixture = _ChatFixture.withMessages(0);
      final entry = _memory('m1');
      await fixture.memories.upsertEntry(entry);
      await fixture.memories.softDeleteEntry(entry.id, _later);
      final context = await fixture.service.loadContext(
        personaId: 'persona-1',
        sessionId: 'session-1',
      );
      expect(context.recent, isEmpty);
    });

    test('pinned memory enters ChatPrompt', () {
      final request = const ChatPromptBuilder().build(
        requestId: 'r',
        persona: _persona(),
        messages: const [],
        memory: ChatMemoryContext(pinned: [_memory('m1', pinned: true)]),
      );
      expect(request.systemPrompt, contains('[固定]'));
      expect(request.systemPrompt, contains('长期记忆内容'));
    });

    test('user edited memory stays protected', () {
      expect(_memory('m1', userEdited: true).isProtected, isTrue);
    });

    test('automatic extraction creates memory after threshold', () async {
      final fixture = _ChatFixture.withMessages(
        100,
        outputs: ['较早对话摘要', '[{"category":"preference","content":"用户不喜欢苦咖啡"}]'],
      );
      await fixture.service.organize('session-1');
      expect(await fixture.memories.listEntries('persona-1'), hasLength(1));
    });

    test('exact duplicate automatic memory is not inserted twice', () async {
      final fixture = _ChatFixture.withMessages(
        100,
        outputs: [
          'summary',
          '[{"category":"preference","content":"用户不喜欢苦咖啡"}]',
        ],
      );
      await fixture.memories.upsertEntry(
        _memory(
          'existing',
          sessionId: 'session-1',
          category: ChatMemoryCategory.preference,
          content: '用户不喜欢苦咖啡',
        ),
      );
      await fixture.service.organize('session-1');
      expect(await fixture.memories.listEntries('persona-1'), hasLength(1));
    });

    test('ConversationSummary is created with source range', () async {
      final fixture = _ChatFixture.withMessages(
        100,
        outputs: ['summary', '[]'],
      );
      await fixture.service.organize('session-1');
      final summary = (await fixture.memories.listSummaries(
        'session-1',
      )).single;
      expect(summary.sourceStartMessageId, 'message-0');
      expect(summary.sourceEndMessageId, 'message-99');
    });

    test('ConversationSummary stores fingerprint', () async {
      final fixture = _ChatFixture.withMessages(
        100,
        outputs: ['summary', '[]'],
      );
      await fixture.service.organize('session-1');
      expect(
        (await fixture.memories.listSummaries(
          'session-1',
        )).single.sourceFingerprint,
        isNotEmpty,
      );
    });

    test('valid summary acts as a watermark', () async {
      final fixture = _ChatFixture.withMessages(
        20,
        outputs: ['summary-1', '[]', 'summary-2', '[]'],
      );
      await fixture.service.organize('session-1', force: true);
      for (var index = 20; index < 40; index++) {
        await fixture.chats.appendMessage(_message(index));
      }
      await fixture.service.organize('session-1', force: true);
      final summaries = await fixture.memories.listSummaries('session-1');
      expect(summaries, hasLength(2));
      expect(summaries.last.sourceStartMessageId, 'message-20');
    });

    test('organize threshold is not reached for every message', () async {
      final fixture = _ChatFixture.withMessages(7, outputs: const []);
      await fixture.service.organize('session-1');
      expect(fixture.runtime.requests, isEmpty);
    });

    test('extractor parses plain JSON', () {
      final values = const ChatMemoryExtractor().parse(
        '[{"category":"userFact","content":"用户叫小铃"}]',
      );
      expect(values.single.category, ChatMemoryCategory.userFact);
    });

    test('extractor parses fenced JSON', () {
      final values = const ChatMemoryExtractor().parse(
        '```json\n[{"category":"sharedEvent","content":"约定继续聊小说"}]\n```',
      );
      expect(values.single.category, ChatMemoryCategory.sharedEvent);
    });

    test('extractor tolerates a short explanation around JSON', () {
      final values = const ChatMemoryExtractor().parse(
        '提取结果如下：\n[{"category":"preference","content":"用户不喜欢苦咖啡"}]\n以上。',
      );
      expect(values.single.category, ChatMemoryCategory.preference);
    });

    test('extractor accepts a memories wrapper object', () {
      final values = const ChatMemoryExtractor().parse(
        '{"memories":[{"category":"userFact","content":"用户希望被称作小铃"}]}',
      );
      expect(values.single.category, ChatMemoryCategory.userFact);
    });

    test(
      'invalid extractor JSON keeps the summary without inventing a fact',
      () async {
        final fixture = _ChatFixture.withMessages(
          100,
          outputs: ['summary', 'not-json'],
        );
        expect(
          await fixture.service.organize('session-1'),
          ChatMemoryOrganizationResult.summarySaved,
        );
        expect(await fixture.memories.listEntries('persona-1'), isEmpty);
        expect(await fixture.memories.listSummaries('session-1'), hasLength(1));
      },
    );

    test('extraction failure does not delete chat messages', () async {
      final fixture = _ChatFixture.withMessages(
        100,
        outputs: ['summary', 'not-json'],
      );
      await fixture.service.organize('session-1');
      expect(await fixture.chats.listMessages('session-1'), hasLength(100));
    });

    test('auto memory disabled still creates conversation summary', () async {
      final fixture = _ChatFixture.withMessages(
        100,
        outputs: ['summary'],
        autoMemory: false,
      );
      await fixture.service.organize('session-1');
      expect(await fixture.memories.listSummaries('session-1'), hasLength(1));
      expect(await fixture.memories.listEntries('persona-1'), isEmpty);
    });

    test('manual memory works while auto memory is disabled', () async {
      final fixture = _ChatFixture.withMessages(0, autoMemory: false);
      await fixture.service.saveManual(
        personaId: 'persona-1',
        sessionId: 'session-1',
        category: ChatMemoryCategory.other,
        content: 'manual',
        pinned: false,
        nowUtc: _now,
      );
      expect(await fixture.memories.listEntries('persona-1'), hasLength(1));
    });

    test('disabling saved memory also disables history reference', () async {
      final fixture = _ChatFixture.withMessages(0, useMemory: false);
      await fixture.memories.upsertEntry(_memory('m1'));
      await fixture.memories.upsertSummary(_summary('s1'));
      final context = await fixture.service.loadContext(
        personaId: 'persona-1',
        sessionId: 'session-1',
      );
      expect(context.recent, isEmpty);
      expect(context.summaries, isEmpty);
    });

    test('ChatPrompt contains long-term memory', () {
      final request = const ChatPromptBuilder().build(
        requestId: 'r',
        persona: _persona(),
        messages: const [],
        memory: ChatMemoryContext(recent: [_memory('m1')]),
      );
      expect(request.systemPrompt, contains('长期记忆内容'));
    });

    test('ChatPrompt contains conversation summary', () {
      final request = const ChatPromptBuilder().build(
        requestId: 'r',
        persona: _persona(),
        messages: const [],
        memory: ChatMemoryContext(summaries: [_summary('s1')]),
      );
      expect(request.systemPrompt, contains('较早对话摘要'));
    });

    test('ChatPrompt retains only recent raw messages from 5000 messages', () {
      final messages = List.generate(5000, _message);
      final request = const ChatPromptBuilder(
        recentMessageLimit: 30,
      ).build(requestId: 'r', persona: _persona(), messages: messages);
      expect(request.messages, hasLength(30));
      expect(request.messages.first.content, 'message 4970');
    });

    test('ChatPrompt ordinary memory has a hard limit', () async {
      final fixture = _ChatFixture.withMessages(0);
      for (var i = 0; i < 100; i++) {
        await fixture.memories.upsertEntry(
          _memory(
            'm$i',
            sessionId: 'session-1',
            content: 'memory $i',
            updatedAt: _now.add(Duration(minutes: i)),
          ),
        );
      }
      final context = await fixture.service.loadContext(
        personaId: 'persona-1',
        sessionId: 'session-1',
      );
      expect(context.recent, hasLength(ChatMemoryPolicy.ordinaryMemoryLimit));
    });

    test('novel system prompt does not enter ChatPrompt', () {
      final request = const ChatPromptBuilder().build(
        requestId: 'r',
        persona: _persona(),
        messages: const [],
      );
      expect(request.systemPrompt, isNot(contains('项目系统提示词内容')));
    });

    test('novel StoryMemory does not enter ChatPrompt', () {
      final request = const ChatPromptBuilder().build(
        requestId: 'r',
        persona: _persona(),
        messages: const [],
      );
      expect(request.systemPrompt, isNot(contains('小说长期事实')));
    });

    test('Chat Memory does not enter NovelPrompt without explicit context', () {
      final prompt = const NovelPromptBuilder().buildContinue(
        project: _project(),
        segments: [_segment(0)],
        characters: const [],
        worldCards: const [],
        instruction: '',
      );
      expect(prompt.systemPrompt, isNot(contains('长期记忆内容')));
    });

    test('same session has one in-flight organization job', () async {
      final gate = Completer<void>();
      final fixture = _ChatFixture.withMessages(
        100,
        outputs: ['summary', '[]'],
        gate: gate,
      );
      final first = fixture.service.organize('session-1');
      final second = fixture.service.organize('session-1');
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future.wait([first, second]);
      expect(fixture.runtime.requests, hasLength(2));
      expect(fixture.runtime.maxConcurrent, 1);
    });

    test('deleted Persona leaves old memory rows recoverable', () async {
      final fixture = _ChatFixture.withMessages(0);
      await fixture.memories.upsertEntry(_memory('m1'));
      await fixture.personas.softDeletePersona('persona-1', _later);
      expect(await fixture.memories.listEntries('persona-1'), hasLength(1));
    });

    test('chat source messages remain intact after summarization', () async {
      final fixture = _ChatFixture.withMessages(
        100,
        outputs: ['summary', '[]'],
      );
      final before = await fixture.chats.listMessages('session-1');
      await fixture.service.organize('session-1');
      final after = await fixture.chats.listMessages('session-1');
      expect(after, before);
    });

    test('automatic memory keeps source range for traceability', () async {
      final fixture = _ChatFixture.withMessages(
        100,
        outputs: [
          'summary',
          '[{"category":"ongoingMatter","content":"下次继续聊小说"}]',
        ],
      );
      await fixture.service.organize('session-1');
      final entry = (await fixture.memories.listEntries('persona-1')).single;
      expect(entry.sourceStartMessageId, 'message-0');
      expect(entry.sourceEndMessageId, 'message-99');
    });

    test('memory extractor prompt prohibits inference', () {
      final request = const ChatMemoryExtractor().buildRequest(
        requestId: 'r',
        persona: _persona(),
        existing: const [],
        messages: const [],
      );
      expect(request.systemPrompt, contains('不得推测'));
      expect(request.systemPrompt, contains('明确出现'));
    });
  });
}

class _NovelFixture {
  _NovelFixture._(this.store, this.memories, this.segments, this.runtime)
    : invalidator = NovelMemoryInvalidator(memories),
      service = NovelMemoryService(
        repository: memories,
        segments: segments,
        runtime: runtime,
        ids: EntityIdGenerator(),
      );

  factory _NovelFixture.empty() =>
      _NovelFixture.withSegments(0, outputs: const []);

  factory _NovelFixture.withSegments(
    int count, {
    required List<String> outputs,
    bool fail = false,
    Completer<void>? gate,
  }) {
    final store = InMemoryIbukiStore()..putProject(_project());
    for (var index = 0; index < count; index++) {
      store.putSegment(_segment(index));
    }
    return _NovelFixture._(
      store,
      InMemoryNovelMemoryRepository(store),
      InMemorySegmentRepository(store),
      _MemoryRuntime(outputs: outputs, fail: fail, gate: gate),
    );
  }

  final InMemoryIbukiStore store;
  final InMemoryNovelMemoryRepository memories;
  final InMemorySegmentRepository segments;
  final _MemoryRuntime runtime;
  late final NovelMemoryInvalidator invalidator;
  late final NovelMemoryService service;
}

class _ChatFixture {
  _ChatFixture._(
    this.store,
    this.memories,
    this.chats,
    this.personas,
    this.runtime,
  ) : service = ChatMemoryService(
        memories: memories,
        chats: chats,
        personas: personas,
        runtime: runtime,
        ids: EntityIdGenerator(),
      );

  factory _ChatFixture.withMessages(
    int count, {
    List<String> outputs = const [],
    bool autoMemory = true,
    bool useMemory = true,
    Completer<void>? gate,
  }) {
    final store = InMemoryIbukiStore();
    store.putChatPersona(
      _persona(autoMemory: autoMemory, useMemory: useMemory),
    );
    store.putChatSession(_session('session-1'));
    store.putChatSession(_session('session-2'));
    for (var index = 0; index < count; index++) {
      store.putChatMessage(_message(index));
    }
    return _ChatFixture._(
      store,
      InMemoryChatMemoryRepository(store),
      InMemoryChatRepository(store),
      InMemoryChatPersonaRepository(store),
      _MemoryRuntime(outputs: outputs, gate: gate),
    );
  }

  final InMemoryIbukiStore store;
  final InMemoryChatMemoryRepository memories;
  final InMemoryChatRepository chats;
  final InMemoryChatPersonaRepository personas;
  final _MemoryRuntime runtime;
  late final ChatMemoryService service;
}

class _MemoryRuntime implements AiGenerationRuntime {
  _MemoryRuntime({required List<String> outputs, this.fail = false, this.gate})
    : outputs = Queue<String>.of(outputs);

  final Queue<String> outputs;
  final bool fail;
  final Completer<void>? gate;
  final List<AiGenerationRequest> requests = [];
  int active = 0;
  int maxConcurrent = 0;

  @override
  Future<AiResolvedProvider> resolveDefault() async => AiResolvedProvider(
    config: AiProviderConfig(
      id: 'deepseek',
      type: AiProviderType.deepseek,
      displayName: 'DeepSeek',
      baseUrl: AiProviderType.deepseek.defaultBaseUrl,
      apiKeyRef: 'secure.fake',
      selectedModel: 'deepseek-test',
      enabled: true,
      connectionStatus: AiProviderConnectionStatus.connected,
      availableModels: const ['deepseek-test'],
      createdAtUtc: _now,
      updatedAtUtc: _now,
    ),
    selection: AiDefaultSelection(
      providerId: 'deepseek',
      modelId: 'deepseek-test',
      updatedAtUtc: _now,
    ),
  );

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in stream(request, cancellation: cancellation)) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    requests.add(request);
    active += 1;
    if (active > maxConcurrent) maxConcurrent = active;
    try {
      if (gate != null && !gate!.isCompleted) await gate!.future;
      if (fail) throw StateError('fake memory failure');
      if (outputs.isEmpty) throw StateError('no fake output');
      yield outputs.removeFirst();
    } finally {
      active -= 1;
    }
  }
}

Project _project({String id = 'project-1'}) => Project(
  metadata: _metadata(id),
  title: '测试小说',
  description: '',
  systemPrompt: '项目系统提示词内容',
);

Segment _segment(int index) => Segment(
  metadata: _metadata('segment-$index'),
  projectId: 'project-1',
  orderIndex: index,
  content: '正文 $index',
);

NovelSummaryChunk _chunk(
  String id, {
  String projectId = 'project-1',
  int start = 0,
  int end = 19,
  String summary = '摘要 1',
}) => NovelSummaryChunk(
  metadata: _metadata(id),
  projectId: projectId,
  sourceStartOrder: start,
  sourceEndOrder: end,
  sourceStartSegmentId: 'segment-$start',
  sourceEndSegmentId: 'segment-$end',
  summary: summary,
  sourceFingerprint: 'fingerprint-$id',
  status: MemoryGenerationStatus.valid,
);

StoryMemoryDigest _digest() => StoryMemoryDigest(
  metadata: _metadata('digest-1'),
  projectId: 'project-1',
  content: '小说长期事实',
  sourceThroughOrder: 19,
  sourceFingerprint: 'digest-fingerprint',
  status: MemoryGenerationStatus.valid,
);

ChatPersona _persona({bool autoMemory = true, bool useMemory = true}) =>
    ChatPersona(
      metadata: _metadata('persona-1'),
      name: '小铃',
      descriptionMode: ChatPersonaDescriptionMode.simple,
      shortDescription: '亲近用户',
      speakingStyle: '自然短句',
      autoMemoryEnabled: autoMemory,
      useLongTermMemory: useMemory,
    );

ChatSession _session(String id) => ChatSession(
  metadata: _metadata(id),
  projectId: null,
  personaId: 'persona-1',
  title: '测试会话',
);

ChatMessage _message(int index) => ChatMessage(
  metadata: EntityMetadata(
    id: 'message-$index',
    createdAt: _now.add(Duration(seconds: index)),
    updatedAt: _now.add(Duration(seconds: index)),
    revision: 1,
  ),
  sessionId: 'session-1',
  projectId: null,
  role: index.isEven ? ChatMessageRole.user : ChatMessageRole.assistant,
  content: 'message $index',
);

ChatMemoryEntry _memory(
  String id, {
  String personaId = 'persona-1',
  ChatMemoryCategory category = ChatMemoryCategory.other,
  String content = '长期记忆内容',
  bool pinned = false,
  bool userEdited = false,
  DateTime? updatedAt,
  String? sessionId,
}) => ChatMemoryEntry(
  metadata: _metadata(id, updatedAt: updatedAt),
  personaId: personaId,
  sessionId: sessionId,
  category: category,
  content: content,
  origin: ChatMemoryOrigin.manual,
  isPinned: pinned,
  isUserEdited: userEdited,
);

ConversationSummary _summary(String id) => ConversationSummary(
  metadata: _metadata(id),
  sessionId: 'session-1',
  sourceStartMessageId: 'message-0',
  sourceEndMessageId: 'message-19',
  summary: '较早对话摘要',
  sourceFingerprint: 'summary-fingerprint',
  status: MemoryGenerationStatus.valid,
);

EntityMetadata _metadata(String id, {int revision = 1, DateTime? updatedAt}) =>
    EntityMetadata(
      id: id,
      createdAt: _now,
      updatedAt: updatedAt ?? _now,
      revision: revision,
    );

final _now = DateTime.utc(2026, 8, 12, 8);
final _later = DateTime.utc(2026, 8, 12, 9);
