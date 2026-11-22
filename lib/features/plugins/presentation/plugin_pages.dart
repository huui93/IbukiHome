import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/ibuki_theme_colors.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../application/plugins/plugin_manager.dart';
import '../../../application/plugins/plugin_creative_state.dart';
import '../../../application/plugins/plugin_providers.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../core/errors/plugin_exceptions.dart';
import '../../../domain/plugins/installed_plugin.dart';
import '../../../domain/plugins/plugin_creative_manifest.dart';

class PluginManagementPage extends ConsumerWidget {
  const PluginManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(installedPluginsProvider);
    return plugins.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _PluginLoadError(
        message: _pluginErrorMessage(error),
        onRetry: () => ref.invalidate(installedPluginsProvider),
      ),
      data: (items) => ListView(
        key: const Key('plugin-management-page'),
        padding: const EdgeInsets.fromLTRB(
          AppTokens.spacingM,
          AppTokens.spacingS,
          AppTokens.spacingM,
          AppTokens.spacingXl,
        ),
        children: [
          if (items.isEmpty)
            _PluginEmptyState(onInstall: () => _pickAndInstall(context, ref))
          else ...[
            Text(
              '已安装插件',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.ibukiColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.spacingS),
            for (final plugin in items) ...[
              _PluginListItem(
                plugin: plugin,
                onToggle: (enabled) =>
                    _togglePlugin(context, ref, plugin, enabled),
                onTap: () => context.push(AppRoutes.plugin(plugin.id)),
              ),
              const SizedBox(height: AppTokens.spacingS),
            ],
            const SizedBox(height: AppTokens.spacingS),
            FilledButton.icon(
              key: const Key('install-plugin-button'),
              onPressed: () => _pickAndInstall(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('安装插件'),
            ),
          ],
        ],
      ),
    );
  }
}

class PluginDetailPage extends ConsumerWidget {
  const PluginDetailPage({required this.pluginId, super.key});

