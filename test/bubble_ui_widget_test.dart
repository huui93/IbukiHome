import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_router.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/app/theme/app_theme.dart';
import 'package:ibukihome/app/theme/bubble_theme.dart';
import 'package:ibukihome/app/theme/theme_controller.dart';
import 'package:ibukihome/app/widgets/ibuki_glass_surface.dart';
import 'package:ibukihome/application/projects/current_project_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/segments/segment.dart';
import 'package:ibukihome/domain/world/world_card.dart';

void main() {
  group('Bubble tokens', () {
    test('light Bubble palette remains readable', () {
      final theme = AppTheme.light();
      final bubble = theme.extension<BubbleTheme>()!;
      expect(bubble.backgroundMiddle.computeLuminance(), greaterThan(0.9));
      expect(
        theme.colorScheme.onSurface.computeLuminance(),
        lessThan(bubble.backgroundMiddle.computeLuminance()),
      );
    });

    test('dark Bubble palette is soft rather than pure black', () {
      final bubble = AppTheme.dark().extension<BubbleTheme>()!;
      expect(bubble.backgroundMiddle, isNot(Colors.black));
      expect(bubble.backgroundMiddle.computeLuminance(), greaterThan(0));
    });

    test('reading glass is more opaque than decorative glass', () {
      final bubble = AppTheme.light().extension<BubbleTheme>()!;
      expect(bubble.glassStrong.a, greaterThan(bubble.glass.a));
    });

    test('incoming and outgoing message colors remain distinct', () {
      final bubble = AppTheme.light().extension<BubbleTheme>()!;
      expect(bubble.messageIncoming, isNot(bubble.messageOutgoingStart));
    });
  });

  testWidgets('bottom navigation is a blurred Bubble surface', (tester) async {
    await _pumpApp(tester);
    final navigation = find.byKey(const Key('primary-bottom-navigation'));
    expect(navigation, findsOneWidget);
    expect(
      find.descendant(of: navigation, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    expect(find.byKey(const Key('bottom-nav-selected-小说')), findsOneWidget);
  });

  testWidgets('chat identity bar uses a glass blur', (tester) async {
    final container = await _pumpApp(tester);
    container.read(appRouterProvider).go(AppRoutes.chat);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
  });

  testWidgets('novel uses one continuous reading glass surface', (
    tester,
  ) async {
    await _pumpApp(tester, seed: true);
    final surface = find.byKey(const Key('novel-reading-glass-surface'));
    expect(surface, findsOneWidget);
    expect(
      find.descendant(of: surface, matching: find.byType(IbukiGlassSurface)),
      findsNothing,
    );
    expect(
      find.byKey(const Key('continuous-segment-segment-1')),
      findsOneWidget,
    );
  });

  testWidgets('novel composer is glass, fixed, and SafeArea protected', (
    tester,
  ) async {
    await _pumpApp(tester, seed: true);
    final composer = find.byKey(const Key('novel-composer'));
    expect(
      find.descendant(of: composer, matching: find.byType(SafeArea)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: composer, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    expect(tester.getSize(composer).height, lessThan(230));
    expect(
      tester.getBottomLeft(composer).dy,
      greaterThan(
        tester.view.physicalSize.height / tester.view.devicePixelRatio - 180,
      ),
    );
  });

  testWidgets(
    'chat home shows conversations without messages or contacts tabs',
    (tester) async {
      final container = await _pumpApp(tester, seed: true);
      container.read(appRouterProvider).go(AppRoutes.chat);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-home-tabs')), findsNothing);
      expect(find.text('消息'), findsNothing);
      expect(find.text('联系人'), findsNothing);
    },
  );

  testWidgets('message entries use light glass cards', (tester) async {
    final container = await _pumpApp(tester, seed: true);
    container.read(appRouterProvider).go(AppRoutes.chat);
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('conversation-session-1'));
    expect(entry, findsOneWidget);
    expect(tester.widget(entry), isA<IbukiGlassSurface>());
  });

  testWidgets('chat composer is one Bubble surface with SafeArea', (
    tester,
  ) async {
    final container = await _pumpApp(tester, seed: true);
    container.read(appRouterProvider).go(AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();
    final composer = find.byKey(const Key('chat-bubble-composer'));
    expect(composer, findsOneWidget);
    expect(
      find.ancestor(of: composer, matching: find.byType(SafeArea)),
      findsOneWidget,
    );
  });

  testWidgets('assistant stays left and user stays right', (tester) async {
    final container = await _pumpApp(tester, seed: true);
    container.read(appRouterProvider).go(AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();
    final assistant = tester.widget<Row>(
      find.byKey(const Key('chat-message-message-assistant')),
    );
    final user = tester.widget<Row>(
      find.byKey(const Key('chat-message-message-user')),
    );
    expect(assistant.mainAxisAlignment, MainAxisAlignment.start);
    expect(user.mainAxisAlignment, MainAxisAlignment.end);
  });

  testWidgets('contacts are ChatPersona cards', (tester) async {
    final container = await _pumpApp(tester, seed: true);
    container.read(appRouterProvider).go(AppRoutes.chat);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-add-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu-session')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contact-persona-1')), findsOneWidget);
    expect(find.byKey(const Key('persona-persona-1')), findsOneWidget);
  });

  testWidgets('novel CharacterCard does not become a contact automatically', (
    tester,
  ) async {
    final container = await _pumpApp(tester, seed: true);
    container.read(appRouterProvider).go(AppRoutes.chat);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-add-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu-session')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contact-character-1')), findsNothing);
  });

  testWidgets('simple persona editor shows only basic fields', (tester) async {
    final container = await _pumpApp(tester, seed: true);
    container.read(appRouterProvider).go(AppRoutes.newChatPersona);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-persona-editor')), findsOneWidget);
    expect(find.text('人格提示词'), findsOneWidget);
    expect(find.text('说话方式'), findsNothing);
    expect(find.byKey(const Key('persona-detailed-fields')), findsNothing);
  });

  testWidgets('preset messages are collapsed until opened', (tester) async {
    final container = await _pumpApp(tester, seed: true);
    container.read(appRouterProvider).go(AppRoutes.newChatPersona);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-persona-example')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const Key('persona-examples-section')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('语料库（选填）'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-persona-example')), findsOneWidget);
  });

  testWidgets('old detailed content is merged into one editable prompt', (
    tester,
  ) async {
    final container = await _pumpApp(tester, seed: true);
    final repository = container.read(chatPersonaRepositoryProvider);
    final persona = await repository.getPersona('persona-1');
    await repository.upsertPersona(
      persona.copyWith(background: '雨夜的旧公寓', personality: '温和'),
    );
    container.read(dataChangeTickProvider.notifier).bump();
    container
        .read(appRouterProvider)
        .go(AppRoutes.editChatPersona('persona-1'));
    await tester.pumpAndSettle();
    final text = tester
        .widget<TextField>(find.byKey(const Key('persona-prompt-field')))
        .controller!
        .text;
    expect(text, contains('雨夜的旧公寓'));
    expect(text, contains('温和'));
    expect(find.byKey(const Key('persona-description-mode')), findsNothing);
  });

  testWidgets('Persona profile uses grouped glass content', (tester) async {
    final container = await _pumpApp(tester, seed: true);
    container.read(appRouterProvider).go(AppRoutes.chatPersona('persona-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-persona-profile')), findsOneWidget);
    expect(find.textContaining('安静又亲近，会轻轻吐槽。'), findsWidgets);
    expect(find.byType(IbukiGlassSurface), findsWidgets);
  });

  testWidgets(
    'retired novel import route redirects to independent persona editor',
    (tester) async {
      final container = await _pumpApp(tester, seed: true);
      container.read(appRouterProvider).go(AppRoutes.importChatPersona);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('persona-name-field')), findsOneWidget);
      expect(find.text('小说里的伊吹'), findsNothing);
      expect(
        find.byKey(const Key('copy-novel-character-persona')),
        findsNothing,
      );
    },
  );

  testWidgets('deleted Persona can be restored without deleting sessions', (
    tester,
  ) async {
    final container = await _pumpApp(tester, seed: true, deletedPersona: true);
    container.read(appRouterProvider).go(AppRoutes.deletedChatPersonas);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('deleted-persona-persona-deleted')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('restore-persona-persona-deleted')));
    await tester.pumpAndSettle();
    final restored = await container
        .read(chatPersonaRepositoryProvider)
        .getPersona('persona-deleted');
    expect(restored.deletedAt, isNull);
  });

  testWidgets('settings groups rows into glass sections', (tester) async {
    final container = await _pumpApp(tester);
    container.read(appRouterProvider).go(AppRoutes.settings);
    await tester.pumpAndSettle();
    for (final title in ['AI 与模型', '外观', '扩展']) {
      await tester.scrollUntilVisible(
        find.byKey(Key('settings-glass-$title')),
        240,
        scrollable: find.descendant(
          of: find.byKey(const Key('settings-page')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.byKey(Key('settings-glass-$title')), findsOneWidget);
    }
    expect(find.byKey(const Key('settings-glass-连接')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-glass-数据与备份')),
      240,
      scrollable: find.descendant(
        of: find.byKey(const Key('settings-page')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-glass-数据与备份')), findsOneWidget);
  });

  testWidgets('Bubble screens build in dark mode', (tester) async {
    final container = await _pumpApp(tester, seed: true, dark: true);
    for (final route in [AppRoutes.novel, AppRoutes.chat, AppRoutes.settings]) {
      container.read(appRouterProvider).go(route);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('360 by 800 novel and chat remain overflow free', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = await _pumpApp(tester, seed: true);
    for (final route in [AppRoutes.novel, AppRoutes.chat]) {
      container.read(appRouterProvider).go(route);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('large text keeps Bubble navigation identifiable', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpApp(tester, seed: true);
    for (final label in ['小说', '聊天', '设置']) {
      expect(find.text(label), findsWidgets);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('long Persona names ellipsize without overflow', (tester) async {
    final container = await _pumpApp(tester, seed: true, longPersona: true);
    container.read(appRouterProvider).go(AppRoutes.chat);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-add-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu-session')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contact-persona-long')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fifty Persona contacts scroll without rebuilding repositories', (
    tester,
  ) async {
    final container = await _pumpApp(tester, seed: true, manyPersonas: true);
    final repository = container.read(chatPersonaRepositoryProvider);
    container.read(appRouterProvider).go(AppRoutes.chat);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-add-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu-session')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('chat-persona-list')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(container.read(chatPersonaRepositoryProvider), same(repository));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long novel scroll keeps composer mounted', (tester) async {
    final container = await _pumpApp(tester, seed: true, manySegments: true);
    container.read(appRouterProvider).go(AppRoutes.novelEditor('project-1'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('continuous-manuscript-list')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deep Persona page has an explicit back path', (tester) async {
    final container = await _pumpApp(tester, seed: true);
    container.read(appRouterProvider).go(AppRoutes.chatPersona('persona-1'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('persona-profile-back-button')),
      findsOneWidget,
    );
  });

  testWidgets('AI provider route keeps its Bubble background in light mode', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    container.read(appRouterProvider).go(AppRoutes.aiProviders);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bubble-background')), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(
      find.byKey(const Key('secondary-page-shell')),
    );
    expect(scaffold.backgroundColor, isNot(Colors.transparent));
  });

  testWidgets('AI provider route keeps its Bubble background in dark mode', (
    tester,
  ) async {
    final container = await _pumpApp(tester, dark: true);
    container.read(appRouterProvider).go(AppRoutes.aiProviders);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bubble-background')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  bool dark = false,
  bool seed = false,
  bool deletedPersona = false,
  bool longPersona = false,
  bool manyPersonas = false,
  bool manySegments = false,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  if (dark) {
    container.read(themeModeControllerProvider.notifier).setDarkMode(true);
  }
  if (seed) {
    await _seed(
      container,
      deletedPersona: deletedPersona,
      longPersona: longPersona,
      manyPersonas: manyPersonas,
      manySegments: manySegments,
    );
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const IbukiHomeApp(),
    ),
  );
  await tester.pumpAndSettle();
  container
      .read(appRouterProvider)
      .go(seed ? AppRoutes.novelEditor('project-1') : AppRoutes.novel);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _seed(
  ProviderContainer container, {
  required bool deletedPersona,
  required bool longPersona,
  required bool manyPersonas,
  required bool manySegments,
}) async {
  await container
      .read(projectRepositoryProvider)
      .upsertProject(
        Project(
          metadata: _metadata('project-1'),
          title: '测试作品',
          description: '',
        ),
      );
  await container
      .read(characterRepositoryProvider)
      .upsertCharacter(
        CharacterCard(
          metadata: _metadata('character-1'),
          projectId: 'project-1',
          name: '小说里的伊吹',
          content: '只属于小说的角色设定',
          sortOrder: 0,
        ),
      );
  await container
      .read(worldRepositoryProvider)
      .upsertWorldCard(
        WorldCard(
          metadata: _metadata('world-1'),
          projectId: 'project-1',
          title: '雨夜街道',
          content: '旧公寓在街道尽头。',
          sortOrder: 0,
        ),
      );
  final segmentCount = manySegments ? 80 : 2;
  for (var index = 0; index < segmentCount; index += 1) {
    await container
        .read(segmentRepositoryProvider)
        .upsertSegment(
          Segment(
            metadata: _metadata('segment-${index + 1}'),
            projectId: 'project-1',
            orderIndex: index,
            content: '第 ${index + 1} 段测试正文，保持连续阅读与足够的行距。',
          ),
        );
  }
  await container
      .read(chatPersonaRepositoryProvider)
      .upsertPersona(
        ChatPersona(
          metadata: _metadata('persona-1'),
          name: '小铃',
          avatarReference: 'pink',
          descriptionMode: ChatPersonaDescriptionMode.simple,
          shortDescription: '安静又亲近，会轻轻吐槽。',
          speakingStyle: '短句、自然、不正式。',
        ),
      );
  if (deletedPersona) {
    await container
        .read(chatPersonaRepositoryProvider)
        .upsertPersona(
          ChatPersona(
            metadata: _metadata('persona-deleted').copyWith(deletedAt: _t2),
            name: '待恢复角色',
            descriptionMode: ChatPersonaDescriptionMode.simple,
            shortDescription: '仍保留历史会话。',
            speakingStyle: '自然。',
          ),
        );
  }
  if (longPersona) {
    await container
        .read(chatPersonaRepositoryProvider)
        .upsertPersona(
          ChatPersona(
            metadata: _metadata('persona-long'),
            name: '这是一个非常非常长但仍然不应该撑破联系人卡片和聊天顶部栏的角色名称',
            descriptionMode: ChatPersonaDescriptionMode.simple,
            shortDescription: '很长的角色描述也应该正常省略而不发生布局溢出。' * 4,
            speakingStyle: '自然。',
          ),
        );
  }
  if (manyPersonas) {
    for (var index = 0; index < 50; index += 1) {
      await container
          .read(chatPersonaRepositoryProvider)
          .upsertPersona(
            ChatPersona(
              metadata: _metadata('persona-many-$index'),
              name: '测试联系人 ${index + 1}',
              descriptionMode: index.isEven
                  ? ChatPersonaDescriptionMode.simple
                  : ChatPersonaDescriptionMode.detailed,
              shortDescription: '用于长列表滚动验证',
              speakingStyle: '自然。',
              personality: index.isOdd ? '沉稳' : '',
            ),
          );
    }
  }
  await container
      .read(chatRepositoryProvider)
      .upsertSession(
        ChatSession(
          metadata: _metadata('session-1'),
          projectId: null,
          personaId: 'persona-1',
          title: '小铃',
        ),
      );
  for (final message in [
    ChatMessage(
      metadata: _metadata('message-assistant'),
      sessionId: 'session-1',
      projectId: null,
      role: ChatMessageRole.assistant,
      content: '你回来啦？',
    ),
    ChatMessage(
      metadata: _metadata('message-user').copyWith(updatedAt: _t2),
      sessionId: 'session-1',
      projectId: null,
      role: ChatMessageRole.user,
      content: '嗯，刚刚回来。',
    ),
  ]) {
    await container.read(chatRepositoryProvider).appendMessage(message);
  }
  container
      .read(currentProjectControllerProvider.notifier)
      .selectProject('project-1');
  container.read(dataChangeTickProvider.notifier).bump();
}

EntityMetadata _metadata(String id) =>
    EntityMetadata(id: id, createdAt: _t1, updatedAt: _t1, revision: 1);

final _t1 = DateTime.utc(2026, 8, 11, 8);
final _t2 = DateTime.utc(2026, 8, 11, 9);
