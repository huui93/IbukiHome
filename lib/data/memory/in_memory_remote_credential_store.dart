import '../../application/remote/remote_connection_profile.dart';
import '../../application/remote/remote_credential_store.dart';

class InMemoryRemoteCredentialStore implements RemoteCredentialStore {
  RemoteConnectionProfile? _profile;

  bool get hasToken => _profile?.token.isNotEmpty ?? false;

  @override
  Future<RemoteConnectionProfile?> load() async => _profile;

  @override
  Future<void> save(RemoteConnectionProfile profile) async {
    _profile = profile;
  }

  @override
  Future<void> delete() async {
    _profile = null;
  }
}
