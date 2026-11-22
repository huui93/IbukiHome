import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';

void main() {
  testWidgets('drawer project item opens the project list', (tester) async {
    await _pumpFlowApp(tester);

    await _openProjectsFromDrawer(tester);

    expect(find.byKey(const Key('projects-page')), findsOneWidget);
  });

  testWidgets('empty project list shows an empty state', (tester) async {
    await _pumpFlowApp(tester);

    await _openProjectsFromDrawer(tester);

    expect(find.byKey(const Key('empty-projects-state')), findsOneWidget);
    expect(find.byKey(const Key('memory-data-notice')), findsNothing);
  });

  testWidgets('new project page can be opened', (tester) async {
    await _pumpFlowApp(tester);
    await _openProjectsFromDrawer(tester);

    await tester.tap(find.byKey(const Key('new-project-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-project-page')), findsOneWidget);
  });

  testWidgets('empty project title does not create a project', (tester) async {
    await _pumpFlowApp(tester);
    await _openProjectsFromDrawer(tester);
    await tester.tap(find.byKey(const Key('new-project-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save-project-button')));
    await tester.pump();

    expect(find.byKey(const Key('new-project-page')), findsOneWidget);
    expect(find.text('项目名称不能为空'), findsOneWidget);
  });

  testWidgets('creating a project opens the segment list', (tester) async {
    await _pumpFlowApp(tester, ids: ['project-1']);

    await _createProject(tester);

    expect(find.byKey(const Key('segment-list-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('novel-tab-settings')));
    await tester.pumpAndSettle();
    expect(find.text('测试故事'), findsWidgets);
  });

  testWidgets('created project is marked as the current project', (
    tester,
  ) async {
    await _pumpFlowApp(tester, ids: ['project-1']);
    await _createProject(tester);

    _goFromVisibleContext(tester, AppRoutes.projects);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('current-project-project-1')), findsOneWidget);
  });

  testWidgets('new project segment list shows an empty state', (tester) async {
    await _pumpFlowApp(tester, ids: ['project-1']);

    await _createProject(tester);

    expect(find.byKey(const Key('empty-segments-state')), findsOneWidget);
  });

  testWidgets('Android back from novel does not invent a project-list layer', (
    tester,
  ) async {
    await _pumpFlowApp(tester, ids: ['project-1']);

    await _createProject(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('projects-page')), findsNothing);
    expect(find.byKey(const Key('novel-workspace-home')), findsOneWidget);
  });

  testWidgets('new segment page can be opened', (tester) async {
    await _pumpFlowApp(tester, ids: ['project-1']);
    await _createProject(tester);

    if (find.byKey(const Key('new-segment-button')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('novel-extra-creation')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('new-segment-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-segment-page')), findsOneWidget);
  });

  testWidgets('creating a segment adds it to the list', (tester) async {
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1']);
    await _createProject(tester);

    await _createSegment(tester, '第一段正文');

    expect(find.byKey(const Key('segment-tile-segment-1')), findsOneWidget);
    expect(find.textContaining('第一段正文'), findsOneWidget);
  });

  testWidgets('tapping a segment opens details and edit remains reachable', (
    tester,
  ) async {
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1']);
    await _createProject(tester);
    await _createSegment(tester, '第一段正文');

    await tester.tap(find.byKey(const Key('segment-tile-segment-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('segment-detail-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-segment-detail-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edit-segment-page')), findsOneWidget);
    expect(find.byKey(const Key('segment-content-field')), findsOneWidget);
  });

  testWidgets('saving unchanged content does not increase revision', (
    tester,
  ) async {
    await _pumpFlowApp(
      tester,
      ids: ['project-1', 'segment-1', 'unused-revision'],
    );
    await _createProject(tester);
    await _createSegment(tester, '第一段正文');
    await _openSegmentEditor(tester);

    await tester.tap(find.byKey(const Key('save-segment-button')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('revision 1'), findsOneWidget);
    expect(find.text('历史 0'), findsOneWidget);
  });

  testWidgets('saving changed content increases revision', (tester) async {
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1', 'revision-1']);
    await _createProject(tester);
    await _createSegment(tester, '第一段正文');
    await _openSegmentEditor(tester);

    await tester.enterText(
      find.byKey(const Key('segment-content-field')),
      '第一段正文，已经修改。',
    );
    await tester.tap(find.byKey(const Key('save-segment-button')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('revision 2'), findsOneWidget);
  });

  testWidgets('saving changed content increases history count', (tester) async {
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1', 'revision-1']);
    await _createProject(tester);
    await _createSegment(tester, '第一段正文');
    await _openSegmentEditor(tester);

    await tester.enterText(
      find.byKey(const Key('segment-content-field')),
      '第一段正文，已经修改。',
    );
    await tester.tap(find.byKey(const Key('save-segment-button')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('历史 1'), findsOneWidget);
  });

  testWidgets('returning to the list shows the updated preview', (
    tester,
  ) async {
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1', 'revision-1']);
    await _createProject(tester);
    await _createSegment(tester, '第一段正文');
    await _openSegmentEditor(tester);

    await tester.enterText(
      find.byKey(const Key('segment-content-field')),
      '第一段正文，已经修改。',
    );
    await tester.tap(find.byKey(const Key('save-segment-button')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const Key('shell-back-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('segment-detail-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('shell-back-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('segment-list-page')), findsOneWidget);
    expect(find.textContaining('已经修改'), findsOneWidget);
  });

  testWidgets('route switching keeps in-memory data available', (tester) async {
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1']);
    await _createProject(tester);
    await _createSegment(tester, '第一段正文');

    _goFromVisibleContext(tester, AppRoutes.chat);
    await tester.pumpAndSettle();
    _goFromVisibleContext(tester, AppRoutes.novelEditor('project-1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('segment-list-page')), findsOneWidget);
    expect(find.textContaining('第一段正文'), findsOneWidget);
  });

  testWidgets('unsaved edits ask for confirmation when using back button', (
    tester,
  ) async {
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1']);
    await _createProject(tester);
    await _createSegment(tester, '第一段正文');
    await _openSegmentEditor(tester);

    await tester.enterText(
      find.byKey(const Key('segment-content-field')),
      '还没保存的正文',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('shell-back-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discard-changes-dialog')), findsOneWidget);
  });

  testWidgets('Android back is intercepted when edits are unsaved', (
    tester,
  ) async {
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1']);
    await _createProject(tester);
    await _createSegment(tester, '第一段正文');
    await _openSegmentEditor(tester);

    await tester.enterText(
      find.byKey(const Key('segment-content-field')),
      '还没保存的正文',
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discard-changes-dialog')), findsOneWidget);
  });

  testWidgets('small 360 by 800 project page does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpFlowApp(tester);
    await _openProjectsFromDrawer(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mode can build the project page', (tester) async {
    await _pumpFlowApp(tester, ids: ['project-1']);
    await _createProject(tester);

    _goFromVisibleContext(tester, AppRoutes.settings);
    await tester.pumpAndSettle();
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
    expect(
      Theme.of(
        tester.element(find.byKey(const Key('settings-theme-switch'))),
      ).brightness,
      Brightness.dark,
    );
    _goFromVisibleContext(tester, AppRoutes.projects);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('projects-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat and settings routes remain available', (tester) async {
    await _pumpFlowApp(tester);

    _goFromVisibleContext(tester, AppRoutes.chat);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-home-page')), findsOneWidget);

    _goFromVisibleContext(tester, AppRoutes.settings);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-page')), findsOneWidget);
  });

  testWidgets('page switching does not recreate the store', (tester) async {
    final container = await _pumpFlowApp(tester);
    final store = container.read(inMemoryIbukiStoreProvider);

    await _openProjectsFromDrawer(tester);
    _goFromVisibleContext(tester, AppRoutes.chat);
    await tester.pumpAndSettle();

    expect(container.read(inMemoryIbukiStoreProvider), same(store));
  });

  testWidgets('theme switching does not clear in-memory data', (tester) async {
    await _pumpFlowApp(tester, ids: ['project-1']);
    await _createProject(tester);

    _goFromVisibleContext(tester, AppRoutes.settings);
    await tester.pumpAndSettle();
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
    expect(
      Theme.of(
        tester.element(find.byKey(const Key('settings-theme-switch'))),
      ).brightness,
      Brightness.dark,
    );
    _goFromVisibleContext(tester, AppRoutes.projects);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('project-tile-project-1')), findsOneWidget);
  });

  testWidgets('segment list exposes the deleted segment entry', (tester) async {
    await _pumpFlowApp(tester, ids: ['project-1']);
    await _createProject(tester);

    expect(find.byKey(const Key('deleted-segments-button')), findsOneWidget);
  });

  testWidgets('segment details expose insert delete and history actions', (
    tester,
  ) async {
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1']);
    await _createProject(tester);
    await _createSegment(tester, '第一段正文');

    await tester.tap(find.byKey(const Key('segment-tile-segment-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('segment-history-button')), findsOneWidget);
    expect(
      find.byKey(const Key('insert-before-detail-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('insert-after-detail-button')), findsOneWidget);
    expect(
      find.byKey(const Key('delete-segment-detail-button')),
      findsOneWidget,
    );
  });

  testWidgets('segment details display the complete body without truncation', (
    tester,
  ) async {
    final longContent = List.filled(40, '完整正文').join('，');
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1']);
    await _createProject(tester);
    await _createSegment(tester, longContent);

    await tester.tap(find.byKey(const Key('segment-tile-segment-1')));
    await tester.pumpAndSettle();

    expect(find.text(longContent), findsOneWidget);
  });

  testWidgets('history page shows the empty state', (tester) async {
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1']);
    await _createProject(tester);
    await _createSegment(tester, '第一段正文');
    await tester.tap(find.byKey(const Key('segment-tile-segment-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('segment-history-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('segment-history-page')), findsOneWidget);
    expect(
      find.byKey(const Key('segment-history-empty-state')),
      findsOneWidget,
    );
  });

  testWidgets('insert before creates a segment and refreshes the list', (
    tester,
  ) async {
    final container = await _pumpFlowApp(
      tester,
      ids: ['project-1', 'segment-1', 'segment-2'],
    );
    await _createProject(tester);
    await _createSegment(tester, '锚点正文');
    await tester.tap(find.byKey(const Key('segment-tile-segment-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('insert-before-detail-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('insert-segment-page')), findsOneWidget);
    expect(find.textContaining('之前'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('segment-content-field')),
      '插入正文',
    );
    await tester.tap(find.byKey(const Key('save-segment-button')));
    await tester.pumpAndSettle();

    final items = await container
        .read(segmentRepositoryProvider)
        .listSegments('project-1');
    expect(items.map((item) => item.content), ['插入正文', '锚点正文']);
    expect(find.byKey(const Key('segment-list-page')), findsOneWidget);
  });

  testWidgets('insert after route clearly identifies the position', (
    tester,
  ) async {
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1']);
    await _createProject(tester);
    await _createSegment(tester, '锚点正文');
    await tester.tap(find.byKey(const Key('segment-tile-segment-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('insert-after-detail-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('insert-segment-page')), findsOneWidget);
    expect(find.textContaining('之后'), findsWidgets);
  });

  testWidgets('moving a segment up refreshes repository order', (tester) async {
    final container = await _pumpFlowApp(
      tester,
      ids: ['project-1', 'segment-1', 'segment-2'],
    );
    await _createProject(tester);
    await _createSegment(tester, '第一段');
    await _createSegment(tester, '第二段');

    await tester.tap(find.byKey(const Key('segment-menu-segment-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上移'));
    await tester.pumpAndSettle();

    final items = await container
        .read(segmentRepositoryProvider)
        .listSegments('project-1');
    expect(items.map((item) => item.id), ['segment-2', 'segment-1']);
  });

  testWidgets('soft deleted segment can be restored from the deleted list', (
    tester,
  ) async {
    final container = await _pumpFlowApp(
      tester,
      ids: ['project-1', 'segment-1'],
    );
    await _createProject(tester);
    await _createSegment(tester, '待删除正文');
    await tester.tap(find.byKey(const Key('segment-tile-segment-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-segment-detail-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delete-segment-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-segment-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empty-segments-state')), findsOneWidget);

    await tester.tap(find.byKey(const Key('deleted-segments-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deleted-segment-segment-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('restore-segment-segment-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('segment-tile-segment-1')), findsOneWidget);
    expect(
      await container.read(segmentRepositoryProvider).listSegments('project-1'),
      hasLength(1),
    );
  });

  testWidgets('history preview shows full content and restores it', (
    tester,
  ) async {
    final container = await _pumpFlowApp(
      tester,
      ids: ['project-1', 'segment-1', 'revision-1', 'rollback-1'],
    );
    await _createProject(tester);
    await _createSegment(tester, '旧正文');
    await _openSegmentEditor(tester);
    await tester.enterText(
      find.byKey(const Key('segment-content-field')),
      '新正文',
    );
    await tester.tap(find.byKey(const Key('save-segment-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shell-back-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('segment-history-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('segment-revision-revision-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('segment-revision-revision-1')));
    await tester.pumpAndSettle();
    expect(find.text('旧正文'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('restore-segment-revision-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restore-segment-revision-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('restore-segment-revision-dialog')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('confirm-restore-segment-revision-button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('segment-detail-page')), findsOneWidget);
    expect(find.text('旧正文'), findsOneWidget);
    final restored = await container
        .read(segmentRepositoryProvider)
        .getSegment('segment-1');
    expect(restored.revision, 3);
    expect(
      await container
          .read(segmentRepositoryProvider)
          .listRevisions('segment-1'),
      hasLength(2),
    );
  });

  testWidgets('forged project id cannot open a segment', (tester) async {
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1']);
    await _createProject(tester);
    await _createSegment(tester, '第一段正文');

    _goFromVisibleContext(
      tester,
      AppRoutes.segment('forged-project', 'segment-1'),
    );
    await tester.pumpAndSettle();

    expect(find.text('项目不存在'), findsOneWidget);
    expect(find.byKey(const Key('segment-detail-page')), findsNothing);
  });

  testWidgets('360 by 800 segment details and history do not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpFlowApp(tester, ids: ['project-1', 'segment-1']);
    await _createProject(tester);
    await _createSegment(tester, '第一段正文');
    await tester.tap(find.byKey(const Key('segment-tile-segment-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('segment-detail-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('segment-history-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('segment-history-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<ProviderContainer> _pumpFlowApp(
  WidgetTester tester, {
  List<String> ids = const [
    'project-1',
    'segment-1',
    'segment-2',
    'revision-1',
    'revision-2',
  ],
}) async {
  final container = ProviderContainer(
    overrides: [
      entityIdGeneratorProvider.overrideWithValue(_QueueIdGenerator(ids)),
      utcClockProvider.overrideWithValue(
        _FixedClock(DateTime.utc(2026, 1, 1, 8)),
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
  _goFromVisibleContext(tester, AppRoutes.novel);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _openProjectsFromDrawer(WidgetTester tester) async {
  _goFromVisibleContext(tester, AppRoutes.projects);
  await tester.pumpAndSettle();
}

Future<void> _createProject(
  WidgetTester tester, {
  String title = '测试故事',
}) async {
  await _openProjectsFromDrawer(tester);
  await tester.tap(find.byKey(const Key('new-project-button')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('project-title-field')), title);
  await tester.tap(find.byKey(const Key('save-project-button')));
  await tester.pumpAndSettle();
}

Future<void> _createSegment(WidgetTester tester, String content) async {
  if (find.byKey(const Key('new-segment-button')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('novel-extra-creation')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('new-segment-button')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('segment-content-field')),
    content,
  );
  await tester.tap(find.byKey(const Key('save-segment-button')));
  await tester.pumpAndSettle();
}

Future<void> _openSegmentEditor(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('segment-tile-segment-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('edit-segment-detail-button')));
  await tester.pumpAndSettle();
}

void _goFromVisibleContext(WidgetTester tester, String location) {
  final candidateKeys = [
    const Key('segment-list-page'),
    const Key('projects-page'),
    const Key('chat-home-page'),
    const Key('settings-page'),
    const Key('new-project-page'),
    const Key('edit-segment-page'),
  ];
  for (final key in candidateKeys) {
    final finder = find.byKey(key);
    if (finder.evaluate().isNotEmpty) {
      final context = tester.element(finder);
      GoRouter.of(context).go(location);
      return;
    }
  }
  final context = tester.element(find.byType(Scaffold).first);
  GoRouter.of(context).go(location);
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
