import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_router.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/world_roleplay/world_roleplay_providers.dart';

void main() {
  for (final path in [
    '/world',
    '/world/new',
    '/world/projects',
    '/world/old-world/setup?session=old-session',
    '/world/sessions/old-session',
    '/world/sessions/old-session/lore',
  ]) {
    testWidgets('retired $path returns to Tavern without creating data', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const IbukiHomeApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = container.read(appRouterProvider);
      router.go(path);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.tavern);
      expect(find.byKey(const Key('tavern-new-story')), findsOneWidget);
      expect(find.byKey(const Key('world-unavailable')), findsNothing);
      expect(find.byKey(const Key('primary-bottom-navigation')), findsNothing);
      expect(
        await container.read(worldRoleplayRepositoryProvider).listWorlds(),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'three primary tabs emphasize chat and retain Tavern under settings',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const IbukiHomeApp(),
        ),
      );
      await tester.pumpAndSettle();
      for (final name in ['novel', 'chat', 'settings']) {
        expect(find.byKey(Key('bottom-nav-$name')), findsOneWidget);
      }
      expect(find.byKey(const Key('bottom-nav-world')), findsNothing);
      expect(find.byKey(const Key('bottom-nav-tavern')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '聊天，主系统',
        ),
        findsOneWidget,
      );
      final bar = find.byKey(const Key('primary-bottom-navigation'));
      final centerX = tester.getCenter(bar).dx;
      expect(
        tester.getCenter(find.byKey(const Key('bottom-nav-chat'))).dx,
        closeTo(centerX, 0.1),
      );
      await tester.tap(find.byKey(const Key('bottom-nav-novel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(
        (tester.getCenter(find.byKey(const Key('bottom-nav-novel'))).dx -
                centerX)
            .abs(),
        greaterThan(1),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byKey(const Key('bottom-nav-novel'))).dx,
        closeTo(centerX, 0.1),
      );
      await tester.tap(find.byKey(const Key('bottom-nav-chat')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-home-page')), findsOneWidget);
      await tester.tap(find.byKey(const Key('bottom-nav-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-tavern')), findsNothing);
      GoRouter.of(
        tester.element(find.byKey(const Key('settings-page'))),
      ).push(AppRoutes.tavern);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tavern-new-story')), findsOneWidget);
      await tester.tap(find.byKey(const Key('shell-back-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-page')), findsOneWidget);
      expect(find.byKey(const Key('bottom-nav-selected-设置')), findsOneWidget);
    },
  );
}
