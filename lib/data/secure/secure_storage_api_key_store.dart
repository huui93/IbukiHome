import '../../application/ai/secure_api_key_store.dart';
import '../../application/security/secure_value_store.dart';

class SecureStorageApiKeyStore implements SecureApiKeyStore {
  const SecureStorageApiKeyStore(this._store);

  final SecureValueStore _store;

  @override
  Future<String?> read(String keyRef) => _store.read(keyRef);

  @override
  Future<bool> contains(String keyRef) async =>
      (await _store.read(keyRef))?.isNotEmpty ?? false;

  @override
  Future<void> write(String keyRef, String apiKey) async {
    final value = apiKey.trim();
    if (value.isEmpty) {
      await delete(keyRef);
      return;
    }
    await _store.write(keyRef, value);
  }

  @override
  Future<void> delete(String keyRef) => _store.delete(keyRef);
}
