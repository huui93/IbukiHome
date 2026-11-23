import 'package:ibukihome/data/memory/in_memory_novel_output_limits_repository.dart';
import 'package:ibukihome/domain/projects/novel_output_limits.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/ai_draft_update.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/application/ai/auto_story_runner.dart';
import 'package:ibukihome/application/ai/ai_model_resolver.dart';
import 'package:ibukihome/application/ai/ai_request_coordinator.dart';
import 'package:ibukihome/application/ai/chat_prompt_builder.dart';
import 'package:ibukihome/application/ai/generate_chat_reply.dart';
import 'package:ibukihome/application/ai/generate_next_segment.dart';
import 'package:ibukihome/application/ai/novel_context_loader.dart';
import 'package:ibukihome/application/ai/novel_prompt_builder.dart';
import 'package:ibukihome/application/ai/segment_ai_drafts.dart';
import 'package:ibukihome/application/chat/send_chat_message.dart';
import 'package:ibukihome/application/segments/create_segment.dart';
import 'package:ibukihome/application/segments/save_segment.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/core/network/ai_provider_exceptions.dart';
import 'package:ibukihome/data/ai/ai_provider_client.dart';
import 'package:ibukihome/data/memory/in_memory_character_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_persona_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_outline_repository.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/data/memory/in_memory_segment_repository.dart';
import 'package:ibukihome/data/memory/in_memory_world_repository.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/ai/ai_default_selection.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/outline/outline_node.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/segments/segment.dart';
import 'package:ibukihome/domain/world/world_card.dart';

