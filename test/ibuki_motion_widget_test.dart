import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_router.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/app/theme/ibuki_motion.dart';
import 'package:ibukihome/app/widgets/ibuki_motion_widgets.dart';
import 'package:ibukihome/application/ai/ai_settings_controller.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/data/memory/in_memory_secure_value_store.dart';
import 'package:ibukihome/domain/chat/chat_message.dart';
import 'package:ibukihome/domain/chat/chat_message_role.dart';
import 'package:ibukihome/domain/chat/chat_persona.dart';
import 'package:ibukihome/domain/chat/chat_session.dart';
import 'package:ibukihome/domain/common/entity_metadata.dart';
import 'package:ibukihome/features/shell/presentation/animated_workspace_container.dart';

void main() {
  testWidgets('workspace transitions retain drafts and scroll positions', (
    tester,
  ) async {
    final index = ValueNotifier(0);
    addTearDown(index.dispose);
    await tester.pumpWidget(_harness(index));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('draft-0')), '未保存的草稿');
    await tester.drag(find.byKey(const Key('list-0')), const Offset(0, -240));
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('list-0')),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;
    index.value = 1;
    await tester.pumpAndSettle();
    index.value = 0;
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('draft-0')))
          .controller!
          .text,
      '未保存的草稿',
    );
    final after = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('list-0')),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;
    expect(after, before);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'outgoing workspace cannot keep focus, receive taps or expose semantics',
    (tester) async {
      final index = ValueNotifier(0);
      addTearDown(index.dispose);
      final taps = [0, 0, 0];
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_harness(index, taps: taps));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('draft-0')));
        await tester.pump();
        index.value = 1;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final outgoingField = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(const Key('draft-0')),
            matching: find.byType(EditableText),
          ),
        );
        expect(outgoingField.focusNode.hasFocus, isFalse);
        await tester.tapAt(
          tester.getCenter(find.byKey(const Key('branch-action-1'))),
        );
        await tester.pump();
        expect(taps[0], 0);
        expect(taps[1], 1);
        final labels = tester.semantics
            .simulatedAccessibilityTraversal()
            .map((node) => node.label)
            .toList();
        expect(labels, isNot(contains('操作页面 0')));
        expect(labels, contains('操作页面 1'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets(
    'rapid workspace retargeting completes without remounting branches or idle tickers',
    (tester) async {
      final index = ValueNotifier(0);
      addTearDown(index.dispose);
      await tester.pumpWidget(_harness(index));
      await tester.pumpAndSettle();
      final original = tester.state(find.byKey(const ValueKey('branch-0')));
      for (final next in [1, 2, 0, 2, 1, 0]) {
        index.value = next;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 55));
      }
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byKey(const ValueKey('branch-0'))),
        same(original),
      );
      expect(find.byKey(const Key('draft-1')), findsNothing);
      expect(find.byKey(const Key('draft-2')), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
  for (final accessible in [false, true]) {
    testWidgets(
      '${accessible ? 'accessible navigation' : 'reduced motion'} settles workspace and entrance immediately',
      (tester) async {
        final index = ValueNotifier(0);
        addTearDown(index.dispose);
        await tester.pumpWidget(
          _harness(index, reduced: !accessible, accessible: accessible),
        );
        await tester.pump();
        index.value = 2;
        await tester.pump();
        expect(find.byKey(const Key('draft-2')), findsOneWidget);
        expect(find.byKey(const Key('draft-0')), findsNothing);
        expect(_opacity(tester, find.byKey(const ValueKey('branch-2'))), 1);
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }
  testWidgets('entrances finish once and content rebuilds do not replay them', (
    tester,
  ) async {
    final text = ValueNotifier('初始');
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: text,
          builder: (_, value, _) => IbukiEntrance(
            key: const Key('entrance'),
            order: 3,
            child: Text(value),
          ),
        ),
      ),
    );
    expect(_opacity(tester, find.text('初始')), 0);
    await tester.pumpAndSettle();
    expect(_opacity(tester, find.text('初始')), 1);
    text.value = '流式内容更新';
    await tester.pump();
    expect(_opacity(tester, find.text('流式内容更新')), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets(
    'press feedback preserves bounds and dragging cancels the visual press',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: IbukiPressMotion(
              key: const Key('press'),
              child: GestureDetector(
                onTap: () => taps++,
                child: const ColoredBox(
                  color: Colors.blue,
                  child: SizedBox(width: 180, height: 60),
                ),
              ),
            ),
          ),
        ),
      );
      final finder = find.byKey(const Key('press'));
      final rect = tester.getRect(finder);
      final gesture = await tester.startGesture(rect.center);
      await tester.pump();
      await tester.pump(IbukiMotion.press);
      expect(tester.getRect(finder), rect);
      final transform = tester.widget<Transform>(
        find.descendant(of: finder, matching: find.byType(Transform)).first,
      );
      expect(transform.transform.storage[0], lessThan(1));
      expect(transform.transformHitTests, isFalse);
      await gesture.moveBy(const Offset(0, 30));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(
        tester
            .widget<Transform>(
              find
                  .descendant(of: finder, matching: find.byType(Transform))
                  .first,
            )
            .transform
            .storage[0],
        1,
      );
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(taps, 1);
    },
  );
  testWidgets(
    'disabled press motion and reduced motion never shrink controls',
    (tester) async {
      for (final reduced in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Center(
                child: IbukiPressMotion(
                  enabled: reduced,
                  child: const SizedBox(width: 100, height: 60),
                ),
              ),
            ),
          ),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(IbukiPressMotion)),
        );
        await tester.pump(IbukiMotion.press);
        final transform = tester.widget<Transform>(
          find
              .descendant(
                of: find.byType(IbukiPressMotion),
                matching: find.byType(Transform),
              )
              .first,
        );
        expect(transform.transform.storage[0], 1);
        await gesture.up();
        await tester.pumpAndSettle();
      }
    },
  );
  testWidgets(
    'real router handles rapid wheel changes and still opens and pops settings pages',
    (tester) async {
      final c = ProviderContainer(
        overrides: [
          aiSecureValueStoreProvider.overrideWithValue(
            InMemorySecureValueStore(),
          ),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const IbukiHomeApp()),
      );
      await tester.pumpAndSettle();
      final router = c.read(appRouterProvider);
      for (final route in [
        AppRoutes.settings,
        AppRoutes.novel,
        AppRoutes.chat,
        AppRoutes.settings,
      ]) {
        router.go(route);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 65));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-page')), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-personal-profile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('personal-profile-page')), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-page')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'opening old messages is static and newly appended messages enter only once',
    (tester) async {
      final c = ProviderContainer(
        overrides: [
          aiSecureValueStoreProvider.overrideWithValue(
            InMemorySecureValueStore(),
          ),
        ],
      );
      addTearDown(c.dispose);
      final now = DateTime.utc(2026, 11, 21);
      EntityMetadata meta(String id) =>
          EntityMetadata(id: id, createdAt: now, updatedAt: now, revision: 1);
      await c
          .read(chatPersonaRepositoryProvider)
          .upsertPersona(
            ChatPersona(
              metadata: meta('p'),
              name: '人格',
              descriptionMode: ChatPersonaDescriptionMode.simple,
              shortDescription: '',
              speakingStyle: '',
            ),
          );
      final chats = c.read(chatRepositoryProvider);
      await chats.upsertSession(
        ChatSession(
          metadata: meta('s'),
          personaId: 'p',
          projectId: null,
          title: '会话',
        ),
      );
      await chats.appendMessage(
        ChatMessage(
          metadata: meta('old'),
          sessionId: 's',
          projectId: null,
          role: ChatMessageRole.user,
          content: '历史消息',
        ),
      );
      c.read(appRouterProvider).go(AppRoutes.chatSession('s'));
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const IbukiHomeApp()),
      );
      await tester.pumpAndSettle();
      expect(_opacity(tester, find.byKey(const ValueKey('old'))), 1);
      await chats.appendMessage(
        ChatMessage(
          metadata: meta(
            'new',
          ).copyWith(createdAt: now.add(const Duration(seconds: 1))),
          sessionId: 's',
          projectId: null,
          role: ChatMessageRole.user,
          content: '新消息',
        ),
      );
      c.read(repositoryRevisionsProvider.notifier).bump(const [
        RepositoryDataArea.chatMessages,
      ]);
      for (
        var i = 0;
        i < 10 && find.byKey(const ValueKey('new')).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(_opacity(tester, find.byKey(const ValueKey('new'))), lessThan(1));
      expect(_opacity(tester, find.byKey(const ValueKey('old'))), 1);
      await tester.pumpAndSettle();
      c.read(repositoryRevisionsProvider.notifier).bump(const [
        RepositoryDataArea.chatMessages,
      ]);
      await tester.pump();
      await tester.pump();
      expect(_opacity(tester, find.byKey(const ValueKey('new'))), 1);
      expect(tester.takeException(), isNull);
    },
  );
}

