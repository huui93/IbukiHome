import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

import '../../domain/import/sillytavern_models.dart';
import 'sillytavern_security.dart';

class SillyTavernParseException implements FormatException {
  const SillyTavernParseException(this.message, [this.source, this.offset]);

  @override
  final String message;
  @override
  final Object? source;
  @override
  final int? offset;

  @override
  String toString() => 'SillyTavernParseException: $message';
}

class SillyTavernParserLimits {
  const SillyTavernParserLimits({
    this.maxSourceBytes = 32 * 1024 * 1024,
    this.maxEmbeddedMetadataBytes = 8 * 1024 * 1024,
    this.maxLoreEntries = 5000,
    this.maxAlternateGreetings = 1000,
  });

  final int maxSourceBytes;
  final int maxEmbeddedMetadataBytes;
  final int maxLoreEntries;
  final int maxAlternateGreetings;
}

class SillyTavernParser {
  const SillyTavernParser({
    this.limits = const SillyTavernParserLimits(),
    this.securityScanner = const SillyTavernSecurityScanner(),
  });

  final SillyTavernParserLimits limits;
  final SillyTavernSecurityScanner securityScanner;

  SillyTavernParsedAsset parse(Uint8List bytes, {required String fileName}) {
    if (bytes.isEmpty || bytes.length > limits.maxSourceBytes) {
      throw const SillyTavernParseException('文件为空或超过安全大小限制。');
    }
    if (_isPng(bytes)) {
      final embedded = _readPngMetadata(bytes);
      final selected = embedded.ccv3 ?? embedded.chara;
      if (selected == null) {
        throw const SillyTavernParseException(
          '未检测到可识别的 SillyTavern Character Card 数据。',
        );
      }
      final warnings = <String>[
        if (embedded.duplicateKeys.isNotEmpty)
          'PNG 包含重复 metadata 字段，已选择最后一个值并重新验证。',
        if (embedded.ccv3 != null && embedded.chara != null)
          'PNG 同时包含 chara 与 ccv3，已优先使用 ccv3。',
      ];
      return _parseJsonText(
        _decodeEmbeddedJson(selected),
        sourceHint: 'png',
        inheritedWarnings: warnings,
      );
    }
    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const SillyTavernParseException('JSON 文件不是有效的 UTF-8。');
    }
    return _parseJsonText(text, sourceHint: _extension(fileName));
  }

  SillyTavernParsedAsset _parseJsonText(
    String text, {
    required String sourceHint,
    List<String> inheritedWarnings = const [],
  }) {
    if (utf8.encode(text).length > limits.maxEmbeddedMetadataBytes) {
      throw const SillyTavernParseException('嵌入 metadata 超过安全大小限制。');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const SillyTavernParseException('Character Card JSON 无法解析。');
    }
    if (decoded is! Map) {
      throw const SillyTavernParseException('顶层 JSON 必须是对象。');
    }
    _validateJsonShape(decoded);
    final root = Map<String, Object?>.from(decoded);
    final spec = _string(root['spec']).toLowerCase();
    if (spec.startsWith('chara_card_') || _looksLikeCharacterCard(root)) {
      return _parseCharacter(root, inheritedWarnings, sourceHint);
    }
    if (_looksLikeLorebook(root)) {
      return _parseLorebook(root, inheritedWarnings);
    }
    if (_looksLikePersona(root)) {
      return _parsePersona(root, inheritedWarnings);
    }
    if (_looksLikePreset(root)) {
      return _parsePreset(root, inheritedWarnings);
    }
    throw const SillyTavernParseException('未检测到受支持的 SillyTavern 资产格式。');
  }

  SillyTavernParsedAsset _parseCharacter(
    Map<String, Object?> root,
    List<String> inheritedWarnings,
    String sourceHint,
  ) {
    final security = securityScanner.scan(root);
    final originalExtensions =
        _map((_map(root['data']) ?? root)['extensions']) ??
        const <String, Object?>{};
    root = _sanitizedMap(root);
    final data = _map(root['data']) ?? root;
    final spec = _string(root['spec']).isEmpty
        ? 'chara_card_v2'
        : _string(root['spec']);
    final version = _string(root['spec_version']).isEmpty
        ? spec.endsWith('_v3')
              ? '3.0'
              : '2.0'
        : _string(root['spec_version']);
    final major = int.tryParse(version.split('.').first) ?? 0;
    if (major < 2) {
      throw SillyTavernParseException('不支持 Character Card $version。');
    }
    final warnings = <String>[
      ...inheritedWarnings,
      if (major > 3) '这是未来版本 Character Card；已解析通用字段并保留未知数据。',
      if (sourceHint != 'png' && sourceHint != 'json')
        '文件扩展名不常见，但内容已通过 Character Card 验证。',
    ];
    final extensions = _map(data['extensions']) ?? const <String, Object?>{};
    final book = _parseCharacterBook(_map(data['character_book']));
    final alternates = _strings(data['alternate_greetings']);
    if (alternates.length > limits.maxAlternateGreetings) {
      throw const SillyTavernParseException('Alternate Greetings 数量超过安全限制。');
    }
    final card = SillyTavernCharacterCardData(
      name: _string(data['name']),
      description: _string(data['description']),
      personality: _string(data['personality']),
      scenario: _string(data['scenario']),
      firstMessage: _string(data['first_mes']),
      exampleMessages: _string(data['mes_example']),
      creatorNotes: _string(data['creator_notes']),
      systemPrompt: _string(data['system_prompt']),
      postHistoryInstructions: _string(data['post_history_instructions']),
      alternateGreetings: List.unmodifiable(alternates),
      tags: List.unmodifiable(_strings(data['tags'])),
      creator: _string(data['creator']),
      characterVersion: _string(data['character_version']),
      extensions: Map.unmodifiable(extensions),
      characterBook: book,
    );
    if (card.name.trim().isEmpty) {
      throw const SillyTavernParseException('Character Card 缺少角色名称。');
    }
    final unsupported = <String, Object?>{
      'topLevel': _without(root, _characterTopLevelKeys),
      'data': _without(data, _characterDataKeys),
      if (extensions.isNotEmpty) 'extensions': extensions,
      if (data['character_book'] != null)
        'characterBook': data['character_book'],
    };
    final sanitizedUnsupported = securityScanner.redactSecrets(unsupported);
    final extensionSummaries = <SillyTavernExtensionSummary>[
      for (final entry in originalExtensions.entries)
        securityScanner.summarizeExtension(entry.key, entry.value),
    ];
    if (security.scriptLikePaths.isNotEmpty) {
      warnings.add('检测到扩展脚本；仅保存兼容数据，不会执行。');
    }
    if (security.remoteReferencePaths.isNotEmpty) {
      warnings.add('检测到远程资源引用；导入过程不会请求或下载。');
    }
    if (security.secretLikePaths.isNotEmpty) {
      warnings.add('检测到疑似密钥或授权信息；解析字段已脱敏，不会导入模型配置。原始 PNG 元数据可能仍保留。');
    }
    if (book?.entries.any((entry) => entry.unsupported.isNotEmpty) == true) {
      warnings.add('CharacterBook 高级规则会被保存，但当前版本不执行。');
    }
    return SillyTavernParsedAsset(
      kind: SillyTavernAssetKind.characterCard,
      sourceFormat: spec,
      sourceVersion: version,
      displayName: card.name,
      characterCard: card,
      normalizedPayload: _sanitizedMap({
        'spec': spec,
        'specVersion': version,
        'name': card.name,
        'description': card.description,
        'personality': card.personality,
        'scenario': card.scenario,
        'firstMessage': card.firstMessage,
        'exampleMessages': card.exampleMessages,
        'creatorNotes': card.creatorNotes,
        'systemPrompt': card.systemPrompt,
        'postHistoryInstructions': card.postHistoryInstructions,
        'alternateGreetings': card.alternateGreetings,
        'tags': card.tags,
        'creator': card.creator,
        'characterVersion': card.characterVersion,
        if (book != null) 'characterBook': _bookToJson(book),
      }),
      unsupportedPayload: Map.unmodifiable(
        sanitizedUnsupported as Map<String, Object?>,
      ),
      security: security,
      warnings: List.unmodifiable(warnings),
      extensionSummaries: List.unmodifiable(extensionSummaries),
    );
  }

  SillyTavernParsedAsset _parseLorebook(
    Map<String, Object?> root,
    List<String> inheritedWarnings,
  ) {
    final security = securityScanner.scan(root);
    root = _sanitizedMap(root);
    final entries = _parseBookEntries(root['entries']);
    final warnings = <String>[
      ...inheritedWarnings,
      if (entries.any((entry) => entry.unsupported.isNotEmpty))
        '高级 World Info 规则已保存，但当前版本暂不执行。',
    ];
    _appendSecurityWarnings(warnings, security);
    final name = _string(root['name']).isEmpty
        ? _string(root['title']).isEmpty
              ? 'SillyTavern 世界书'
              : _string(root['title'])
        : _string(root['name']);
    final unsupported = securityScanner.redactSecrets(
      _without(root, const {'name', 'title', 'spec', 'version'}),
    );
    return SillyTavernParsedAsset(
      kind: SillyTavernAssetKind.lorebook,
      sourceFormat: _string(root['spec']).isEmpty
          ? 'sillytavern_world_info'
          : _string(root['spec']),
      sourceVersion: _string(root['version']).isEmpty
          ? 'unknown'
          : _string(root['version']),
      displayName: name,
      lorebook: SillyTavernLorebookData(
        name: name,
        entries: List.unmodifiable(entries),
      ),
      normalizedPayload: _sanitizedMap({
        'name': name,
        'entries': entries.map(_entryToJson).toList(growable: false),
      }),
      unsupportedPayload: Map.unmodifiable(unsupported as Map<String, Object?>),
      security: security,
      warnings: List.unmodifiable(warnings),
      extensionSummaries: const [],
    );
  }

  SillyTavernParsedAsset _parsePersona(
    Map<String, Object?> root,
    List<String> inheritedWarnings,
  ) {
    final security = securityScanner.scan(root);
    root = _sanitizedMap(root);
    var data = _map(root['persona']) ?? _map(root['data']) ?? root;
    final names = _map(root['personas']);
    final descriptions = _map(root['persona_descriptions']);
    if (names != null && descriptions != null) {
      if (names.length != 1) {
        throw const SillyTavernParseException(
          '这是多角色 Persona 备份。当前请提供仅含一个我的角色的备份；不会猜测或自动导入全部角色。',
        );
      }
      final entry = names.entries.single;
      final descriptor = _map(descriptions[entry.key]);
      if (descriptor == null) {
        throw const SillyTavernParseException('Persona 备份缺少对应角色描述。');
      }
      data = {...descriptor, 'name': entry.value, 'avatar': entry.key};
    }
    final name = _string(data['name']);
    final description = _string(data['description']);
    if (name.isEmpty || description.isEmpty) {
      throw const SillyTavernParseException('Persona 缺少明确的名称或描述。');
    }
    final persona = SillyTavernPersonaData(
      name: name,
      description: description,
      avatarReference: _nullableString(data['avatar']),
      promptIdentity: _string(data['prompt_identity']).isEmpty
          ? _string(data['position'])
          : _string(data['prompt_identity']),
    );
    final warnings = <String>[...inheritedWarnings];
    _appendSecurityWarnings(warnings, security);
    final unsupported = securityScanner.redactSecrets({
      ..._without(root, const {'persona', 'data'}),
      'persona': _without(data, const {
        'name',
        'description',
        'avatar',
        'prompt_identity',
        'position',
      }),
    });
    return SillyTavernParsedAsset(
      kind: SillyTavernAssetKind.persona,
      sourceFormat: _string(root['spec']).isEmpty
          ? 'sillytavern_persona'
          : _string(root['spec']),
      sourceVersion: _string(root['version']).isEmpty
          ? 'unknown'
          : _string(root['version']),
      displayName: name,
      persona: persona,
      normalizedPayload: _sanitizedMap({
        'name': name,
        'description': description,
        'avatarReference': persona.avatarReference,
        'promptIdentity': persona.promptIdentity,
      }),
      unsupportedPayload: Map.unmodifiable(unsupported as Map<String, Object?>),
      security: security,
      warnings: List.unmodifiable(warnings),
      extensionSummaries: const [],
    );
  }

  SillyTavernParsedAsset _parsePreset(
    Map<String, Object?> root,
    List<String> inheritedWarnings,
  ) {
    final security = securityScanner.scan(root);
    root = _sanitizedMap(root);
    final mainPrompt =
        _promptContent(root, const ['main', 'system']) ??
        _string(root['main_prompt']);
    final postHistory =
        _promptContent(root, const [
          'jailbreak',
          'post_history_instructions',
        ]) ??
        _string(root['post_history_instructions']);
    final authorsNote =
        _promptContent(root, const ['authors_note', 'author_note']) ??
        _string(root['authors_note']);
    final parameters = <String, Object?>{
      for (final key in _generationParameterKeys)
        if (root.containsKey(key)) key: root[key],
    };
    final name = _string(root['name']).isEmpty
        ? 'SillyTavern Prompt Preset'
        : _string(root['name']);
    final preset = SillyTavernPromptPresetData(
      name: name,
      mainPrompt: mainPrompt,
      postHistoryInstructions: postHistory,
      authorsNote: authorsNote,
      generationParameters: Map.unmodifiable(parameters),
    );
    final warnings = <String>[
      ...inheritedWarnings,
      if (parameters.isNotEmpty) '生成参数仅保存兼容信息；不会覆盖 Provider 配置。',
    ];
    _appendSecurityWarnings(warnings, security);
    final unsupported = securityScanner.redactSecrets(
      _without(root, {
        'spec',
        'version',
        'name',
        'main_prompt',
        'post_history_instructions',
        'authors_note',
        ..._generationParameterKeys,
      }),
    );
    return SillyTavernParsedAsset(
      kind: SillyTavernAssetKind.promptPreset,
      sourceFormat: _string(root['spec']).isEmpty
          ? 'sillytavern_prompt_preset'
          : _string(root['spec']),
      sourceVersion: _string(root['version']).isEmpty
          ? 'unknown'
          : _string(root['version']),
      displayName: name,
      promptPreset: preset,
      normalizedPayload: _sanitizedMap({
        'name': name,
        'mainPrompt': mainPrompt,
        'postHistoryInstructions': postHistory,
        'authorsNote': authorsNote,
        'generationParameters': parameters,
      }),
      unsupportedPayload: Map.unmodifiable(unsupported as Map<String, Object?>),
      security: security,
      warnings: List.unmodifiable(warnings),
      extensionSummaries: const [],
    );
  }

  _PngMetadata _readPngMetadata(Uint8List bytes) {
    var offset = 8;
    String? chara;
    String? ccv3;
    final seen = <String>{};
    final duplicates = <String>{};
    var reachedEnd = false;
    while (offset < bytes.length) {
      if (offset + 12 > bytes.length) {
        throw const SillyTavernParseException('PNG chunk header 不完整。');
      }
      final length = ByteData.sublistView(
        bytes,
        offset,
        offset + 4,
      ).getUint32(0, Endian.big);
      String type;
      try {
        type = ascii.decode(bytes.sublist(offset + 4, offset + 8));
      } on FormatException {
        throw const SillyTavernParseException('PNG chunk 类型无效。');
      }
      final dataStart = offset + 8;
      final dataEnd = dataStart + length;
      final next = dataEnd + 4;
      if (next > bytes.length) {
        throw const SillyTavernParseException('PNG chunk 长度无效。');
      }
      final checksum = ByteData.sublistView(
        bytes,
        dataEnd,
        next,
      ).getUint32(0, Endian.big);
      if (getCrc32(Uint8List.sublistView(bytes, offset + 4, dataEnd)) !=
          checksum) {
        throw const SillyTavernParseException('PNG chunk 校验失败，文件可能损坏。');
      }
      if (offset == 8) {
        if (type != 'IHDR' || length != 13) {
          throw const SillyTavernParseException('PNG 缺少有效的 IHDR。');
        }
        final header = ByteData.sublistView(bytes, dataStart, dataEnd);
        final width = header.getUint32(0, Endian.big);
        final height = header.getUint32(4, Endian.big);
        if (width == 0 ||
            height == 0 ||
            width > 8192 ||
            height > 8192 ||
            width * height > 16000000) {
          throw const SillyTavernParseException('PNG 图片尺寸超过安全限制。');
        }
      } else if (type == 'IHDR') {
        throw const SillyTavernParseException('PNG 包含重复 IHDR。');
      }
      if (type == 'tEXt') {
        if (length > limits.maxEmbeddedMetadataBytes) {
          throw const SillyTavernParseException('PNG metadata 超过安全大小限制。');
        }
        final data = Uint8List.sublistView(bytes, dataStart, dataEnd);
        final separator = data.indexOf(0);
        if (separator > 0) {
          final key = latin1.decode(data.sublist(0, separator));
          if (key == 'chara' || key == 'ccv3') {
            if (!seen.add(key)) duplicates.add(key);
            final value = latin1.decode(data.sublist(separator + 1));
            if (key == 'ccv3') {
              ccv3 = value;
            } else {
              chara = value;
            }
          }
        }
      }
      offset = next;
      if (type == 'IEND') {
        reachedEnd = true;
        break;
      }
    }
    if (!reachedEnd) {
      throw const SillyTavernParseException('PNG 缺少 IEND chunk。');
    }
    return _PngMetadata(
      chara: chara,
      ccv3: ccv3,
      duplicateKeys: List.unmodifiable(duplicates),
    );
  }

  String _decodeEmbeddedJson(String encoded) {
    final trimmed = encoded.trim();
    if (trimmed.startsWith('{')) return trimmed;
    try {
      final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
      final padded = compact.padRight((compact.length + 3) ~/ 4 * 4, '=');
      final decoded = base64Decode(padded);
      if (decoded.length > limits.maxEmbeddedMetadataBytes) {
        throw const SillyTavernParseException('解码后的 metadata 超过安全大小限制。');
      }
      return utf8.decode(decoded, allowMalformed: false);
    } on SillyTavernParseException {
      rethrow;
    } on FormatException {
      throw const SillyTavernParseException('PNG metadata Base64 无效。');
    }
  }

  SillyTavernCharacterBook? _parseCharacterBook(Map<String, Object?>? raw) {
    if (raw == null) return null;
    final entries = _parseBookEntries(raw['entries']);
    return SillyTavernCharacterBook(
      name: _string(raw['name']).isEmpty ? '角色附带世界书' : _string(raw['name']),
      entries: List.unmodifiable(entries),
      unsupported: Map.unmodifiable(
        _without(raw, const {'name', 'entries', 'description'}),
      ),
    );
  }

  List<SillyTavernCharacterBookEntry> _parseBookEntries(Object? raw) {
    final values = raw is List
        ? raw
        : raw is Map
        ? raw.values.toList(growable: false)
        : const <Object?>[];
    if (values.length > limits.maxLoreEntries) {
      throw const SillyTavernParseException('World Info entries 数量超过安全限制。');
    }
    final result = <SillyTavernCharacterBookEntry>[];
    for (var index = 0; index < values.length; index += 1) {
      final item = _map(values[index]);
      if (item == null) continue;
      final keys = _strings(item['keys']).isEmpty
          ? _strings(item['key'])
          : _strings(item['keys']);
      final secondary = _strings(item['secondary_keys']).isEmpty
          ? _strings(item['keysecondary'])
          : _strings(item['secondary_keys']);
      final probabilityRaw = _number(item['probability']) ?? 100;
      final probability = (probabilityRaw / 100).clamp(0, 1).toDouble();
      result.add(
        SillyTavernCharacterBookEntry(
          id: (item['id'] ?? item['uid'] ?? index).toString(),
          title: _string(item['name']).isEmpty
              ? (_string(item['comment']).isEmpty
                    ? (keys.firstOrNull ?? '条目 ${index + 1}')
                    : _string(item['comment']))
              : _string(item['name']),
          content: _string(item['content']),
          keys: List.unmodifiable(keys),
          secondaryKeys: List.unmodifiable(secondary),
          enabled: item['enabled'] is bool
              ? item['enabled']! as bool
              : item['disable'] != true,
          constant: item['constant'] == true,
          selective: item['selective'] == true,
          order: (_number(item['order']) ?? index).round(),
          position: _string(item['position']).isEmpty
              ? _string(item['insertion_position']).isEmpty
                    ? 'context'
                    : _string(item['insertion_position'])
              : _string(item['position']),
          probability: probability,
          unsupported: Map.unmodifiable({
            ..._without(item, _loreEntryKeys),
            if (item['position'] != null) 'position': item['position'],
            if (probability < 1) 'probability': item['probability'],
          }),
        ),
      );
    }
    return result;
  }

  void _appendSecurityWarnings(
    List<String> warnings,
    SillyTavernSecurityReport security,
  ) {
    if (security.scriptLikePaths.isNotEmpty) {
      warnings.add('检测到脚本式内容；只保存，不执行。');
    }
    if (security.remoteReferencePaths.isNotEmpty) {
      warnings.add('检测到远程引用；不会发起网络请求。');
    }
    if (security.secretLikePaths.isNotEmpty) {
      warnings.add('疑似密钥内容已从解析字段中移除，不会导入模型配置。');
    }
  }

  bool _looksLikeCharacterCard(Map<String, Object?> root) {
    final data = _map(root['data']);
    return data != null &&
        data['name'] is String &&
        (data.containsKey('first_mes') || data.containsKey('description'));
  }

  bool _looksLikeLorebook(Map<String, Object?> root) {
    if (!root.containsKey('entries')) return false;
    final entries = root['entries'];
    return entries is List || entries is Map;
  }

  bool _looksLikePersona(Map<String, Object?> root) {
    if (root['personas'] is Map && root['persona_descriptions'] is Map) {
      return true;
    }
    final spec = _string(root['spec']).toLowerCase();
    if (spec.contains('persona')) return true;
    final type = _string(root['type']).toLowerCase();
    return type == 'persona' &&
        (_map(root['persona']) ?? _map(root['data']) ?? root).containsKey(
          'description',
        );
  }

  bool _looksLikePreset(Map<String, Object?> root) {
    final spec = _string(root['spec']).toLowerCase();
    return spec.contains('preset') ||
        root['prompts'] is List ||
        (root.containsKey('main_prompt') &&
            (root.containsKey('temperature') ||
                root.containsKey('post_history_instructions')));
  }

  String? _promptContent(Map<String, Object?> root, List<String> ids) {
    final prompts = root['prompts'];
    if (prompts is! List) return null;
    for (final raw in prompts) {
      final prompt = _map(raw);
      if (prompt == null) continue;
      final id =
          (_string(prompt['identifier']).isEmpty
                  ? _string(prompt['name'])
                  : _string(prompt['identifier']))
              .toLowerCase();
      if (ids.contains(id)) return _string(prompt['content']);
    }
    return null;
  }

  bool _isPng(Uint8List bytes) {
    if (bytes.length < _pngSignature.length) return false;
    for (var index = 0; index < _pngSignature.length; index += 1) {
      if (bytes[index] != _pngSignature[index]) return false;
    }
    return true;
  }

  String _extension(String fileName) {
    final index = fileName.lastIndexOf('.');
    return index < 0 ? '' : fileName.substring(index + 1).toLowerCase();
  }

  Map<String, Object?> _sanitizedMap(Map<String, Object?> value) {
    return Map.unmodifiable(
      securityScanner.redactSecrets(value) as Map<String, Object?>,
    );
  }

  void _validateJsonShape(Object root) {
    final pending = <(Object?, int)>[(root, 0)];
    var nodes = 0;
    while (pending.isNotEmpty) {
      final (value, depth) = pending.removeLast();
      if (++nodes > 150000 || depth > 64) {
        throw const SillyTavernParseException('资产结构过于复杂，超过安全解析限制。');
      }
      if (value is Map) {
        for (final child in value.values) {
          pending.add((child, depth + 1));
        }
      } else if (value is List) {
        for (final child in value) {
          pending.add((child, depth + 1));
        }
      }
    }
  }
}