  final String pluginId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(installedPluginsProvider);
    return plugins.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _PluginLoadError(
        message: _pluginErrorMessage(error),
        onRetry: () => ref.invalidate(installedPluginsProvider),
      ),
      data: (items) {
        final plugin = items.where((item) => item.id == pluginId).firstOrNull;
        if (plugin == null) {
          return const Center(child: Text('插件不存在或已卸载。'));
        }
        final manifest = plugin.manifest;
        return ListView(
          key: Key('plugin-detail-${plugin.id}'),
          padding: const EdgeInsets.fromLTRB(
            AppTokens.spacingM,
            AppTokens.spacingS,
            AppTokens.spacingM,
            AppTokens.spacingXl,
          ),
          children: [
            IbukiGlassSurface(
              strong: true,
              padding: const EdgeInsets.all(AppTokens.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          manifest.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Switch(
                        key: const Key('plugin-detail-enabled-switch'),
                        value: plugin.enabled,
                        onChanged: plugin.isBroken
                            ? null
                            : (value) =>
                                  _togglePlugin(context, ref, plugin, value),
                      ),
                    ],
                  ),
                  Text(
                    plugin.isBroken
                        ? _brokenStatus(plugin)
                        : plugin.enabled
                        ? '已启用'
                        : '已停用',
                    style: TextStyle(
                      color: plugin.isBroken
                          ? Theme.of(context).colorScheme.error
                          : context.ibukiColors.textMuted,
                    ),
                  ),
                  if (manifest.description.isNotEmpty) ...[
                    const SizedBox(height: AppTokens.spacingS),
                    Text(manifest.description),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppTokens.spacingM),
            _PluginDetailsSurface(
              rows: [
                ('版本', manifest.version),
                ('作者', manifest.author.isEmpty ? '未填写' : manifest.author),
                ('Plugin ID', manifest.id),
                ('Manifest', 'v${manifest.manifestVersion}'),
                ('Extension API', 'v${manifest.extensionApiVersion}'),
                ('文件大小', _formatBytes(plugin.extractedSize)),
                ('安装时间', _formatTime(plugin.installedAt)),
              ],
            ),
            const SizedBox(height: AppTokens.spacingM),
            _StringListSection(
              title: 'Capabilities',
              values: manifest.capabilities,
              emptyText: '此插件暂未提供可运行扩展',
            ),
            if (manifest.promptContributions.isNotEmpty ||
                manifest.settingsSchema.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spacingM),
              _PluginCreativeRuntimeSection(plugin: plugin),
            ],
            const SizedBox(height: AppTokens.spacingM),
            _StringListSection(
              title: 'Permissions',
              values: manifest.permissions,
              emptyText: '暂无特殊权限',
            ),
            const SizedBox(height: AppTokens.spacingM),
            OutlinedButton.icon(
              key: const Key('reinstall-plugin-button'),
              onPressed: () => _pickAndInstall(context, ref),
              icon: const Icon(Icons.system_update_alt_rounded),
              label: const Text('重新安装 / 更新'),
            ),
            const SizedBox(height: AppTokens.spacingS),
            TextButton.icon(
              key: const Key('uninstall-plugin-button'),
              onPressed: () => _confirmUninstall(context, ref, plugin),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('卸载插件'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PluginCreativeRuntimeSection extends ConsumerStatefulWidget {
  const _PluginCreativeRuntimeSection({required this.plugin});

  final InstalledPlugin plugin;

  @override
  ConsumerState<_PluginCreativeRuntimeSection> createState() =>
      _PluginCreativeRuntimeSectionState();
}

class _PluginCreativeRuntimeSectionState
    extends ConsumerState<_PluginCreativeRuntimeSection> {
  PluginScopeRef _settingsScope = const PluginScopeRef.global();
  int _revision = 0;

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectListProvider).value ?? const [];
    final sessions = ref.watch(chatSessionListProvider).value ?? const [];
    final store = ref.watch(pluginCreativeStateStoreProvider);
    List<PluginSettingDefinition> definitions;
    try {
      definitions = widget.plugin.manifest
          .parseSettingsSchema()
          .values
          .toList();
    } catch (error) {
      return IbukiGlassSurface(
        strong: true,
        padding: const EdgeInsets.all(AppTokens.spacingM),
        child: Text(
          '插件设置格式无效，本次将使用默认创作流程。',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    return Column(
      children: [
        IbukiGlassSurface(
          key: const Key('plugin-prompt-scope-section'),
          strong: true,
          padding: const EdgeInsets.all(AppTokens.spacingM),
          child: FutureBuilder<List<PluginScopeBinding>>(
            key: ValueKey('plugin-bindings-$_revision'),
            future: store.bindingsFor(widget.plugin.id),
            builder: (context, snapshot) {
              final bindings = snapshot.data ?? const [];
              bool bound(PluginScopeRef scope) =>
                  bindings.any((item) => item.scope == scope);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '影响 AI 的范围',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spacingXs),
                  Text(
                    widget.plugin.enabled
                        ? '只有绑定的作品或聊天会使用此插件。'
                        : '插件已停用，已保存的绑定当前不会生效。',
                    style: TextStyle(color: context.ibukiColors.textMuted),
                  ),
                  SwitchListTile(
                    key: const Key('plugin-scope-global'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('全局'),
                    subtitle: const Text('没有更具体绑定时生效'),
                    value: bound(const PluginScopeRef.global()),
                    onChanged: (value) =>
                        _setBinding(const PluginScopeRef.global(), value),
                  ),
                  if (projects.isNotEmpty) ...[
                    const Divider(height: 18),
                    Text('小说作品', style: Theme.of(context).textTheme.labelLarge),
                    for (final project in projects)
                      SwitchListTile(
                        key: Key('plugin-scope-project-${project.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(project.title),
                        value: bound(PluginScopeRef.project(project.id)),
                        onChanged: (value) => _setBinding(
                          PluginScopeRef.project(project.id),
                          value,
                        ),
                      ),
                  ],
                  if (sessions.isNotEmpty) ...[
                    const Divider(height: 18),
                    Text('聊天会话', style: Theme.of(context).textTheme.labelLarge),
                    for (final session in sessions)
                      SwitchListTile(
                        key: Key('plugin-scope-chat-${session.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(session.title),
                        value: bound(PluginScopeRef.chatSession(session.id)),
                        onChanged: (value) => _setBinding(
                          PluginScopeRef.chatSession(session.id),
                          value,
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
        if (definitions.isNotEmpty) ...[
          const SizedBox(height: AppTokens.spacingM),
          IbukiGlassSurface(
            key: const Key('plugin-settings-schema-section'),
            strong: true,
            padding: const EdgeInsets.all(AppTokens.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '插件设置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppTokens.spacingS),
                DropdownButtonFormField<PluginScopeRef>(
                  key: const Key('plugin-settings-scope-picker'),
                  initialValue: _settingsScope,
                  decoration: const InputDecoration(labelText: '设置作用范围'),
                  items: [
                    const DropdownMenuItem(
                      value: PluginScopeRef.global(),
                      child: Text('全局设置'),
                    ),
                    for (final project in projects)
                      DropdownMenuItem(
                        value: PluginScopeRef.project(project.id),
                        child: Text('作品 · ${project.title}'),
                      ),
                    for (final session in sessions)
                      DropdownMenuItem(
                        value: PluginScopeRef.chatSession(session.id),
                        child: Text('聊天 · ${session.title}'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _settingsScope = value;
                      _revision += 1;
                    });
                  },
                ),
                const SizedBox(height: AppTokens.spacingM),
                FutureBuilder<Map<String, Object?>>(
                  key: ValueKey(
                    'plugin-settings-${_settingsScope.storageKey}-$_revision',
                  ),
                  future: store.settingsFor(
                    widget.plugin.manifest,
                    _settingsScope,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text(
                        '插件设置读取失败。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return Column(
                      children: [
                        for (final definition in definitions)
                          _PluginSettingField(
                            definition: definition,
                            value: snapshot.data![definition.key],
                            onChanged: (value) =>
                                _saveSetting(definition.key, value),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _setBinding(PluginScopeRef scope, bool enabled) async {
    final store = ref.read(pluginCreativeStateStoreProvider);
    try {
      if (enabled) {
        await store.bind(plugin: widget.plugin, scope: scope);
      } else {
        await store.unbind(widget.plugin.id, scope);
      }
      if (mounted) setState(() => _revision += 1);
    } on PluginScopeConflictException catch (error) {
      if (!mounted) return;
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('切换文风插件？'),
          content: Text(
            '当前范围已经使用 ${error.conflicts.map((item) => item.pluginName).join('、')}。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('replace-prompt-plugin'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('切换'),
            ),
          ],
        ),
      );
      if (replace == true) {
        await store.bind(
          plugin: widget.plugin,
          scope: scope,
          replaceConflicts: true,
        );
        if (mounted) setState(() => _revision += 1);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_pluginErrorMessage(error))));
    }
  }

  Future<void> _saveSetting(String key, Object? value) async {
    try {
      await ref
          .read(pluginCreativeStateStoreProvider)
          .setSetting(
            manifest: widget.plugin.manifest,
            scope: _settingsScope,
            key: key,
            value: value,
          );
      if (mounted) setState(() => _revision += 1);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_pluginErrorMessage(error))));
    }
  }
}

class _PluginSettingField extends StatelessWidget {
  const _PluginSettingField({
    required this.definition,
    required this.value,
    required this.onChanged,
  });

  final PluginSettingDefinition definition;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = definition.label ?? definition.key;
    final description = definition.description;
    switch (definition.type) {
      case PluginSettingType.boolean:
        return SwitchListTile(
          key: Key('plugin-setting-${definition.key}'),
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: description == null ? null : Text(description),
          value: value as bool,
          onChanged: onChanged,
        );
      case PluginSettingType.enumeration:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spacingM),
          child: DropdownButtonFormField<String>(
            key: Key('plugin-setting-${definition.key}'),
            initialValue: value as String,
            decoration: InputDecoration(
              labelText: label,
              helperText: description,
            ),
            items: [
              for (final item in definition.values)
                DropdownMenuItem(
                  value: item,
                  child: Text(definition.valueLabels[item] ?? item),
                ),
            ],
            onChanged: onChanged,
          ),
        );
      case PluginSettingType.number:
        final minimum = definition.minimum ?? 0;
        final maximum = definition.maximum ?? 100;
        final number = (value as num).toDouble().clamp(minimum, maximum);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spacingS),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$label · ${number.round()}'),
              if (description != null)
                Text(
                  description,
                  style: TextStyle(color: context.ibukiColors.textMuted),
                ),
              Slider(
                key: Key('plugin-setting-${definition.key}'),
                value: number,
                min: minimum,
                max: maximum,
                divisions: (maximum - minimum).round().clamp(1, 100),
                onChanged: onChanged,
              ),
            ],
          ),
        );
      case PluginSettingType.string:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spacingM),
          child: TextFormField(
            key: Key('plugin-setting-${definition.key}'),
            initialValue: value as String,
            decoration: InputDecoration(
              labelText: label,
              helperText: description,
            ),
            onFieldSubmitted: onChanged,
          ),
        );
    }
  }
}

class _PluginListItem extends StatelessWidget {
  const _PluginListItem({
    required this.plugin,
    required this.onToggle,
    required this.onTap,
  });

  final InstalledPlugin plugin;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final manifest = plugin.manifest;
    return IbukiGlassSurface(
      key: Key('plugin-card-${plugin.id}'),
      strong: true,
      onTap: onTap,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 5, 8, 5),
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: context.ibukiColors.primarySoft,
            borderRadius: BorderRadius.circular(AppTokens.bubbleSmallRadius),
          ),
          child: const SizedBox.square(
            dimension: 42,
            child: Icon(Icons.extension_rounded),
          ),
        ),
        title: Text(
          manifest.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            if (manifest.author.isNotEmpty) manifest.author,
            'v${manifest.version}',
            if (plugin.isBroken) _brokenStatus(plugin),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Switch(
          key: Key('plugin-switch-${plugin.id}'),
          value: plugin.enabled,
          onChanged: plugin.isBroken ? null : onToggle,
        ),
      ),
    );
  }
}

class _PluginEmptyState extends StatelessWidget {
  const _PluginEmptyState({required this.onInstall});

  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    return IbukiGlassSurface(
      key: const Key('plugin-empty-state'),
      strong: true,
      padding: const EdgeInsets.all(AppTokens.spacingL),
      child: Column(
        children: [
          Icon(
            Icons.extension_off_outlined,
            size: 42,
            color: context.ibukiColors.textMuted,
          ),
          const SizedBox(height: AppTokens.spacingM),
          Text(
            '还没有安装插件',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppTokens.spacingXs),
          Text(
            '你可以从手机中选择一个 .ibuki 插件。',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.ibukiColors.textMuted),
          ),
          const SizedBox(height: AppTokens.spacingM),
          FilledButton.icon(
            key: const Key('choose-plugin-button'),
            onPressed: onInstall,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('选择插件'),
          ),
        ],
      ),
    );
  }
}

class _PluginDetailsSurface extends StatelessWidget {
  const _PluginDetailsSurface({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return IbukiGlassSurface(
      strong: true,
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spacingXs),
      child: Column(
        children: [
          for (final row in rows)
            ListTile(
              dense: true,
              title: Text(row.$1),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Text(
                  row.$2,
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.ibukiColors.textMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StringListSection extends StatelessWidget {
  const _StringListSection({
    required this.title,
    required this.values,
    required this.emptyText,
  });

  final String title;
  final List<String> values;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return IbukiGlassSurface(
      strong: true,
      padding: const EdgeInsets.all(AppTokens.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: AppTokens.spacingS),
          if (values.isEmpty)
            Text(
              emptyText,
              style: TextStyle(color: context.ibukiColors.textMuted),
            )
          else
            Wrap(
              spacing: AppTokens.spacingXs,
              runSpacing: AppTokens.spacingXs,
              children: [for (final value in values) Chip(label: Text(value))],
            ),
        ],
      ),
    );
  }
}

class _PluginLoadError extends StatelessWidget {
  const _PluginLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppTokens.spacingM),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _pickAndInstall(BuildContext context, WidgetRef ref) async {
  final manager = ref.read(pluginManagerProvider);
  PreparedPluginInstall? prepared;
  try {
    prepared = await manager.pickAndPrepareInstall();
    if (prepared == null || !context.mounted) return;
    final shouldInstall = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(prepared!.isUpdate ? '更新插件' : '安装插件'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PreviewLine('插件名称', prepared.manifest.name),
              _PreviewLine(
                '作者',
                prepared.manifest.author.isEmpty
                    ? '未填写'
                    : prepared.manifest.author,
              ),
              _PreviewLine('版本', prepared.manifest.version),
              if (prepared.manifest.description.isNotEmpty)
                _PreviewLine('描述', prepared.manifest.description),
              _PreviewLine('来自', prepared.sourceFileName),
              if (prepared.manifest.publisher != null)
                _PreviewLine(
                  '来源类型',
                  _publisherLabel(prepared.manifest.publisher),
                ),
              _PreviewLine(
                '权限',
                prepared.manifest.permissions.isEmpty
                    ? '暂无特殊权限'
                    : prepared.manifest.permissions
                          .map(_permissionLabel)
                          .join('\n'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-install-plugin-button'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(prepared.isUpdate ? '更新' : '安装'),
          ),
        ],
      ),
    );
    if (shouldInstall != true) {
      await manager.discardPrepared(prepared);
      return;
    }
    await manager.installPrepared(prepared);
    ref.invalidate(installedPluginsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('插件安装成功。')));
    }
  } catch (error) {
    if (prepared != null) await manager.discardPrepared(prepared);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_pluginErrorMessage(error))));
    }
  }
}

