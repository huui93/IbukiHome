import 'dart:async';

import '../../core/errors/plugin_exceptions.dart';
import '../../domain/plugins/installed_plugin.dart';
import '../../domain/plugins/plugin_creative_manifest.dart';
import 'plugin_permissions.dart';

class PluginUiContribution {
  const PluginUiContribution({
    required this.pluginId,
    required this.id,
    required this.label,
    required this.entry,
    this.icon = 'extension',
    this.style,
    this.script,
  });

  final String pluginId;
  final String id;
  final String label;
  final String entry;
  final String icon;
  final String? style;
  final String? script;
}

class PluginWorldNavigationContribution {
  const PluginWorldNavigationContribution({
    required this.pluginId,
    required this.id,
    required this.label,
    required this.entry,
    this.icon = 'extension',
    this.worldId,
    this.worldSessionId,
  });

  final String pluginId;
  final String id;
  final String label;
  final String entry;
  final String icon;
  final String? worldId;
  final String? worldSessionId;

  bool appliesTo({required String worldId, required String worldSessionId}) {
    return (this.worldId == null || this.worldId == worldId) &&
        (this.worldSessionId == null || this.worldSessionId == worldSessionId);
  }
}

class PluginContributionRegistry {
  final Map<String, List<PluginUiContribution>> _chatPanels = {};
  final Map<String, List<PluginWorldNavigationContribution>> _worldNavigation =
      {};
  final Map<String, List<PluginPromptContribution>> _promptContributions = {};
  final Map<String, PluginContributionIssue> _issues = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  List<PluginUiContribution> get chatPanels =>
      List.unmodifiable(_chatPanels.values.expand((items) => items));

  List<RegisteredPluginPromptContribution> get promptContributions =>
      List.unmodifiable(
        _promptContributions.entries.expand(
          (entry) => entry.value.map(
            (item) => RegisteredPluginPromptContribution(
              pluginId: entry.key,
              contribution: item,
            ),
          ),
        ),
      );

  List<PluginWorldNavigationContribution> get worldNavigation =>
      List.unmodifiable(_worldNavigation.values.expand((items) => items));

  PluginContributionIssue? issueFor(String pluginId) => _issues[pluginId];

  List<PluginContributionIssue> get issues => List.unmodifiable(_issues.values);

  Stream<List<PluginUiContribution>> watchChatPanels() async* {
    yield chatPanels;
    await for (final _ in _changes.stream) {
      yield chatPanels;
    }
  }

  Stream<List<PluginWorldNavigationContribution>>
  watchWorldNavigation() async* {
    yield worldNavigation;
    await for (final _ in _changes.stream) {
      yield worldNavigation;
    }
  }

  void registerPlugin(InstalledPlugin plugin) {
    unregisterPlugin(plugin.id, notify: false);
    _registerPromptContributions(plugin);
    _registerWorldNavigation(plugin);
    final rawPanels = plugin.manifest.contributions['chatPanels'];
    if (rawPanels != null) {
      PluginPermissionGuard(
        plugin.manifest,
      ).require(PluginPermissions.uiExtend);
      if (rawPanels is! List) {
        throw const PluginException(
          PluginErrorCategory.pluginRuntimeFailure,
          '插件 chatPanels contribution 格式无效。',
        );
      }
      final panels = <PluginUiContribution>[];
      for (final raw in rawPanels) {
        if (raw is! Map) {
          throw const PluginException(
            PluginErrorCategory.pluginRuntimeFailure,
            '插件界面入口格式无效。',
          );
        }
        final map = Map<String, Object?>.from(raw);
        final id = _requiredString(map, 'id');
        final label = _requiredString(map, 'label');
        final entry = _requiredString(map, 'entry');
        if (!_safePath(entry)) {
          throw const PluginException(
            PluginErrorCategory.pluginRuntimeFailure,
            '插件界面 entry 路径无效。',
          );
        }
        panels.add(
          PluginUiContribution(
            pluginId: plugin.id,
            id: id,
            label: label,
            entry: entry,
            icon: map['icon'] is String ? map['icon']! as String : 'extension',
            style: _optionalSafePath(map['style']),
            script: _optionalSafePath(map['script']),
          ),
        );
      }
      _chatPanels[plugin.id] = List.unmodifiable(panels);
    }
    _changes.add(null);
  }