void main() {
  group('NovelContextLoader', () {
    test('empty selections use current-project cards', () async {
      final fixture = await _Fixture.create();
      final context = await fixture.loader.load(
        projectId: 'project-1',
        selectedCharacterIds: const {},
        selectedWorldCardIds: const {},
      );
      expect(context.characters.map((item) => item.id), ['character-1']);
      expect(context.worldCards.map((item) => item.id), ['world-1']);
      expect(context.outline.current?.id, 'outline-current');
      expect(context.outline.nextPlanned?.id, 'outline-next');
    });

    test('explicit selections use only selected cards', () async {
      final fixture = await _Fixture.create(secondCharacter: true);
      final context = await fixture.loader.load(
        projectId: 'project-1',
        selectedCharacterIds: const {'character-2'},
        selectedWorldCardIds: const {'world-1'},
      );
      expect(context.characters.single.id, 'character-2');
    });

    test('cross-project character selection is rejected', () async {
      final fixture = await _Fixture.create(secondProject: true);
      expect(
        fixture.loader.load(
          projectId: 'project-1',
          selectedCharacterIds: const {'other-character'},
          selectedWorldCardIds: const {},
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('cross-project world selection is rejected', () async {
      final fixture = await _Fixture.create(secondProject: true);
      expect(
        fixture.loader.load(
          projectId: 'project-1',
          selectedCharacterIds: const {},
          selectedWorldCardIds: const {'other-world'},
        ),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('deleted cards are not implicitly injected', () async {
      final fixture = await _Fixture.create();
      await fixture.characters.softDeleteCharacter('character-1', _later);
      await fixture.worlds.softDeleteWorldCard('world-1', _later);
      final context = await fixture.loader.load(
        projectId: 'project-1',
        selectedCharacterIds: const {},
        selectedWorldCardIds: const {},
      );
      expect(context.characters, isEmpty);
      expect(context.worldCards, isEmpty);
    });

    test('deleted projects cannot build AI context', () async {
      final fixture = await _Fixture.create();
      await fixture.projects.softDeleteProject('project-1', _later);
      expect(
        fixture.loader.load(
          projectId: 'project-1',
          selectedCharacterIds: const {},
          selectedWorldCardIds: const {},
        ),
        throwsA(isA<DataConflictException>()),
      );
    });
  });

  group('GenerateNextSegment', () {
    test('streams an in-memory draft before saving', () async {
      final fixture = await _Fixture.create(output: const ['新', '正文']);
      final updates = await fixture
          .next(requestId: 'request-1', segmentId: 'segment-new')
          .toList();
      expect(updates.first.status, AiDraftStatus.streaming);
      expect(updates.last.status, AiDraftStatus.completed);
      expect(updates.last.draft, '新正文');
    });

    test('saves exactly one segment after completion', () async {
      final fixture = await _Fixture.create(output: const ['新正文']);
      await fixture
          .next(requestId: 'request-1', segmentId: 'segment-new')
          .drain<void>();
      final segments = await fixture.segments.listSegments('project-1');
      expect(segments.where((item) => item.id == 'segment-new'), hasLength(1));
      expect(segments.last.orderIndex, 2);
    });

    test('auto story uses the real generation pipeline serially', () async {
      final fixture = await _Fixture.create(output: const ['自动生成的正文']);
      var id = 0;
      late AutoStoryRunner runner;
      runner = AutoStoryRunner(
        generateSegment:
            ({
              required projectId,
              required userInstruction,
              required selectedCharacterIds,
              required selectedWorldCardIds,
              required requestId,
              required segmentId,
              required nowUtc,
            }) => fixture.generateNext(
              projectId: projectId,
              userInstruction: userInstruction,
              selectedCharacterIds: selectedCharacterIds,
              selectedWorldCardIds: selectedWorldCardIds,
              requestId: requestId,
              segmentId: segmentId,
              nowUtc: nowUtc,
            ),
        cancelGeneration: fixture.generateNext.cancel,
        nextId: (prefix) => '$prefix-auto-${id++}',
        now: () => _later,
      );
      addTearDown(runner.dispose);
      final subscription = runner.updates.listen((update) {
        if (update.status == AutoStoryRunStatus.segmentCompleted &&
            update.generatedCount == 3) {
          runner.stop(projectId: 'project-1');
        }
      });
      addTearDown(subscription.cancel);

      await runner.start(
        projectId: 'project-1',
        initialInstruction: '只用于第一段的方向',
        selectedCharacterIds: const {},
        selectedWorldCardIds: const {},
      );

      final segments = await fixture.segments.listSegments('project-1');
      expect(segments, hasLength(5));
      expect(
        segments.where((segment) => segment.id.contains('-auto-')),
        hasLength(3),
      );
      expect(fixture.runtime.requests, hasLength(3));
      expect(
        fixture.runtime.requests.first.messages.single.content,
        contains('只用于第一段的方向'),
      );
      expect(
        fixture.runtime.requests[1].messages.single.content,
        contains('自动生成的正文'),
      );
      expect(
        fixture.runtime.requests
            .map((request) => request.providerConfigId)
            .toSet(),
        hasLength(1),
      );
      expect(
        fixture.runtime.requests.map((request) => request.model).toSet(),
        hasLength(1),
      );
    });

    test('allows an empty next-segment instruction', () async {
      final fixture = await _Fixture.create(output: const ['自然继续']);
      await fixture
          .next(
            requestId: 'request-1',
            segmentId: 'segment-new',
            instruction: '',
          )
          .drain<void>();
      expect(
        fixture.runtime.requests.single.messages.single.content,
        isNotEmpty,
      );
    });

    test('passes character and world context into the prompt', () async {
      final fixture = await _Fixture.create(output: const ['继续']);
      await fixture
          .next(requestId: 'request-1', segmentId: 'segment-new')
          .drain<void>();
      final request = fixture.runtime.requests.single;
      expect(request.systemPrompt, contains('测试角色A'));
      expect(request.systemPrompt, contains('旧公寓失踪事件'));
    });

    test(
      'passes project guidance and relevant outline without mutating status',
      () async {
        final fixture = await _Fixture.create(output: const ['继续']);
        final before = await fixture.outlines.listOutlineNodes('project-1');

        await fixture
            .next(requestId: 'request-1', segmentId: 'segment-new')
            .drain<void>();

        final prompt = fixture.runtime.requests.single.systemPrompt;
        expect(prompt, contains('使用自然简洁的第三人称叙事'));
        expect(prompt, contains('【当前剧情目标】'));
        expect(prompt, contains('发现门没有锁'));
        expect(prompt, contains('【后续剧情方向】'));
        expect(prompt, contains('温热的茶'));
        final after = await fixture.outlines.listOutlineNodes('project-1');
        expect(
          after.map((node) => (node.id, node.status)),
          before.map((node) => (node.id, node.status)),
        );
      },
    );

    test('provider failure creates no segment', () async {
      final fixture = await _Fixture.create(
        error: const AiProviderNetworkException(),
      );
      await expectLater(
        fixture
            .next(requestId: 'request-1', segmentId: 'segment-new')
            .drain<void>(),
        throwsA(isA<AiProviderNetworkException>()),
      );
      expect(await fixture.segments.listSegments('project-1'), hasLength(2));
    });

    test(
      'zero-content transport interruption retries once before saving',
      () async {
        final fixture = await _Fixture.create(
          output: const ['重试后的正文'],
          error: _beforeContentInterruption('responseBodyInterrupted'),
          errorOnlyOnFirstAttempt: true,
        );

        final updates = await fixture
            .next(requestId: 'retry-once', segmentId: 'segment-retry')
            .toList();

        expect(
          updates.map((update) => update.status),
          contains(AiDraftStatus.retrying),
        );
        expect(updates.last.status, AiDraftStatus.completed);
        expect(fixture.runtime.streamAttemptCount, 2);
        expect(fixture.runtime.requests, hasLength(2));
        expect(
          fixture.runtime.requests.map((request) => request.requestId).toSet(),
          {'retry-once'},
        );
        expect(
          fixture.runtime.requests.map((request) => request.model).toSet(),
          hasLength(1),
        );
        final segments = await fixture.segments.listSegments('project-1');
        expect(
          segments.where((segment) => segment.id == 'segment-retry'),
          hasLength(1),
        );
      },
    );

    test('second zero-content interruption stops after one retry', () async {
      final fixture = await _Fixture.create(
        error: _beforeContentInterruption('responseBodyInterrupted'),
      );

      await expectLater(
        fixture
            .next(requestId: 'retry-twice', segmentId: 'segment-retry')
            .drain<void>(),
        throwsA(isA<AiProviderInterruptedBeforeContentException>()),
      );

      expect(fixture.runtime.streamAttemptCount, 2);
      expect(await fixture.segments.listSegments('project-1'), hasLength(2));
    });

    test('transient before-content causes use the same retry policy', () async {
      for (final cause in const [
        'SocketException',
        'ClientException',
        'TimeoutException',
      ]) {
        final fixture = await _Fixture.create(
          output: ['正文-$cause'],
          error: _beforeContentInterruption(cause),
          errorOnlyOnFirstAttempt: true,
        );

        await fixture
            .next(requestId: 'retry-$cause', segmentId: 'segment-$cause')
            .drain<void>();
        expect(fixture.runtime.streamAttemptCount, 2, reason: cause);
      }
    });

    for (final binding in const [
      ('gemini-config', 'gemini-3.1-flash-lite'),
      ('deepseek-config', 'deepseek-v4-flash'),
    ]) {
      test('zero-content retry preserves ${binding.$2}', () async {
        final fixture = await _Fixture.create(
          output: const ['绑定保持正确'],
          error: _beforeContentInterruption('responseBodyInterrupted'),
          errorOnlyOnFirstAttempt: true,
          projectProviderId: binding.$1,
          projectModel: binding.$2,
        );

        await fixture
            .next(
              requestId: 'bound-${binding.$1}',
              segmentId: 'segment-${binding.$1}',
            )
            .drain<void>();

        expect(fixture.runtime.requests, hasLength(2));
        expect(
          fixture.runtime.requests
              .map((request) => request.providerConfigId)
              .toSet(),
          {binding.$1},
        );
        expect(
          fixture.runtime.requests.map((request) => request.model).toSet(),
          {binding.$2},
        );
      });
    }

    test('HTTP provider errors are not retried as transport EOF', () async {
      final fixture = await _Fixture.create(
        error: const AiProviderProtocolException('HTTP 400 INVALID_ARGUMENT'),
      );

      await expectLater(
        fixture
            .next(requestId: 'http-400', segmentId: 'segment-http')
            .drain<void>(),
        throwsA(isA<AiProviderProtocolException>()),
      );
      expect(fixture.runtime.streamAttemptCount, 1);
    });

    test('provider parser errors are not rewritten as providerEmpty', () async {
      final fixture = await _Fixture.create(
        error: const AiProviderInvalidResponseException(
          'gemini response parse: candidates has invalid type',
        ),
      );

      await expectLater(
        fixture
            .next(requestId: 'parser-error', segmentId: 'segment-parser')
            .drain<void>(),
        throwsA(
          isA<AiProviderInvalidResponseException>()
              .having((error) => error.emptyKind, 'emptyKind', isNull)
              .having(
                (error) => error.diagnostic,
                'diagnostic',
                contains('candidates has invalid type'),
              )
              .having(
                (error) => error.responseDiagnostics?.abnormalEof,
                'abnormalEof',
                isFalse,
              ),
        ),
      );
      expect(fixture.runtime.streamAttemptCount, 1);
      expect(await fixture.segments.listSegments('project-1'), hasLength(2));
    });

    test('filtered and legal empty responses are not retried', () async {
      for (final kind in const [
        AiEmptyResponseKind.promptBlocked,
        AiEmptyResponseKind.filteredEmpty,
        AiEmptyResponseKind.candidateEmpty,
        AiEmptyResponseKind.providerEmpty,
      ]) {
        final fixture = await _Fixture.create(
          error: AiProviderInvalidResponseException.empty(
            emptyKind: kind,
            responseDiagnostics: const AiProviderResponseDiagnostics(
              httpStatus: 200,
              rawFinishReason: 'STOP',
              streamClosedNormally: true,
              abnormalEof: false,
            ),
          ),
        );

        await expectLater(
          fixture
              .next(
                requestId: 'no-retry-${kind.name}',
                segmentId: 'segment-${kind.name}',
              )
              .drain<void>(),
          throwsA(isA<AiProviderInvalidResponseException>()),
        );
        expect(fixture.runtime.streamAttemptCount, 1, reason: kind.name);
      }
    });

    test('cancelled generation keeps draft out of storage', () async {
      final fixture = await _Fixture.create(waitForCancel: true);
      final updatesFuture = fixture
          .next(requestId: 'request-1', segmentId: 'segment-new')
          .toList();
      await fixture.runtime.started.future;
      expect(fixture.generateNext.cancel('request-1'), isTrue);
      final updates = await updatesFuture;
      expect(updates.last.status, AiDraftStatus.cancelled);
      expect(await fixture.segments.listSegments('project-1'), hasLength(2));
    });

    test('cancel with a different request id is ignored', () async {
      final fixture = await _Fixture.create(waitForCancel: true);
      final updatesFuture = fixture
          .next(requestId: 'request-1', segmentId: 'segment-new')
          .toList();
      await fixture.runtime.started.future;
      expect(fixture.generateNext.cancel('request-other'), isFalse);
      expect(fixture.generateNext.cancel('request-1'), isTrue);
      await updatesFuture;
    });

    test('cleans markdown fences before persistence', () async {
      final fixture = await _Fixture.create(output: const ['```text\n正文\n```']);
      await fixture
          .next(requestId: 'request-1', segmentId: 'segment-new')
          .drain<void>();
      expect((await fixture.segments.getSegment('segment-new')).content, '正文');
    });

    test(
      'classifies a provider response with no text as providerEmpty',
      () async {
        final fixture = await _Fixture.create(output: const []);

        await expectLater(
          fixture
              .next(requestId: 'empty-provider', segmentId: 'segment-new')
              .drain<void>(),
          throwsA(
            isA<AiProviderInvalidResponseException>().having(
              (error) => error.emptyKind,
              'emptyKind',
              AiEmptyResponseKind.providerEmpty,
            ),
          ),
        );
        expect(await fixture.segments.listSegments('project-1'), hasLength(2));
      },
    );

    test('classifies whitespace-only adapter text separately', () async {
      final fixture = await _Fixture.create(output: const ['  \n\t  ']);

      await expectLater(
        fixture
            .next(requestId: 'empty-whitespace', segmentId: 'segment-new')
            .drain<void>(),
        throwsA(
          isA<AiProviderInvalidResponseException>().having(
            (error) => error.emptyKind,
            'emptyKind',
            AiEmptyResponseKind.whitespaceOnly,
          ),
        ),
      );
    });

    test('classifies novel cleaner data loss as parserEmpty', () async {
      final fixture = await _Fixture.create(output: const ['```text\n```']);

      await expectLater(
        fixture
            .next(requestId: 'empty-parser', segmentId: 'segment-new')
            .drain<void>(),
        throwsA(
          isA<AiProviderInvalidResponseException>()
              .having(
                (error) => error.emptyKind,
                'emptyKind',
                AiEmptyResponseKind.parserEmpty,
              )
              .having(
                (error) => error.responseDiagnostics?.normalizedChars,
                'normalizedChars',
                greaterThan(0),
              )
              .having(
                (error) => error.responseDiagnostics?.finalResultChars,
                'finalResultChars',
                0,
              ),
        ),
      );
    });

    test(
      'uses provider terminal semantics for filtered empty output',
      () async {
        final fixture = await _Fixture.create(
          output: const [],
          finishReason: AiFinishReason.contentFiltered,
        );

        await expectLater(
          fixture
              .next(requestId: 'empty-filtered', segmentId: 'segment-new')
              .drain<void>(),
          throwsA(
            isA<AiProviderInvalidResponseException>()
                .having(
                  (error) => error.emptyKind,
                  'emptyKind',
                  AiEmptyResponseKind.filteredEmpty,
                )
                .having(
                  (error) => error.responseDiagnostics?.normalizedFinishReason,
                  'finishReason',
                  'contentFiltered',
                ),
          ),
        );
      },
    );
  });

  group('segment AI draft operations', () {
    test('rewrite generation does not modify the segment', () async {
      final fixture = await _Fixture.create(output: const ['重写草稿']);
      await fixture
          .rewrite(
            projectId: 'project-1',
            segmentId: 'segment-1',
            instruction: '',
            selectedCharacterIds: const {},
            selectedWorldCardIds: const {},
            requestId: 'rewrite-1',
          )
          .drain<void>();
      expect(
        (await fixture.segments.getSegment('segment-1')).content,
        '雨一直没有停。',
      );
      expect(await fixture.segments.listRevisions('segment-1'), isEmpty);
    });

    test('confirmed rewrite archives the prior revision', () async {
      final fixture = await _Fixture.create(output: const ['重写草稿']);
      final original = await fixture.segments.getSegment('segment-1');
      final updated = await fixture.rewrite.apply(
        segmentId: original.id,
        originalContent: original.content,
        draft: '重写后的正文',
        instruction: '更压抑',
        nowUtc: _later,
        revisionId: 'revision-1',
      );
      expect(updated.revision, 2);
      final revisions = await fixture.segments.listRevisions(original.id);
      expect(revisions.single.content, original.content);
      expect(revisions.single.mode, 'ai_rewrite');
    });

    test('failed rewrite leaves the original unchanged', () async {
      final fixture = await _Fixture.create(
        error: const AiProviderTimeoutException(),
      );
      await expectLater(
        fixture
            .rewrite(
              projectId: 'project-1',
              segmentId: 'segment-1',
              instruction: '',
              selectedCharacterIds: const {},
              selectedWorldCardIds: const {},
              requestId: 'rewrite-1',
            )
            .drain<void>(),
        throwsA(isA<AiProviderTimeoutException>()),
      );
      expect((await fixture.segments.getSegment('segment-1')).revision, 1);
    });

    test('modify rejects an empty instruction', () async {
      final fixture = await _Fixture.create();
      expect(
        () => fixture.modify(
          projectId: 'project-1',
          segmentId: 'segment-1',
          instruction: ' ',
          selectedCharacterIds: const {},
          selectedWorldCardIds: const {},
          requestId: 'modify-1',
        ),
        throwsA(isA<DataFormatException>()),
      );
    });

    test('confirmed modify creates an ai_modify revision', () async {
      final fixture = await _Fixture.create();
      final original = await fixture.segments.getSegment('segment-1');
      await fixture.modify.apply(
        segmentId: original.id,
        originalContent: original.content,
        draft: '更压抑的雨夜。',
        instruction: '语气更压抑',
        nowUtc: _later,
        revisionId: 'revision-1',
      );
      final revision = (await fixture.segments.listRevisions(
        original.id,
      )).single;
      expect(revision.mode, 'ai_modify');
      expect(revision.userInstruction, '语气更压抑');
    });

    test('selection modify changes only the selected range', () async {
      final fixture = await _Fixture.create();
      final original = await fixture.segments.getSegment('segment-2');
      final updated = await fixture.selection.apply(
        segmentId: original.id,
        originalContent: original.content,
        selectionStart: 2,
        selectionEnd: 6,
        replacementDraft: '缓慢走到门前',
        instruction: '增加动作',
        nowUtc: _later,
        revisionId: 'revision-selection',
      );
      expect(
        updated.content.startsWith(original.content.substring(0, 2)),
        isTrue,
      );
      expect(updated.content.endsWith(original.content.substring(6)), isTrue);
      expect(updated.content, contains('缓慢走到门前'));
    });

    test('selection modify archives the complete original segment', () async {
      final fixture = await _Fixture.create();
      final original = await fixture.segments.getSegment('segment-2');
      await fixture.selection.apply(
        segmentId: original.id,
        originalContent: original.content,
        selectionStart: 0,
        selectionEnd: 2,
        replacementDraft: '女孩',
        instruction: '',
        nowUtc: _later,
        revisionId: 'revision-selection',
      );
      final revision = (await fixture.segments.listRevisions(
        original.id,
      )).single;
      expect(revision.content, original.content);
      expect(revision.mode, 'ai_selection_modify');
    });

    test('stale segment content rejects a generated replacement', () async {
      final fixture = await _Fixture.create();
      final original = await fixture.segments.getSegment('segment-1');
      await fixture.segments.upsertSegment(
        original.copyWith(content: '用户已经改过'),
      );
      expect(
        fixture.rewrite.apply(
          segmentId: original.id,
          originalContent: original.content,
          draft: '过期 AI 草稿',
          instruction: '',
          nowUtc: _later,
          revisionId: 'revision-stale',
        ),
        throwsA(isA<DataConflictException>()),
      );
    });
  });

  group('GenerateChatReply', () {
    test('streams and stores one assistant message', () async {
      final fixture = await _Fixture.create(output: const ['我还', '不能回去。']);
      final updates = await fixture
          .chatReply(
            sessionId: 'session-1',
            userMessageId: 'user-1',
            requestId: 'chat-1',
            assistantMessageId: 'assistant-1',
            nowUtc: _later,
          )
          .toList();
      expect(updates.last.status, AiDraftStatus.completed);
      final messages = await fixture.chats.listMessages('session-1');
      expect(messages.last.role, ChatMessageRole.assistant);
      expect(messages.last.content, '我还不能回去。');
    });

    test('chat prompt uses the bound persona identity', () async {
      final fixture = await _Fixture.create(output: const ['回答']);
      await fixture
          .chatReply(
            sessionId: 'session-1',
            userMessageId: 'user-1',
            requestId: 'chat-1',
            assistantMessageId: 'assistant-1',
            nowUtc: _later,
          )
          .drain<void>();
      expect(fixture.runtime.requests.single.systemPrompt, contains('测试角色A'));
      expect(fixture.runtime.requests.single.systemPrompt, contains('安静、谨慎'));
    });

    test(
      'chat prompt stays independent from novel project background',
      () async {
        final fixture = await _Fixture.create(output: const ['回答']);
        await fixture
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'chat-1',
              assistantMessageId: 'assistant-1',
              nowUtc: _later,
            )
            .drain<void>();
        expect(
          fixture.runtime.requests.single.systemPrompt,
          isNot(contains('保持悬疑')),
        );
      },
    );

    test('AI failure preserves the already stored user message', () async {
      final fixture = await _Fixture.create(
        error: const AiProviderServerException(),
      );
      await expectLater(
        fixture
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'chat-1',
              assistantMessageId: 'assistant-1',
              nowUtc: _later,
            )
            .drain<void>(),
        throwsA(isA<AiProviderServerException>()),
      );
      final messages = await fixture.chats.listMessages('session-1');
      expect(messages.map((item) => item.id), ['user-1']);
    });

    test(
      'zero-content chat interruption retries the original reply once',
      () async {
        final fixture = await _Fixture.create(
          output: const ['重试后的聊天回复'],
          error: _beforeContentInterruption('responseBodyInterrupted'),
          errorOnlyOnFirstAttempt: true,
        );

        final updates = await fixture
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'chat-before-content',
              assistantMessageId: 'assistant-before-content',
              nowUtc: _later,
            )
            .toList();

        expect(
          updates.map((update) => update.status),
          contains(AiDraftStatus.autoRecovering),
        );
        expect(updates.last.status, AiDraftStatus.completed);
        expect(fixture.runtime.streamAttemptCount, 2);
        final assistants = (await fixture.chats.listMessages('session-1'))
            .where((message) => message.role == ChatMessageRole.assistant)
            .toList();
        expect(assistants, hasLength(1));
        expect(assistants.single.id, 'assistant-before-content');
        expect(assistants.single.content, '重试后的聊天回复');
      },
    );

    test(
      'second zero-content chat interruption creates no empty assistant',
      () async {
        final fixture = await _Fixture.create(
          error: _beforeContentInterruption('responseBodyInterrupted'),
        );

        await expectLater(
          fixture
              .chatReply(
                sessionId: 'session-1',
                userMessageId: 'user-1',
                requestId: 'chat-before-content-failed',
                assistantMessageId: 'assistant-before-content-failed',
                nowUtc: _later,
              )
              .drain<void>(),
          throwsA(isA<AiProviderInterruptedBeforeContentException>()),
        );

        expect(fixture.runtime.streamAttemptCount, 2);
        expect(await fixture.chats.listMessages('session-1'), hasLength(1));
      },
    );

    test('cancel does not store a partial assistant message', () async {
      final fixture = await _Fixture.create(waitForCancel: true);
      final updatesFuture = fixture
          .chatReply(
            sessionId: 'session-1',
            userMessageId: 'user-1',
            requestId: 'chat-1',
            assistantMessageId: 'assistant-1',
            nowUtc: _later,
          )
          .toList();
      await fixture.runtime.started.future;
      expect(fixture.chatReply.cancel('chat-1'), isTrue);
      expect((await updatesFuture).last.status, AiDraftStatus.cancelled);
      expect(await fixture.chats.listMessages('session-1'), hasLength(1));
    });

    test('legacy sessions without persona cannot generate', () async {
      final fixture = await _Fixture.create(legacySession: true);
      await expectLater(
        fixture
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'chat-1',
              assistantMessageId: 'assistant-1',
              nowUtc: _later,
            )
            .drain<void>(),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('deleted personas cannot generate a new reply', () async {
      final fixture = await _Fixture.create();
      await fixture.personas.softDeletePersona('persona-1', _later);
      await expectLater(
        fixture
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'chat-1',
              assistantMessageId: 'assistant-1',
              nowUtc: _later,
            )
            .drain<void>(),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('deleted sessions cannot generate a new reply', () async {
      final fixture = await _Fixture.create();
      await fixture.chats.softDeleteSession('session-1', _later);
      await expectLater(
        fixture
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'chat-1',
              assistantMessageId: 'assistant-1',
              nowUtc: _later,
            )
            .drain<void>(),
        throwsA(isA<DataConflictException>()),
      );
    });

    test('assistant message keeps the session persona relationship', () async {
      final fixture = await _Fixture.create(output: const ['回答']);
      await fixture
          .chatReply(
            sessionId: 'session-1',
            userMessageId: 'user-1',
            requestId: 'chat-1',
            assistantMessageId: 'assistant-1',
            nowUtc: _later,
          )
          .drain<void>();
      expect(
        (await fixture.chats.getSession('session-1')).personaId,
        'persona-1',
      );
    });

    for (final length in const [100, 1000, 5000, 10000]) {
      test(
        'preserves a $length character reply through repository readback',
        () async {
          final content = List.filled(length, '文').join();
          final fixture = await _Fixture.create(output: [content]);
          final updates = await fixture
              .chatReply(
                sessionId: 'session-1',
                userMessageId: 'user-1',
                requestId: 'chat-$length',
                assistantMessageId: 'assistant-$length',
                nowUtc: _later,
              )
              .toList();

          final saved = (await fixture.chats.listMessages('session-1')).last;
          expect(updates.last.draft.length, length);
          expect(saved.content, content);
          expect(saved.content.length, length);
        },
      );
    }

    for (final count in const [100, 500, 1000, 5000]) {
      test(
        'preserves order and uniqueness across $count stream chunks',
        () async {
          final chunks = List.generate(
            count,
            (index) => '[${index.toString().padLeft(5, '0')}]',
          );
          final fixture = await _Fixture.create(output: chunks);
          await fixture
              .chatReply(
                sessionId: 'session-1',
                userMessageId: 'user-1',
                requestId: 'chunks-$count',
                assistantMessageId: 'assistant-chunks-$count',
                nowUtc: _later,
              )
              .drain<void>();

          final saved = (await fixture.chats.listMessages('session-1')).last;
          expect(saved.content, chunks.join());
        },
      );
    }

    test('normal chat STOP never schedules another assistant reply', () async {
      final fixture = await _Fixture.create(
        output: const ['一次正常回复。'],
        finishReason: AiFinishReason.stop,
      );

      await fixture
          .chatReply(
            sessionId: 'session-1',
            userMessageId: 'user-1',
            requestId: 'single-stop-reply',
            assistantMessageId: 'assistant-single-stop',
            nowUtc: _later,
          )
          .drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fixture.runtime.requests, hasLength(1));
      final assistants = (await fixture.chats.listMessages(
        'session-1',
      )).where((message) => message.role == ChatMessageRole.assistant).toList();
      expect(assistants, hasLength(1));
      expect(assistants.single.id, 'assistant-single-stop');
      expect(assistants.single.finishReason, AiFinishReason.stop);
    });

    test('length continuation appends to the same assistant message', () async {
      final fixture = await _Fixture.create(
        output: const ['前半段，'],
        finishReason: AiFinishReason.length,
      );
      final first = await fixture
          .chatReply(
            sessionId: 'session-1',
            userMessageId: 'user-1',
            requestId: 'limited',
            assistantMessageId: 'assistant-limited',
            nowUtc: _later,
          )
          .toList();
      expect(first.last.status, AiDraftStatus.limited);

      fixture.runtime
        ..chunks = const ['接着写完。']
        ..finishReason = AiFinishReason.stop;
      await fixture
          .chatReply(
            sessionId: 'session-1',
            userMessageId: 'user-1',
            requestId: 'continued',
            assistantMessageId: 'unused-assistant-id',
            continueMessageId: 'assistant-limited',
            nowUtc: _later.add(const Duration(minutes: 1)),
          )
          .drain<void>();

      final assistants = (await fixture.chats.listMessages(
        'session-1',
      )).where((message) => message.role == ChatMessageRole.assistant).toList();
      expect(assistants, hasLength(1));
      expect(assistants.single.id, 'assistant-limited');
      expect(assistants.single.content, '前半段，接着写完。');
      expect(assistants.single.finishReason, AiFinishReason.stop);
    });

    test('abnormal EOF keeps partial content marked as interrupted', () async {
      final fixture = await _Fixture.create(
        output: const ['partial reply'],
        interruptAfterOutput: true,
      );
      final updates = await fixture
          .chatReply(
            sessionId: 'session-1',
            userMessageId: 'user-1',
            requestId: 'interrupted',
            assistantMessageId: 'assistant-interrupted',
            nowUtc: _later,
          )
          .toList();

      expect(updates.last.status, AiDraftStatus.interrupted);
      expect(fixture.runtime.requests, hasLength(2));
      final saved = (await fixture.chats.listMessages('session-1')).last;
      expect(saved.content, 'partial reply');
      expect(saved.finishReason, AiFinishReason.interrupted);
    });

    test(
      'interrupted reply automatically continues once in one message',
      () async {
        final fixture = await _Fixture.create(
          output: const ['她缓缓推开门，门后的走廊已经完全'],
          interruptAfterOutput: true,
          recoverAfterInterruption: true,
          recoveryOutput: const ['门后的走廊已经完全陷入黑暗。'],
        );

        final updates = await fixture
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'auto-recovery',
              assistantMessageId: 'assistant-auto-recovery',
              nowUtc: _later,
            )
            .toList();

        expect(
          updates.map((update) => update.status),
          contains(AiDraftStatus.autoRecovering),
        );
        expect(updates.last.status, AiDraftStatus.completed);
        expect(fixture.runtime.requests, hasLength(2));
        final assistants = (await fixture.chats.listMessages('session-1'))
            .where((message) => message.role == ChatMessageRole.assistant)
            .toList();
        expect(assistants, hasLength(1));
        expect(assistants.single.id, 'assistant-auto-recovery');
        expect(assistants.single.content, '她缓缓推开门，门后的走廊已经完全陷入黑暗。');
        expect(assistants.single.finishReason, AiFinishReason.stop);
      },
    );

    test(
      'provider error during automatic recovery preserves interrupted reply',
      () async {
        final fixture = await _Fixture.create(
          output: const ['已经收到的部分内容'],
          interruptAfterOutput: true,
          recoverAfterInterruption: true,
          recoveryError: const AiProviderRateLimitedException(),
        );

        final updates = await fixture
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'recovery-provider-error',
              assistantMessageId: 'assistant-provider-error',
              nowUtc: _later,
            )
            .toList();

        expect(updates.last.status, AiDraftStatus.interrupted);
        expect(fixture.runtime.requests, hasLength(2));
        final saved = await fixture.chats.getMessage(
          'assistant-provider-error',
        );
        expect(saved.content, '已经收到的部分内容');
        expect(saved.finishReason, AiFinishReason.interrupted);
      },
    );

    test(
      'user stop during automatic recovery keeps the first partial',
      () async {
        final fixture = await _Fixture.create(
          output: const ['中断前已经收到的内容'],
          interruptAfterOutput: true,
          recoverAfterInterruption: true,
          recoveryWaitForCancel: true,
        );
        final updates = <AiDraftUpdate>[];
        final done = fixture
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'stop-recovery',
              assistantMessageId: 'assistant-stop-recovery',
              nowUtc: _later,
            )
            .listen(updates.add)
            .asFuture<void>();
        await fixture.runtime.recoveryStarted.future;
        expect(fixture.chatReply.cancel('stop-recovery'), isTrue);
        await done;

        expect(updates.last.status, AiDraftStatus.cancelled);
        expect(updates.last.savedMessage?.id, 'assistant-stop-recovery');
        final saved = await fixture.chats.getMessage('assistant-stop-recovery');
        expect(saved.content, '中断前已经收到的内容');
        expect(saved.finishReason, AiFinishReason.interrupted);
      },
    );

    test('MAX_TOKENS is saved without automatic recovery', () async {
      final fixture = await _Fixture.create(
        output: const ['达到长度限制的部分回复'],
        finishReason: AiFinishReason.length,
      );

      final updates = await fixture
          .chatReply(
            sessionId: 'session-1',
            userMessageId: 'user-1',
            requestId: 'length-limited',
            assistantMessageId: 'assistant-length-limited',
            nowUtc: _later,
          )
          .toList();

      expect(updates.last.status, AiDraftStatus.limited);
      expect(fixture.runtime.requests, hasLength(1));
      expect(
        (await fixture.chats.getMessage(
          'assistant-length-limited',
        )).finishReason,
        AiFinishReason.length,
      );
    });

    test(
      'interrupted continuation includes partial assistant context',
      () async {
        final fixture = await _Fixture.create(
          output: const ['partial sentence'],
          interruptAfterOutput: true,
        );
        await fixture
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'interrupted-first',
              assistantMessageId: 'assistant-interrupted-context',
              nowUtc: _later,
            )
            .drain<void>();

        fixture.runtime
          ..chunks = const [' continued']
          ..interruptAfterOutput = false
          ..finishReason = AiFinishReason.stop;
        await fixture
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'interrupted-continued',
              assistantMessageId: 'unused',
              continueMessageId: 'assistant-interrupted-context',
              nowUtc: _later.add(const Duration(minutes: 1)),
            )
            .drain<void>();

        final request = fixture.runtime.requests.last;
        expect(
          request.messages.any(
            (message) =>
                message.role == AiMessageRole.assistant &&
                message.content == 'partial sentence',
          ),
          isTrue,
        );
        final saved = (await fixture.chats.listMessages(
          'session-1',
        )).where((message) => message.role == ChatMessageRole.assistant).single;
        expect(saved.content, 'partial sentence continued');
        expect(saved.finishReason, AiFinishReason.stop);
      },
    );
  });

  group('AiRequestCoordinator', () {
    test('starting a new request cancels the old request', () {
      final coordinator = AiRequestCoordinator();
      final first = coordinator.begin('novel', 'one');
      coordinator.begin('novel', 'two');
      expect(first.isCancelled, isTrue);
      expect(coordinator.isCurrent('novel', 'two'), isTrue);
    });

    test('finishing a stale request keeps the current request', () {
      final coordinator = AiRequestCoordinator();
      coordinator.begin('novel', 'one');
      coordinator.begin('novel', 'two');
      coordinator.finish('novel', 'one');
      expect(coordinator.isCurrent('novel', 'two'), isTrue);
    });

    test('channels isolate novel and chat requests', () {
      final coordinator = AiRequestCoordinator();
      coordinator.begin('novel', 'novel-1');
      coordinator.begin('chat', 'chat-1');
      expect(coordinator.isCurrent('novel', 'novel-1'), isTrue);
      expect(coordinator.isCurrent('chat', 'chat-1'), isTrue);
    });
  });
  group('latest chat controls', () {
    Future<void> firstReply(_Fixture f) => f
        .chatReply(
          sessionId: 'session-1',
          userMessageId: 'user-1',
          requestId: 'first',
          assistantMessageId: 'original',
          nowUtc: _later,
        )
        .drain<void>();
    test(
      'regeneration replaces last assistant and excludes old content from prompt',
      () async {
        final f = await _Fixture.create(output: ['old unique answer']);
        await firstReply(f);
        final original = await f.chats.getMessage('original');
        f.runtime.chunks = ['new answer'];
        await f
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'regen',
              assistantMessageId: 'unused',
              regenerateMessageId: original.id,
              nowUtc: _later,
            )
            .drain<void>();
        final messages = await f.chats.listMessages('session-1');
        expect(messages, hasLength(2));
        expect(messages.last.id, original.id);
        expect(messages.last.content, 'new answer');
        expect(messages.last.revision, original.revision + 1);
        expect(
          f.runtime.requests.last.messages.any(
            (m) => m.content.contains('old unique answer'),
          ),
          isFalse,
        );
      },
    );
    test(
      'interrupted regeneration preserves old answer and revision',
      () async {
        final f = await _Fixture.create(output: ['old answer']);
        await firstReply(f);
        final original = await f.chats.getMessage('original');
        f.runtime
          ..chunks = ['partial new answer']
          ..interruptAfterOutput = true;
        final updates = await f
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'regen',
              assistantMessageId: 'unused',
              regenerateMessageId: original.id,
              nowUtc: _later,
            )
            .toList();
        final kept = await f.chats.getMessage(original.id);
        expect(kept.content, original.content);
        expect(kept.revision, original.revision);
        expect(updates.last.status, AiDraftStatus.interrupted);
        expect(updates.last.savedMessage, isNull);
      },
    );
    test('cancelled regeneration preserves original reply', () async {
      final f = await _Fixture.create(output: ['old answer']);
      await firstReply(f);
      final original = await f.chats.getMessage('original');
      final updates = f.chatReply(
        sessionId: 'session-1',
        userMessageId: 'user-1',
        requestId: 'regen',
        assistantMessageId: 'unused',
        regenerateMessageId: original.id,
        nowUtc: _later,
      );
      await for (final update in updates) {
        if (update.status == AiDraftStatus.streaming) {
          f.chatReply.cancel('regen');
        }
      }
      expect((await f.chats.getMessage('original')).content, original.content);
      expect(
        (await f.chats.getMessage('original')).revision,
        original.revision,
      );
    });
    test(
      'new user message during regeneration prevents overwrite of older answer',
      () async {
        final f = await _Fixture.create(output: ['old answer']);
        await firstReply(f);
        final original = await f.chats.getMessage('original');
        f.runtime.chunks = ['new answer'];
        Future<void> run() async {
          await for (final update in f.chatReply(
            sessionId: 'session-1',
            userMessageId: 'user-1',
            requestId: 'regen',
            assistantMessageId: 'unused',
            regenerateMessageId: original.id,
            nowUtc: _later,
          )) {
            if (update.status == AiDraftStatus.streaming) {
              await SendChatMessage(f.chats)(
                sessionId: 'session-1',
                messageId: 'new-user',
                role: ChatMessageRole.user,
                content: 'later user',
                nowUtc: _later.add(const Duration(hours: 1)),
              );
            }
          }
        }

        await expectLater(run(), throwsA(isA<DataConflictException>()));
        expect(
          (await f.chats.getMessage('original')).content,
          original.content,
        );
        await expectLater(
          f
              .chatReply(
                sessionId: 'session-1',
                userMessageId: 'user-1',
                requestId: 'old',
                assistantMessageId: 'unused',
                regenerateMessageId: 'original',
                nowUtc: _later,
              )
              .drain<void>(),
          throwsA(isA<DataConflictException>()),
        );
      },
    );
  });
  group('novel output length targets', () {
    test(
      'work temperature reaches generation and labels are removed before clipping',
      () async {
        final f = await _Fixture.create(output: ['【第 １２ 段】\n风 吹开💡门。']);
        await f.outputLimits.save(
          const NovelOutputLimits(
            projectId: 'project-1',
            maximum: 4,
            temperature: .35,
          ),
          expectedRevision: 0,
          now: _later,
        );
        final updates = await f
            .next(requestId: 'cap', segmentId: 'cap-segment')
            .toList();
        expect(f.runtime.requests.single.temperature, .35);
        expect(f.runtime.requests.single.maxTokens, 136);
        expect(
          f.runtime.requests.single.messages.last.content,
          isNot(contains('[段落 ')),
        );
        expect(updates.last.savedSegment!.content, '风 吹开💡');
        expect(updates.last.outputNotice, contains('最多字数'));
      },
    );
    test(
      'default preserves old budget and custom range sends a token allowance',
      () async {
        final f = await _Fixture.create();
        await f
            .next(requestId: 'default', segmentId: 'default-segment')
            .drain<void>();
        expect(f.runtime.requests.last.maxTokens, 2400);
        expect(
          f.runtime.requests.last.systemPrompt,
          isNot(contains('【本作品输出字数】')),
        );
        await f.outputLimits.save(
          const NovelOutputLimits(
            projectId: 'project-1',
            minimum: 100,
            maximum: 300,
          ),
          expectedRevision: 0,
          now: _later,
        );
        await f
            .next(requestId: 'custom', segmentId: 'custom-segment')
            .drain<void>();
        expect(f.runtime.requests.last.maxTokens, 728);
        expect(f.runtime.requests.last.systemPrompt, contains('100–300 字'));
        expect(f.runtime.requests.last.systemPrompt, contains('输出上限始终优先'));
      },
    );
    test(
      'whole rewrites use the range, selection and chat remain independent',
      () async {
        final f = await _Fixture.create();
        await f.outputLimits.save(
          const NovelOutputLimits(projectId: 'project-1', maximum: 200),
          expectedRevision: 0,
          now: _later,
        );
        final target = (await f.segments.listSegments('project-1')).first;
        await f
            .rewrite(
              projectId: 'project-1',
              segmentId: target.id,
              instruction: '重写',
              selectedCharacterIds: const {},
              selectedWorldCardIds: const {},
              requestId: 'rewrite',
            )
            .drain<void>();
        expect(f.runtime.requests.last.systemPrompt, contains('最多 200 字'));
        await f
            .selection(
              projectId: 'project-1',
              segmentId: target.id,
              selectionStart: 0,
              selectionEnd: 1,
              instruction: '修改',
              selectedCharacterIds: const {},
              selectedWorldCardIds: const {},
              requestId: 'selection',
            )
            .drain<void>();
        expect(
          f.runtime.requests.last.systemPrompt,
          isNot(contains('【本作品输出字数】')),
        );
        expect(f.runtime.requests.last.maxTokens, 2400);
        await f
            .chatReply(
              sessionId: 'session-1',
              userMessageId: 'user-1',
              requestId: 'chat',
              assistantMessageId: 'assistant-limit-test',
              nowUtc: _later,
            )
            .drain<void>();
        expect(
          f.runtime.requests.last.systemPrompt,
          isNot(contains('【本作品输出字数】')),
        );
      },
    );
    test(
      'huge minimum never causes automatic retry to fill a word target',
      () async {
        final f = await _Fixture.create(
          output: ['模型上限内的正文'],
          finishReason: AiFinishReason.length,
        );
        await f.outputLimits.save(
          const NovelOutputLimits(projectId: 'project-1', minimum: 1000000),
          expectedRevision: 0,
          now: _later,
        );
        final updates = await f
            .next(requestId: 'limited', segmentId: 'limited-segment')
            .toList();
        expect(f.runtime.requests, hasLength(1));
        expect(updates.last.savedSegment!.content, '模型上限内的正文');
        expect(updates.last.outputNotice, contains('未达到最少字数'));
      },
    );
  });
}

