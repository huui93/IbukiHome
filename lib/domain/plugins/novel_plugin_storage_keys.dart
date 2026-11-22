import 'dart:convert';

String _encode(String id) =>
    base64Url.encode(utf8.encode(id)).replaceAll('=', '');
String novelPluginSettingsKey(String projectId) =>
    '__ibuki_host__:novel_settings:${_encode(projectId)}';
String novelPluginPrivatePrefix(String projectId) =>
    '__ibuki_host__:novel_private:${_encode(projectId)}:';
bool isNovelPluginStorageKey(String key) =>
    key.startsWith('__ibuki_host__:novel_');
String? novelPluginStorageOwner(String key) {
  String? encoded;
  if (key.startsWith('__ibuki_host__:novel_settings:')) {
    encoded = key.substring('__ibuki_host__:novel_settings:'.length);
  }
  if (key.startsWith('__ibuki_host__:novel_private:')) {
    encoded = key
        .substring('__ibuki_host__:novel_private:'.length)
        .split(':')
        .first;
  }
  if (encoded == null) return null;
  final owner = utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
  if (owner.isEmpty || owner.length > 200) {
    throw const FormatException('小说插件存储作用域无效。');
  }
  return owner;
}
