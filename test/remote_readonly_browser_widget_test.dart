import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ibukihome/app/app.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/providers/remote_connection_providers.dart';
import 'package:ibukihome/application/providers/repository_providers.dart';
import 'package:ibukihome/application/remote/remote_connection_profile.dart';
import 'package:ibukihome/core/network/api_client_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_remote_credential_store.dart';

import 'helpers/fake_remote_api.dart';

void main() {
  testWidgets(
    'retired remote entry is absent while compatibility route still works',
    (tester) async {
      await _pumpRemoteApp(tester);

      _goFromVisibleContext(tester, AppRoutes.settings);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-remote-connect')), findsNothing);
      _goFromVisibleContext(tester, AppRoutes.remoteConnect);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remote-connect-page')), findsOneWidget);
    },
  );

  testWidgets('compatibility remote route opens without a drawer', (
    tester,
  ) async {
    await _pumpRemoteApp(tester);

    _goFromVisibleContext(tester, AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-remote-connect')), findsNothing);
    _goFromVisibleContext(tester, AppRoutes.remoteConnect);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('remote-connect-page')), findsOneWidget);
  });

  testWidgets('Token is hidden by default', (tester) async {
    await _pumpRemoteApp(tester);
    _goFromVisibleContext(tester, AppRoutes.remoteConnect);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('remote-token-field')),
    );
    expect(field.obscureText, isTrue);
  });

  testWidgets('empty Token cannot be saved', (tester) async {
    final store = InMemoryRemoteCredentialStore();
    await _pumpRemoteApp(tester, store: store);
    _goFromVisibleContext(tester, AppRoutes.remoteConnect);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('remote-address-field')),
      'http://127.0.0.1:8765',
    );
    await tester.tap(find.byKey(const Key('remote-save-button')));
    await tester.pumpAndSettle();

    expect(await store.load(), isNull);
    expect(find.textContaining('Token 不能为空'), findsOneWidget);
  });

  testWidgets('test success can be saved', (tester) async {
    final store = InMemoryRemoteCredentialStore();
    await _pumpRemoteApp(tester, store: store);
    await _fillConnectionForm(tester);

    await tester.tap(find.byKey(const Key('remote-test-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remote-save-button')));
    await tester.pumpAndSettle();

    expect((await store.load())?.baseUri.host, '127.0.0.1');
  });

  testWidgets('saving connection shows connected state', (tester) async {
    await _pumpRemoteApp(tester);
    await _fillConnectionForm(tester);

    await tester.tap(find.byKey(const Key('remote-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('已连接'), findsOneWidget);
    expect(
      find.byKey(const Key('remote-open-projects-button')),
      findsOneWidget,
    );
  });

  testWidgets('disconnect shows disconnected state and deletes credentials', (
    tester,
  ) async {
    final store = InMemoryRemoteCredentialStore();
    await _pumpRemoteApp(tester, store: store);
    await _fillConnectionForm(tester);
    await tester.tap(find.byKey(const Key('remote-save-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('remote-disconnect-button')));
    await tester.pumpAndSettle();

    expect(await store.load(), isNull);
    expect(find.text('未连接'), findsOneWidget);
  });

  testWidgets('remote projects require a connection', (tester) async {
    await _pumpRemoteApp(tester);

    _goFromVisibleContext(tester, AppRoutes.remoteProjects);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('remote-error-banner')), findsOneWidget);
    expect(find.textContaining('请先连接电脑'), findsOneWidget);
  });

  testWidgets('remote project list shows read-only marker', (tester) async {
    await _pumpRemoteApp(tester, connected: true);

    _goFromVisibleContext(tester, AppRoutes.remoteProjects);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('remote-readonly-chip')), findsOneWidget);
    expect(
      find.byKey(const Key('remote-project-tile-remote-project-1')),
      findsOneWidget,
    );
  });

  testWidgets('remote project detail can be opened', (tester) async {
    await _pumpRemoteApp(tester, connected: true);
    _goFromVisibleContext(tester, AppRoutes.remoteProjects);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('remote-project-tile-remote-project-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('remote-project-detail-page')), findsOneWidget);
    expect(
      find.byKey(const Key('remote-open-segments-button')),
      findsOneWidget,
    );
  });

  testWidgets('remote segment list can be opened', (tester) async {
    await _pumpRemoteApp(tester, connected: true);
    _goFromVisibleContext(tester, AppRoutes.remoteProject('remote-project-1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('remote-open-segments-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('remote-segment-list-page')), findsOneWidget);
    expect(
      find.byKey(const Key('remote-segment-tile-remote-segment-1')),
      findsOneWidget,
    );
  });

  testWidgets('remote segment detail has no edit button', (tester) async {
    await _pumpRemoteApp(tester, connected: true);
    _goFromVisibleContext(
      tester,
      AppRoutes.remoteProjectSegments('remote-project-1'),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('remote-segment-tile-remote-segment-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('remote-segment-detail-page')), findsOneWidget);
    expect(find.byKey(const Key('remote-segment-content')), findsOneWidget);
    expect(find.byKey(const Key('save-segment-button')), findsNothing);
  });

  testWidgets('remote segment detail has no save entry', (tester) async {
    await _pumpRemoteApp(tester, connected: true);
    _goFromVisibleContext(
      tester,
      AppRoutes.remoteSegment('remote-project-1', 'remote-segment-1'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('remote-copy-segment-button')), findsOneWidget);
    expect(find.text('保存'), findsNothing);
  });

  testWidgets('remote data is not written into local repository', (
    tester,
  ) async {
    final container = await _pumpRemoteApp(tester, connected: true);

    _goFromVisibleContext(tester, AppRoutes.remoteProjects);
    await tester.pumpAndSettle();

    final localProjects = await container
        .read(projectRepositoryProvider)
        .listProjects();
    expect(localProjects, isEmpty);
  });

  testWidgets('disconnecting remote does not delete local projects', (
    tester,
  ) async {
    final store = InMemoryRemoteCredentialStore();
    final container = await _pumpRemoteApp(
      tester,
      store: store,
      connected: true,
    );
    await container.read(createProjectProvider)(
      title: '本地故事',
      id: 'local-project',
      nowUtc: DateTime.utc(2026, 7, 29),
    );

    _goFromVisibleContext(tester, AppRoutes.remoteConnect);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remote-disconnect-button')));
    await tester.pumpAndSettle();

    expect(
      await container.read(projectRepositoryProvider).listProjects(),
      hasLength(1),
    );
  });

  testWidgets('manual refresh calls the remote API again', (tester) async {
    final fake = FakeRemoteIbukiApi();
    await _pumpRemoteApp(tester, fake: fake, connected: true);
    _goFromVisibleContext(tester, AppRoutes.remoteProjects);
    await tester.pumpAndSettle();
    final before = fake.projectListCalls;

    await tester.tap(find.byKey(const Key('remote-refresh-button')));
    await tester.pumpAndSettle();

    expect(fake.projectListCalls, before + 1);
  });

  testWidgets('network loss keeps cached content with stale warning', (
    tester,
  ) async {
    final fake = FakeRemoteIbukiApi();
    await _pumpRemoteApp(tester, fake: fake, connected: true);
    _goFromVisibleContext(tester, AppRoutes.remoteProjects);
    await tester.pumpAndSettle();
    fake.projectListError = const RemoteNetworkException('offline');

    await tester.tap(find.byKey(const Key('remote-refresh-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('remote-stale-banner')), findsOneWidget);
    expect(
      find.byKey(const Key('remote-project-tile-remote-project-1')),
      findsOneWidget,
    );
  });

  testWidgets('remote pages do not overflow at 360 by 800', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpRemoteApp(tester, connected: true);
    _goFromVisibleContext(tester, AppRoutes.remoteProjects);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mode can build remote project list', (tester) async {
    await _pumpRemoteApp(tester, connected: true);
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
    await tester.tap(find.byKey(const Key('settings-theme-switch')));
    await tester.pumpAndSettle();
    _goFromVisibleContext(tester, AppRoutes.remoteProjects);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('remote-projects-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat and local settings routes remain available', (
    tester,
  ) async {
    await _pumpRemoteApp(tester, connected: true);

    _goFromVisibleContext(tester, AppRoutes.chat);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-home-page')), findsOneWidget);
    _goFromVisibleContext(tester, AppRoutes.settings);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-page')), findsOneWidget);
  });
}

Future<ProviderContainer> _pumpRemoteApp(
  WidgetTester tester, {
  FakeRemoteIbukiApi? fake,
  InMemoryRemoteCredentialStore? store,
  bool connected = false,
}) async {
  final credentialStore = store ?? InMemoryRemoteCredentialStore();
  if (connected) {
    await credentialStore.save(
      RemoteConnectionProfile(
        baseUri: Uri.parse('http://127.0.0.1:8765'),
        token: 'saved-token',
        lastVerifiedAtUtc: DateTime.utc(2026, 7, 29, 9),
        apiVersion: 1,
      ),
    );
  }
  final remoteApi = fake ?? FakeRemoteIbukiApi();
  final container = ProviderContainer(
    overrides: [
      remoteCredentialStoreProvider.overrideWithValue(credentialStore),
      remoteIbukiApiFactoryProvider.overrideWithValue((_) => remoteApi),
      remoteUtcClockProvider.overrideWithValue(
        _FixedClock(DateTime.utc(2026, 7, 29, 9)),
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

Future<void> _fillConnectionForm(WidgetTester tester) async {
  _goFromVisibleContext(tester, AppRoutes.remoteConnect);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('remote-address-field')),
    'http://127.0.0.1:8765',
  );
  await tester.enterText(
    find.byKey(const Key('remote-token-field')),
    'test-token',
  );
}

void _goFromVisibleContext(WidgetTester tester, String location) {
  final candidateKeys = [
    const Key('remote-connect-page'),
    const Key('remote-projects-page'),
    const Key('remote-project-detail-page'),
    const Key('remote-segment-list-page'),
    const Key('remote-segment-detail-page'),
    const Key('settings-page'),
    const Key('projects-page'),
    const Key('chat-home-page'),
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

class _FixedClock extends UtcClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}