class _Fixture {
  _Fixture._({
    required this.runtime,
    required this.outputLimits,
    required this.projects,
    required this.segments,
    required this.characters,
    required this.worlds,
    required this.outlines,
    required this.chats,
    required this.personas,
    required this.loader,
    required this.generateNext,
    required this.rewrite,
    required this.modify,
    required this.selection,
    required this.chatReply,
  });

  final _FakeRuntime runtime;
  final InMemoryNovelOutputLimitsRepository outputLimits;
  final InMemoryProjectRepository projects;
  final InMemorySegmentRepository segments;
  final InMemoryCharacterRepository characters;
  final InMemoryWorldRepository worlds;
  final InMemoryOutlineRepository outlines;
  final InMemoryChatRepository chats;
  final InMemoryChatPersonaRepository personas;
  final NovelContextLoader loader;
  final GenerateNextSegment generateNext;
  final RewriteSegment rewrite;
  final ModifySegmentWithInstruction modify;
  final SelectionModifySegment selection;
  final GenerateChatReply chatReply;

  Stream<AiDraftUpdate> next({
    required String requestId,
    required String segmentId,
    String instruction = '下一段保持安静，不要立刻揭露真相。',
  }) {
    return generateNext(
      projectId: 'project-1',
      userInstruction: instruction,
      selectedCharacterIds: const {},
      selectedWorldCardIds: const {},
      requestId: requestId,
      segmentId: segmentId,
      nowUtc: _later,
    );
  }

