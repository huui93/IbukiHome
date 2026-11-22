import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/application/common/utc_clock.dart';
import 'package:ibukihome/application/providers/remote_connection_providers.dart';
import 'package:ibukihome/application/remote/remote_connection_controller.dart';
import 'package:ibukihome/application/remote/remote_connection_profile.dart';
import 'package:ibukihome/application/remote/remote_connection_state.dart';
import 'package:ibukihome/core/network/api_client_exceptions.dart';
import 'package:ibukihome/data/memory/in_memory_remote_credential_store.dart';

import '../helpers/fake_remote_api.dart';

void main() {
  group('Remote credentials', () {
    test('Token is saved through CredentialStore', () async {
      final store = InMemoryRemoteCredentialStore();
      await store.save(_profile(token: 'token-one'));

      expect((await store.load())?.token, 'token-one');
      expect(store.hasToken, isTrue);
    });

    test('disconnect deletes Token', () async {
      final store = InMemoryRemoteCredentialStore();
      final fake = FakeRemoteIbukiApi();
      final container = _container(store: store, fake: fake);
      addTearDown(container.dispose);

      await container
          .read(remoteConnectionControllerProvider.notifier)
          .saveConnection(address: 'http://127.0.0.1:8765', token: 'token-two');
      await container
          .read(remoteConnectionControllerProvider.notifier)
          .disconnect();

      expect(await store.load(), isNull);
      expect(store.hasToken, isFalse);
    });

    test('Token does not enter connection error text', () async {
      final fake = FakeRemoteIbukiApi()
        ..capabilitiesError = const RemoteAuthException('bad');
      final container = _container(fake: fake);
      addTearDown(container.dispose);

      await container
          .read(remoteConnectionControllerProvider.notifier)
          .testConnection(
            address: 'http://127.0.0.1:8765',
            token: 'token-should-not-appear',
          );

      expect(
        container.read(remoteConnectionControllerProvider).message,
        isNot(contains('token-should-not-appear')),
      );
    });

    test('tests can use in-memory credential store', () async {
      final store = InMemoryRemoteCredentialStore();
      await store.save(_profile(token: 'memory-token'));
      expect((await store.load())?.baseUri.host, '127.0.0.1');
    });

    test('ordinary connection state does not expose plain Token', () async {
      final container = _container(fake: FakeRemoteIbukiApi());
      addTearDown(container.dispose);

      await container
          .read(remoteConnectionControllerProvider.notifier)
          .saveConnection(
            address: 'http://127.0.0.1:8765',
            token: 'plain-token',
          );

      expect(
        container.read(remoteConnectionControllerProvider).toString(),
        isNot(contains('plain-token')),
      );
    });
  });

  group('Remote address validation', () {
    test('HTTP address is accepted', () {
      expect(normalizeRemoteBaseUri('http://192.168.1.10:8765').scheme, 'http');
    });

    test('HTTPS address is accepted', () {
      expect(normalizeRemoteBaseUri('https://example.local').scheme, 'https');
    });

    test('address without host fails', () {
      expect(
        () => normalizeRemoteBaseUri('http:///missing'),
        throwsA(isA<InvalidRemoteAddressException>()),
      );
    });

    test('file scheme fails', () {
      expect(
        () => normalizeRemoteBaseUri('file:///tmp/project'),
        throwsA(isA<InvalidRemoteAddressException>()),
      );
    });

    test('embedded username and password fail', () {
      expect(
        () => normalizeRemoteBaseUri('http://user:pass@127.0.0.1:8765'),
        throwsA(isA<InvalidRemoteAddressException>()),
      );
    });

    test('trailing slash is normalized', () {
      expect(
        normalizeRemoteBaseUri('http://127.0.0.1:8765///').toString(),
        'http://127.0.0.1:8765',
      );
    });

    test('10.0.2.2 is accepted as normal input', () {
      expect(normalizeRemoteBaseUri('http://10.0.2.2:8765').host, '10.0.2.2');
    });
  });

  group('Remote handshake', () {
    test('health and capabilities success connect', () async {
      final container = _container(fake: FakeRemoteIbukiApi());
      addTearDown(container.dispose);

      final ok = await container
          .read(remoteConnectionControllerProvider.notifier)
          .testConnection(address: 'http://127.0.0.1:8765', token: 'good');

      expect(ok, isTrue);
      expect(
        container.read(remoteConnectionControllerProvider).status,
        RemoteConnectionStatus.connected,
      );
    });

    test('health success but wrong Token does not connect', () async {
      final fake = FakeRemoteIbukiApi()
        ..capabilitiesError = const RemoteAuthException('bad');
      final container = _container(fake: fake);
      addTearDown(container.dispose);

      await container
          .read(remoteConnectionControllerProvider.notifier)
          .testConnection(address: 'http://127.0.0.1:8765', token: 'bad');

      expect(
        container.read(remoteConnectionControllerProvider).status,
        RemoteConnectionStatus.unauthorized,
      );
    });

    test('API version mismatch is incompatible', () async {
      final fake = FakeRemoteIbukiApi()..healthApiVersion = 2;
      final container = _container(fake: fake);
      addTearDown(container.dispose);

      await container
          .read(remoteConnectionControllerProvider.notifier)
          .testConnection(address: 'http://127.0.0.1:8765', token: 'good');

      expect(
        container.read(remoteConnectionControllerProvider).status,
        RemoteConnectionStatus.incompatible,
      );
    });

    test('supportsProjects false does not connect', () async {
      final fake = FakeRemoteIbukiApi()..supportsProjects = false;
      final container = _container(fake: fake);
      addTearDown(container.dispose);

      await container
          .read(remoteConnectionControllerProvider.notifier)
          .testConnection(address: 'http://127.0.0.1:8765', token: 'good');

      expect(
        container.read(remoteConnectionControllerProvider).status,
        RemoteConnectionStatus.incompatible,
      );
    });

    test('supportsSegments false does not connect', () async {
      final fake = FakeRemoteIbukiApi()..supportsSegments = false;
      final container = _container(fake: fake);
      addTearDown(container.dispose);

      await container
          .read(remoteConnectionControllerProvider.notifier)
          .testConnection(address: 'http://127.0.0.1:8765', token: 'good');

      expect(
        container.read(remoteConnectionControllerProvider).status,
        RemoteConnectionStatus.incompatible,
      );
    });

    test('supportsWrite true is rejected', () async {
      final fake = FakeRemoteIbukiApi()..supportsWrite = true;
      final container = _container(fake: fake);
      addTearDown(container.dispose);

      await container
          .read(remoteConnectionControllerProvider.notifier)
          .testConnection(address: 'http://127.0.0.1:8765', token: 'good');

      expect(
        container.read(remoteConnectionControllerProvider).status,
        RemoteConnectionStatus.incompatible,
      );
    });

    test('timeout maps to unreachable', () async {
      final fake = FakeRemoteIbukiApi()
        ..healthError = const RemoteNetworkException('timeout');
      final container = _container(fake: fake);
      addTearDown(container.dispose);

      await container
          .read(remoteConnectionControllerProvider.notifier)
          .testConnection(address: 'http://127.0.0.1:8765', token: 'good');

      expect(
        container.read(remoteConnectionControllerProvider).status,
        RemoteConnectionStatus.unreachable,
      );
    });

    test('protocol failure maps to error', () async {
      final fake = FakeRemoteIbukiApi()
        ..healthError = const RemoteProtocolException('not json');
      final container = _container(fake: fake);
      addTearDown(container.dispose);

      await container
          .read(remoteConnectionControllerProvider.notifier)
          .testConnection(address: 'http://127.0.0.1:8765', token: 'good');

      expect(
        container.read(remoteConnectionControllerProvider).status,
        RemoteConnectionStatus.error,
      );
    });
  });
}

ProviderContainer _container({
  InMemoryRemoteCredentialStore? store,
  required FakeRemoteIbukiApi fake,
}) {
  return ProviderContainer(
    overrides: [
      remoteCredentialStoreProvider.overrideWithValue(
        store ?? InMemoryRemoteCredentialStore(),
      ),
      remoteIbukiApiFactoryProvider.overrideWithValue((_) => fake),
      remoteUtcClockProvider.overrideWithValue(
        _FixedClock(DateTime.utc(2026, 7, 29, 9)),
      ),
    ],
  );
}

RemoteConnectionProfile _profile({required String token}) {
  return RemoteConnectionProfile(
    baseUri: Uri.parse('http://127.0.0.1:8765'),
    token: token,
    lastVerifiedAtUtc: DateTime.utc(2026, 7, 29, 9),
    apiVersion: 1,
  );
}

class _FixedClock extends UtcClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}
