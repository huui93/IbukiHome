import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/application/chat/chat_usage_tracker.dart';
import 'package:ibukihome/data/ai/ai_provider_client.dart';
import 'package:ibukihome/data/memory/in_memory_chat_controls_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/ai/ai_token_usage.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import '../data/sqlite/sqlite_test_helpers.dart' show metadata;

void main() {
  test(
    'tracks compiled input and visible output, actual usage overrides estimates without double counting',
    () async {
      final repo = await fixture();
      final tracker = ChatUsageTracker(repo);
      final runtime = _Runtime();
      await tracker
          .stream(
            sessionId: 'a',
            operation: 'chat-reply',
            runtime: runtime,
            request: request('one'),
          )
          .toList();
      await tracker
          .stream(
            sessionId: 'a',
            operation: 'chat-reply',
            runtime: runtime,
            request: request('one'),
          )
          .toList();
      final records = await repo.listUsage('a');
      expect(records, hasLength(1));
      final record = records.single;
      expect(record.usage!.inputTokens, 123);
      expect(record.usage!.outputTokens, 45);
      expect(record.estimatedInputTokens, greaterThan(10));
      expect(record.estimatedOutputTokens, greaterThan(0));
      expect(record.model, 'selected-model');
      expect(record.status, 'stop');
      expect(await repo.listUsage('b'), isEmpty);
    },
  );
  test(
    'local validation failures excluded, transport failure counted, memory operations use same ledger',
    () async {
      final repo = await fixture();
      final tracker = ChatUsageTracker(repo);
      await expectLater(
        tracker
            .stream(
              sessionId: 'a',
              operation: 'chat-reply',
              runtime: _Runtime(localFailure: true),
              request: request('local'),
            )
            .toList(),
        throwsStateError,
      );
      expect(await repo.listUsage('a'), isEmpty);
      await expectLater(
        tracker
            .stream(
              sessionId: 'a',
              operation: 'chat-reply-retry',
              runtime: _Runtime(transportFailure: true),
              request: request('network'),
            )
            .toList(),
        throwsStateError,
      );
      expect((await repo.listUsage('a')).single.status, 'failed');
      await tracker.generate(
        sessionId: 'a',
        operation: 'memory-summary',
        runtime: _Runtime(),
        request: request('summary'),
      );
      expect(
        (await repo.listUsage('a')).map((r) => r.operation),
        containsAll(['chat-reply-retry', 'memory-summary']),
      );
    },
  );
}

Future<InMemoryChatControlsRepository> fixture() async {
  final store = InMemoryIbukiStore();
  final chats = InMemoryChatRepository(store);
  for (final id in ['a', 'b']) {
    await chats.upsertSession(
      ChatSession(
        metadata: metadata(id),
        projectId: null,
        characterId: null,
        title: id,
      ),
    );
  }
  return InMemoryChatControlsRepository(store);
}

AiGenerationRequest request(String id) => AiGenerationRequest(
  requestId: id,
  systemPrompt: '人格与会话记忆',
  messages: const [
    AiGenerationMessage(role: AiMessageRole.user, content: '你好，请继续'),
  ],
);

class _Runtime implements AiGenerationRuntime {
  _Runtime({this.localFailure = false, this.transportFailure = false});
  final bool localFailure, transportFailure;
  @override
  Future<AiResolvedProvider> resolveDefault() => throw UnimplementedError();
  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    if (localFailure) throw StateError('no model');
    request.reportTransportStarted('provider', 'selected-model');
    if (transportFailure) throw StateError('network');
    yield '你好';
    request.reportUsage(
      const AiTokenUsage(inputTokens: 123, outputTokens: 45, isFinal: true),
    );
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async {
    request.reportTransportStarted('provider', 'selected-model');
    request.reportUsage(
      const AiTokenUsage(inputTokens: 100, outputTokens: 10, isFinal: true),
    );
    return '摘要';
  }
}
