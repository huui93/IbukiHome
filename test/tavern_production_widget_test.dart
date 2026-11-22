import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ibukihome/app/theme/app_theme.dart';
import 'package:ibukihome/application/tavern/tavern_story_service.dart';
import 'package:ibukihome/application/tavern/tavern_execution_providers.dart';
import 'package:ibukihome/application/tavern/tavern_presentation_providers.dart';
import 'package:ibukihome/application/tavern/tavern_presentation_controller.dart';
import 'package:ibukihome/application/tavern/tavern_generation_runtime.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/domain/tavern/tavern_models.dart';
import 'package:ibukihome/features/tavern/presentation/tavern_creation_page.dart';
import 'package:ibukihome/features/tavern/presentation/tavern_story_page.dart';
import 'package:ibukihome/features/tavern/presentation/tavern_home_page.dart';
import 'package:ibukihome/features/tavern/presentation/tavern_transcript.dart';
import 'package:ibukihome/features/tavern/presentation/tavern_detail_sheets.dart';
import 'support/tavern_ui_rig.dart';

Future<void> flushSql(
  WidgetTester tester, [
  Future<void> Function()? action,
]) async {
  await tester.runAsync(() async {
    if (action != null) await action();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
}

Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 80 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 30));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
  expect(ready(), true);
}

Future<void> disposeRig(WidgetTester tester, TavernUiRig rig) async {
  final finished = Completer<void>();
  unawaited(
    rig.dispose().then(
      (_) => finished.complete(),
      onError: finished.completeError,
    ),
  );
  await pumpUntil(tester, () => finished.isCompleted);
  await finished.future;
}

