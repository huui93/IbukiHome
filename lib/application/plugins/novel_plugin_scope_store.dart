import 'dart:async';
import 'dart:convert';
import '../../data/repositories/novel_plugin_repository.dart';
import '../../data/repositories/plugin_storage_repository.dart';
import '../../domain/plugins/installed_plugin.dart';
import '../../domain/plugins/novel_plugin_models.dart';
import '../../domain/plugins/novel_plugin_storage_keys.dart';
import 'novel_prompt_compiler.dart';

class NovelPluginScopeState {
  const NovelPluginScopeState({
    required this.enabled,
    required this.settings,
    required this.sourceProjectId,
    this.inherited = false,
    this.allowEnd = false,
    this.automaticMemory = false,
    this.batchSize = 6,
  });
  final bool enabled;
  final Map<String, Object?> settings;
  final String sourceProjectId;
  final bool inherited;
  final bool allowEnd;
  final bool automaticMemory;
  final int batchSize;
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'settings': settings,
    'sourceProjectId': sourceProjectId,
    'inherited': inherited,
    'allowEnd': allowEnd,
    'automaticMemory': automaticMemory,
    'batchSize': batchSize,
  };
}

class NovelPluginScopeStore {
  NovelPluginScopeStore({required this.repository, required this.storage});
  final NovelPluginRepository repository;
  final PluginStorageRepository storage;
  final _changes =
      StreamController<({String pluginId, String projectId})>.broadcast();
  final Map<String, Future<void>> _writes = {};
  Stream<({String pluginId, String projectId})> get changes => _changes.stream;
  static String key(String projectId) => novelPluginSettingsKey(projectId);
  static String privatePrefix(String projectId) =>
      novelPluginPrivatePrefix(projectId);

  Future<Map<String, Object?>?> _read(String pluginId, String projectId) async {
    final raw = await storage.getValue(pluginId, key(projectId));
    if (raw == null) return null;
    if (raw is! Map) throw const NovelPluginRequestException('本作插件设置已损坏。');
    return Map<String, Object?>.from(raw);
  }

  Future<NovelPluginScopeState> resolve(
    InstalledPlugin plugin,
    String projectId,
  ) async {
    final options = plugin.manifest.contributions['novel'];
    final memory = options is Map ? options['memory'] : null;
    final automaticDefault =
        memory is Map && memory['automaticDefault'] == true;
    final defaultBatch = (memory is Map ? memory['batchSize'] as int? ?? 4 : 4)
        .clamp(1, 50);
    var current = projectId;
    final visited = <String>{};
    while (visited.add(current) && visited.length <= 100) {
      final branch = await repository.branch(current);
      final state = await _read(plugin.id, current);
      if (state != null &&
          (branch.parentId == null || state['inherit'] != true)) {
        return NovelPluginScopeState(
          enabled:
              plugin.enabled && !plugin.isBroken && state['enabled'] == true,
          settings: Map.unmodifiable(
            Map<String, Object?>.from(state['settings'] as Map? ?? const {}),
          ),
          sourceProjectId: current,
          inherited: current != projectId,
          allowEnd: current == projectId && state['allowEnd'] == true,
          automaticMemory:
              state['automaticMemory'] as bool? ?? automaticDefault,
          batchSize: (state['batchSize'] as int? ?? defaultBatch).clamp(1, 50),
        );
      }
      if (branch.parentId == null || !branch.inheritSettings) {
        return NovelPluginScopeState(
          enabled: false,
          settings: const {},
          sourceProjectId: current,
          inherited: current != projectId,
          automaticMemory: automaticDefault,
          batchSize: defaultBatch,
        );
      }
      current = branch.parentId!;
    }
    throw const NovelPluginRequestException('故事线继承关系无效。');
  }