  static Future<_Fixture> create({
    List<String> output = const ['AI 输出'],
    Object? error,
    bool errorOnlyOnFirstAttempt = false,
    bool waitForCancel = false,
    bool interruptAfterOutput = false,
    bool recoverAfterInterruption = false,
    List<String>? recoveryOutput,
    Object? recoveryError,
    bool recoveryWaitForCancel = false,
    AiFinishReason finishReason = AiFinishReason.stop,
    bool secondProject = false,
    bool secondCharacter = false,
    bool legacySession = false,
    String? projectProviderId,
    String? projectModel,
    String? sessionProviderId,
    String? sessionModel,
  }) async {
    final store = InMemoryIbukiStore();
    final projects = InMemoryProjectRepository(store);
    final outputLimits = InMemoryNovelOutputLimitsRepository(projects);
    final segments = InMemorySegmentRepository(store);
    final characters = InMemoryCharacterRepository(store);
    final worlds = InMemoryWorldRepository(store);
    final outlines = InMemoryOutlineRepository(store);
    final chats = InMemoryChatRepository(store);
    final personas = InMemoryChatPersonaRepository(store);
    final runtime = _FakeRuntime(
      chunks: output,
      error: error,
      errorOnlyOnFirstAttempt: errorOnlyOnFirstAttempt,
      waitForCancel: waitForCancel,
      interruptAfterOutput: interruptAfterOutput,
      recoverAfterInterruption: recoverAfterInterruption,
      recoveryChunks: recoveryOutput,
      recoveryError: recoveryError,
      recoveryWaitForCancel: recoveryWaitForCancel,
      finishReason: finishReason,
    );
    await projects.upsertProject(
      Project(
        metadata: _metadata('project-1'),
        title: 'AI 联调测试',
        description: '保持悬疑，慢慢揭露真相。',
        systemPrompt: '使用自然简洁的第三人称叙事，通过动作表现紧张感。',
        aiProviderConfigId: projectProviderId,
        aiModel: projectModel,
      ),
    );
    await segments.upsertSegment(
      Segment(
        metadata: _metadata('segment-1'),
        projectId: 'project-1',
        orderIndex: 0,
        content: '雨一直没有停。',
      ),
    );
    await segments.upsertSegment(
      Segment(
        metadata: _metadata('segment-2'),
        projectId: 'project-1',
        orderIndex: 1,
        content: '少女站在便利店门口。',
      ),
    );
    await characters.upsertCharacter(
      CharacterCard(
        metadata: _metadata('character-1'),
        projectId: 'project-1',
        name: '测试角色A',
        content: '安静、谨慎，对陌生环境保持警觉。',
        sortOrder: 0,
      ),
    );
    if (secondCharacter) {
      await characters.upsertCharacter(
        CharacterCard(
          metadata: _metadata('character-2'),
          projectId: 'project-1',
          name: '测试角色B',
          content: '开朗。',
          sortOrder: 1,
        ),
      );
    }
    await worlds.upsertWorldCard(
      WorldCard(
        metadata: _metadata('world-1'),
        projectId: 'project-1',
        title: '测试世界观',
        content: '旧公寓失踪事件。',
        sortOrder: 0,
      ),
    );
    await outlines.upsertOutlineNode(
      OutlineNode(
        metadata: _metadata('outline-current'),
        projectId: 'project-1',
        title: '发现门没有锁',
        summary: '角色发现门没有锁，但仍保持警觉。',
        orderIndex: 0,
        status: OutlineNodeStatus.current,
      ),
    );
    await outlines.upsertOutlineNode(
      OutlineNode(
        metadata: _metadata('outline-next'),
        projectId: 'project-1',
        title: '温热的茶',
        summary: '进入房间后发现桌上有一杯仍然温热的茶。',
        orderIndex: 1,
        status: OutlineNodeStatus.planned,
      ),
    );
    await personas.upsertPersona(
      ChatPersona(
        metadata: _metadata('persona-1'),
        name: '测试角色A',
        descriptionMode: ChatPersonaDescriptionMode.simple,
        shortDescription: '安静、谨慎，对陌生环境保持警觉。',
        speakingStyle: '短句，自然。',
      ),
    );
    if (secondProject) {
      await projects.upsertProject(
        Project(
          metadata: _metadata('project-2'),
          title: '其它项目',
          description: '',
        ),
      );
      await characters.upsertCharacter(
        CharacterCard(
          metadata: _metadata('other-character'),
          projectId: 'project-2',
          name: '其它角色',
          content: '',
          sortOrder: 0,
        ),
      );
      await worlds.upsertWorldCard(
        WorldCard(
          metadata: _metadata('other-world'),
          projectId: 'project-2',
          title: '其它世界',
          content: '',
          sortOrder: 0,
        ),
      );
    }
    await chats.upsertSession(
      ChatSession(
        metadata: _metadata('session-1'),
        projectId: null,
        characterId: null,
        personaId: legacySession ? null : 'persona-1',
        title: '测试对话',
        aiProviderConfigId: sessionProviderId,
        aiModel: sessionModel,
      ),
    );
    final sendMessage = SendChatMessage(chats);
    await sendMessage(
      sessionId: 'session-1',
      messageId: 'user-1',
      role: ChatMessageRole.user,
      content: '外面还在下雨，你为什么还不回去？',
      nowUtc: _now,
    );
    final loader = NovelContextLoader(
      projects: projects,
      segments: segments,
      characters: characters,
      worlds: worlds,
      outlines: outlines,
    );
    final coordinator = AiRequestCoordinator();
    final modelResolver = AiModelResolver(
      projects: projects,
      chats: chats,
      runtime: runtime,
    );
    final createSegment = CreateSegment(projects, segments);
    final saveSegment = SaveSegment(segments);
    final runner = SegmentAiDraftRunner(
      outputLimits: outputLimits,
      contextLoader: loader,
      promptBuilder: const NovelPromptBuilder(),
      runtime: runtime,
      coordinator: coordinator,
    );
    return _Fixture._(
      runtime: runtime,
      outputLimits: outputLimits,
      projects: projects,
      segments: segments,
      characters: characters,
      worlds: worlds,
      outlines: outlines,
      chats: chats,
      personas: personas,
      loader: loader,
      generateNext: GenerateNextSegment(
        outputLimits: outputLimits,
        contextLoader: loader,
        promptBuilder: const NovelPromptBuilder(),
        runtime: runtime,
        coordinator: coordinator,
        createSegment: createSegment,
        modelResolver: modelResolver,
      ),
      rewrite: RewriteSegment(runner, segments, saveSegment),
      modify: ModifySegmentWithInstruction(runner, segments, saveSegment),
      selection: SelectionModifySegment(runner, segments, saveSegment),
      chatReply: GenerateChatReply(
        chats: chats,
        personas: personas,
        promptBuilder: const ChatPromptBuilder(),
        runtime: runtime,
        coordinator: coordinator,
        modelResolver: modelResolver,
      ),
    );
  }
}

