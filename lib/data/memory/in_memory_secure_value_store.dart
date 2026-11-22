import '../../application/security/secure_value_store.dart';

class InMemorySecureValueStore implements SecureValueStore {
  final Map<String, String> _values = {};

  Map<String, String> get debugSnapshot => Map.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