Future<void> mountStory(
  WidgetTester tester,
  TavernUiRig rig,
  TavernSessionController c, {
  Size size = const Size(360, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final assets = await tester.runAsync(rig.service.loadAssets);
  final router = GoRouter(
    initialLocation: '/tavern/stories/s',
    routes: [
      GoRoute(
        path: '/tavern',
        builder: (_, _) => const Scaffold(body: Text('Tavern Lobby')),
      ),
      GoRoute(
        path: '/tavern/stories/s',
        builder: (_, _) => const TavernStoryPage(sessionId: 's'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tavernStoryServiceProvider.overrideWithValue(rig.service),
        tavernExecutionProvider.overrideWithValue(rig.env.owner),
        tavernAssetsProvider.overrideWith((ref) async => assets!),
        tavernSessionControllerProvider('s').overrideWithValue(c),
        tavernReadingStoreProvider.overrideWithValue(
          TavernReadingStore(InMemorySecureValueStore()),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await flushSql(tester);
}

void main() {
  testWidgets(
    'creation chrome stays opaque and readable under the real transparent app theme',
    (tester) async {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              tavernAssetsProvider.overrideWith(
                (_) async => const TavernAssetCatalog(
                  characters: [],
                  worlds: [],
                  personas: [],
                  books: [],
                ),
              ),
            ],
            child: MaterialApp(theme: theme, home: const TavernCreationPage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          theme.colorScheme.surface,
        );
        expect(theme.colorScheme.surface.a, 1);
        expect(
          tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
          theme.colorScheme.surface,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets('drawer world detail uses the selected real native asset', (
    tester,
  ) async {
    final rig = TavernUiRig();
    await tester.runAsync(rig.initialize);
    final c = rig.controller();
    await tester.runAsync(c.load);
    final assets = await tester.runAsync(rig.service.loadAssets);
    final session = c.projection!.session;
    final world = assets!.worlds.singleWhere(
      (w) => w.type == session.worldAssetType && w.id == session.worldAssetId,
    );
    await mountStory(tester, rig, c);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(world.name));
    await tester.pumpAndSettle();
    expect(find.text(world.description), findsOneWidget);
    expect(rig.env.sent, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await disposeRig(tester, rig);
  });
  testWidgets(
    'visible typed content preserves event position between text blocks',
    (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TavernPartsView(
              parts: [
                for (final entry in [
                  (TavernContentKind.text, 'Before'),
                  (TavernContentKind.event, 'Event'),
                  (TavernContentKind.text, 'After'),
                ].indexed)
                  TavernContentPart(
                    id: 'p-${entry.$1}',
                    alternativeId: 'a',
                    position: entry.$1,
                    kind: entry.$2.$1,
                    text: entry.$2.$2,
                    createdAt: now,
                  ),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Before')).dy,
        lessThan(tester.getTopLeft(find.text('Event')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Event')).dy,
        lessThan(tester.getTopLeft(find.text('After')).dy),
      );
    },
  );
  testWidgets(
    'regenerate previews real stream without changing selection; manual choice survives completion',
    (tester) async {
      final rig = TavernUiRig();
      await tester.runAsync(rig.initialize);
      final c = rig.controller();
      await tester.runAsync(() async {
        await c.load();
        await c.send('north');
        await c.act(
          TavernGenerationCommandKind.regenerate,
          c.projection!.turns.last,
        );
      });
      final first = c.projection!.turns.last.alternatives.first.id;
      final transport = ControlledTavernTransport();
      rig.env.clients.add(transport);
      await mountStory(tester, rig, c);
      await tester.tap(
        find.byKey(Key('tavern-turn-menu-${c.projection!.turns.last.turn.id}')),
      );
      await pumpUntil(tester, () => find.text('生成另一种回答').evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成另一种回答'));
      await pumpUntil(tester, () => transport.started.isCompleted);
      transport.text('Distinct streaming answer');
      await pumpUntil(
        tester,
        () => find.text('Distinct streaming answer').evaluate().isNotEmpty,
      );
      expect(find.text('另一种回答 · 正在生成'), findsOneWidget);
      await tester.tap(find.byTooltip('上一种回答'));
      await pumpUntil(
        tester,
        () => c.projection!.turns.last.selectedAlternative.id == first,
      );
      transport.stream.add('data: [DONE]\n\n'.codeUnits);
      await pumpUntil(
        tester,
        () =>
            !c.busy &&
            c.traces[c
                    .attempts[c.projection!.turns.last.selectedAlternative.id]!
                    .last
                    .id] !=
                null,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.projection!.turns.last.selectedAlternative.id, first);
      expect(c.projection!.turns.last.alternatives.length, 3);
      await tester.pumpWidget(const SizedBox());
      await disposeRig(tester, rig);
    },
  );
  testWidgets(
    '360 phone real scene/cast/composer, Drawer and Back return to lobby',
    (tester) async {
      final rig = TavernUiRig();
      await tester.runAsync(rig.initialize);
      final c = rig.controller();
      await tester.runAsync(c.load);
      await mountStory(tester, rig, c);
      expect(find.text('Dining Hall'), findsOneWidget);
      expect(find.text('Mira'), findsWidgets);
      expect(find.byKey(const Key('tavern-composer')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Tavern Lobby'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Tavern Lobby'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await disposeRig(tester, rig);
    },
  );
  testWidgets(
    'missing model leaves multiline draft editable and emits no request',
    (tester) async {
      final rig = TavernUiRig();
      await tester.runAsync(rig.initialize);
      await tester.runAsync(
        () => rig.service.saveSettings('s', {'tavernBindingV1': {}}),
      );
      final c = rig.controller();
      await tester.runAsync(c.load);
      await mountStory(tester, rig, c);
      await tester.enterText(
        find.byKey(const Key('tavern-composer')),
        'Keep this\nsecond line',
      );
      await tester.tap(find.byKey(const Key('tavern-send')));
      await flushSql(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('tavern-composer')))
            .controller!
            .text,
        'Keep this\nsecond line',
      );
      expect(rig.env.sent, isEmpty);
      expect(find.textContaining('选择可用的模型'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await disposeRig(tester, rig);
    },
  );
  testWidgets(
    'actual streamed parts and Stop; active leave confirmation waits then settles',
    (tester) async {
      final rig = TavernUiRig();
      await tester.runAsync(rig.initialize);
      final c = rig.controller();
      await tester.runAsync(c.load);
      final transport = ControlledTavernTransport();
      rig.env.clients.add(transport);
      await mountStory(tester, rig, c);
      await tester.enterText(
        find.byKey(const Key('tavern-composer')),
        'Hello north',
      );
      await tester.tap(find.byKey(const Key('tavern-send')));
      await pumpUntil(tester, () => transport.started.isCompleted);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.runAsync(() async {
        transport.text('A streamed reaction');
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await tester.pump(const Duration(milliseconds: 100));
      await pumpUntil(
        tester,
        () => find.text('A streamed reaction').evaluate().isNotEmpty,
      );
      expect(find.byKey(const Key('tavern-stop')), findsOneWidget);
      expect(find.text('A streamed reaction'), findsOneWidget);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('tavern-return-home')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('故事正在回应'), findsOneWidget);
      await tester.tap(find.text('继续等待'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.busy, true);
      expect(find.text('Tavern Lobby'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('停止并返回'));
      await pumpUntil(
        tester,
        () => find.text('Tavern Lobby').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(c.busy, false);
      expect(transport.closed, true);
      expect(find.text('Tavern Lobby'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await disposeRig(tester, rig);
    },
  );
  testWidgets(
    'answer controls, regenerate/continue menus, truthful Prompt/Runtime Inspector',
    (tester) async {
      final rig = TavernUiRig();
      await tester.runAsync(rig.initialize);
      final c = rig.controller();
      await tester.runAsync(() async {
        await c.load();
        await c.send('north');
        await c.act(
          TavernGenerationCommandKind.regenerate,
          c.projection!.turns.last,
        );
      });
      await mountStory(tester, rig, c);
      expect(find.text('回答 2 / 2'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('上一种回答'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('回答 1 / 2'), findsOneWidget);
      final row = c.projection!.turns.last;
      await tester.runAsync(() async {
        await tester.tap(find.byKey(Key('tavern-turn-menu-${row.turn.id}')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('生成另一种回答'), findsOneWidget);
      expect(find.text('续写当前回答'), findsOneWidget);
      await tester.tap(find.text('查看本轮详情'));
      await pumpUntil(tester, () => find.text('Prompt').evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      expect(find.text('Prompt'), findsOneWidget);
      expect(find.textContaining('世界书候选'), findsOneWidget);
      await tester.tap(find.text('Runtime'));
      await tester.pumpAndSettle();
      expect(find.textContaining('completed'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await disposeRig(tester, rig);
    },
  );
  testWidgets('historical inspector explicitly unavailable, never recompiles', (
    tester,
  ) async {
    final rig = TavernUiRig();
    await tester.runAsync(rig.initialize);
    final c = rig.controller();
    await tester.runAsync(() async {
      await c.load();
      await c.send('north');
    });
    final clean = TavernSessionController(
      sessionId: 's',
      service: rig.service,
      owner: rig.env.owner,
      traces: TavernTraceCache(),
    );
    rig.controllers.add(clean);
    await tester.runAsync(clean.load);
    await mountStory(tester, rig, clean);
    await tester.runAsync(() async {
      unawaited(
        showTavernInspector(
          tester.element(find.byType(TavernStoryPage)),
          clean,
          clean.projection!.turns.last,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('原始 Prompt Trace 不可用'), findsOneWidget);
    expect(rig.env.sent.length, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(rig.dispose);
  });
  testWidgets(
    'typed multipart distinguishes narrator, dialogue, summary and unavailable reasoning',
    (tester) async {
      final now = DateTime.now();
      final parts = [
        for (final kind in [
          TavernContentKind.text,
          TavernContentKind.reasoning,
          TavernContentKind.reasoningSummary,
          TavernContentKind.reasoningUnavailable,
        ])
          TavernContentPart(
            id: kind.name,
            alternativeId: 'a',
            position: kind.index,
            kind: kind,
            text: kind == TavernContentKind.text
                ? 'Visible dialogue'
                : 'Hidden ${kind.name}',
            createdAt: now,
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TavernPartsView(parts: parts, narrator: true)),
        ),
      );
      expect(find.text('Visible dialogue'), findsOneWidget);
      expect(find.text('Hidden reasoning'), findsNothing);
      await tester.tap(find.text('推理信息'));
      await tester.pumpAndSettle();
      expect(find.text('模型原生推理'), findsOneWidget);
      expect(find.text('模型推理摘要'), findsOneWidget);
      expect(find.text('推理不可用'), findsOneWidget);
    },
  );
  testWidgets(
    'real three-step creation saves native asset references and no fake Session',
    (tester) async {
      final rig = TavernUiRig();
      await tester.runAsync(rig.initialize);
      final assets = await tester.runAsync(rig.service.loadAssets);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const TavernCreationPage()),
          GoRoute(
            path: '/tavern/stories/:id',
            builder: (_, _) => const Scaffold(body: Text('Saved Session')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tavernStoryServiceProvider.overrideWithValue(rig.service),
            tavernAssetsProvider.overrideWith((_) async => assets!),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('tavern-story-title')),
        'New Story',
      );
      await tester.tap(find.text('Player'));
      await tester.tap(find.byKey(const Key('tavern-create-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mira'));
      await tester.tap(find.byKey(const Key('tavern-create-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tavern-create-next')));
      await pumpUntil(
        tester,
        () => find.text('Saved Session').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved Session'), findsOneWidget);
      final sessions = await tester.runAsync(rig.repo.listSessions);
      expect(sessions!.length, 2);
      final saved = sessions.firstWhere((s) => s.title == 'New Story');
      expect(saved.personaId, 'persona');
      final participants = await tester.runAsync(
        () => rig.repo.listParticipants(saved.id),
      );
      expect(participants!.last.entityId, 'character');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(rig.dispose);
    },
  );
  testWidgets('home real story excerpt and empty state; no demo content', (
    tester,
  ) async {
    final rig = TavernUiRig();
    await tester.runAsync(rig.initialize);
    final summaries = await tester.runAsync(rig.repo.listStorySummaries);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tavernStoriesProvider(false).overrideWith((_) async => summaries!),
        ],
        child: const MaterialApp(home: Scaffold(body: TavernHomePage())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Real Foundation fixture'), findsOneWidget);
    expect(find.text('新建故事'), findsOneWidget);
    expect(find.text('Mira'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(rig.dispose);
  });
}
