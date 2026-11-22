import 'dart:async';

import '../../core/errors/plugin_exceptions.dart';
import '../../data/repositories/plugin_registry.dart';
import '../../data/repositories/plugin_storage_repository.dart';
import '../../domain/plugins/ibuki_plugin_manifest.dart';
import '../../domain/plugins/installed_plugin.dart';
import '../../domain/plugins/plugin_creative_manifest.dart';

enum PluginScopeType { global, project, chatSession, world, worldSession }

class PluginScopeRef {
  const PluginScopeRef._(this.type, this.id);

  const PluginScopeRef.global() : this._(PluginScopeType.global, null);

  const PluginScopeRef.project(String projectId)
    : this._(PluginScopeType.project, projectId);

  const PluginScopeRef.chatSession(String sessionId)
    : this._(PluginScopeType.chatSession, sessionId);

  const PluginScopeRef.world(String worldId)
    : this._(PluginScopeType.world, worldId);

  const PluginScopeRef.worldSession(String sessionId)
    : this._(PluginScopeType.worldSession, sessionId);

  final PluginScopeType type;
  final String? id;

  String get storageKey => '${type.name}:${id ?? '*'}';

  factory PluginScopeRef.fromJson(Map<String, Object?> json) {
    final rawType = json['type'];
    final type = PluginScopeType.values
        .where((item) => item.name == rawType)
        .firstOrNull;
    if (type == null) {
      throw const PluginException(
        PluginErrorCategory.storageFailure,
        '插件作用范围数据已损坏。',
      );
    }
    final id = json['id'];
    if (type == PluginScopeType.global) return const PluginScopeRef.global();
    if (id is! String || id.trim().isEmpty || id.length > 200) {
      throw const PluginException(
        PluginErrorCategory.storageFailure,
        '插件作用范围 ID 无效。',
      );
    }
    return PluginScopeRef._(type, id.trim());
  }

  Map<String, Object?> toJson() => {'type': type.name, 'id': id};

  @override
  bool operator ==(Object other) {
    return other is PluginScopeRef && other.type == type && other.id == id;
  }

  @override
  int get hashCode => Object.hash(type, id);
}

class PluginScopeBinding {
  const PluginScopeBinding({required this.scope, required this.operations});

  final PluginScopeRef scope;
  final Set<String> operations;

  bool appliesTo(PluginPromptOperation operation) {
    return operations.contains(operation.key);
  }

  factory PluginScopeBinding.fromJson(Map<String, Object?> json) {
    final rawScope = json['scope'];
    final rawOperations = json['operations'];
    if (rawScope is! Map ||
        rawOperations is! List ||
        rawOperations.any((item) => item is! String)) {
      throw const PluginException(
        PluginErrorCategory.storageFailure,
        '插件作用范围数据已损坏。',
      );
    }
    return PluginScopeBinding(
      scope: PluginScopeRef.fromJson(Map<String, Object?>.from(rawScope)),
      operations: Set.unmodifiable(rawOperations.cast<String>().toSet()),
    );
  }

  Map<String, Object?> toJson() => {
    'scope': scope.toJson(),
    'operations': operations.toList()..sort(),
  };
}

class PluginScopeConflict {
  const PluginScopeConflict({
    required this.pluginId,
    required this.pluginName,
    required this.operations,
  });

  final String pluginId;
  final String pluginName;
  final Set<String> operations;
}

class PluginScopeConflictException extends PluginException {
  PluginScopeConflictException(this.conflicts)
    : super(
        PluginErrorCategory.promptConflict,
        '当前作用范围已经使用其它文风插件。',
        detail: conflicts.map((item) => item.pluginId).join(','),
      );

  final List<PluginScopeConflict> conflicts;
}

class PluginCreativeStateStore {
  PluginCreativeStateStore({required this.registry, required this.storage});

  static const _stateStorageKey = '__ibuki_host__:creative_runtime_v1';

  final PluginRegistry registry;
  final PluginStorageRepository storage;
  final Map<String, _PluginCreativeState> _cache = {};
  final StreamController<String> _changes = StreamController.broadcast();

  Stream<String> get changes => _changes.stream;

  Future<List<PluginScopeBinding>> bindingsFor(String pluginId) async {
    return List.unmodifiable((await _load(pluginId)).bindings);
  }

  Future<Map<String, Object?>> settingsFor(
    IbukiPluginManifest manifest,
    PluginScopeRef scope,
  ) async {
    final definitions = manifest.parseSettingsSchema();
    final state = await _load(manifest.id);
    final stored = state.settings[scope.storageKey] ?? const {};
    final result = <String, Object?>{};
    for (final entry in definitions.entries) {
      final value = stored.containsKey(entry.key)
          ? stored[entry.key]
          : entry.value.defaultValue;
      result[entry.key] = entry.value.validate(value);
    }
    return Map.unmodifiable(result);
  }

