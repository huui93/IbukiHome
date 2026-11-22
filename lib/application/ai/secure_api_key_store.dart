abstract class SecureApiKeyStore {
  Future<String?> read(String keyRef);

  Future<bool> contains(String keyRef);

  Future<void> write(String keyRef, String apiKey);

  Future<void> delete(String keyRef);
}
