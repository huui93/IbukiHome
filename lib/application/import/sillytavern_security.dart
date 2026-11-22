import 'dart:convert';

import '../../domain/import/sillytavern_models.dart';

class SillyTavernSecurityScanner {
  const SillyTavernSecurityScanner();

  static final RegExp _remote = RegExp(
    r'https?://[^\s"\x27<>]+',
    caseSensitive: false,
  );
  static final RegExp _secret = RegExp(
    r'(?:Bearer\s+[A-Za-z0-9._~+/=-]{12,}|AIza[0-9A-Za-z_-]{20,}|sk-[A-Za-z0-9_-]{16,}|Authorization\s*[:=]\s*[^\s,;}]+)',
    caseSensitive: false,
  );
  static final RegExp _script = RegExp(
    r'(?:\beval\s*\(|\bFunction\s*\(|<script\b|\b(?:window|document)\.|\bfetch\s*\(|=>|\bfunction\s*[A-Za-z_$]*\s*\(|\bMutationObserver\b|\bquerySelector(?:All)?\s*\(|\binnerHTML\b)',
    caseSensitive: false,
  );
  static final RegExp _secretKey = RegExp(
    r'^(?:api[_-]?key|authorization|access[_-]?token|refresh[_-]?token|client[_-]?secret|password)$',
    caseSensitive: false,
  );

  SillyTavernSecurityReport scan(Object? value) {
    final scripts = <String>[];
    final remotes = <String>[];
    final secrets = <String>[];
    _visit(
      value,
      r'$',
      scriptPaths: scripts,
      remotePaths: remotes,
      secretPaths: secrets,
    );
    return SillyTavernSecurityReport(
      scriptLikePaths: List.unmodifiable(scripts),
      remoteReferencePaths: List.unmodifiable(remotes),
      secretLikePaths: List.unmodifiable(secrets),
    );
  }

  Object? redactSecrets(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _secretKey.hasMatch(entry.key.toString())
              ? '[redacted]'
              : redactSecrets(entry.value),
      };
    }
    if (value is List) {
      return value.map(redactSecrets).toList(growable: false);
    }
    if (value is String) {
      return value.replaceAll(_secret, '[redacted]');
    }
    return value;
  }

  SillyTavernExtensionKind classifyExtension(String key, Object? value) {
    final normalizedKey = key.toLowerCase();
    final encoded = _safeEncode(value);
    if (_looksScriptLike(normalizedKey, encoded)) {
      return SillyTavernExtensionKind.scriptLike;
    }
    if (_remote.hasMatch(encoded) || normalizedKey.contains('network')) {
      return SillyTavernExtensionKind.networkRelated;
    }
    if (normalizedKey.contains('prompt') || normalizedKey.contains('depth')) {
      return SillyTavernExtensionKind.promptRelated;
    }
    if (normalizedKey.contains('ui') ||
        normalizedKey.contains('css') ||
        normalizedKey.contains('theme')) {
      return SillyTavernExtensionKind.uiRelated;
    }
    if (value is num || value is bool || value is List || value is Map) {
      return SillyTavernExtensionKind.dataOnly;
    }
    return SillyTavernExtensionKind.unknown;
  }

  SillyTavernExtensionSummary summarizeExtension(String key, Object? value) {
    final encoded = _safeEncode(value);
    return SillyTavernExtensionSummary(
      key: key,
      kind: classifyExtension(key, value),
      encodedChars: encoded.length,
      scriptLike: _looksScriptLike(key.toLowerCase(), encoded),
      remoteReference: _remote.hasMatch(encoded),
      secretLike: _secret.hasMatch(encoded),
    );
  }

  bool _looksScriptLike(String key, String encoded) {
    return key.contains('xiaobaix-tasks') ||
        key.contains('tavern_helper') ||
        key.contains('tavern-helper') ||
        key.contains('stscript') ||
        key.contains('javascript') ||
        key == 'scripts' ||
        _script.hasMatch(encoded);
  }

  void _visit(
    Object? value,
    String path, {
    required List<String> scriptPaths,
    required List<String> remotePaths,
    required List<String> secretPaths,
  }) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final childPath = '$path.$key';
        if (_secretKey.hasMatch(key)) secretPaths.add(childPath);
        if (_looksScriptLike(key.toLowerCase(), '')) {
          scriptPaths.add(childPath);
        }
        _visit(
          entry.value,
          childPath,
          scriptPaths: scriptPaths,
          remotePaths: remotePaths,
          secretPaths: secretPaths,
        );
      }
      return;
    }
    if (value is List) {
      for (var index = 0; index < value.length; index += 1) {
        _visit(
          value[index],
          '$path[$index]',
          scriptPaths: scriptPaths,
          remotePaths: remotePaths,
          secretPaths: secretPaths,
        );
      }
      return;
    }
    if (value is! String) return;
    if (_script.hasMatch(value)) scriptPaths.add(path);
    if (_remote.hasMatch(value)) remotePaths.add(path);
    if (_secret.hasMatch(value)) secretPaths.add(path);
  }

  String _safeEncode(Object? value) {
    try {
      return value is String ? value : jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }
}