  Future<void> _write(
    String pluginId,
    String projectId,
    Future<Map<String, Object?>> Function() update,
  ) {
    final lockKey = '$pluginId|$projectId';
    final write = (_writes[lockKey] ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) async {
          await storage.setValue(pluginId, key(projectId), await update());
          if (!_changes.isClosed) {
            _changes.add((pluginId: pluginId, projectId: projectId));
          }
        });
    _writes[lockKey] = write;
    return write.whenComplete(() {
      if (identical(_writes[lockKey], write)) _writes.remove(lockKey);
    });
  }

  Future<Map<String, Object?>> _materialized(
    InstalledPlugin plugin,
    String projectId,
  ) async {
    final state = await resolve(plugin, projectId);
    return {
      'inherit': false,
      'enabled': state.enabled,
      'settings': {...state.settings},
      'allowEnd': state.allowEnd,
      'automaticMemory': state.automaticMemory,
      'batchSize': state.batchSize,
    };
  }

  Future<void> enable(InstalledPlugin plugin, String projectId, bool enabled) =>
      _write(
        plugin.id,
        projectId,
        () async => {
          ...await _materialized(plugin, projectId),
          'enabled': enabled,
        },
      );
  Future<void> inherit(
    InstalledPlugin plugin,
    String projectId,
    bool enabled,
  ) => _write(plugin.id, projectId, () async {
    final branch = await repository.branch(projectId);
    if (branch.parentId == null) {
      throw const NovelPluginRequestException('主线没有上级故事线。');
    }
    return enabled ? {'inherit': true} : await _materialized(plugin, projectId);
  });
  Future<void> saveSettings(
    InstalledPlugin plugin,
    String projectId,
    NovelPluginPreset preset,
    Map<String, Object?> values,
  ) => _write(plugin.id, projectId, () async {
    _validate(preset, values);
    return {...await _materialized(plugin, projectId), 'settings': values};
  });
  Future<void> setSetting(
    InstalledPlugin plugin,
    String projectId,
    NovelPluginPreset preset,
    String section,
    String name,
    Object? value,
  ) => _write(plugin.id, projectId, () async {
    if (!const {
      'entries',
      'groups',
      'request',
      'variables',
    }.contains(section)) {
      throw const NovelPluginRequestException('插件不能修改宿主授权或启用状态。');
    }
    final state = await _materialized(plugin, projectId);
    final settings = Map<String, Object?>.from(state['settings'] as Map);
    final values = Map<String, Object?>.from(
      settings[section] as Map? ?? const {},
    );
    values[name] = value;
    settings[section] = values;
    _validate(preset, settings);
    return {...state, 'settings': settings};
  });
  Future<void> applyScheme(
    InstalledPlugin plugin,
    String projectId,
    NovelPluginPreset preset,
    Map<String, Object?> scheme, {
    bool complete = false,
  }) => _write(plugin.id, projectId, () async {
    final state = await _materialized(plugin, projectId);
    final values = complete
        ? <String, Object?>{}
        : Map<String, Object?>.from(state['settings'] as Map);
    for (final entry in scheme.entries) {
      values[entry.key] = !complete && entry.value is Map
          ? {
              ...Map<String, Object?>.from(
                values[entry.key] as Map? ?? const {},
              ),
              ...Map<String, Object?>.from(entry.value as Map),
            }
          : entry.value;
    }
    _validate(preset, values);
    return {...state, 'settings': values};
  });
  void _validate(NovelPluginPreset preset, Map<String, Object?> settings) {
    final entries = Map<String, Object?>.from(
      settings['entries'] as Map? ?? const {},
    );
    if (entries.keys.any((id) => !preset.entries.any((e) => e.id == id)) ||
        entries.values.any((v) => v is! bool)) {
      throw const NovelPluginRequestException('提示词开关无效。');
    }
    final groups = Map<String, Object?>.from(
      settings['groups'] as Map? ?? const {},
    );
    if (groups.entries.any(
      (e) =>
          !preset.groups.containsKey(e.key) ||
          (e.value != null && !preset.groups[e.key]!.contains(e.value)),
    )) {
      throw const NovelPluginRequestException('互斥组选择无效。');
    }
    final advice = NovelRequestAdvice.fromJson(
      Map<String, Object?>.from(settings['request'] as Map? ?? const {}),
    );
    if (advice.temperature?.isFinite == false ||
        (advice.contextTokens != null && advice.contextTokens! <= 0) ||
        (advice.outputTokens != null && advice.outputTokens! <= 0)) {
      throw const NovelPluginRequestException('请求参数无效。');
    }
  }

  Future<void> authorizeEnd(
    InstalledPlugin plugin,
    String projectId,
    bool allowed, {
    required bool userGesture,
  }) => _write(plugin.id, projectId, () async {
    if (!userGesture ||
        !plugin.manifest.permissions.contains('novel.session.end')) {
      throw const NovelPluginRequestException('结束故事线需要作者明确授权。');
    }
    return {...await _materialized(plugin, projectId), 'allowEnd': allowed};
  });
  Future<void> configureMemory(
    InstalledPlugin plugin,
    String projectId, {
    required bool automatic,
    required int batchSize,
  }) => _write(plugin.id, projectId, () async {
    if (batchSize < 1 || batchSize > 50) {
      throw const NovelPluginRequestException('记忆批次应在 1 至 50 段之间。');
    }
    return {
      ...await _materialized(plugin, projectId),
      'automaticMemory': automatic,
      'batchSize': batchSize,
    };
  });
  Future<Map<String, Map<String, Object?>>> savedSchemes(
    String pluginId,
  ) async {
    final raw = await storage.getValue(
      pluginId,
      '__ibuki_host__:novel_schemes',
    );
    return {
      for (final e in (raw as Map? ?? const {}).entries)
        e.key as String: Map<String, Object?>.from(e.value as Map),
    };
  }

  Future<void> saveScheme(
    InstalledPlugin plugin,
    String name,
    Map<String, Object?> settings,
  ) async {
    if (name.trim().isEmpty || name.length > 80) {
      throw const NovelPluginRequestException('方案名称无效。');
    }
    final current = await savedSchemes(plugin.id);
    await storage.setValue(plugin.id, '__ibuki_host__:novel_schemes', {
      ...current,
      name.trim(): settings,
    });
  }

  Future<Object?> privateGet(
    InstalledPlugin plugin,
    String projectId,
    String name,
  ) => storage.getValue(
    plugin.id,
    '${privatePrefix(projectId)}${_privateKey(name)}',
  );
  Future<void> privateSet(
    InstalledPlugin plugin,
    String projectId,
    String name,
    Object? value,
  ) {
    if (utf8.encode(jsonEncode(value)).length > 1024 * 1024) {
      throw const NovelPluginRequestException('单条插件私有数据过大。');
    }
    return storage.setValue(
      plugin.id,
      '${privatePrefix(projectId)}${_privateKey(name)}',
      value,
    );
  }

  Future<void> privateRemove(
    InstalledPlugin plugin,
    String projectId,
    String name,
  ) => storage.removeValue(
    plugin.id,
    '${privatePrefix(projectId)}${_privateKey(name)}',
  );
  String _privateKey(String value) {
    if (value.isEmpty ||
        value.length > 150 ||
        value.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const NovelPluginRequestException('插件存储键无效。');
    }
    return value;
  }

  void dispose() => _changes.close();
}