class _FakeRuntime implements AiDetailedGenerationRuntime {
  _FakeRuntime({
    required this.chunks,
    this.error,
    this.errorOnlyOnFirstAttempt = false,
    this.waitForCancel = false,
    this.interruptAfterOutput = false,
    this.recoverAfterInterruption = false,
    this.recoveryChunks,
    this.recoveryError,
    this.recoveryWaitForCancel = false,
    this.finishReason = AiFinishReason.stop,
  });

  List<String> chunks;
  final Object? error;
  final bool errorOnlyOnFirstAttempt;
  final bool waitForCancel;
  bool interruptAfterOutput;
  final bool recoverAfterInterruption;
  final List<String>? recoveryChunks;
  final Object? recoveryError;
  final bool recoveryWaitForCancel;
  AiFinishReason finishReason;
  final List<AiGenerationRequest> requests = [];
  final Completer<void> started = Completer<void>();
  final Completer<void> recoveryStarted = Completer<void>();
  var streamAttemptCount = 0;

  @override
  Future<AiResolvedProvider> resolveDefault() async =>
      _resolved('deepseek-config', 'deepseek-v4-flash');

  @override
  Future<AiResolvedProvider> resolveSelection({
    String? providerConfigId,
    String? model,
  }) async => providerConfigId == null || model == null
      ? resolveDefault()
      : _resolved(providerConfigId, model);

