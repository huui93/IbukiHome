import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_router.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/app/theme/theme_controller.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/projects/current_project_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/segments/segment.dart';

void main() {
  testWidgets(
    'bookshelf load failure remains distinct from empty state and retries',
    (tester) async {
      var calls = 0;
      final c = ProviderContainer(
        overrides: [
          aiSecureValueStoreProvider.overrideWithValue(
            InMemorySecureValueStore(),
          ),
          projectListProvider.overrideWith((ref) async {
            if (++calls == 1) throw StateError('读取失败');
            return <Project>[];
          }),
        ],
      );
      addTearDown(c.dispose);
      c.read(appRouterProvider).go(AppRoutes.novel);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const IbukiHomeApp()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('project-flow-error-view')), findsOneWidget);
      expect(find.text('还没有创作的作品'), findsNothing);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('还没有创作的作品'), findsOneWidget);
    },
  );
  testWidgets(
    'a deleted current work cannot leave an editable creation or settings page',
    (tester) async {
      final c = await pumpNovel(tester, projects: 1, current: 'p1');
      await tab(tester, 'creation');
      await openWork(tester, 'p1');
      await c.read(projectRepositoryProvider).softDeleteProject('p1', now);
      c.read(repositoryRevisionsProvider.notifier).bump(const [
        RepositoryDataArea.projects,
      ]);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('novel-composer-field')), findsNothing);
      expect(find.text('作品已删除，返回创作列表'), findsOneWidget);
      await tab(tester, 'settings');
      expect(find.text('作品已删除，返回书架'), findsOneWidget);
      await tester.tap(find.text('作品已删除，返回书架'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('empty-novel-bookshelf')), findsOneWidget);
    },
  );
  testWidgets(
    'novel opens an empty bookshelf with only its message and three text tabs',
    (tester) async {
      final c = await pumpNovel(tester);
      expect(find.text('还没有创作的作品'), findsOneWidget);
      expect(find.byKey(const Key('empty-novel-bookshelf')), findsOneWidget);
      expect(find.byKey(const Key('novel-switch-project')), findsNothing);
      expect(find.byKey(const Key('novel-new-project')), findsNothing);
      expect(find.byKey(const Key('new-project-button')), findsNothing);
      for (final name in ['bookshelf', 'creation', 'settings']) {
        expect(find.byKey(Key('novel-tab-$name')), findsOneWidget);
      }
      expect(
        selectedColor(tester, 'bookshelf'),
        Theme.of(
          tester.element(find.byKey(const Key('novel-tab-bookshelf'))),
        ).colorScheme.primary,
      );
      expect(
        selectedColor(tester, 'creation'),
        isNot(selectedColor(tester, 'bookshelf')),
      );
      expect(
        c.read(appRouterProvider).routeInformationProvider.value.uri.toString(),
        AppRoutes.novel,
      );
    },
  );
  testWidgets(
    'a previously selected work does not bypass the default bookshelf',
    (tester) async {
      await pumpNovel(tester, projects: 1, current: 'p1');
      expect(
        find.byKey(const PageStorageKey('novel-bookshelf-page')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('project-tile-p1')), findsOneWidget);
      expect(find.byKey(const Key('segment-list-page')), findsNothing);
    },
  );
  testWidgets(
    'bookshelf opens reading without changing the writing selection',
    (tester) async {
      final c = await pumpNovel(tester, projects: 2, current: 'p1');
      await openWork(tester, 'p2');
      expect(c.read(currentProjectControllerProvider), 'p1');
      expect(find.byKey(const Key('novel-reader-page')), findsOneWidget);
      expect(find.text('这部作品还没有正文。'), findsOneWidget);
      expect(find.byKey(const Key('novel-composer-field')), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const PageStorageKey('novel-bookshelf-page')),
        findsOneWidget,
      );
      expect(
        selectedColor(tester, 'bookshelf'),
        Theme.of(
          tester.element(find.byKey(const Key('novel-tab-bookshelf'))),
        ).colorScheme.primary,
      );
    },
  );
  testWidgets(
    'creation new row creates one project opens its editor and returns to its list',
    (tester) async {
      final c = await pumpNovel(tester);
      await tab(tester, 'creation');
      expect(
        find.byKey(const PageStorageKey('novel-creation-list')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('novel-create-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('project-title-field')),
        '新的小说',
      );
      await tester.tap(find.byKey(const Key('save-project-button')));
      await tester.pumpAndSettle();
      final projects = await c.read(projectRepositoryProvider).listProjects();
      expect(projects, hasLength(1));
      expect(c.read(currentProjectControllerProvider), projects.single.id);
      expect(find.byKey(const Key('segment-list-page')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exit-app-dialog')), findsNothing);
      expect(
        find.byKey(const PageStorageKey('novel-creation-list')),
        findsOneWidget,
      );
      expect(find.text('创作新的小说'), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(Key('project-tile-${projects.single.id}')))
            .dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('novel-create-new'))).dy,
        ),
      );
      await tab(tester, 'bookshelf');
      expect(find.text('新的小说'), findsOneWidget);
    },
  );
  testWidgets('creation and settings are safe before choosing a work', (
    tester,
  ) async {
    await pumpNovel(tester);
    await tab(tester, 'settings');
    expect(find.text('从创作页选择作品后，在这里管理它的创作设置。'), findsOneWidget);
    expect(find.byKey(const Key('settings-personal-profile')), findsNothing);
    await tab(tester, 'creation');
    expect(find.byKey(const Key('novel-create-new')), findsOneWidget);
    await tab(tester, 'bookshelf');
    expect(find.byKey(const Key('novel-new-project')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('work settings modify only the selected novels system prompt', (
    tester,
  ) async {
    final c = await pumpNovel(tester, projects: 2, current: 'p2');
    await tab(tester, 'settings');
    expect(find.text('作品 2'), findsOneWidget);
    for (final title in ['角色卡', '世界观', '本作品模型', '阅读', '已删除内容', '作品信息']) {
      await tester.scrollUntilVisible(
        find.text(title),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(title), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.byKey(const Key('novel-creation-settings-entry')),
      -250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-creation-settings-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('project-system-prompt-field')),
      '仅属于作品二的要求',
    );
    await tester.ensureVisible(
      find.byKey(const Key('save-system-prompt-button')),
    );
    await tester.tap(find.byKey(const Key('save-system-prompt-button')));
    await tester.pumpAndSettle();
    expect(
      (await c.read(projectRepositoryProvider).getProject('p2')).systemPrompt,
      '仅属于作品二的要求',
    );
    expect(
      (await c.read(projectRepositoryProvider).getProject('p1')).systemPrompt,
      '作品 1 提示词',
    );
  });
  testWidgets(
    'switching novel tabs retains the composer draft and manuscript scroll',
    (tester) async {
      await pumpNovel(tester, projects: 1, current: 'p1', segments: 35);
      await tab(tester, 'creation');
      await openWork(tester, 'p1');
      await tester.enterText(
        find.byKey(const Key('novel-composer-field')),
        '尚未发送的剧情方向',
      );
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('continuous-manuscript-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(scrollable, const Offset(0, -280));
      await tester.pumpAndSettle();
      final before = tester.state<ScrollableState>(scrollable).position.pixels;
      await tab(tester, 'settings');
      await tab(tester, 'bookshelf');
      await tab(tester, 'creation');
      await openWork(tester, 'p1');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('novel-composer-field')))
            .controller!
            .text,
        '尚未发送的剧情方向',
      );
      expect(tester.state<ScrollableState>(scrollable).position.pixels, before);
    },
  );
  testWidgets(
    'unsent directions are restored per work and never copied into another work',
    (tester) async {
      await pumpNovel(tester, projects: 2);
      await tab(tester, 'creation');
      await openWork(tester, 'p1');
      await tester.enterText(
        find.byKey(const Key('novel-composer-field')),
        '作品一的方向',
      );
      await tab(tester, 'creation');
      await openWork(tester, 'p2');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('novel-composer-field')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('novel-composer-field')),
        '作品二的方向',
      );
      await tab(tester, 'creation');
      await openWork(tester, 'p1');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('novel-composer-field')))
            .controller!
            .text,
        '作品一的方向',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'main mode wheel returns to the selected novel section and keeps its draft',
    (tester) async {
      await pumpNovel(tester, projects: 1, current: 'p1');
      await tab(tester, 'creation');
      await openWork(tester, 'p1');
      await tester.enterText(
        find.byKey(const Key('novel-composer-field')),
        '保留的方向',
      );
      await tester.tap(find.byKey(const Key('bottom-nav-chat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bottom-nav-novel')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('novel-composer-field')))
            .controller!
            .text,
        '保留的方向',
      );
      expect(
        selectedColor(tester, 'creation'),
        Theme.of(
          tester.element(find.byKey(const Key('novel-tab-creation'))),
        ).colorScheme.primary,
      );
    },
  );
  testWidgets('unknown section falls back to bookshelf', (tester) async {
    final c = await pumpNovel(tester);
    c.read(appRouterProvider).go('/novel?section=unknown');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empty-novel-bookshelf')), findsOneWidget);
    expect(
      selectedColor(tester, 'bookshelf'),
      Theme.of(
        tester.element(find.byKey(const Key('novel-tab-bookshelf'))),
      ).colorScheme.primary,
    );
  });
  testWidgets('creation always lists every work then the new novel row', (
    tester,
  ) async {
    final c = await pumpNovel(tester, projects: 2, current: 'p1');
    await tab(tester, 'creation');
    expect(find.byKey(const Key('segment-list-page')), findsNothing);
    for (final id in ['p1', 'p2']) {
      expect(find.byKey(Key('project-tile-$id')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(Key('project-tile-$id'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('novel-create-new'))).dy,
        ),
      );
    }
    expect(find.byKey(const Key('novel-new-project')), findsNothing);
    await openWork(tester, 'p2');
    expect(c.read(currentProjectControllerProvider), 'p2');
    expect(find.byKey(const Key('segment-list-page')), findsOneWidget);
    await tab(tester, 'creation');
    expect(
      find.byKey(const PageStorageKey('novel-creation-list')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('segment-list-page')), findsNothing);
    await openWork(tester, 'p1');
    await tester.tap(find.byKey(const Key('novel-back-to-creation-list')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const PageStorageKey('novel-creation-list')),
      findsOneWidget,
    );
  });
  testWidgets(
    'bookshelf reader shows the chosen manuscript and returns to shelf',
    (tester) async {
      final c = await pumpNovel(
        tester,
        projects: 2,
        current: 'p2',
        segments: 1,
      );
      await openWork(tester, 'p1');
      expect(find.byKey(const Key('novel-reader-page')), findsOneWidget);
      expect(find.textContaining('段落 0：'), findsOneWidget);
      expect(c.read(currentProjectControllerProvider), 'p2');
      expect(
        await c.read(segmentRepositoryProvider).listSegments('p1'),
        hasLength(1),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const PageStorageKey('novel-bookshelf-page')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('novel-create-new')), findsNothing);
    },
  );
  testWidgets('canceling new novel returns to creation without creating data', (
    tester,
  ) async {
    final c = await pumpNovel(tester, projects: 1, current: 'p1');
    await tab(tester, 'creation');
    await tester.tap(find.byKey(const Key('novel-create-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-title-field')), findsOneWidget);
    await tester.tap(find.byKey(const Key('shell-back-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const PageStorageKey('novel-creation-list')),
      findsOneWidget,
    );
    expect(
      await c.read(projectRepositoryProvider).listProjects(),
      hasLength(1),
    );
    expect(c.read(currentProjectControllerProvider), 'p1');
  });
  testWidgets(
    'three tabs remain visible and tappable on a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(280, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpNovel(tester);
      for (final name in ['creation', 'settings', 'bookshelf']) {
        await tab(tester, name);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets('selected section stays bright in dark mode', (tester) async {
    final c = await pumpNovel(tester);
    c.read(themeModeControllerProvider.notifier).setDarkMode(true);
    await tester.pumpAndSettle();
    await tab(tester, 'settings');
    expect(
      selectedColor(tester, 'settings'),
      Theme.of(
        tester.element(find.byKey(const Key('novel-tab-settings'))),
      ).colorScheme.primary,
    );
    expect(
      selectedColor(tester, 'creation'),
      isNot(selectedColor(tester, 'settings')),
    );
  });
}

Color? selectedColor(WidgetTester tester, String name) => tester
    .widget<AnimatedDefaultTextStyle>(
      find
          .descendant(
            of: find.byKey(Key('novel-tab-$name')),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first,
    )
    .style
    .color;
Future<void> tab(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(Key('novel-tab-$name')));
  await tester.pumpAndSettle();
}

Future<void> openWork(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('project-tile-$id')));
  await tester.pumpAndSettle();
}

final now = DateTime.utc(2026, 11, 21);
EntityMetadata meta(String id) =>
    EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);
Future<ProviderContainer> pumpNovel(
  WidgetTester tester, {
  int projects = 0,
  String? current,
  int segments = 0,
}) async {
  final c = ProviderContainer(
    overrides: [
      aiSecureValueStoreProvider.overrideWithValue(InMemorySecureValueStore()),
    ],
  );
  addTearDown(c.dispose);
  for (var i = 1; i <= projects; i++) {
    await c
        .read(projectRepositoryProvider)
        .upsertProject(
          Project(
            metadata: meta('p$i'),
            title: '作品 $i',
            description: '简介 $i',
            systemPrompt: '作品 $i 提示词',
          ),
        );
  }
  for (var i = 0; i < segments; i++) {
    await c
        .read(segmentRepositoryProvider)
        .upsertSegment(
          Segment(
            metadata: meta('s$i'),
            projectId: 'p1',
            orderIndex: i,
            content: '段落 $i：${'正文内容，' * 20}',
          ),
        );
  }
  if (current != null) {
    c.read(currentProjectControllerProvider.notifier).selectProject(current);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(container: c, child: const IbukiHomeApp()),
  );
  await tester.pumpAndSettle();
  c.read(appRouterProvider).go(AppRoutes.novel);
  await tester.pumpAndSettle();
  return c;
}
