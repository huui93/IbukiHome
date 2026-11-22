import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ibukihome/app/theme/app_theme.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_project_repository.dart';
import 'package:ibukihome/data/memory/in_memory_reader_repository.dart';
import 'package:ibukihome/data/memory/in_memory_segment_repository.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/reader/reader_preferences.dart';
import 'package:ibukihome/domain/segments/segment.dart';
import 'package:ibukihome/features/projects/presentation/novel_reader_page.dart';

void main() {
  testWidgets('Reader route opens a dedicated page', (tester) async {
    await _pumpReader(tester, count: 3);
    expect(find.byKey(const Key('novel-reader-page')), findsOneWidget);
  });

  testWidgets('Reader hides the four-tab bottom navigation', (tester) async {
    await _pumpReader(tester, count: 3);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('世界'), findsNothing);
  });

  testWidgets('Reader has an explicit back control', (tester) async {
    final fixture = await _pumpReader(tester, count: 3);
    await tester.tap(find.byKey(const Key('reader-back-button')));
    await tester.pumpAndSettle();
    expect(fixture.router.state.uri.path, '/novel');
  });

  testWidgets('Android back returns to the novel workbench', (tester) async {
    final fixture = await _pumpReader(tester, count: 3);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(fixture.router.state.uri.path, '/novel');
  });

  testWidgets('Reader presents continuous manuscript text', (tester) async {
    await _pumpReader(tester, count: 3);
    expect(find.text('阅读正文 0'), findsOneWidget);
    expect(find.text('阅读正文 1'), findsOneWidget);
  });

  testWidgets('Reader exposes no paragraph edit controls', (tester) async {
    await _pumpReader(tester, count: 3);
    expect(find.text('编辑'), findsNothing);
    expect(find.text('删除'), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
  });

  testWidgets('Reader exposes no AI composer', (tester) async {
    await _pumpReader(tester, count: 3);
    expect(find.text('告诉伊吹，接下来想怎么写……'), findsNothing);
    expect(find.text('生成下一段'), findsNothing);
  });

  testWidgets('tapping the page hides and restores controls', (tester) async {
    await _pumpReader(tester, count: 3);
    final controls = tester.widget<AnimatedPositioned>(
      find.ancestor(
        of: find.byKey(const Key('reader-controls')),
        matching: find.byType(AnimatedPositioned),
      ),
    );
    expect(controls.top, 0);
    await tester.tapAt(const Offset(180, 400));
    await tester.pump();
    final hidden = tester.widget<AnimatedPositioned>(
      find.ancestor(
        of: find.byKey(const Key('reader-controls')),
        matching: find.byType(AnimatedPositioned),
      ),
    );
    expect(hidden.top, -90);
  });

  testWidgets('Reader settings sheet exposes font, line and margin controls', (
    tester,
  ) async {
    await _pumpReader(tester, count: 3);
    await tester.tap(find.byKey(const Key('reader-settings-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-settings-sheet')), findsOneWidget);
    expect(find.text('字号'), findsOneWidget);
    expect(find.text('行距'), findsOneWidget);
    expect(find.text('左右边距'), findsOneWidget);
  });

  testWidgets('Reader theme can be saved independently from App theme', (
    tester,
  ) async {
    final fixture = await _pumpReader(tester, count: 3);
    await tester.tap(find.byKey(const Key('reader-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.tap(find.byKey(const Key('save-reader-settings')));
    await tester.pumpAndSettle();
    expect(
      (await fixture.readers.loadPreferences('project-1')).theme,
      ReaderThemeMode.dark,
    );
  });

  testWidgets('font-size changes persist', (tester) async {
    final fixture = await _pumpReader(tester, count: 3);
    await tester.tap(find.byKey(const Key('reader-settings-button')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).at(0), const Offset(80, 0));
    await tester.tap(find.byKey(const Key('save-reader-settings')));
    await tester.pumpAndSettle();
    expect(
      (await fixture.readers.loadPreferences('project-1')).fontSize,
      greaterThan(18),
    );
  });

  testWidgets('scroll position and last segment are saved', (tester) async {
    final fixture = await _pumpReader(tester, count: 60);
    await tester.drag(
      find.byKey(const Key('reader-segment-list')),
      const Offset(0, -1200),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final progress = await fixture.readers.loadProgress('project-1');
    expect(progress.scrollOffset, greaterThan(0));
    expect(progress.lastReadSegmentId, isNotNull);
  });

  testWidgets('stored reading position restores after rebuild', (tester) async {
    final progress = ReaderProgress(
      projectId: 'project-1',
      lastReadSegmentId: 'segment-20',
      scrollOffset: 800,
      updatedAt: _now,
    );
    await _pumpReader(tester, count: 60, progress: progress);
    final list = tester.widget<ListView>(
      find.byKey(const Key('reader-segment-list')),
    );
    expect(list.controller?.offset, closeTo(800, 1));
  });

  testWidgets('missing last-read segment falls back without crashing', (
    tester,
  ) async {
    final progress = ReaderProgress(
      projectId: 'project-1',
      lastReadSegmentId: 'deleted-segment',
      scrollOffset: 500,
      updatedAt: _now,
    );
    await _pumpReader(tester, count: 10, progress: progress);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('novel-reader-page')), findsOneWidget);
  });

  testWidgets('empty novel Reader has a readable empty state', (tester) async {
    await _pumpReader(tester, count: 0);
    expect(find.text('这部作品还没有正文。'), findsOneWidget);
  });

  testWidgets('1000 segments use lazy widget construction', (tester) async {
    await _pumpReader(tester, count: 1000);
    expect(find.byKey(const Key('reader-segment-list')), findsOneWidget);
    final built = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('reader-segment-'),
    );
    expect(built.evaluate().length, lessThan(80));
  });

  testWidgets('360 by 800 Reader has no overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpReader(tester, count: 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text Reader remains usable', (tester) async {
    await _pumpReader(tester, count: 20, textScale: 1.6);
    expect(find.byKey(const Key('reader-back-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('reader preferences persist all reading controls', () async {
    final store = InMemoryIbukiStore();
    final repository = InMemoryReaderRepository(store);
    final value = ReaderPreferences(
      projectId: 'project-1',
      fontSize: 23,
      lineHeight: 2,
      horizontalMargin: 36,
      theme: ReaderThemeMode.warm,
      updatedAt: _now,
    );
    await repository.savePreferences(value);
    final restored = await repository.loadPreferences('project-1');
    expect(restored.fontSize, 23);
    expect(restored.lineHeight, 2);
    expect(restored.horizontalMargin, 36);
    expect(restored.theme, ReaderThemeMode.warm);
  });

  test('reader progress is isolated per project', () async {
    final repository = InMemoryReaderRepository(InMemoryIbukiStore());
    await repository.saveProgress(
      ReaderProgress(
        projectId: 'project-1',
        lastReadSegmentId: 'a',
        scrollOffset: 10,
        updatedAt: _now,
      ),
    );
    await repository.saveProgress(
      ReaderProgress(
        projectId: 'project-2',
        lastReadSegmentId: 'b',
        scrollOffset: 20,
        updatedAt: _now,
      ),
    );
    expect((await repository.loadProgress('project-1')).lastReadSegmentId, 'a');
    expect((await repository.loadProgress('project-2')).lastReadSegmentId, 'b');
  });
}

class _ReaderFixture {
  const _ReaderFixture(this.router, this.readers);

  final GoRouter router;
  final InMemoryReaderRepository readers;
}

Future<_ReaderFixture> _pumpReader(
  WidgetTester tester, {
  required int count,
  ReaderPreferences? preferences,
  ReaderProgress? progress,
  double textScale = 1,
}) async {
  final store = InMemoryIbukiStore()..putProject(_project());
  for (var index = 0; index < count; index++) {
    store.putSegment(_segment(index));
  }
  if (preferences != null) store.putReaderPreferences(preferences);
  if (progress != null) store.putReaderProgress(progress);
  final projects = InMemoryProjectRepository(store);
  final segments = InMemorySegmentRepository(store);
  final readers = InMemoryReaderRepository(store);
  final router = GoRouter(
    initialLocation: '/novel',
    routes: [
      GoRoute(
        path: '/novel',
        builder: (_, _) => const Scaffold(body: Text('小说工作台')),
      ),
      GoRoute(
        path: '/reader',
        builder: (_, _) => const NovelReaderPage(projectId: 'project-1'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        projectRepositoryProvider.overrideWithValue(projects),
        segmentRepositoryProvider.overrideWithValue(segments),
        readerRepositoryProvider.overrideWithValue(readers),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/reader');
  await tester.pumpAndSettle();
  return _ReaderFixture(router, readers);
}

Project _project() => Project(
  metadata: _metadata('project-1'),
  title: '很长但适合阅读的测试小说',
  description: '',
);

Segment _segment(int index) => Segment(
  metadata: _metadata('segment-$index'),
  projectId: 'project-1',
  orderIndex: index,
  content: '阅读正文 $index',
);

EntityMetadata _metadata(String id) =>
    EntityMetadata(id: id, createdAt: _now, updatedAt: _now, revision: 1);

final _now = DateTime.utc(2026, 8, 12, 8);