  void _registerWorldNavigation(InstalledPlugin plugin) {
    final rawItems = plugin.manifest.contributions['worldNavigation'];
    if (rawItems == null) return;
    PluginPermissionGuard(plugin.manifest).require(PluginPermissions.uiExtend);
    if (rawItems is! List) {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件 worldNavigation contribution 格式无效。',
      );
    }
    final items = <PluginWorldNavigationContribution>[];
    for (final raw in rawItems) {
      if (raw is! Map) {
        throw const PluginException(
          PluginErrorCategory.pluginRuntimeFailure,
          '世界扩展入口格式无效。',
        );
      }
      final map = Map<String, Object?>.from(raw);
      final entry = _requiredString(map, 'entry');
      if (!_safePath(entry)) {
        throw const PluginException(
          PluginErrorCategory.pluginRuntimeFailure,
          '世界扩展 entry 路径无效。',
        );
      }
      items.add(
        PluginWorldNavigationContribution(
          pluginId: plugin.id,
          id: _requiredString(map, 'id'),
          label: _requiredString(map, 'label'),
          entry: entry,
          icon: map['icon'] is String ? map['icon']! as String : 'extension',
          worldId: _optionalScopeId(map['worldId']),
          worldSessionId: _optionalScopeId(map['worldSessionId']),
        ),
      );
    }
    _worldNavigation[plugin.id] = List.unmodifiable(items);
  }

  void _registerPromptContributions(InstalledPlugin plugin) {
    if (plugin.manifest.promptContributions.isEmpty) return;
    try {
      PluginPermissionGuard(
        plugin.manifest,
      ).require(PluginPermissions.aiPromptModify);
      final parsed = plugin.manifest.parsePromptContributions();
      plugin.manifest.parseSettingsSchema();
      _promptContributions[plugin.id] = parsed;
    } catch (error) {
      _issues[plugin.id] = PluginContributionIssue(
        pluginId: plugin.id,
        errorType: error.runtimeType.toString(),
        message: error is PluginException ? error.message : '插件 Prompt 配置无效。',
      );
    }
  }

  void unregisterPlugin(String pluginId, {bool notify = true}) {
    final removedPanels = _chatPanels.remove(pluginId) != null;
    final removedWorldNavigation = _worldNavigation.remove(pluginId) != null;
    final removedPrompts = _promptContributions.remove(pluginId) != null;
    final removedIssue = _issues.remove(pluginId) != null;
    final changed =
        removedPanels ||
        removedWorldNavigation ||
        removedPrompts ||
        removedIssue;
    if (notify && changed) _changes.add(null);
  }

  void dispose() => _changes.close();

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty || value.length > 200) {
      throw PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件界面字段 $key 无效。',
      );
    }
    return value.trim();
  }

  static bool _safePath(String value) {
    final normalized = value.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) {
      return false;
    }
    return normalized
        .split('/')
        .every((part) => part.isNotEmpty && part != '.' && part != '..');
  }

  static String? _optionalSafePath(Object? value) {
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty || !_safePath(value.trim())) {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件界面资源路径无效。',
      );
    }
    return value.trim();
  }

  static String? _optionalScopeId(Object? value) {
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty || value.length > 200) {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '世界扩展作用范围无效。',
      );
    }
    return value.trim();
  }
}

class RegisteredPluginPromptContribution {
  const RegisteredPluginPromptContribution({
    required this.pluginId,
    required this.contribution,
  });

  final String pluginId;
  final PluginPromptContribution contribution;
}

class PluginContributionIssue {
  const PluginContributionIssue({
    required this.pluginId,
    required this.errorType,
    required this.message,
  });

  final String pluginId;
  final String errorType;
  final String message;
}
