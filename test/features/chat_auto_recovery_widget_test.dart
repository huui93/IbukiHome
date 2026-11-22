import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/application/ai/ai_model_resolver.dart';
import 'package:ibukihome/application/ai/ai_request_coordinator.dart';
import 'package:ibukihome/application/ai/chat_prompt_builder.dart';
import 'package:ibukihome/application/ai/generate_chat_reply.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/core/network/ai_provider_exceptions.dart';
import 'package:ibukihome/data/ai/ai_provider_client.dart';
import 'package:ibukihome/domain/ai/ai_default_selection.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';

void main() {
  testWidgets(
    'partial EOF automatically continues in application layer and one bubble',
    (tester) async {
      final runtime = _InterruptThenRecoverRuntime();
      final container = ProviderContainer(
        overrides: [
          generateChatReplyProvider.overrideWith((ref) {
            final chats = ref.watch(chatRepositoryProvider);
            return GenerateChatReply(
              chats: chats,
              personas: ref.watch(chatPersonaRepositoryProvider),
              promptBuilder: const ChatPromptBuilder(),
              runtime: runtime,
              coordinator: AiRequestCoordinator(),
              modelResolver: AiModelResolver(
                projects: ref.watch(projectRepositoryProvider),
                chats: chats,
                runtime: runtime,
              ),
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      await _seed(container);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const IbukiHomeApp(),
        ),
      );
      await tester.pumpAndSettle();
      GoRouter.of(
        tester.element(find.byType(Scaffold).first),
      ).go(AppRoutes.chatSession('session'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('chat-input-field')),
        '请继续测试',
      );
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('chat-send-button')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('chat-send-button')));
      await tester.pumpAndSettle();

      final assistants =
          (await container.read(chatRepositoryProvider).listMessages('session'))
              .where((message) => message.role == ChatMessageRole.assistant)
              .toList();
      expect(runtime.streamAttempts, 2);
      expect(runtime.resolveCalls, 2);
      expect(runtime.requests, hasLength(2));
      expect(
        runtime.requests.map((request) => request.providerConfigId),
        everyElement('gemini'),
      );
      expect(
        runtime.requests.map((request) => request.model),
        everyElement('gemini-test'),
      );
      expect(assistants, hasLength(1));
      expect(assistants.single.id, isNotEmpty);
      expect(assistants.single.content, '她缓缓推开门，门后的走廊已经完全陷入黑暗。');
      expect(assistants.single.finishReason, AiFinishReason.stop);
      expect(find.text('回复中断'), findsNothing);
      expect(find.text('正在续接…'), findsNothing);
      expect(find.text(assistants.single.content), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(runtime.requests, hasLength(2));
      expect(
        (await container.read(chatRepositoryProvider).listMessages('session'))
            .where((message) => message.role == ChatMessageRole.assistant),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'second interruption stops automatic recovery and keeps one bubble',
    (tester) async {
      final runtime = _InterruptThenRecoverRuntime(
        recoveryAlsoInterrupts: true,
      );
      final container = ProviderContainer(
        overrides: [
          generateChatReplyProvider.overrideWith((ref) {
            final chats = ref.watch(chatRepositoryProvider);
            return GenerateChatReply(
              chats: chats,
              personas: ref.watch(chatPersonaRepositoryProvider),
              promptBuilder: const ChatPromptBuilder(),
              runtime: runtime,
              coordinator: AiRequestCoordinator(),
              modelResolver: AiModelResolver(
                projects: ref.watch(projectRepositoryProvider),
                chats: chats,
                runtime: runtime,
              ),
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      await _seed(container);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const IbukiHomeApp(),
        ),
      );
      await tester.pumpAndSettle();
      GoRouter.of(
        tester.element(find.byType(Scaffold).first),
      ).go(AppRoutes.chatSession('session'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('chat-input-field')),
        'continue test',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('chat-send-button')));
      await tester.pumpAndSettle();

      final assistants =
          (await container.read(chatRepositoryProvider).listMessages('session'))
              .where((message) => message.role == ChatMessageRole.assistant)
              .toList();
      expect(runtime.streamAttempts, 2);
      expect(runtime.resolveCalls, 2);
      expect(assistants, hasLength(1));
      expect(assistants.single.finishReason, AiFinishReason.interrupted);
      expect(find.text('回复中断 · 继续'), findsOneWidget);
    },
  );
}

Future<void> _seed(ProviderContainer container) async {
  final now = DateTime.utc(2026, 8, 21);
  await container
      .read(projectRepositoryProvider)
      .upsertProject(
        Project(
          metadata: _metadata('project', now),
          title: '测试作品',
          description: '',
        ),
      );
  await container
      .read(chatPersonaRepositoryProvider)
      .upsertPersona(
        ChatPersona(
          metadata: _metadata('persona', now),
          name: '测试角色',
          descriptionMode: ChatPersonaDescriptionMode.simple,
          shortDescription: '自然友好',
          speakingStyle: '简洁',
        ),
      );
  await container
      .read(chatRepositoryProvider)
      .upsertSession(
        ChatSession(
          metadata: _metadata('session', now),
          projectId: null,
          personaId: 'persona',
          title: '测试聊天',
          aiProviderConfigId: 'gemini',
          aiModel: 'gemini-test',
        ),
      );
  container.read(dataChangeTickProvider.notifier).bump();
}

EntityMetadata _metadata(String id, DateTime now) =>
    EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);

class _InterruptThenRecoverRuntime implements AiDetailedGenerationRuntime {
  _InterruptThenRecoverRuntime({this.recoveryAlsoInterrupts = false});

  final bool recoveryAlsoInterrupts;
  var streamAttempts = 0;
  var resolveCalls = 0;
  final requests = <AiGenerationRequest>[];

  @override
  Future<AiResolvedProvider> resolveDefault() =>
      resolveSelection(providerConfigId: 'deepseek', model: 'deepseek-test');

  @override
  Future<AiResolvedProvider> resolveSelection({
    String? providerConfigId,
    String? model,
  }) async {
    resolveCalls += 1;
    final provider = providerConfigId ?? 'deepseek';
    final selectedModel = model ?? 'deepseek-test';
    final now = DateTime.utc(2026, 8, 21);
    return AiResolvedProvider(
      config: AiProviderConfig(
        id: provider,
        type: provider == 'gemini'
            ? AiProviderType.gemini
            : AiProviderType.deepseek,
        displayName: provider,
        baseUrl: 'https://example.test',
        apiKeyRef: 'secure.$provider',
        selectedModel: selectedModel,
        enabled: true,
        connectionStatus: AiProviderConnectionStatus.connected,
        availableModels: [selectedModel],
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
      selection: AiDefaultSelection(
        providerId: provider,
        modelId: selectedModel,
        updatedAtUtc: now,
      ),
    );
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async => '';

  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {}

  @override
  Stream<AiStreamEvent> streamEvents(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    streamAttempts += 1;
    requests.add(request);
    if (streamAttempts == 1) {
      yield const AiStreamEvent.content('她缓缓推开门，门后的走廊已经完全');
      throw const AiProviderInterruptedException(causeType: 'abnormal-eof');
    }
    yield const AiStreamEvent.content('门后的走廊已经完全陷入黑暗。');
    if (recoveryAlsoInterrupts) {
      throw const AiProviderInterruptedException(causeType: 'abnormal-eof');
    }
    yield const AiStreamEvent.finished(AiFinishReason.stop);
  }
}
