import '../../core/errors/plugin_exceptions.dart';

enum PluginPromptOperation {
  novelGenerate('novel.generate', isNovel: true),
  novelRewrite('novel.rewrite', isNovel: true),
  novelModify('novel.modify', isNovel: true),
  novelSelectionModify('novel.selectionModify', isNovel: true),
  chatReply('chat.reply', isNovel: false),
  chatContinue('chat.continue', isNovel: false),
  worldDirector('world.director', isNovel: false, isWorld: true),
  worldCharacter('world.character', isNovel: false, isWorld: true),
  worldNarration('world.narration', isNovel: false, isWorld: true);

  const PluginPromptOperation(
    this.key, {
    required this.isNovel,
    this.isWorld = false,
  });

  final String key;
  final bool isNovel;
  final bool isWorld;

  bool get isChat => !isNovel && !isWorld;

  static PluginPromptOperation? fromKey(String key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

class PluginPromptContribution {
  const PluginPromptContribution({
    required this.id,
    required this.operationKeys,
    this.styleInstruction = '',
    this.beforeUserInstruction = '',
    this.afterContext = '',
    this.finalInstruction = '',
    this.exclusive = true,
    this.metadata = const {},
    this.unknownFields = const {},
  });

  final String id;
  final List<String> operationKeys;
  final String styleInstruction;
  final String beforeUserInstruction;
  final String afterContext;
  final String finalInstruction;
  final bool exclusive;
  final Map<String, Object?> metadata;
  final Map<String, Object?> unknownFields;

  Set<PluginPromptOperation> get supportedOperations => operationKeys
      .map(PluginPromptOperation.fromKey)
      .whereType<PluginPromptOperation>()
      .toSet();

  bool appliesTo(PluginPromptOperation operation) {
    return operationKeys.contains(operation.key);
  }

  factory PluginPromptContribution.fromJson(Map<String, Object?> json) {
    final id = _requiredString(json, 'id');
    final rawOperations = json['operations'];
    if (rawOperations is! List ||
        rawOperations.isEmpty ||
        rawOperations.any((item) => item is! String)) {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        'Prompt Contribution 必须声明 operations。',
      );
    }
    final operationKeys = rawOperations
        .cast<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (operationKeys.isEmpty) {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        'Prompt Contribution operations 不能为空。',
      );
    }
    final metadata = _object(json['metadata'], 'metadata');
    return PluginPromptContribution(
      id: id,
      operationKeys: List.unmodifiable(operationKeys),
      styleInstruction: _optionalString(json, 'styleInstruction'),
      beforeUserInstruction: _optionalString(json, 'beforeUserInstruction'),
      afterContext: _optionalString(json, 'afterContext'),
      finalInstruction: _optionalString(json, 'finalInstruction'),
      exclusive: json['exclusive'] is bool ? json['exclusive']! as bool : true,
      metadata: metadata,
      unknownFields: Map.unmodifiable(
        Map<String, Object?>.fromEntries(
          json.entries.where((entry) => !_knownFields.contains(entry.key)),
        ),
      ),
    );
  }

  Map<String, Object?> toJson() => {
    ...unknownFields,
    'id': id,
    'operations': operationKeys,
    'styleInstruction': styleInstruction,
    'beforeUserInstruction': beforeUserInstruction,
    'afterContext': afterContext,
    'finalInstruction': finalInstruction,
    'exclusive': exclusive,
    'metadata': metadata,
  };

  static const _knownFields = {
    'id',
    'operations',
    'styleInstruction',
    'beforeUserInstruction',
    'afterContext',
    'finalInstruction',
    'exclusive',
    'metadata',
  };
}

enum PluginSettingType { boolean, enumeration, number, string }

class PluginSettingDefinition {
  const PluginSettingDefinition({
    required this.key,
    required this.type,
    required this.defaultValue,
    this.label,
    this.description,
    this.values = const [],
    this.valueLabels = const {},
    this.minimum,
    this.maximum,
    this.unknownFields = const {},
  });

  final String key;
  final PluginSettingType type;
  final Object? defaultValue;
  final String? label;
  final String? description;
  final List<String> values;
  final Map<String, String> valueLabels;
  final double? minimum;
  final double? maximum;
  final Map<String, Object?> unknownFields;

