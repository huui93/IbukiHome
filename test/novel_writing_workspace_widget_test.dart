import 'package:ibukihome/application/projects/novel_output_limits_providers.dart';
import 'package:ibukihome/application/plugins/novel_plugin_providers.dart';
import 'package:ibukihome/application/ai/ai_runtime_providers.dart';
import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/navigation/app_workspace_mode.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/app/theme/theme_controller.dart';
import 'package:ibukihome/application/common/entity_id_generator.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/ai/ai_draft_update.dart';
import 'package:ibukihome/application/ai/auto_story_runner.dart';
import 'package:ibukihome/application/projects/current_project_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/data/memory/in_memory_ibuki_store.dart';
import 'package:ibukihome/data/memory/in_memory_segment_repository.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/domain/projects/project.dart';
import 'package:ibukihome/domain/segments/segment.dart';

void main() {
  testWidgets(
    'novel settings confirms deletion, clears only the selected work and returns to the bookshelf',
    (tester) async {
      final h = await _pumpNovel(tester);
      await h.container
          .read(projectRepositoryProvider)
          .upsertProject(
            Project(
              metadata: _metadata('other-work'),
              title: '另一部作品',
              description: '',
            ),
          );
      await h.container
          .read(novelPluginRepositoryProvider)
          .fork(
            projectId: 'project-1',
            newProjectId: 'child-storyline',
            label: '分支',
            now: DateTime.utc(2026, 11, 22),
          );
      final coordinator = h.container.read(aiRequestCoordinatorProvider);
      final novelTask = coordinator.begin(
        'novel-task',
        'request-novel',
        scopeId: 'child-storyline',
      );
      final chatTask = coordinator.begin(
        'chat-task',
        'request-chat',
        scopeId: 'unrelated-chat',
      );
      await tester.tap(find.byKey(const Key('novel-tab-settings')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('novel-delete-current-project')),
        400,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('novel-settings-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.drag(
        find.byKey(const PageStorageKey('novel-settings-scroll')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('novel-delete-current-project')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('novel-delete-current-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        (await h.container
                .read(projectRepositoryProvider)
                .getProject('project-1'))
            .deletedAt,
        isNull,
      );
      expect(novelTask.isCancelled, isFalse);
      await tester.tap(find.byKey(const Key('novel-delete-current-project')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('novel-confirm-delete-project')));
      await tester.pumpAndSettle();
      expect(
        (await h.container
                .read(projectRepositoryProvider)
                .getProject('project-1'))
            .deletedAt,
        isNotNull,
      );
      expect(
        (await h.container
                .read(projectRepositoryProvider)
                .getProject('other-work'))
            .deletedAt,
        isNull,
      );
      expect(h.container.read(currentProjectControllerProvider), isNull);
      expect(
        (await h.container
                .read(projectRepositoryProvider)
                .getProject('child-storyline'))
            .deletedAt,
        isNotNull,
      );
      expect(novelTask.isCancelled, isTrue);
      expect(chatTask.isCancelled, isFalse);
      expect(find.text('另一部作品'), findsOneWidget);
      expect(find.byKey(const Key('novel-tab-bookshelf')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'creation tab with a current project opens the manuscript workbench',
    (tester) async {
      await _pumpNovel(tester);

      expect(find.byKey(const Key('segment-list-page')), findsOneWidget);
      expect(
        find.byKey(const Key('continuous-manuscript-list')),
        findsOneWidget,
      );
    },
  );

  testWidgets('empty bookshelf removes the former select and create buttons', (
    tester,
  ) async {
    await _pumpNovel(tester, seedProject: false);

    expect(find.byKey(const Key('empty-novel-bookshelf')), findsOneWidget);
    expect(find.text('还没有创作的作品'), findsOneWidget);
    expect(find.byKey(const Key('novel-switch-project')), findsNothing);
    expect(find.byKey(const Key('novel-new-project')), findsNothing);
    expect(find.byKey(const Key('segment-list-page')), findsNothing);
  });

  testWidgets('manuscript renders segments continuously by orderIndex', (
    tester,
  ) async {
    final harness = await _pumpNovel(
      tester,
      segments: const [
        _SegmentSeed('segment-late', 2, '第三段正文'),
        _SegmentSeed('segment-first', 0, '第一段正文'),
        _SegmentSeed('segment-middle', 1, '第二段正文'),
      ],
    );

    final stored = await harness.container
        .read(segmentRepositoryProvider)
        .listSegments('project-1');
    expect(stored.map((segment) => segment.id), [
      'segment-first',
      'segment-middle',
      'segment-late',
    ]);
    expect(
      find.byKey(const Key('continuous-segment-segment-first')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('continuous-segment-segment-late')),
      400,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('continuous-manuscript-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.byKey(const Key('continuous-segment-segment-late')),
      findsOneWidget,
    );
  });

  testWidgets('segment more menu contains the complete existing action set', (
    tester,
  ) async {
    await _pumpNovel(tester, segments: _twoSegments);

    await _openSegmentMenu(tester);

    for (final label in [
      '手动编辑',
      'AI 重写这一段',
      '按要求修改',
      '选择性修改',
      '在后面生成 · AI 接入后开放',
      '在前面插入',
      '在后面插入',
      '上移',
      '下移',
      '查看历史',
      '删除',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('segment actions are not permanently laid out', (tester) async {
    await _pumpNovel(tester, segments: _twoSegments);

    expect(find.byKey(const Key('segment-menu-segment-1')), findsOneWidget);
    for (final label in ['手动编辑', 'AI 重写这一段', '在前面插入', '在后面插入', '查看历史', '删除']) {
      expect(find.text(label), findsNothing);
    }
  });

  testWidgets('fixed direction composer is present below the manuscript', (
    tester,
  ) async {
    await _pumpNovel(tester);

    expect(find.byKey(const Key('novel-composer')), findsOneWidget);
    expect(find.byKey(const Key('novel-direction-composer')), findsOneWidget);
    expect(find.byKey(const Key('novel-composer-field')), findsOneWidget);
    expect(find.byKey(const Key('novel-generate-next')), findsOneWidget);
    expect(find.byKey(const Key('novel-extra-creation')), findsOneWidget);
    expect(find.byKey(const Key('new-segment-button')), findsNothing);
    expect(find.text('告诉伊吹，接下来想怎么写……'), findsOneWidget);
  });

  testWidgets(
    'context toolbar stays above manuscript and extra creation expands upwards',
    (tester) async {
      await _pumpNovel(tester);
      final toolbar = find.byKey(const Key('novel-context-toolbar'));
      final composer = find.byKey(const Key('novel-direction-composer'));
      expect(
        tester.getBottomLeft(toolbar).dy,
        lessThanOrEqualTo(
          tester
              .getTopLeft(find.byKey(const Key('continuous-manuscript-list')))
              .dy,
        ),
      );
      expect(
        tester.getSize(find.byKey(const Key('novel-generate-next'))).width,
        greaterThan(tester.getSize(composer).width - 12),
      );
      await tester.enterText(
        find.byKey(const Key('novel-composer-field')),
        'keep this direction',
      );
      await tester.tap(find.byKey(const Key('novel-extra-creation')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-segment-button')), findsOneWidget);
      expect(find.byKey(const Key('novel-auto-story-toggle')), findsOneWidget);
      expect(
        tester
            .getBottomLeft(find.byKey(const Key('novel-extra-creation-panel')))
            .dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('novel-composer-field'))).dy,
        ),
      );
      await tester.tap(find.byKey(const Key('novel-extra-creation')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('novel-composer-field')))
            .controller!
            .text,
        'keep this direction',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('AI generation is the primary action and shows provider state', (
    tester,
  ) async {
    final harness = await _pumpNovel(tester, segments: const []);

    await tester.enterText(
      find.byKey(const Key('novel-composer-field')),
      '下一段让角色发现门外有人',
    );
    await tester.pump();

    final generate = tester.widget<FilledButton>(
      find.byKey(const Key('novel-generate-next')),
    );
    expect(generate.onPressed, isNotNull);
    expect(find.text('生成下一段'), findsOneWidget);
    expect(find.text('尚未配置 AI'), findsOneWidget);
    final segments = await harness.container
        .read(segmentRepositoryProvider)
        .listSegments('project-1');
    expect(segments, isEmpty);
  });

  testWidgets(
    'auto story is opt-in and stop preserves the enabled preference',
    (tester) async {
      final started = Completer<void>();
      final cancelled = Completer<void>();
      var id = 0;
      final runner = AutoStoryRunner(
        generateSegment:
            ({
              required projectId,
              required userInstruction,
              required selectedCharacterIds,
              required selectedWorldCardIds,
              required requestId,
              required segmentId,
              required nowUtc,
            }) async* {
              yield AiDraftUpdate(
                requestId: requestId,
                draft: '正在生成',
                status: AiDraftStatus.streaming,
              );
              if (!started.isCompleted) started.complete();
              await cancelled.future;
              yield AiDraftUpdate(
                requestId: requestId,
                draft: '正在生成',
                status: AiDraftStatus.cancelled,
              );
            },
        cancelGeneration: (_) {
          if (!cancelled.isCompleted) cancelled.complete();
          return true;
        },
        nextId: (prefix) => '$prefix-${id++}',
        now: () => DateTime.utc(2026, 8, 25),
      );
      addTearDown(runner.dispose);
      await _pumpNovel(tester, autoStoryRunner: runner);

      await tester.tap(find.byKey(const Key('novel-extra-creation')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const Key('novel-auto-story-toggle')),
            )
            .selected,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('novel-auto-story-toggle')));
      await tester.pump();
      expect(find.text('开始自动剧情'), findsOneWidget);

      await tester.tap(find.byKey(const Key('novel-generate-next')));
      await started.future;
      await tester.pump();
      expect(find.text('停止自动剧情'), findsOneWidget);

      await tester.tap(find.byKey(const Key('novel-generate-next')));
      await tester.pumpAndSettle();
      expect(find.text('开始自动剧情'), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const Key('novel-auto-story-toggle')),
            )
            .selected,
        isTrue,
      );
    },
  );

  testWidgets('missing AI configuration does not consume the direction', (
    tester,
  ) async {
    await _pumpNovel(tester, segments: const []);
    const direction = '气氛安静一点，不要立刻揭露真相';

    await tester.enterText(
      find.byKey(const Key('novel-composer-field')),
      direction,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('novel-generate-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final segments = await _repositorySegments(tester);
    expect(segments, isEmpty);
    final field = tester.widget<TextField>(
      find.byKey(const Key('novel-composer-field')),
    );
    expect(field.controller?.text, direction);
    expect(
      find.byKey(const Key('continuous-segment-segment-new')),
      findsNothing,
    );
    expect(find.textContaining('还没有配置'), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('manual add is secondary and uses the existing create page', (
    tester,
  ) async {
    await _pumpNovel(tester, segments: const []);
    const direction = '从铃语的视角描写这场争吵';

    await tester.enterText(
      find.byKey(const Key('novel-composer-field')),
      direction,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('novel-extra-creation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-segment-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-segment-page')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('segment-content-field')),
      '这是一段手动补录的正文。',
    );
    await tester.tap(find.byKey(const Key('save-segment-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('novel-workspace-home')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('novel-composer-field')))
          .controller!
          .text,
      direction,
    );
    expect(find.text('这是一段手动补录的正文。'), findsOneWidget);
    final segments = await _repositorySegments(tester);
    expect(segments.single.content, '这是一段手动补录的正文。');
    expect(segments.single.content, isNot(direction));
  });

  testWidgets(
    'novel length settings validate, save repeatedly, and reset to default',
    (tester) async {
      final h = await _pumpNovel(tester);
      _go(tester, AppRoutes.projectOutputLimits('project-1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('novel-output-limits-page')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('novel-output-minimum')),
        '500',
      );
      await tester.enterText(
        find.byKey(const Key('novel-output-maximum')),
        '100',
      );
      await tester.tap(find.byKey(const Key('save-novel-output-limits')));
      await tester.pumpAndSettle();
      expect(find.text('最少字数不能大于最多字数。'), findsOneWidget);
      expect(
        (await h.container
                .read(novelOutputLimitsRepositoryProvider)
                .get('project-1'))
            .isDefault,
        isTrue,
      );
      await tester.enterText(
        find.byKey(const Key('novel-output-maximum')),
        '800',
      );
      await tester.tap(find.byKey(const Key('save-novel-output-limits')));
      await tester.pumpAndSettle();
      expect(
        (await h.container
                .read(novelOutputLimitsRepositoryProvider)
                .get('project-1'))
            .minimum,
        500,
      );
      await tester.enterText(find.byKey(const Key('novel-output-minimum')), '');
      await tester.tap(find.byKey(const Key('save-novel-output-limits')));
      await tester.pumpAndSettle();
      final second = await h.container
          .read(novelOutputLimitsRepositoryProvider)
          .get('project-1');
      expect(second.minimum, isNull);
      expect(second.maximum, 800);
      await tester.tap(find.byKey(const Key('reset-novel-output-limits')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-novel-output-limits')));
      await tester.pumpAndSettle();
      expect(
        (await h.container
                .read(novelOutputLimitsRepositoryProvider)
                .get('project-1'))
            .isDefault,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard focus keeps the SafeArea composer usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpNovel(tester);

    await tester.showKeyboard(find.byKey(const Key('novel-composer-field')));
    await tester.enterText(
      find.byKey(const Key('novel-composer-field')),
      '键盘弹出后的正文',
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('novel-composer')),
        matching: find.byType(SafeArea),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('novel-generate-next')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('novel settings exposes the existing writing navigation', (
    tester,
  ) async {
    await _pumpNovel(tester);
    await tester.tap(find.byKey(const Key('novel-tab-settings')));
    await tester.pumpAndSettle();

    expect(find.text('切换作品'), findsOneWidget);
    expect(find.text('角色卡'), findsOneWidget);
    expect(find.text('世界观'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('novel-creation-settings-entry')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('创作设定'), findsOneWidget);
    expect(find.text('本作系统提示词与提示词方案'), findsOneWidget);
    for (final label in ['已删除内容', '作品信息']) {
      await tester.scrollUntilVisible(
        find.text(label),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('整体方向'), findsNothing);
    expect(find.text('创作要求 / 历史要求'), findsNothing);
    expect(find.text('历史要求'), findsNothing);
    expect(find.text('连接电脑'), findsNothing);
    expect(find.byKey(const Key('drawer-chat')), findsNothing);
    expect(find.byKey(const Key('drawer-world-map')), findsNothing);
  });

  testWidgets('creation settings saves the project system prompt', (
    tester,
  ) async {
    final harness = await _pumpNovel(tester);
    await _openCreationSettings(tester);

    expect(find.byKey(const Key('creation-settings-page')), findsOneWidget);
    expect(find.text('系统提示词'), findsOneWidget);
    expect(find.byKey(const Key('outline-tab')), findsNothing);
    expect(find.byKey(const Key('long-memory-tab')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('project-system-prompt-field')),
      '  使用自然简洁的第三人称叙事。  ',
    );
    await tester.tap(find.byKey(const Key('save-system-prompt-button')));
    await tester.pumpAndSettle();

    final project = await harness.container
        .read(projectRepositoryProvider)
        .getProject('project-1');
    expect(project.systemPrompt, '使用自然简洁的第三人称叙事。');
  });

  testWidgets('outline tab creates nodes and exposes explicit status actions', (
    tester,
  ) async {
    final harness = await _pumpNovel(tester);
    await _openCreationSettings(tester);
    _go(tester, AppRoutes.projectOutline('project-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-outline-node-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('outline-title-field')),
      '发现门没有锁',
    );
    await tester.enterText(
      find.byKey(const Key('outline-summary-field')),
      '角色发现门没有锁，但仍保持警觉。',
    );
    await tester.tap(find.byKey(const Key('save-outline-node-button')));
    await tester.pumpAndSettle();

    expect(find.text('发现门没有锁'), findsOneWidget);
    expect(find.text('未开始'), findsOneWidget);
    final menu = find.byKey(const Key('outline-menu-segment-new'));
    final dynamic menuState = tester.state(menu);
    menuState.showButtonMenu();
    await tester.pumpAndSettle();
    for (final label in ['编辑', '设为当前', '标记完成', '重新设为未开始', '删除']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('设为当前'));
    await tester.pumpAndSettle();

    final nodes = await harness.container
        .read(outlineRepositoryProvider)
        .listOutlineNodes('project-1');
    expect(nodes.single.status.name, 'current');
    expect(find.text('当前'), findsOneWidget);
  });

  testWidgets('creation settings stays usable above a small-screen keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpNovel(tester);
    await _openCreationSettings(tester);

    await tester.showKeyboard(
      find.byKey(const Key('project-system-prompt-field')),
    );
    await tester.enterText(
      find.byKey(const Key('project-system-prompt-field')),
      '长篇创作规则\n${'保持叙事一致。' * 40}',
    );
    await tester.pump();

    expect(find.byKey(const Key('save-system-prompt-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('segment history is entered from the paragraph menu', (
    tester,
  ) async {
    await _pumpNovel(tester);

    await _openSegmentMenu(tester);
    await tester.ensureVisible(find.text('查看历史'));
    await tester.tap(find.text('查看历史'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('segment-history-page')), findsOneWidget);
  });

  testWidgets('360 by 800 novel workbench does not overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpNovel(tester, segments: _twoSegments);

    expect(find.byKey(const Key('novel-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long manuscript scrolls while the composer stays fixed', (
    tester,
  ) async {
    final longSegments = List.generate(
      12,
      (index) => _SegmentSeed(
        'segment-$index',
        index,
        '第 ${index + 1} 段。${'这是一段用于验证长篇连续滚动的正文。' * 5}',
      ),
    );
    await _pumpNovel(tester, segments: longSegments);

    expect(find.byKey(const Key('novel-composer')), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('continuous-manuscript-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    for (var attempt = 0; attempt < 3; attempt += 1) {
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }

    expect(
      find.byKey(const Key('continuous-segment-segment-11')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('novel-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light manuscript colors retain readable contrast', (
    tester,
  ) async {
    await _pumpNovel(tester);
    final context = tester.element(
      find.byKey(const Key('segment-preview-segment-1')),
    );
    final colors = Theme.of(context).colorScheme;

    expect(_contrastRatio(colors.onSurface, colors.surface), greaterThan(4.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('500 segments virtualize widgets while retaining the data', (
    tester,
  ) async {
    final seeds = List.generate(
      500,
      (index) => _SegmentSeed('segment-$index', index, '第 $index 段合成性能测试正文。'),
    );
    await _pumpNovel(tester, segments: seeds);

    final mountedSegments = find
        .byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('continuous-segment-');
        })
        .evaluate()
        .length;
    expect(mountedSegments, lessThan(40));
    expect(
      find.byKey(const Key('continuous-segment-segment-499')),
      findsNothing,
    );

    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('continuous-manuscript-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    for (var attempt = 0; attempt < 4; attempt += 1) {
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(
      find.byKey(const Key('continuous-segment-segment-499')),
      findsOneWidget,
    );
  });

  testWidgets(
    'primary destinations retain composer, scroll, and chat list state',
    (tester) async {
      final seeds = List.generate(
        80,
        (index) =>
            _SegmentSeed('segment-$index', index, '第 $index 段用于状态保活的正文。'),
      );
      await _pumpNovel(tester, segments: seeds);
      await tester.enterText(
        find.byKey(const Key('novel-composer-field')),
        '保留这条下一段方向',
      );
      await tester.drag(
        find.byKey(const Key('continuous-manuscript-list')),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('continuous-manuscript-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final retainedOffset = scrollable.position.pixels;
      expect(retainedOffset, greaterThan(0));

      await tester.tap(find.byKey(const Key('bottom-nav-chat')));
      await tester.pumpAndSettle();
      for (var index = 0; index < 25; index += 1) {
        await tester.tap(find.byKey(const Key('bottom-nav-novel')));
        await tester.pump(const Duration(milliseconds: 220));
        await tester.tap(find.byKey(const Key('bottom-nav-chat')));
        await tester.pump(const Duration(milliseconds: 220));
      }
      expect(find.byKey(const Key('chat-home-page')), findsOneWidget);

      await tester.tap(find.byKey(const Key('bottom-nav-novel')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const Key('novel-composer-field')),
      );
      expect(field.controller?.text, '保留这条下一段方向');
      final restoredScrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('continuous-manuscript-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(restoredScrollable.position.pixels, closeTo(retainedOffset, 0.1));
    },
  );

  testWidgets(
    'novel append preserves an older reading position and offers bottom',
    (tester) async {
      final seeds = List.generate(
        40,
        (index) => _SegmentSeed(
          'segment-$index',
          index,
          '第 $index 段。${'用于滚动稳定测试的连续正文。' * 4}',
        ),
      );
      final harness = await _pumpNovel(tester, segments: seeds);
      final list = find.byKey(const Key('continuous-manuscript-list'));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      await tester.tap(find.byKey(const Key('novel-scroll-to-bottom')));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);

      for (var index = 0; index < 2; index += 1) {
        await tester.drag(list, const Offset(0, 700));
        await tester.pumpAndSettle();
      }
      final readingOffset = scrollable.position.pixels;
      expect(readingOffset, greaterThan(0));
      expect(
        readingOffset,
        lessThan(scrollable.position.maxScrollExtent - 160),
      );

      await harness.container
          .read(segmentRepositoryProvider)
          .upsertSegment(
            Segment(
              metadata: _metadata('segment-appended'),
              projectId: 'project-1',
              orderIndex: 40,
              content: '新生成的段落。${'正文继续向前。' * 8}',
            ),
          );
      harness.container.read(repositoryRevisionsProvider.notifier).bump(const {
        RepositoryDataArea.segments,
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(scrollable.position.pixels, closeTo(readingOffset, 1));
      expect(find.byKey(const Key('novel-scroll-to-bottom')), findsOneWidget);
      expect(find.byKey(const ValueKey('segment-appended')), findsNothing);

      await tester.tap(find.byKey(const Key('novel-scroll-to-bottom')));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
      expect(find.byKey(const Key('novel-scroll-to-bottom')), findsNothing);
      expect(find.byKey(const ValueKey('segment-appended')), findsOneWidget);
    },
  );

  testWidgets('novel append follows the bottom without resetting to zero', (
    tester,
  ) async {
    final seeds = List.generate(
      24,
      (index) =>
          _SegmentSeed('segment-$index', index, '第 $index 段。${'较长正文。' * 8}'),
    );
    final harness = await _pumpNovel(tester, segments: seeds);
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('continuous-manuscript-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('novel-scroll-to-bottom')));
    await tester.pumpAndSettle();

    await harness.container
        .read(segmentRepositoryProvider)
        .upsertSegment(
          Segment(
            metadata: _metadata('segment-new-bottom'),
            projectId: 'project-1',
            orderIndex: 24,
            content: '最新正文。${'继续。' * 12}',
          ),
        );
    harness.container.read(repositoryRevisionsProvider.notifier).bump(const {
      RepositoryDataArea.segments,
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
    expect(find.byKey(const Key('novel-scroll-to-bottom')), findsNothing);
  });

  testWidgets('dark manuscript workbench builds', (tester) async {
    final harness = await _pumpNovel(tester);
    harness.container
        .read(themeModeControllerProvider.notifier)
        .setDarkMode(true);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('segment-list-page')), findsOneWidget);
    expect(find.byKey(const Key('novel-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('simple chat remains reachable after the novel correction', (
    tester,
  ) async {
    await _pumpNovel(tester);
    _go(tester, AppRoutes.chat);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-home-page')), findsOneWidget);
    expect(find.byKey(const Key('primary-bottom-navigation')), findsOneWidget);
    expect(find.text('消息'), findsNothing);
    expect(find.text('联系人'), findsNothing);
  });

  testWidgets(
    'legacy world redirects while character and remote routes remain reachable',
    (tester) async {
      await _pumpNovel(tester);

      _go(tester, AppRoutes.world);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tavern-new-story')), findsOneWidget);
      expect(find.text('你的第一个故事，从这里开始。'), findsOneWidget);

      _go(tester, AppRoutes.projectCharacters('project-1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('character-list-page')), findsOneWidget);

      _go(tester, AppRoutes.remoteConnectFor(AppWorkspaceMode.novel));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('remote-connect-page')), findsOneWidget);
    },
  );
}

Future<List<Segment>> _repositorySegments(WidgetTester tester) async {
  final scope = ProviderScope.containerOf(
    tester.element(find.byKey(const Key('segment-list-page'))),
  );
  return scope.read(segmentRepositoryProvider).listSegments('project-1');
}

const _twoSegments = [
  _SegmentSeed('segment-1', 0, '第一段正文'),
  _SegmentSeed('segment-2', 1, '第二段正文'),
];

Future<_NovelHarness> _pumpNovel(
  WidgetTester tester, {
  bool seedProject = true,
  List<_SegmentSeed> segments = const [_SegmentSeed('segment-1', 0, '第一段正文')],
  AutoStoryRunner? autoStoryRunner,
}) async {
  final store = InMemoryIbukiStore();
  final delegate = InMemorySegmentRepository(store);
  final container = ProviderContainer(
    overrides: [
      inMemoryIbukiStoreProvider.overrideWithValue(store),
      segmentRepositoryProvider.overrideWithValue(delegate),
      entityIdGeneratorProvider.overrideWithValue(
        _QueueIdGenerator(const ['segment-new', 'segment-next']),
      ),
      utcClockProvider.overrideWithValue(
        _FixedClock(DateTime.utc(2026, 8, 2, 8)),
      ),
      if (autoStoryRunner != null)
        autoStoryRunnerProvider.overrideWithValue(autoStoryRunner),
    ],
  );
  addTearDown(container.dispose);

  if (seedProject) {
    await container
        .read(projectRepositoryProvider)
        .upsertProject(
          Project(
            metadata: _metadata('project-1'),
            title: '长篇测试项目',
            description: '用于连续创作工作台测试',
          ),
        );
    for (final seed in segments) {
      await delegate.upsertSegment(
        Segment(
          metadata: _metadata(seed.id),
          projectId: 'project-1',
          orderIndex: seed.orderIndex,
          content: seed.content,
        ),
      );
    }
    container
        .read(currentProjectControllerProvider.notifier)
        .selectProject('project-1');
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const IbukiHomeApp(),
    ),
  );
  await tester.pumpAndSettle();
  _go(
    tester,
    seedProject ? AppRoutes.novelEditor('project-1') : AppRoutes.novel,
  );
  await tester.pumpAndSettle();
  return _NovelHarness(container);
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

Future<void> _openCreationSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('novel-tab-settings')));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('novel-creation-settings-entry')),
    120,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.text('创作设定'));
  await tester.pumpAndSettle();
}

EntityMetadata _metadata(String id) {
  final now = DateTime.utc(2026, 8, 2, 8);
  return EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);
}

double _contrastRatio(Color foreground, Color background) {
  final bright = foreground.computeLuminance();
  final dark = background.computeLuminance();
  final lighter = bright > dark ? bright : dark;
  final darker = bright > dark ? dark : bright;
  return (lighter + 0.05) / (darker + 0.05);
}

class _NovelHarness {
  const _NovelHarness(this.container);

  final ProviderContainer container;
}

class _SegmentSeed {
  const _SegmentSeed(this.id, this.orderIndex, this.content);

  final String id;
  final int orderIndex;
  final String content;
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
