import 'package:ibukihome/app/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/projects/current_project_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/domain/characters/character_card.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/segments/segment.dart';
import 'package:ibukihome/domain/world/world_card.dart';

void main() {
  testWidgets('primary navigation has three equal top-level targets', (
    tester,
  ) async {
    await _pump(tester);
    final sizes = <Size>[];
    for (final key in _bottomKeys) {
      final finder = find.byKey(key);
      expect(finder, findsOneWidget);
      sizes.add(tester.getSize(finder));
    }
    expect(sizes.map((size) => size.width).toSet(), hasLength(1));
  });

  testWidgets('settings is a primary tab with the bottom navigation', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('bottom-nav-settings')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-page')), findsOneWidget);
    expect(find.byKey(const Key('primary-bottom-navigation')), findsOneWidget);
    expect(find.byKey(const Key('bottom-nav-selected-设置')), findsOneWidget);
  });

  testWidgets('novel can switch directly to chat and settings', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('bottom-nav-chat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-home-page')), findsOneWidget);

    await tester.tap(find.byKey(const Key('bottom-nav-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-page')), findsOneWidget);
  });

  testWidgets('novel opens manuscript without dashboard cards', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('continuous-manuscript-list')), findsOneWidget);
    expect(find.byKey(const Key('app-home-page')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('continuous-manuscript-list')),
        matching: find.byType(Card),
      ),
      findsNothing,
    );
  });

  testWidgets('novel settings tab exposes work management', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('novel-tab-settings')));
    await tester.pumpAndSettle();

    expect(find.text('当前作品'), findsOneWidget);
    expect(find.text('切换作品'), findsOneWidget);
    expect(find.text('创作设定'), findsOneWidget);
  });

  testWidgets('selecting another project returns directly to its manuscript', (
    tester,
  ) async {
    final container = await _pump(tester);
    await tester.tap(find.byKey(const Key('novel-tab-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('切换作品'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project-tile-project-2')));
    await tester.pumpAndSettle();

    expect(container.read(currentProjectControllerProvider), 'project-2');
    expect(find.text('第二部作品的正文'), findsOneWidget);
    expect(find.byKey(const Key('project-overview-page')), findsNothing);
  });

  testWidgets('project selection page has an explicit back control', (
    tester,
  ) async {
    await _pump(tester);
    _go(tester, AppRoutes.projects);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shell-back-button')), findsOneWidget);
  });

  testWidgets('segment menu maps restored desktop AI actions', (tester) async {
    await _pump(tester);
    await _openSegmentMenu(tester);

    for (final text in ['AI 重写这一段', '按要求修改', '选择性修改']) {
      final textFinder = find.text(text);
      expect(textFinder, findsOneWidget);
      final item = tester.widget<PopupMenuItem<dynamic>>(
        find.ancestor(
          of: textFinder,
          matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
        ),
      );
      expect(item.enabled, isTrue);
    }
    final futureInsert = find.text('在后面生成 · AI 接入后开放');
    expect(futureInsert, findsOneWidget);
    expect(
      tester
          .widget<PopupMenuItem<dynamic>>(
            find.ancestor(
              of: futureInsert,
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            ),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets('manual segment operations remain in the paragraph menu', (
    tester,
  ) async {
    await _pump(tester);
    await _openSegmentMenu(tester);
    for (final text in ['手动编辑', '在前面插入', '在后面插入', '上移', '下移', '查看历史', '删除']) {
      expect(find.text(text), findsOneWidget);
    }
  });

  testWidgets('history entered from manuscript has an explicit return', (
    tester,
  ) async {
    await _pump(tester);
    await _openSegmentMenu(tester);
    await tester.ensureVisible(find.text('查看历史'));
    await tester.tap(find.text('查看历史'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('segment-history-page')), findsOneWidget);
    expect(find.byKey(const Key('shell-back-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('shell-back-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('segment-list-page')), findsOneWidget);
  });

  testWidgets(
    'composer presents one primary AI action and secondary manual add',
    (tester) async {
      await _pump(tester);
      final composer = find.byKey(const Key('novel-composer'));
      expect(
        find.descendant(of: composer, matching: find.byType(FilledButton)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: composer, matching: find.byType(OutlinedButton)),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('novel-extra-creation')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: composer, matching: find.byType(OutlinedButton)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('novel-generate-next')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('direction input does not create a segment or fake AI text', (
    tester,
  ) async {
    final container = await _pump(tester);
    final before = await container
        .read(segmentRepositoryProvider)
        .listSegments('project-1');
    final beforeSnapshot = [
      for (final segment in before) (segment.id, segment.content),
    ];
    await tester.enterText(
      find.byKey(const Key('novel-composer-field')),
      '下一段先不要揭露真相',
    );
    await tester.pump();

    final after = await container
        .read(segmentRepositoryProvider)
        .listSegments('project-1');
    expect([
      for (final segment in after) (segment.id, segment.content),
    ], beforeSnapshot);
    expect(find.textContaining('生成的正文'), findsNothing);
  });

  testWidgets('character context selection does not mutate CharacterCard', (
    tester,
  ) async {
    final container = await _pump(tester);
    final before = await container
        .read(characterRepositoryProvider)
        .getCharacter('character-1');
    await tester.tap(find.byKey(const Key('novel-character-context')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-character-character-1')));
    await tester.pump();
    final after = await container
        .read(characterRepositoryProvider)
        .getCharacter('character-1');
    expect(after, before);
  });

  testWidgets('settings uses flat rows rather than setting cards', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('bottom-nav-settings')));
    await tester.pumpAndSettle();
    final page = find.byKey(const Key('settings-page'));
    expect(
      find.descendant(of: page, matching: find.byType(Card)),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-plugins')),
      220,
      scrollable: find.descendant(of: page, matching: find.byType(Scrollable)),
    );
    expect(find.byKey(const Key('settings-plugins')), findsOneWidget);
  });

  testWidgets('character profile and chat show explicit back controls', (
    tester,
  ) async {
    await _pump(tester);
    _go(tester, AppRoutes.chatContact('character-1'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('character-profile-back-button')),
      findsOneWidget,
    );

    _go(tester, AppRoutes.chatSession('session-1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-back-button')), findsOneWidget);
  });

  testWidgets('deep edit routes have a visible shell back button', (
    tester,
  ) async {
    await _pump(tester);
    for (final route in [
      AppRoutes.editSegment('project-1', 'segment-1'),
      AppRoutes.editCharacter('project-1', 'character-1'),
      AppRoutes.editWorldCard('project-1', 'world-1'),
    ]) {
      _go(tester, route);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shell-back-button')), findsOneWidget);
    }
  });

  testWidgets('360 by 800 keeps all four navigation labels readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester);

    for (final label in ['小说', '聊天', '设置']) {
      expect(find.text(label), findsWidgets);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('large system text keeps the three-tab navigation identifiable', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester);
    for (final key in _bottomKeys) {
      expect(find.byKey(key), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}

const _bottomKeys = [
  Key('bottom-nav-novel'),
  Key('bottom-nav-chat'),
  Key('bottom-nav-settings'),
];

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await _seed(container);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const IbukiHomeApp(),
    ),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go(AppRoutes.novelEditor('project-1'));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _seed(ProviderContainer container) async {
  for (final project in [
    Project(
      metadata: _metadata('project-1'),
      title: '长篇测试作品',
      description: '第一部作品',
    ),
    Project(
      metadata: _metadata('project-2'),
      title: '第二部作品',
      description: '用于切换测试',
    ),
  ]) {
    await container.read(projectRepositoryProvider).upsertProject(project);
  }
  await container
      .read(segmentRepositoryProvider)
      .upsertSegment(
        Segment(
          metadata: _metadata('segment-1'),
          projectId: 'project-1',
          orderIndex: 0,
          content: '第一段正文',
        ),
      );
  await container
      .read(segmentRepositoryProvider)
      .upsertSegment(
        Segment(
          metadata: _metadata('segment-2'),
          projectId: 'project-2',
          orderIndex: 0,
          content: '第二部作品的正文',
        ),
      );
  await container
      .read(characterRepositoryProvider)
      .upsertCharacter(
        CharacterCard(
          metadata: _metadata('character-1'),
          projectId: 'project-1',
          name: '伊吹',
          content: '安静但敏锐',
          sortOrder: 0,
        ),
      );
  await container
      .read(chatPersonaRepositoryProvider)
      .upsertPersona(
        ChatPersona(
          metadata: _metadata('character-1'),
          name: '伊吹',
          descriptionMode: ChatPersonaDescriptionMode.simple,
          shortDescription: '安静但敏锐',
          speakingStyle: '自然、简洁',
        ),
      );
  await container
      .read(worldRepositoryProvider)
      .upsertWorldCard(
        WorldCard(
          metadata: _metadata('world-1'),
          projectId: 'project-1',
          title: '蓝色时刻',
          content: '店铺位于城市与旧森林之间',
          sortOrder: 0,
        ),
      );
  await container
      .read(chatRepositoryProvider)
      .upsertSession(
        ChatSession(
          metadata: _metadata('session-1'),
          projectId: null,
          personaId: 'character-1',
          characterId: null,
          title: '伊吹',
        ),
      );
  container
      .read(currentProjectControllerProvider.notifier)
      .selectProject('project-1');
  container.read(dataChangeTickProvider.notifier).bump();
}

EntityMetadata _metadata(String id) {
  final now = DateTime.utc(2026, 8, 10, 8);
  return EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);
}

void _go(WidgetTester tester, String location) {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
}

Future<void> _openSegmentMenu(WidgetTester tester) async {
  final menu = find.byKey(const Key('segment-menu-segment-1'));
  await tester.ensureVisible(menu);
  final dynamic state = tester.state(menu);
  state.showButtonMenu();
  await tester.pumpAndSettle();
}
