import 'remote_connection_profile.dart';

abstract class RemoteCredentialStore {
  Future<RemoteConnectionProfile?> load();

  Future<void> save(RemoteConnectionProfile profile);

  Future<void> delete();
}
