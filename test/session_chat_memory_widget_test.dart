import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_router.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/domain/chat/chat_memory_entry.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';

void main() {
  testWidgets(
    'settings are grouped by session and switches never change persona or sibling',
    (tester) async {
      final c = await setup(tester);
      c.read(appRouterProvider).go(AppRoutes.chatMemorySettings);
      await tester.pumpAndSettle();
      expect(find.text('会话甲'), findsOneWidget);
      expect(find.text('会话乙'), findsOneWidget);
      await tester.tap(find.byKey(const Key('memory-settings-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session-use-memory-a')));
      await tester.pumpAndSettle();
      final service = c.read(chatMemoryServiceProvider);
      expect((await service.settings('a')).historyEnabled, isFalse);
      expect((await service.settings('b')).historyEnabled, isTrue);
      expect(
        (await c.read(chatPersonaRepositoryProvider).getPersona('p'))
            .useLongTermMemory,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('compression round setting stays in the selected session', (
    tester,
  ) async {
    final c = await setup(tester);
    c.read(appRouterProvider).go(AppRoutes.chatMemorySettings);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('memory-settings-a')));
    await tester.pumpAndSettle();
    final rounds = find.byKey(const Key('memory-compression-rounds-a'));
    await Scrollable.ensureVisible(tester.element(rounds), alignment: .25);
    await tester.pumpAndSettle();
    expect(find.text('每 50 个完整轮次整理一次'), findsOneWidget);
    await tester.tap(rounds);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('memory-compression-rounds-input')),
      '20',
    );
    await tester.tap(find.byKey(const Key('save-memory-compression-rounds')));
    await tester.pumpAndSettle();
    expect(
      (await c.read(chatMemoryServiceProvider).settings('a')).compressionRounds,
      20,
    );
    expect(
      (await c.read(chatMemoryServiceProvider).settings('b')).compressionRounds,
      50,
    );
  });

  testWidgets(
    'manual memory, local search and editable overview fit a small screen and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final c = await setup(tester);
      c.read(appRouterProvider).go(AppRoutes.chatSessionMemory('a'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-chat-memory')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('chat-memory-content')),
        '用户喜欢乌龙茶',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 270);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('save-chat-memory')));
      await tester.tap(find.byKey(const Key('save-chat-memory')));
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(
        (await c.read(chatMemoryRepositoryProvider).listEntriesForSession('a'))
            .single
            .content,
        '用户喜欢乌龙茶',
      );
      expect(
        await c.read(chatMemoryRepositoryProvider).listEntriesForSession('b'),
        isEmpty,
      );
      await tester.ensureVisible(
        find.byKey(const Key('search-session-memory')),
      );
      await tester.enterText(
        find.byKey(const Key('search-session-memory')),
        '乌龙茶',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('本地检索结果（1）'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('edit-memory-overview')));
      await tester.tap(find.byKey(const Key('edit-memory-overview')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('memory-overview-content')),
        '本会话只谈茶',
      );
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await tester.pumpAndSettle();
      expect(
        (await c.read(chatMemoryServiceProvider).settings('a')).overview,
        '本会话只谈茶',
      );
      expect(
        (await c.read(chatMemoryServiceProvider).settings('b')).overview,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reply badge opens persisted local sources and supports suppression',
    (tester) async {
      final c = await setup(tester);
      final service = c.read(chatMemoryServiceProvider);
      final entry = await service.saveManual(
        personaId: 'p',
        sessionId: 'a',
        category: ChatMemoryCategory.preference,
        content: '用户喜欢乌龙茶',
        pinned: false,
        nowUtc: now,
      );
      final chats = c.read(chatRepositoryProvider);
      await chats.appendMessage(
        ChatMessage(
          metadata: meta('user'),
          sessionId: 'a',
          projectId: null,
          role: ChatMessageRole.user,
          content: '喝什么茶',
        ),
      );
      await chats.appendMessage(
        ChatMessage(
          metadata: meta(
            'reply',
          ).copyWith(createdAt: now.add(const Duration(seconds: 1))),
          sessionId: 'a',
          projectId: null,
          role: ChatMessageRole.assistant,
          content: '泡一杯乌龙茶。',
        ),
      );
      final context = await service.loadContext(
        personaId: 'p',
        sessionId: 'a',
        query: '乌龙茶',
      );
      await service.recordUsage('a', 'reply', context);
      c.read(repositoryRevisionsProvider.notifier).bump(const [
        RepositoryDataArea.chatMessages,
      ]);
      c.read(appRouterProvider).go(AppRoutes.chatSession('a'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reply-memory-sources-reply')));
      await tester.pumpAndSettle();
      expect(find.text('用户喜欢乌龙茶'), findsOneWidget);
      await tester.tap(find.text('不再引用此来源'));
      await tester.pumpAndSettle();
      expect(
        (await service.settings('a')).excludedSources,
        contains('saved:${entry.id}'),
      );
      expect(
        (await service.loadContext(
          personaId: 'p',
          sessionId: 'a',
          query: '乌龙茶',
        )).recent,
        isEmpty,
      );
      expect(
        await c.read(chatMemoryRepositoryProvider).listEntriesForSession('a'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'clearing requires an explicit choice and keeps raw chats and sibling memory',
    (tester) async {
      final c = await setup(tester);
      final service = c.read(chatMemoryServiceProvider);
      for (final id in ['a', 'b']) {
        await service.saveManual(
          personaId: 'p',
          sessionId: id,
          category: ChatMemoryCategory.other,
          content: '$id 的记忆',
          pinned: false,
          nowUtc: now,
        );
      }
      c.read(appRouterProvider).go(AppRoutes.chatSessionMemory('a'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('clear-session-memory')));
      await tester.tap(find.byKey(const Key('clear-session-memory')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(
        await c.read(chatMemoryRepositoryProvider).listEntriesForSession('a'),
        hasLength(1),
      );
      await tester.tap(find.byKey(const Key('clear-session-memory')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '清空并关闭'));
      await tester.pumpAndSettle();
      expect(
        await c.read(chatMemoryRepositoryProvider).listEntriesForSession('a'),
        isEmpty,
      );
      expect(
        await c.read(chatMemoryRepositoryProvider).listEntriesForSession('b'),
        hasLength(1),
      );
      expect((await service.settings('a')).savedEnabled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

final now = DateTime.utc(2026, 11, 21);
EntityMetadata meta(String id) =>
    EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);
Future<ProviderContainer> setup(WidgetTester tester) async {
  final c = ProviderContainer(
    overrides: [
      aiSecureValueStoreProvider.overrideWithValue(InMemorySecureValueStore()),
    ],
  );
  addTearDown(c.dispose);
  await c
      .read(chatPersonaRepositoryProvider)
      .upsertPersona(
        ChatPersona(
          metadata: meta('p'),
          name: '相同人格',
          descriptionMode: ChatPersonaDescriptionMode.simple,
          shortDescription: '',
          speakingStyle: '',
        ),
      );
  for (final id in ['a', 'b']) {
    await c
        .read(chatRepositoryProvider)
        .upsertSession(
          ChatSession(
            metadata: meta(id),
            personaId: 'p',
            projectId: null,
            title: id == 'a' ? '会话甲' : '会话乙',
          ),
        );
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(container: c, child: const IbukiHomeApp()),
  );
  await tester.pumpAndSettle();
  return c;
}