Future<void> _togglePlugin(
  BuildContext context,
  WidgetRef ref,
  InstalledPlugin plugin,
  bool enabled,
) async {
  try {
    final manager = ref.read(pluginManagerProvider);
    if (enabled) {
      await manager.enablePlugin(plugin.id);
    } else {
      await manager.disablePlugin(plugin.id);
    }
    ref.invalidate(installedPluginsProvider);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_pluginErrorMessage(error))));
    }
  }
}

Future<void> _confirmUninstall(
  BuildContext context,
  WidgetRef ref,
  InstalledPlugin plugin,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('卸载“${plugin.manifest.name}”？'),
      content: const Text('插件安装文件会被删除；独立的插件数据目录将保留。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('confirm-uninstall-plugin-button'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('卸载'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await ref.read(pluginManagerProvider).uninstallPlugin(plugin.id);
    ref.invalidate(installedPluginsProvider);
    if (context.mounted && Navigator.of(context).canPop()) context.pop();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_pluginErrorMessage(error))));
    }
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spacingS),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: context.ibukiColors.textMuted)),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}

String _pluginErrorMessage(Object error) {
  return error is PluginException ? error.message : '插件操作失败，请重试。';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _permissionLabel(String permission) => switch (permission) {
  'chat.read' => '• 读取当前聊天',
  'novel.read' => '• 读取启用插件的小说故事线',
  'novel.events' => '• 接收本作定稿、编辑和分叉事件',
  'novel.generate' => '• 使用本作品的模型生成与整理记忆',
  'novel.presentation' => '• 展示小说中的插件卡片',
  'novel.session.end' => '• 经作者单独授权后结束当前故事线',
  'character.read' => '• 读取当前角色',
  'storage.private' => '• 保存插件自己的设置',
  'ui.extend' => '• 在适用页面增加插件界面',
  'ai.generate' => '• 调用当前作用域的 AI',
  'ai.prompt.modify' => '• 修改 AI Prompt 风格',
  'network' => '• 通过 Host 访问网络',
  'core.service.override' => '• 改变伊吹之家的核心行为',
  _ => '• $permission',
};

String _brokenStatus(InstalledPlugin plugin) {
  if (plugin.errorCategory == PluginErrorCategory.unsupportedRuntime.name) {
    return '当前版本不支持此插件的运行环境';
  }
  return '插件文件损坏';
}

String _publisherLabel(Map<String, Object?>? publisher) {
  final label = publisher?['label'];
  if (label is String && label.trim().isNotEmpty) return label.trim();
  final type = publisher?['type'];
  if (type is String && type.trim().isNotEmpty) return type.trim();
  return '第三方插件';
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
