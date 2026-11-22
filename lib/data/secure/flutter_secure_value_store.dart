import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../application/security/secure_value_store.dart';

class FlutterSecureValueStore implements SecureValueStore {
  const FlutterSecureValueStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
