import 'dart:convert';

import '../../core/errors/plugin_exceptions.dart';
import 'plugin_creative_manifest.dart';

class IbukiPluginManifest {
  const IbukiPluginManifest({
    required this.manifestVersion,
    required this.id,
    required this.name,
    required this.version,
    this.extensionApiVersion = 1,
    this.author = '',
    this.description = '',
    this.minIbukiVersion,
    this.entry,
    this.permissions = const [],
    this.capabilities = const [],
    this.contributions = const {},
    this.promptContributions = const [],
    this.settingsSchema = const {},
    this.runtime,
    this.publisher,
    this.metadata = const {},
    this.unknownFields = const {},
  });

  static final RegExp _validId = RegExp(r'^[a-zA-Z0-9._-]+$');

  final int manifestVersion;
  final int extensionApiVersion;
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String? minIbukiVersion;
  final String? entry;
  final List<String> permissions;
  final List<String> capabilities;
  final Map<String, Object?> contributions;
  final List<Object?> promptContributions;
  final Map<String, Object?> settingsSchema;
  final Map<String, Object?>? runtime;
  final Map<String, Object?>? publisher;
  final Map<String, Object?> metadata;
  final Map<String, Object?> unknownFields;

  factory IbukiPluginManifest.parse(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw PluginException(
        PluginErrorCategory.malformedManifest,
        'manifest.json 不是有效的 JSON。',
        detail: error.message,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PluginException(
        PluginErrorCategory.malformedManifest,
        'manifest.json 必须是 JSON 对象。',
      );
    }
    return IbukiPluginManifest.fromJson(decoded);
  }

  factory IbukiPluginManifest.fromJson(Map<String, dynamic> json) {
    final manifestVersion = json['manifestVersion'];
    if (manifestVersion is! int) {
      throw const PluginException(
        PluginErrorCategory.invalidManifest,
        '插件缺少有效的 manifestVersion。',
      );
    }
    if (manifestVersion != 1) {
      throw PluginException(
        PluginErrorCategory.unsupportedManifestVersion,
        '暂不支持 Manifest v$manifestVersion。',
      );
    }
    final extensionApiVersion = json['extensionApiVersion'] ?? 1;
    if (extensionApiVersion is! int || extensionApiVersion < 1) {
      throw const PluginException(
        PluginErrorCategory.invalidManifest,
        '插件缺少有效的 extensionApiVersion。',
      );
    }
    if (extensionApiVersion > 2) {
      throw PluginException(
        PluginErrorCategory.incompatibleExtensionApi,
        '此插件需要 Extension API v$extensionApiVersion，当前版本支持至 v2。',
      );
    }

    final id = _requiredString(json, 'id');
    if (!_validId.hasMatch(id) || id == '.' || id == '..') {
      throw const PluginException(
        PluginErrorCategory.invalidManifest,
        'Plugin ID 只能包含字母、数字、点、下划线和连字符。',
      );
    }
    final name = _requiredString(json, 'name');
    final version = _requiredString(json, 'version');
    final entry = _optionalString(json, 'entry');
    if (entry != null && !_isSafeRelativePath(entry)) {
      throw const PluginException(
        PluginErrorCategory.invalidManifest,
        '插件 entry 必须是包内的安全相对路径。',
      );
    }

    return IbukiPluginManifest(
      manifestVersion: manifestVersion,
      extensionApiVersion: extensionApiVersion,
      id: id,
      name: name,
      version: version,
      author: _optionalString(json, 'author') ?? '',
      description: _optionalString(json, 'description') ?? '',
      minIbukiVersion: _optionalString(json, 'minIbukiVersion'),
      entry: entry,
      permissions: _stringList(json, 'permissions'),
      capabilities: _stringList(json, 'capabilities'),
      contributions: _jsonObject(json['contributions'], 'contributions'),
      promptContributions: _promptContributions(json),
      settingsSchema: _jsonObject(json['settingsSchema'], 'settingsSchema'),
      runtime: _optionalJsonObject(json['runtime'], 'runtime'),
      publisher: _optionalJsonObject(json['publisher'], 'publisher'),
      metadata: _metadata(json['metadata']),
      unknownFields: Map.unmodifiable(
        Map<String, Object?>.fromEntries(
          json.entries
              .where((entry) => !_knownFields.contains(entry.key))
              .map((entry) => MapEntry(entry.key, entry.value)),
        ),
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    ...unknownFields,
    'manifestVersion': manifestVersion,
    'extensionApiVersion': extensionApiVersion,
    'id': id,
    'name': name,
    'version': version,
    'author': author,
    'description': description,
    if (minIbukiVersion != null) 'minIbukiVersion': minIbukiVersion,
    'entry': entry,
    'permissions': permissions,
    'capabilities': capabilities,
    'contributions': contributions,
    'promptContributions': promptContributions,
    'settingsSchema': settingsSchema,
    'runtime': runtime,
    if (publisher != null) 'publisher': publisher,
    'metadata': metadata,
  };

  String encode() => jsonEncode(toJson());

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw PluginException(
        PluginErrorCategory.invalidManifest,
        '插件缺少必填字段：$key。',
      );
    }
    if (_containsControlCharacter(value)) {
      throw PluginException(
        PluginErrorCategory.invalidManifest,
        '字段 $key 包含控制字符。',
      );
    }
    return value.trim();
  }

