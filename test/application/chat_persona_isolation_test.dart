import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/ai/ai_generation_service.dart';
import 'package:ibukihome/application/ai/ai_runtime_providers.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/data/ai/ai_provider_client.dart';
import 'package:ibukihome/domain/ai/ai_default_selection.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_preset_message.dart';

void main() {
  test(
    'chat generation uses only chat data and keeps preset pairs out of history',
    () async {
      final runtime = _Runtime();
      final c = ProviderContainer(
        overrides: [
          aiGenerationServiceProvider.overrideWithValue(runtime),
          projectRepositoryProvider.overrideWith(
            (_) => throw StateError('Novel project accessed'),
          ),
          characterRepositoryProvider.overrideWith(
            (_) => throw StateError('Novel character accessed'),
          ),
          worldRepositoryProvider.overrideWith(
            (_) => throw StateError('Novel world accessed'),
          ),
          novelMemoryRepositoryProvider.overrideWith(
            (_) => throw StateError('Novel memory accessed'),
          ),
        ],
      );
      addTearDown(c.dispose);
      final now = DateTime.utc(2026, 11, 21);
      final persona = await c.read(createChatPersonaProvider)(
        id: 'persona',
        name: '伙伴',
        personaPrompt: '耐心而简洁',
        presetMessages: const [
          ChatPresetMessage(user: '你好', assistant: '晚上好。'),
        ],
        autoMemoryEnabled: false,
        nowUtc: now,
      );
      expect(ChatPersona.fromJson(persona.toJson()), persona);
      final session = await c
          .read(openPersonaChatProvider)
          .createNew(
            personaId: persona.id,
            newSessionId: 'session',
            nowUtc: now,
          );
      expect(session.projectId, isNull);
      expect(session.characterId, isNull);
      await c.read(sendChatMessageProvider)(
        sessionId: session.id,
        messageId: 'user',
        role: ChatMessageRole.user,
        content: '今天如何？',
        nowUtc: now,
      );
      await c
          .read(generateChatReplyProvider)(
            sessionId: session.id,
            userMessageId: 'user',
            requestId: 'request',
            assistantMessageId: 'answer',
            nowUtc: now.add(const Duration(seconds: 1)),
          )
          .toList();
      expect(runtime.requests.single.systemPrompt, contains('耐心而简洁'));
      expect(runtime.requests.single.messages.map((m) => m.content), [
        '你好',
        '晚上好。',
        '今天如何？',
      ]);
      expect(runtime.requests.single.messages.map((m) => m.role), [
        AiMessageRole.user,
        AiMessageRole.assistant,
        AiMessageRole.user,
      ]);
      expect(
        (await c.read(chatRepositoryProvider).listMessages(session.id)).map(
          (m) => m.content,
        ),
        ['今天如何？', '离线回答'],
      );
    },
  );

  test(
    'novel generation does not access chat repositories or memory',
    () async {
      final runtime = _Runtime();
      final c = ProviderContainer(
        overrides: [
          aiGenerationServiceProvider.overrideWithValue(runtime),
          chatRepositoryProvider.overrideWith(
            (_) => throw StateError('Chat session accessed'),
          ),
          chatPersonaRepositoryProvider.overrideWith(
            (_) => throw StateError('Chat persona accessed'),
          ),
          chatMemoryRepositoryProvider.overrideWith(
            (_) => throw StateError('Chat memory accessed'),
          ),
        ],
      );
      addTearDown(c.dispose);
      final now = DateTime.utc(2026, 11, 21);
      await c.read(createProjectProvider)(
        id: 'novel',
        title: '小说作品',
        description: '小说独有背景',
        nowUtc: now,
      );
      await c.read(saveProjectSystemPromptProvider)(
        projectId: 'novel',
        systemPrompt: '小说独有背景',
        nowUtc: now,
      );
      final updates = await c
          .read(generateNextSegmentProvider)(
            projectId: 'novel',
            userInstruction: '继续',
            selectedCharacterIds: {},
            selectedWorldCardIds: {},
            requestId: 'novel-request',
            segmentId: 'segment',
            nowUtc: now,
          )
          .toList();
      expect(updates.last.savedSegment, isNotNull);
      expect(
        runtime.requests.single.systemPrompt +
            runtime.requests.single.messages.map((m) => m.content).join(),
        contains('小说独有背景'),
      );
      expect(
        (await c.read(segmentRepositoryProvider).listSegments('novel'))
            .single
            .content,
        '离线回答',
      );
    },
  );

  test('memory-only changes preserve prompt, examples and avatar', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final now = DateTime.utc(2026, 11, 21);
    final original = await c.read(createChatPersonaProvider)(
      id: 'p',
      name: '名字',
      personaPrompt: '人格',
      avatarReference: 'avatar:mint',
      presetMessages: const [ChatPresetMessage(user: '问', assistant: '答')],
      nowUtc: now,
    );
    final saved = await c.read(saveChatPersonaProvider)(
      personaId: 'p',
      name: original.name,
      autoMemoryEnabled: false,
      nowUtc: now,
    );
    expect(saved.personaPrompt, original.personaPrompt);
    expect(saved.presetMessages, original.presetMessages);
    expect(saved.avatarReference, original.avatarReference);
    expect(saved.autoMemoryEnabled, isFalse);
    final cleared = await c.read(saveChatPersonaProvider)(
      personaId: 'p',
      name: original.name,
      personaPrompt: '',
      presetMessages: [],
      avatarReference: null,
      nowUtc: now,
    );
    expect(cleared.personaPrompt, '');
    expect(cleared.presetMessages, isEmpty);
    expect(cleared.avatarReference, isNull);
  });

  test('half-filled or malformed preset pairs cannot enter the domain', () {
    for (final value in [
      42,
      [true],
      [
        {'user': '问'},
      ],
      [
        {'user': '', 'assistant': '答'},
      ],
    ]) {
      expect(
        () => ChatPresetMessage.parseList(value),
        throwsA(isA<DataFormatException>()),
      );
    }
  });
}

class _Runtime implements AiGenerationRuntime {
  final requests = <AiGenerationRequest>[];
  @override
  Future<AiResolvedProvider> resolveDefault() async => AiResolvedProvider(
    config: AiProviderConfig(
      id: 'mock',
      type: AiProviderType.openai,
      displayName: 'Mock',
      baseUrl: 'https://example.invalid',
      apiKeyRef: 'mock',
      enabled: true,
      selectedModel: 'test',
      availableModels: const ['test'],
      connectionStatus: AiProviderConnectionStatus.untested,
      createdAtUtc: DateTime.utc(2026),
      updatedAtUtc: DateTime.utc(2026),
    ),
    selection: AiDefaultSelection(
      providerId: 'mock',
      modelId: 'test',
      updatedAtUtc: DateTime.utc(2026),
    ),
  );
  @override
  Stream<String> stream(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    requests.add(request);
    yield '离线回答';
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async => '离线记忆';
}
