import 'dart:convert';

class BackupSecuritySanitizer {
  const BackupSecuritySanitizer();

  static final RegExp _secretKey = RegExp(
    r'(^|[_-])(api[_-]?key|authorization|access[_-]?token|refresh[_-]?token|client[_-]?secret|private[_-]?key|bearer|password|credential)([_-]|$)',
    caseSensitive: false,
  );
  static final RegExp _bearer = RegExp(
    r'\bBearer\s+[A-Za-z0-9._~+/=-]{8,}',
    caseSensitive: false,
  );
  static final RegExp _keyValue = RegExp(
    r'\b(sk-[A-Za-z0-9_-]{12,}|AIza[A-Za-z0-9_-]{20,})\b',
  );

  Object? sanitize(Object? value) {
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (_isSecretKey(key)) continue;
        result[key] = sanitize(entry.value);
      }
      return result;
    }
    if (value is List) return value.map(sanitize).toList(growable: false);
    if (value is String) {
      return value
          .replaceAll(_bearer, '[redacted]')
          .replaceAll(_keyValue, '[redacted]');
    }
    return value;
  }

  String sanitizeJson(String source) {
    try {
      return jsonEncode(sanitize(jsonDecode(source)));
    } catch (_) {
      return sanitize(source)?.toString() ?? '';
    }
  }

  bool containsSecret(String source) =>
      _bearer.hasMatch(source) || _keyValue.hasMatch(source);

  bool _isSecretKey(String key) {
    if (_secretKey.hasMatch(key)) return true;
    final compact = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return const {
      'apikey',
      'authorization',
      'authorizationheader',
      'accesstoken',
      'refreshtoken',
      'clientsecret',
      'privatekey',
      'bearertoken',
      'password',
      'credential',
      'credentials',
    }.contains(compact);
  }
}