  static String? _optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String || _containsControlCharacter(value)) {
      throw PluginException(
        PluginErrorCategory.invalidManifest,
        '字段 $key 的格式无效。',
      );
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _stringList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return const [];
    if (value is! List || value.any((item) => item is! String)) {
      throw PluginException(
        PluginErrorCategory.invalidManifest,
        '字段 $key 必须是字符串列表。',
      );
    }
    return List.unmodifiable(value.cast<String>().map((item) => item.trim()));
  }

  static Map<String, Object?> _metadata(Object? value) {
    return _jsonObject(value, 'metadata');
  }

  static Map<String, Object?> _jsonObject(Object? value, String key) {
    if (value == null) return const {};
    if (value is! Map<String, dynamic>) {
      throw PluginException(
        PluginErrorCategory.invalidManifest,
        '字段 $key 必须是 JSON 对象。',
      );
    }
    return Map.unmodifiable(Map<String, Object?>.from(value));
  }

  static Map<String, Object?>? _optionalJsonObject(Object? value, String key) {
    if (value == null) return null;
    return _jsonObject(value, key);
  }

  static bool _containsControlCharacter(String value) {
    return value.codeUnits.any((code) => code < 0x20 || code == 0x7f);
  }

  static bool _isSafeRelativePath(String value) {
    final normalized = value.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) {
      return false;
    }
    final parts = normalized.split('/');
    return parts.isNotEmpty &&
        parts.every((part) => part.isNotEmpty && part != '.' && part != '..');
  }

  static const Set<String> _knownFields = {
    'manifestVersion',
    'extensionApiVersion',
    'id',
    'name',
    'version',
    'author',
    'description',
    'minIbukiVersion',
    'entry',
    'permissions',
    'capabilities',
    'contributions',
    'promptContributions',
    'settingsSchema',
    'runtime',
    'publisher',
    'metadata',
  };

  List<PluginPromptContribution> parsePromptContributions() {
    return parsePromptContributionsRaw(promptContributions);
  }

  Map<String, PluginSettingDefinition> parseSettingsSchema() {
    return parsePluginSettingsSchema(settingsSchema);
  }

  static List<Object?> _promptContributions(Map<String, dynamic> json) {
    final direct = json['promptContributions'];
    final nested = json['contributions'] is Map
        ? (json['contributions'] as Map)['promptContributions']
        : null;
    final value = direct ?? nested;
    if (value == null) return const [];
    if (value is! List) {
      throw const PluginException(
        PluginErrorCategory.invalidManifest,
        '字段 promptContributions 必须是列表。',
      );
    }
    return List.unmodifiable(value);
  }
}

List<PluginPromptContribution> parsePromptContributionsRaw(Object? raw) {
  return parsePromptContributions(raw);
}