  factory PluginSettingDefinition.fromJson(
    String key,
    Map<String, Object?> json,
  ) {
    if (key.isEmpty || key.length > 100) {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件设置键无效。',
      );
    }
    final rawType = json['type'];
    final type = switch (rawType) {
      'boolean' => PluginSettingType.boolean,
      'enum' => PluginSettingType.enumeration,
      'number' => PluginSettingType.number,
      'string' => PluginSettingType.string,
      _ => throw PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件设置 $key 的类型无效。',
      ),
    };
    final rawValues = json['values'];
    final values = rawValues == null
        ? const <String>[]
        : rawValues is List && rawValues.every((item) => item is String)
        ? rawValues.cast<String>().toList(growable: false)
        : throw PluginException(
            PluginErrorCategory.pluginRuntimeFailure,
            '插件设置 $key 的 enum values 无效。',
          );
    if (type == PluginSettingType.enumeration && values.isEmpty) {
      throw PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件设置 $key 必须提供 enum values。',
      );
    }
    final labels = <String, String>{};
    final rawLabels = json['valueLabels'];
    if (rawLabels != null) {
      if (rawLabels is! Map ||
          rawLabels.entries.any(
            (entry) => entry.key is! String || entry.value is! String,
          )) {
        throw PluginException(
          PluginErrorCategory.pluginRuntimeFailure,
          '插件设置 $key 的 valueLabels 无效。',
        );
      }
      for (final entry in rawLabels.entries) {
        labels[entry.key as String] = entry.value as String;
      }
    }
    final minimum = _number(json['min'], '$key.min');
    final maximum = _number(json['max'], '$key.max');
    if (minimum != null && maximum != null && minimum > maximum) {
      throw PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件设置 $key 的数值范围无效。',
      );
    }
    final defaultValue = json['default'] ?? _fallbackDefault(type, values);
    final definition = PluginSettingDefinition(
      key: key,
      type: type,
      defaultValue: defaultValue,
      label: _nullableString(json['label']),
      description: _nullableString(json['description']),
      values: List.unmodifiable(values),
      valueLabels: Map.unmodifiable(labels),
      minimum: minimum,
      maximum: maximum,
      unknownFields: Map.unmodifiable(
        Map<String, Object?>.fromEntries(
          json.entries.where((entry) => !_settingFields.contains(entry.key)),
        ),
      ),
    );
    definition.validate(defaultValue);
    return definition;
  }

  Object? validate(Object? value) {
    switch (type) {
      case PluginSettingType.boolean:
        if (value is! bool) return _invalid();
      case PluginSettingType.enumeration:
        if (value is! String || !values.contains(value)) return _invalid();
      case PluginSettingType.number:
        if (value is! num) return _invalid();
        final number = value.toDouble();
        if ((minimum != null && number < minimum!) ||
            (maximum != null && number > maximum!)) {
          return _invalid();
        }
      case PluginSettingType.string:
        if (value is! String || value.length > 4000) return _invalid();
    }
    return value;
  }

  Never _invalid() {
    throw PluginException(
      PluginErrorCategory.pluginRuntimeFailure,
      '插件设置 $key 的值无效。',
    );
  }

  static Object? _fallbackDefault(
    PluginSettingType type,
    List<String> values,
  ) => switch (type) {
    PluginSettingType.boolean => false,
    PluginSettingType.enumeration => values.first,
    PluginSettingType.number => 0,
    PluginSettingType.string => '',
  };

  static const _settingFields = {
    'type',
    'default',
    'label',
    'description',
    'values',
    'valueLabels',
    'min',
    'max',
  };
}

List<PluginPromptContribution> parsePromptContributions(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw const PluginException(
      PluginErrorCategory.pluginRuntimeFailure,
      'promptContributions 必须是列表。',
    );
  }
  return List.unmodifiable(
    raw.map((item) {
      if (item is! Map) {
        throw const PluginException(
          PluginErrorCategory.pluginRuntimeFailure,
          'Prompt Contribution 格式无效。',
        );
      }
      return PluginPromptContribution.fromJson(Map<String, Object?>.from(item));
    }),
  );
}

Map<String, PluginSettingDefinition> parsePluginSettingsSchema(Object? raw) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw const PluginException(
      PluginErrorCategory.pluginRuntimeFailure,
      'settingsSchema 必须是对象。',
    );
  }
  final result = <String, PluginSettingDefinition>{};
  for (final entry in raw.entries) {
    if (entry.key is! String || entry.value is! Map) {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        'settingsSchema 包含无效设置。',
      );
    }
    result[entry.key as String] = PluginSettingDefinition.fromJson(
      entry.key as String,
      Map<String, Object?>.from(entry.value as Map),
    );
  }
  return Map.unmodifiable(result);
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty || value.length > 200) {
    throw PluginException(
      PluginErrorCategory.pluginRuntimeFailure,
      'Prompt Contribution 字段 $key 无效。',
    );
  }
  return value.trim();
}

String _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return '';
  if (value is! String || value.length > 16000) {
    throw PluginException(
      PluginErrorCategory.pluginRuntimeFailure,
      'Prompt Contribution 字段 $key 无效。',
    );
  }
  return value.trim();
}

Map<String, Object?> _object(Object? value, String key) {
  if (value == null) return const {};
  if (value is! Map) {
    throw PluginException(
      PluginErrorCategory.pluginRuntimeFailure,
      'Prompt Contribution 字段 $key 无效。',
    );
  }
  return Map.unmodifiable(Map<String, Object?>.from(value));
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  if (value is! String || value.length > 500) {
    throw const PluginException(
      PluginErrorCategory.pluginRuntimeFailure,
      '插件设置文案无效。',
    );
  }
  return value.trim().isEmpty ? null : value.trim();
}

double? _number(Object? value, String field) {
  if (value == null) return null;
  if (value is! num || !value.isFinite) {
    throw PluginException(
      PluginErrorCategory.pluginRuntimeFailure,
      '插件设置 $field 必须是有限数值。',
    );
  }
  return value.toDouble();
}