  AiResolvedProvider _resolved(String providerId, String model) {
    final isGemini = providerId.toLowerCase().contains('gemini');
    return AiResolvedProvider(
      config: AiProviderConfig(
        id: providerId,
        type: isGemini ? AiProviderType.gemini : AiProviderType.deepseek,
        displayName: isGemini ? 'Gemini' : 'DeepSeek',
        baseUrl: 'https://example.test',
        apiKeyRef: 'secure.$providerId',
        selectedModel: model,
        enabled: true,
        connectionStatus: AiProviderConnectionStatus.connected,
        availableModels: [model],
        createdAtUtc: _now,
        updatedAtUtc: _now,
      ),
      selection: AiDefaultSelection(
        providerId: providerId,
        modelId: model,
        updatedAtUtc: _now,
      ),
    );
  }

  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    streamAttemptCount += 1;
    requests.add(request);
    if (!started.isCompleted) {
      started.complete();
    }
    if (error != null &&
        (!errorOnlyOnFirstAttempt || streamAttemptCount == 1)) {
      throw error!;
    }
    if (streamAttemptCount > 1 && recoveryError != null) {
      throw recoveryError!;
    }
    if (streamAttemptCount > 1 && recoveryWaitForCancel) {
      if (!recoveryStarted.isCompleted) recoveryStarted.complete();
      while (!(cancellation?.isCancelled ?? false)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      throw const AiProviderCancelledException();
    }
    if (waitForCancel) {
      while (!(cancellation?.isCancelled ?? false)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      throw const AiProviderCancelledException();
    }
    final attemptChunks = streamAttemptCount > 1 && recoveryChunks != null
        ? recoveryChunks!
        : chunks;
    for (final chunk in attemptChunks) {
      if (cancellation?.isCancelled ?? false) {
        throw const AiProviderCancelledException();
      }
      yield chunk;
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Stream<AiStreamEvent> streamEvents(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    await for (final chunk in stream(request, cancellation: cancellation)) {
      yield AiStreamEvent.content(chunk);
    }
    if (interruptAfterOutput &&
        (!recoverAfterInterruption || streamAttemptCount == 1)) {
      throw const AiProviderInterruptedException();
    }
    yield AiStreamEvent.finished(finishReason);
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async {
    final output = StringBuffer();
    await for (final chunk in stream(request, cancellation: cancellation)) {
      output.write(chunk);
    }
    return output.toString();
  }
}

EntityMetadata _metadata(String id) =>
    EntityMetadata(id: id, createdAt: _now, updatedAt: _now, revision: 1);

AiProviderInterruptedBeforeContentException _beforeContentInterruption(
  String causeType,
) => AiProviderInterruptedBeforeContentException(
  causeType: causeType,
  timeoutType: causeType == 'TimeoutException' ? 'firstByte' : 'none',
  responseDiagnostics: AiProviderResponseDiagnostics(
    provider: 'gemini',
    model: 'gemini-3.1-flash-lite',
    httpStatus: 200,
    responseContentType: 'text/event-stream',
    firstByteReceived: false,
    firstSseEventReceived: false,
    streamEventCount: 0,
    rawReceivedChars: 0,
    normalizedChars: 0,
    finalResultChars: 0,
    streamClosedNormally: false,
    abnormalEof: true,
    exceptionType: causeType,
  ),
);

final _now = DateTime.utc(2026, 8, 10, 8);
final _later = DateTime.utc(2026, 8, 10, 9);
