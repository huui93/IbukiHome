import 'dart:convert';

import '../../core/errors/plugin_exceptions.dart';
import '../../data/repositories/plugin_storage_repository.dart';

class PluginStorage {
  PluginStorage({
    required this.pluginId,
    required this.repository,
    this.maxEncodedValueBytes = 256 * 1024,
    this.namespace = '',
  });

  final String pluginId;
  final PluginStorageRepository repository;
  final int maxEncodedValueBytes;
  final String namespace;

  Future<Object?> get(String key) {
    _validateKey(key);
    return repository.getValue(pluginId, '$namespace$key');
  }

  Future<void> set(String key, Object? value) async {
    _validateKey(key);
    final encoded = _encodeJsonSafe(value);
    if (utf8.encode(encoded).length > maxEncodedValueBytes) {
      throw const PluginException(
        PluginErrorCategory.storageFailure,
        '插件设置内容过大。',
      );
    }
    await repository.setValue(pluginId, '$namespace$key', jsonDecode(encoded));
  }

  Future<void> remove(String key) {
    _validateKey(key);
    return repository.removeValue(pluginId, '$namespace$key');
  }

  Future<void> clear() async {
    if (namespace.isEmpty) {
      await repository.clearPluginUserValues(pluginId);
      return;
    }
    for (final key in (await repository.listValues(
      pluginId,
    )).keys.where((key) => key.startsWith(namespace))) {
      await repository.removeValue(pluginId, key);
    }
  }

  static String _encodeJsonSafe(Object? value) {
    try {
      return jsonEncode(value);
    } on JsonUnsupportedObjectError {
      throw const PluginException(
        PluginErrorCategory.storageFailure,
        '插件设置只支持 JSON 数据。',
      );
    }
  }

  static void _validateKey(String key) {
    if (key.isEmpty ||
        key.length > 128 ||
        key.startsWith('__ibuki_host__:') ||
        key.codeUnits.any((code) => code < 32)) {
      throw const PluginException(
        PluginErrorCategory.storageFailure,
        '插件设置键无效。',
      );
    }
  }
}