class _PngMetadata {
  const _PngMetadata({
    required this.chara,
    required this.ccv3,
    required this.duplicateKeys,
  });

  final String? chara;
  final String? ccv3;
  final List<String> duplicateKeys;
}

Map<String, Object?>? _map(Object? value) {
  if (value is! Map) return null;
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

String _string(Object? value) => value is String ? value.trim() : '';

String? _nullableString(Object? value) {
  final text = _string(value);
  return text.isEmpty ? null : text;
}

num? _number(Object? value) => switch (value) {
  num number => number,
  String text => num.tryParse(text),
  _ => null,
};

List<String> _strings(Object? value) {
  if (value is String) {
    return value
        .split(RegExp(r'[,\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, Object?> _without(Map<String, Object?> source, Set<String> keys) {
  return <String, Object?>{
    for (final entry in source.entries)
      if (!keys.contains(entry.key)) entry.key: entry.value,
  };
}

Map<String, Object?> _entryToJson(SillyTavernCharacterBookEntry entry) => {
  'id': entry.id,
  'title': entry.title,
  'content': entry.content,
  'keys': entry.keys,
  'secondaryKeys': entry.secondaryKeys,
  'enabled': entry.enabled,
  'constant': entry.constant,
  'selective': entry.selective,
  'order': entry.order,
  'position': entry.position,
  'probability': entry.probability,
};

Map<String, Object?> _bookToJson(SillyTavernCharacterBook book) => {
  'name': book.name,
  'entries': book.entries.map(_entryToJson).toList(growable: false),
};

const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

const _characterTopLevelKeys = <String>{'spec', 'spec_version', 'data'};

const _characterDataKeys = <String>{
  'name',
  'description',
  'personality',
  'scenario',
  'first_mes',
  'mes_example',
  'creator_notes',
  'system_prompt',
  'post_history_instructions',
  'alternate_greetings',
  'tags',
  'creator',
  'character_version',
  'extensions',
  'character_book',
};

const _loreEntryKeys = <String>{
  'id',
  'uid',
  'name',
  'comment',
  'content',
  'keys',
  'key',
  'secondary_keys',
  'keysecondary',
  'enabled',
  'disable',
  'constant',
  'selective',
  'order',
  'position',
  'insertion_position',
  'probability',
};

const _generationParameterKeys = <String>{
  'temperature',
  'top_p',
  'top_k',
  'min_p',
  'repetition_penalty',
  'frequency_penalty',
  'presence_penalty',
  'sampler_order',
  'max_tokens',
};