  Future<void> setSetting({
    required IbukiPluginManifest manifest,
    required PluginScopeRef scope,
    required String key,
    required Object? value,
  }) async {
    final definition = manifest.parseSettingsSchema()[key];
    if (definition == null) {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件没有声明这个设置。',
      );
    }
    final validated = definition.validate(value);
    final state = await _load(manifest.id);
    final settings = <String, Map<String, Object?>>{
      for (final entry in state.settings.entries)
        entry.key: Map<String, Object?>.from(entry.value),
    };
    (settings[scope.storageKey] ??= <String, Object?>{})[key] = validated;
    await _save(
      manifest.id,
      state.copyWith(settings: Map.unmodifiable(settings)),
    );
  }

  Future<void> bind({
    required InstalledPlugin plugin,
    required PluginScopeRef scope,
    bool replaceConflicts = false,
  }) async {
    final contributions = plugin.manifest.parsePromptContributions();
    final operations = contributions
        .expand((item) => item.operationKeys)
        .where((key) => PluginPromptOperation.fromKey(key) != null)
        .toSet();
    if (operations.isEmpty) {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '此插件没有当前版本可用的 Prompt Contribution。',
      );
    }
    final exclusiveOperations = contributions
        .where((item) => item.exclusive)
        .expand((item) => item.operationKeys)
        .toSet();
    final conflicts = await _findConflicts(
      pluginId: plugin.id,
      scope: scope,
      operations: exclusiveOperations,
    );
    if (conflicts.isNotEmpty && !replaceConflicts) {
      throw PluginScopeConflictException(conflicts);
    }
    if (replaceConflicts) {
      for (final conflict in conflicts) {
        await unbind(conflict.pluginId, scope);
      }
    }
    final state = await _load(plugin.id);
    final bindings =
        state.bindings
            .where((item) => item.scope != scope)
            .toList(growable: true)
          ..add(
            PluginScopeBinding(
              scope: scope,
              operations: Set.unmodifiable(operations),
            ),
          );
    await _save(
      plugin.id,
      state.copyWith(bindings: List.unmodifiable(bindings)),
    );
  }

  Future<void> unbind(String pluginId, PluginScopeRef scope) async {
    final state = await _load(pluginId);
    final bindings = state.bindings
        .where((item) => item.scope != scope)
        .toList(growable: false);
    if (bindings.length == state.bindings.length) return;
    await _save(
      pluginId,
      state.copyWith(bindings: List.unmodifiable(bindings)),
    );
  }

  Future<List<PluginScopeConflict>> _findConflicts({
    required String pluginId,
    required PluginScopeRef scope,
    required Set<String> operations,
  }) async {
    if (operations.isEmpty) return const [];
    final conflicts = <PluginScopeConflict>[];
    for (final candidate in await registry.listPlugins()) {
      if (!candidate.enabled ||
          candidate.isBroken ||
          candidate.id == pluginId) {
        continue;
      }
      Set<String> exclusive;
      try {
        exclusive = candidate.manifest
            .parsePromptContributions()
            .where((item) => item.exclusive)
            .expand((item) => item.operationKeys)
            .toSet();
      } catch (_) {
        continue;
      }
      final overlap = exclusive.intersection(operations);
      if (overlap.isEmpty) continue;
      final bindings = await bindingsFor(candidate.id);
      if (bindings.any(
        (binding) =>
            binding.scope == scope &&
            binding.operations.intersection(overlap).isNotEmpty,
      )) {
        conflicts.add(
          PluginScopeConflict(
            pluginId: candidate.id,
            pluginName: candidate.manifest.name,
            operations: Set.unmodifiable(overlap),
          ),
        );
      }
    }
    return List.unmodifiable(conflicts);
  }

  Future<_PluginCreativeState> _load(String pluginId) async {
    final cached = _cache[pluginId];
    if (cached != null) return cached;
    final raw = await storage.getValue(pluginId, _stateStorageKey);
    if (raw == null) {
      const empty = _PluginCreativeState();
      _cache[pluginId] = empty;
      return empty;
    }
    if (raw is! Map) {
      throw const PluginException(
        PluginErrorCategory.storageFailure,
        '插件 Creative Runtime 状态已损坏。',
      );
    }
    final state = _PluginCreativeState.fromJson(Map<String, Object?>.from(raw));
    _cache[pluginId] = state;
    return state;
  }

  Future<void> _save(String pluginId, _PluginCreativeState state) async {
    await storage.setValue(pluginId, _stateStorageKey, state.toJson());
    _cache[pluginId] = state;
    _changes.add(pluginId);
  }

  void invalidate(String pluginId) {
    _cache.remove(pluginId);
    _changes.add(pluginId);
  }

  void dispose() => _changes.close();
}

class _PluginCreativeState {
  const _PluginCreativeState({
    this.bindings = const [],
    this.settings = const {},
  });

  final List<PluginScopeBinding> bindings;
  final Map<String, Map<String, Object?>> settings;

  factory _PluginCreativeState.fromJson(Map<String, Object?> json) {
    final rawBindings = json['bindings'];
    final rawSettings = json['settings'];
    if ((rawBindings != null && rawBindings is! List) ||
        (rawSettings != null && rawSettings is! Map)) {
      throw const PluginException(
        PluginErrorCategory.storageFailure,
        '插件 Creative Runtime 状态已损坏。',
      );
    }
    final bindings = <PluginScopeBinding>[];
    for (final item in rawBindings as List? ?? const []) {
      if (item is! Map) {
        throw const PluginException(
          PluginErrorCategory.storageFailure,
          '插件作用范围数据已损坏。',
        );
      }
      bindings.add(
        PluginScopeBinding.fromJson(Map<String, Object?>.from(item)),
      );
    }
    final settings = <String, Map<String, Object?>>{};
    for (final entry in (rawSettings as Map? ?? const {}).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const PluginException(
          PluginErrorCategory.storageFailure,
          '插件设置作用范围数据已损坏。',
        );
      }
      settings[entry.key as String] = Map<String, Object?>.from(
        entry.value as Map,
      );
    }
    return _PluginCreativeState(
      bindings: List.unmodifiable(bindings),
      settings: Map.unmodifiable(settings),
    );
  }

  _PluginCreativeState copyWith({
    List<PluginScopeBinding>? bindings,
    Map<String, Map<String, Object?>>? settings,
  }) {
    return _PluginCreativeState(
      bindings: bindings ?? this.bindings,
      settings: settings ?? this.settings,
    );
  }

  Map<String, Object?> toJson() => {
    'bindings': bindings.map((item) => item.toJson()).toList(),
    'settings': settings,
  };
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
