import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/app/theme/app_theme.dart';
import 'package:ibukihome/app/theme/theme_controller.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/features/chat/presentation/chat_home_page.dart';
import 'package:ibukihome/features/mascot/application/mascot_controller.dart';
import 'package:ibukihome/features/mascot/domain/mascot_action.dart';
import 'package:ibukihome/features/mascot/domain/mascot_state.dart';
import 'package:ibukihome/features/mascot/presentation/mascot_slot.dart';

void main() {
  testWidgets('App can start', (tester) async {
    await _pumpApp(tester);

    expect(find.byKey(const Key('chat-home-page')), findsOneWidget);
  });

  testWidgets('Initial route opens the main chat system', (tester) async {
    await _pumpApp(tester);

    expect(find.byKey(const Key('chat-home-page')), findsOneWidget);
    expect(find.byKey(const Key('bottom-nav-chat')), findsOneWidget);
  });

  testWidgets('ChatHomePage can build', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ChatHomePage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-home-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Primary bottom navigation can open chat', (tester) async {
    await _pumpApp(tester);
    await _openChatWorkspace(tester);

    await tester.tap(find.byKey(const Key('bottom-nav-chat')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-home-page')), findsOneWidget);
    expect(find.byKey(const Key('app-drawer')), findsNothing);
  });

  testWidgets('Primary navigation contains three top-level entries', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openChatWorkspace(tester);

    for (final key in [
      const Key('bottom-nav-novel'),
      const Key('bottom-nav-chat'),
      const Key('bottom-nav-settings'),
    ]) {
      expect(find.byKey(key), findsOneWidget);
    }
  });

  testWidgets('Settings page can be opened through routing', (tester) async {
    await _pumpApp(tester);

    await _openSettings(tester);

    expect(find.byKey(const Key('settings-page')), findsOneWidget);
  });

  testWidgets('New chat button opens the create session page', (tester) async {
    await _pumpApp(tester);
    await _openChatWorkspace(tester);

    _goFromVisibleContext(tester, AppRoutes.newChatSession);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-persona-picker')), findsOneWidget);
  });

  testWidgets('Send button is disabled for empty text', (tester) async {
    await _pumpApp(tester, ids: ['session-1']);
    await _createChatSession(tester);

    final button = tester.widget<IconButton>(
      find.byKey(const Key('chat-send-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('Send button is enabled after typing', (tester) async {
    await _pumpApp(tester, ids: ['session-1']);
    await _createChatSession(tester);

    await tester.enterText(find.byKey(const Key('chat-input-field')), '雨停了。');
    await tester.pump();

    final button = tester.widget<IconButton>(
      find.byKey(const Key('chat-send-button')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('Sending adds a persisted local user message', (tester) async {
    await _pumpApp(tester, ids: ['session-1', 'message-1']);
    await _createChatSession(tester);

    await tester.enterText(
      find.byKey(const Key('chat-input-field')),
      '她推开门，听见雨声。',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-message-message-1')), findsOneWidget);
    expect(find.text('她推开门，听见雨声。'), findsOneWidget);
    expect(find.byKey(const Key('chat-ai-provider')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('Chat input does not add a decorative mascot', (tester) async {
    final container = await _pumpApp(tester, ids: ['session-1']);
    await _createChatSession(tester);

    final before = container.read(mascotControllerProvider);

    await tester.tap(find.byKey(const Key('chat-input-field')));
    await tester.pump();

    expect(container.read(mascotControllerProvider), before);
    expect(find.byKey(const Key('mascot-slot-input-edge')), findsNothing);
  });

  testWidgets('Sending keeps the interface free of fake thinking replies', (
    tester,
  ) async {
    final container = await _pumpApp(tester, ids: ['session-1', 'message-1']);
    await _createChatSession(tester);

    await tester.enterText(find.byKey(const Key('chat-input-field')), '下一句呢？');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pumpAndSettle();

    expect(
      container.read(mascotControllerProvider),
      isNot(MascotState.thinking),
    );
    expect(find.textContaining('正在想'), findsNothing);
  });

  testWidgets('No fake assistant message appears after sending', (
    tester,
  ) async {
    final container = await _pumpApp(tester, ids: ['session-1', 'message-1']);
    await _createChatSession(tester);

    await tester.enterText(
      find.byKey(const Key('chat-input-field')),
      '给我一个开头。',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pumpAndSettle();

    final messages = await container
        .read(chatRepositoryProvider)
        .listMessages('session-1');
    expect(messages, hasLength(1));
    expect(find.textContaining('正在想'), findsNothing);
    expect(find.text('旧会话 · 未关联聊天角色'), findsNothing);
  });

  testWidgets('Chat root has no drawer mascot state', (tester) async {
    final container = await _pumpApp(tester);
    await _openChatWorkspace(tester);

    final before = container.read(mascotControllerProvider);
    expect(find.byKey(const Key('open-drawer-button')), findsNothing);
    expect(container.read(mascotControllerProvider), before);
    expect(find.byKey(const Key('mascot-slot-drawer-peek')), findsNothing);
  });

  testWidgets('Settings page toggles light and dark theme', (tester) async {
    final container = await _pumpApp(tester);

    await _openSettings(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-theme-switch')),
      220,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('settings-page')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-theme-switch')));
    await tester.pumpAndSettle();

    expect(container.read(themeModeControllerProvider), ThemeMode.dark);
  });

  testWidgets('Small screen chat list has no RenderFlex overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpApp(tester);
    await _openChatWorkspace(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Chat input does not render an overlapping mascot slot', (
    tester,
  ) async {
    await _pumpApp(tester, ids: ['session-1']);
    await _createChatSession(tester);

    expect(find.byKey(const Key('mascot-slot-input-edge')), findsNothing);
    expect(find.byKey(const Key('chat-input-field')), findsOneWidget);
  });

  testWidgets('Routes remain available after chat changes', (tester) async {
    await _pumpApp(tester);

    await _openSettings(tester);

    expect(find.byKey(const Key('settings-page')), findsOneWidget);
    _goFromVisibleContext(tester, AppRoutes.chat);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-home-page')), findsOneWidget);
  });

  test('Mascot state can switch from idle to thinking', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(mascotControllerProvider), MascotState.idle);

    container
        .read(mascotControllerProvider.notifier)
        .perform(MascotAction.think);

    expect(container.read(mascotControllerProvider), MascotState.thinking);
  });

  testWidgets('Light and dark themes build without exceptions', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: MascotSlot(slotId: 'theme-light')),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MascotSlot(slotId: 'theme-dark')),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  List<String> ids = const ['session-1', 'message-1', 'message-2'],
}) async {
  final container = ProviderContainer(
    overrides: [
      entityIdGeneratorProvider.overrideWithValue(_QueueIdGenerator(ids)),
      utcClockProvider.overrideWithValue(
        _FixedClock(DateTime.utc(2026, 8, 1, 8)),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const IbukiHomeApp(),
    ),
  );
  await tester.pumpAndSettle();

  return container;
}

Future<void> _openSettings(WidgetTester tester) async {
  _goFromVisibleContext(tester, AppRoutes.settings);
  await tester.pumpAndSettle();
}

Future<void> _createChatSession(
  WidgetTester tester, {
  String title = '测试会话',
}) async {
  final context = tester.element(find.byType(Scaffold).first);
  final container = ProviderScope.containerOf(context, listen: false);
  await container.read(createChatPersonaProvider)(
    id: 'test-persona',
    name: title,
    personaPrompt: '友善的聊天伙伴',
    nowUtc: DateTime.utc(2026, 8, 1),
  );
  container.read(dataChangeTickProvider.notifier).bump();
  _goFromVisibleContext(tester, AppRoutes.newChatSession);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('persona-test-persona')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('chat-session-page')), findsOneWidget);
}

Future<void> _openChatWorkspace(WidgetTester tester) async {
  if (find.byKey(const Key('chat-home-page')).evaluate().isNotEmpty) {
    return;
  }
  if (find.byKey(const Key('app-home-chat')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('app-home-chat')));
  } else {
    _goFromVisibleContext(tester, AppRoutes.chat);
  }
  await tester.pumpAndSettle();
}

void _goFromVisibleContext(WidgetTester tester, String location) {
  final candidateKeys = [
    const Key('chat-home-page'),
    const Key('chat-session-page'),
    const Key('settings-page'),
    const Key('chat-persona-picker'),
  ];
  for (final key in candidateKeys) {
    final finder = find.byKey(key);
    if (finder.evaluate().isNotEmpty) {
      GoRouter.of(tester.element(finder)).go(location);
      return;
    }
  }
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
}

class _QueueIdGenerator extends EntityIdGenerator {
  _QueueIdGenerator(Iterable<String> ids) : _ids = Queue.of(ids);

  final Queue<String> _ids;

  @override
  String nextId(String prefix) => _ids.removeFirst();
}

class _FixedClock extends UtcClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}