double _opacity(WidgetTester tester, Finder target) {
  final descendant = find.descendant(
    of: target,
    matching: find.byType(Opacity),
  );
  if (descendant.evaluate().isNotEmpty) {
    return tester.widget<Opacity>(descendant.first).opacity;
  }
  return tester
      .widgetList<Opacity>(
        find.ancestor(of: target, matching: find.byType(Opacity)),
      )
      .first
      .opacity;
}

Widget _harness(
  ValueNotifier<int> index, {
  bool reduced = false,
  bool accessible = false,
  List<int>? taps,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: reduced,
      accessibleNavigation: accessible,
    ),
    child: Scaffold(
      body: ValueListenableBuilder(
        valueListenable: index,
        builder: (context, current, _) => AnimatedWorkspaceContainer(
          currentIndex: current,
          children: [
            for (var i = 0; i < 3; i++)
              _Branch(
                key: ValueKey('branch-$i'),
                index: i,
                onTap: () {
                  if (taps != null) taps[i]++;
                },
              ),
          ],
        ),
      ),
    ),
  ),
);

class _Branch extends StatefulWidget {
  const _Branch({required this.index, required this.onTap, super.key});
  final int index;
  final VoidCallback onTap;
  @override
  State<_Branch> createState() => _BranchState();
}

class _BranchState extends State<_Branch> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(key: Key('draft-${widget.index}'), controller: controller),
      TextButton(
        key: Key('branch-action-${widget.index}'),
        onPressed: widget.onTap,
        child: Text('操作页面 ${widget.index}'),
      ),
      Expanded(
        child: ListView(
          key: Key('list-${widget.index}'),
          children: [
            for (var i = 0; i < 50; i++)
              SizedBox(height: 50, child: Text('段落 $i')),
          ],
        ),
      ),
    ],
  );
}
