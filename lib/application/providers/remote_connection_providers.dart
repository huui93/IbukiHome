import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../application/common/utc_clock.dart';
import '../../application/remote/remote_connection_profile.dart';
import '../../application/remote/remote_credential_store.dart';
import '../../core/network/remote_api_config.dart';
import '../../data/remote/http_remote_ibuki_api.dart';
import '../../data/remote/remote_ibuki_api.dart';
import '../../data/secure/secure_remote_credential_store.dart';

final remoteUtcClockProvider = Provider<UtcClock>((ref) {
  return const UtcClock();
});

final remoteCredentialStoreProvider = Provider<RemoteCredentialStore>((ref) {
  return const SecureRemoteCredentialStore(FlutterSecureStorage());
});

final remoteIbukiApiFactoryProvider =
    Provider<RemoteIbukiApi Function(RemoteConnectionProfile)>((ref) {
      return (profile) {
        return HttpRemoteIbukiApi.withDefaultClient(
          config: RemoteApiConfig(
            baseUri: profile.baseUri,
            bearerToken: profile.token,
          ),
        );
      };
    });
