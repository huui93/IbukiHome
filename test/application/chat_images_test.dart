import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/application/ai/ai_model_resolver.dart';
import 'package:ibukihome/application/ai/ai_request_coordinator.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/ai/chat_prompt_builder.dart';
import 'package:ibukihome/application/ai/generate_chat_reply.dart';
import 'package:ibukihome/application/chat/chat_vision_preferences.dart';
import 'package:ibukihome/application/chat/recognize_chat_image.dart';
import 'package:ibukihome/application/chat/send_chat_message.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/memory/chat_memory_service.dart';
import 'package:ibukihome/core/network/ai_provider_exceptions.dart';
import 'package:ibukihome/data/ai/ai_provider_client.dart';
import 'package:ibukihome/data/memory/in_memory_chat_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_persona_repository.dart';
import 'package:ibukihome/data/memory/in_memory_chat_memory_repository.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/domain/ai/ai_default_selection.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/chat/chat_image.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import '../helpers/chat_image_fixture.dart';
import '../data/ai/provider_expansion_test.dart' as fixtures;
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';

final now = DateTime.utc(2026, 11, 22);
EntityMetadata meta(String id) =>
    EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);

void main() {
  test(
    'image-only messages persist, caption routes to current chat model once and regeneration reuses it',
    () async {
      final f = ImageFixture();
      await f.init();
      await f.reply();
      final requests = f.runtime.requests;
      expect(requests.length, 2);
      expect(requests[0].model, 'current-chat-model');
      expect(
        requests[0].messages.single.images.single.base64Data,
        imageFixtureBase64,
      );
      expect(requests[1].messages.single.content, contains('ORBIT-73'));
      expect(requests[1].messages.every((m) => m.images.isEmpty), isTrue);
      final saved = await f.chats.getMessage('u');
      expect(saved.image!.description, contains('ORBIT-73'));
      expect(saved.image!.userText, '');
      expect(saved.revision, 2);
      await f.reply(regenerate: true);
      expect(
        requests
            .where((r) => r.messages.any((m) => m.images.isNotEmpty))
            .length,
        1,
      );
    },
  );
  test(
    'separate vision model does not change the session reply model',
    () async {
      final f = ImageFixture(
        override: AiDefaultSelection(
          providerId: 'vision-only',
          modelId: 'separate-vision',
          updatedAtUtc: now,
        ),
      );
      await f.init();
      await f.reply();
      expect(f.runtime.requests[0].providerConfigId, 'vision-only');
      expect(f.runtime.requests[0].model, 'separate-vision');
      expect(f.runtime.requests[1].providerConfigId, 'current');
      expect(f.runtime.requests[1].model, 'current-chat-model');
    },
  );
  test(
    'vision failure and cancellation preserve pending image and never manufacture a reply or caption',
    () async {
      for (final cancel in [false, true]) {
        final f = ImageFixture();
        await f.init();
        f.runtime.failVision = !cancel;
        f.runtime.cancelVision = cancel;
        await expectLater(f.reply(), throwsA(isA<AiProviderException>()));
        final messages = await f.chats.listMessages('a');
        expect(messages.length, 1);
        expect(messages.single.image!.needsRecognition, isTrue);
        f.runtime.failVision = false;
        f.runtime.cancelVision = false;
        await f.reply();
        expect(
          (await f.chats.listMessages('a')).last.role,
          ChatMessageRole.assistant,
        );
      }
    },
  );
  test(
    'truncated recognition and changed last message cannot commit visual memory',
    () async {
      final f = ImageFixture();
      await f.init();
      f.runtime.visionFinish = AiFinishReason.length;
      await expectLater(
        f.reply(),
        throwsA(isA<AiProviderValidationException>()),
      );
      expect((await f.chats.getMessage('u')).image!.description, isNull);
      f.runtime.visionFinish = AiFinishReason.stop;
      f.runtime.beforeVisionEnd = () async {
        await SendChatMessage(f.chats)(
          sessionId: 'a',
          messageId: 'newer',
          role: ChatMessageRole.user,
          content: '另一句话',
          nowUtc: now.add(const Duration(seconds: 2)),
        );
      };
      await expectLater(f.reply(), throwsException);
      expect((await f.chats.getMessage('u')).image!.description, isNull);
    },
  );
  test(
    'image observations are searchable and organized locally only within the originating session',
    () async {
      final f = ImageFixture();
      await f.init();
      await f.reply();
      expect((await f.memory.search('a', 'ORBIT-73')).isNotEmpty, isTrue);
      expect(await f.memory.search('b', 'ORBIT-73'), isEmpty);
      await f.memory.organize('a', force: true);
      final entries = await f.memories.listEntriesForSession('a');
      expect(entries.single.content, contains('ORBIT-73'));
      expect(entries.single.sessionId, 'a');
      expect(await f.memories.listEntriesForSession('b'), isEmpty);
      expect(
        f.runtime.requests
            .where((r) => r.requestId.contains('memory'))
            .every((r) => r.messages.every((m) => m.images.isEmpty)),
        isTrue,
      );
      final ai = (await f.chats.listMessages('a')).last;
      await f.chats.mutateLatestMessage(
        expected: ai,
        nowUtc: now.add(const Duration(seconds: 5)),
      );
      await f.chats.mutateLatestMessage(
        expected: await f.chats.getMessage('u'),
        nowUtc: now.add(const Duration(seconds: 6)),
      );
      expect(await f.memory.search('a', 'ORBIT-73'), isEmpty);
    },
  );
  test('invalid image data is rejected before storage', () {
    expect(
      () =>
          ChatImage(base64Data: 'invalid', mimeType: 'image/png', userText: ''),
      throwsFormatException,
    );
    expect(
      () => ChatImage(
        base64Data: imageFixtureBase64,
        mimeType: 'image/svg+xml',
        userText: '',
      ),
      throwsFormatException,
    );
    expect(() => imageFixture(description: ' '), throwsFormatException);
  });
  test(
    'vision model preference survives a new container and resetting follows chat without changing defaults',
    () async {
      final store = InMemorySecureValueStore();
      var container = ProviderContainer(
        overrides: [aiSecureValueStoreProvider.overrideWithValue(store)],
      );
      expect(
        await container.read(chatVisionPreferencesProvider.future),
        isNull,
      );
      await container
          .read(chatVisionPreferencesProvider.notifier)
          .setSelection(
            AiDefaultSelection(
              providerId: 'v',
              modelId: 'vision',
              updatedAtUtc: now,
            ),
          );
      container.dispose();
      container = ProviderContainer(
        overrides: [aiSecureValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      expect(
        (await container.read(chatVisionPreferencesProvider.future))!.modelId,
        'vision',
      );
      await container
          .read(chatVisionPreferencesProvider.notifier)
          .setSelection(null);
      expect(
        await container.read(chatVisionPreferencesProvider.future),
        isNull,
      );
    },
  );
}

class ImageFixture {
  ImageFixture({this.override}) {
    chats = InMemoryChatRepository(store);
    personas = InMemoryChatPersonaRepository(store);
    memories = InMemoryChatMemoryRepository(store);
    resolver = AiModelResolver(chats: chats, runtime: runtime);
    memory = ChatMemoryService(
      memories: memories,
      chats: chats,
      personas: personas,
      runtime: runtime,
      ids: EntityIdGenerator(),
    );
    generator = GenerateChatReply(
      chats: chats,
      personas: personas,
      promptBuilder: const ChatPromptBuilder(),
      runtime: runtime,
      coordinator: AiRequestCoordinator(),
      modelResolver: resolver,
      imageRecognizer: RecognizeChatImage(
        chats: chats,
        runtime: runtime,
        modelResolver: resolver,
        selection: () async => override,
      ),
    );
  }
  final AiDefaultSelection? override;
  final store = InMemoryIbukiStore();
  final runtime = ImageRuntime();
  late final InMemoryChatRepository chats;
  late final InMemoryChatPersonaRepository personas;
  late final InMemoryChatMemoryRepository memories;
  late final AiModelResolver resolver;
  late final ChatMemoryService memory;
  late final GenerateChatReply generator;
  Future<void> init() async {
    await personas.upsertPersona(
      ChatPersona(
        metadata: meta('p'),
        name: '人格',
        descriptionMode: ChatPersonaDescriptionMode.simple,
        shortDescription: '',
        speakingStyle: '',
        personaPrompt: '友好',
      ),
    );
    for (final id in ['a', 'b']) {
      await chats.upsertSession(
        ChatSession(
          metadata: meta(id),
          projectId: null,
          personaId: 'p',
          title: id,
          aiProviderConfigId: 'current',
          aiModel: 'current-chat-model',
        ),
      );
    }
    await SendChatMessage(chats)(
      sessionId: 'a',
      messageId: 'u',
      role: ChatMessageRole.user,
      content: '',
      image: imageFixture(),
      nowUtc: now,
    );
  }

  Future<void> reply({bool regenerate = false}) => generator(
    sessionId: 'a',
    userMessageId: 'u',
    requestId: regenerate ? 'regen' : 'reply',
    assistantMessageId: 'ai',
    nowUtc: now.add(const Duration(seconds: 1)),
    regenerateMessageId: regenerate ? 'ai' : null,
  ).drain<void>();
}

class ImageRuntime implements AiDetailedGenerationRuntime {
  final requests = <AiGenerationRequest>[];
  bool failVision = false;
  bool cancelVision = false;
  AiFinishReason visionFinish = AiFinishReason.stop;
  Future<void> Function()? beforeVisionEnd;
  @override
  Future<AiResolvedProvider> resolveDefault() => resolveSelection(
    providerConfigId: 'current',
    model: 'current-chat-model',
  );
  @override
  Future<AiResolvedProvider> resolveSelection({
    String? providerConfigId,
    String? model,
  }) async => AiResolvedProvider(
    config: AiProviderConfig.fromJson({
      ...fixtures.config(AiProviderType.gemini).toJson(),
      'id': providerConfigId ?? 'current',
    }),
    selection: AiDefaultSelection(
      providerId: providerConfigId ?? 'current',
      modelId: model ?? 'current-chat-model',
      updatedAtUtc: now,
    ),
  );
  @override
  Stream<AiStreamEvent> streamEvents(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    requests.add(request);
    if (request.messages.any((m) => m.images.isNotEmpty)) {
      if (failVision) throw const AiProviderModelUnavailableException();
      if (cancelVision) {
        cancellation?.cancel();
        throw const AiProviderCancelledException();
      }
      yield const AiStreamEvent.content('图片中有一个蓝色杯子，标签写着 ORBIT-73。');
      await beforeVisionEnd?.call();
      yield AiStreamEvent.finished(visionFinish);
    } else {
      yield const AiStreamEvent.content('我看到蓝色杯子。');
      yield const AiStreamEvent.finished(AiFinishReason.stop);
    }
  }

  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    await for (final e in streamEvents(request, cancellation: cancellation)) {
      if (!e.isTerminal) yield e.content;
    }
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async {
    requests.add(request);
    return request.requestId.contains('extract')
        ? '[{"category":"sharedEvent","content":"用户发送的图片中，模型观察到蓝色杯子，标签为 ORBIT-73。"}]'
        : '用户发送一张图片，模型观察到蓝色杯子和 ORBIT-73 标签。';
  }
}
