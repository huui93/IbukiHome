import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../application/remote/remote_connection_profile.dart';
import '../../application/remote/remote_credential_store.dart';

class SecureRemoteCredentialStore implements RemoteCredentialStore {
  const SecureRemoteCredentialStore(this._storage);

  static const _baseUriKey = 'remote.base_uri';
  static const _displayNameKey = 'remote.display_name';
  static const _tokenKey = 'remote.token';
  static const _lastVerifiedAtUtcKey = 'remote.last_verified_at_utc';
  static const _apiVersionKey = 'remote.api_version';

  final FlutterSecureStorage _storage;

  @override
  Future<RemoteConnectionProfile?> load() async {
    final baseUriText = await _storage.read(key: _baseUriKey);
    final token = await _storage.read(key: _tokenKey);
    final verifiedText = await _storage.read(key: _lastVerifiedAtUtcKey);
    final apiVersionText = await _storage.read(key: _apiVersionKey);
    if (baseUriText == null || token == null) {
      return null;
    }
    final baseUri = Uri.tryParse(baseUriText);
    final verifiedAt = DateTime.tryParse(verifiedText ?? '')?.toUtc();
    final apiVersion = int.tryParse(apiVersionText ?? '');
    if (baseUri == null || verifiedAt == null || apiVersion == null) {
      return null;
    }
    return RemoteConnectionProfile(
      baseUri: baseUri,
      token: token,
      lastVerifiedAtUtc: verifiedAt,
      apiVersion: apiVersion,
      displayName: await _storage.read(key: _displayNameKey),
    );
  }

  @override
  Future<void> save(RemoteConnectionProfile profile) async {
    await _storage.write(key: _baseUriKey, value: profile.baseUri.toString());
    await _storage.write(key: _tokenKey, value: profile.token);
    await _storage.write(
      key: _lastVerifiedAtUtcKey,
      value: profile.lastVerifiedAtUtc.toUtc().toIso8601String(),
    );
    await _storage.write(key: _apiVersionKey, value: '${profile.apiVersion}');
    final displayName = profile.displayName;
    if (displayName == null || displayName.isEmpty) {
      await _storage.delete(key: _displayNameKey);
    } else {
      await _storage.write(key: _displayNameKey, value: displayName);
    }
  }

  @override
  Future<void> delete() async {
    await _storage.delete(key: _baseUriKey);
    await _storage.delete(key: _displayNameKey);
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _lastVerifiedAtUtcKey);
    await _storage.delete(key: _apiVersionKey);
  }
}
