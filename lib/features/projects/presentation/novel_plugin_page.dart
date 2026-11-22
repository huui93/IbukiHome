import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routing/app_routes.dart';
import '../../../application/plugins/novel_plugin_bundle.dart';
import '../../../application/plugins/novel_plugin_providers.dart';
import '../../../application/plugins/novel_plugin_scope_store.dart';
import '../../../application/plugins/plugin_providers.dart';
import '../../../application/world_roleplay/world_roleplay_providers.dart';
import '../../../domain/ai/ai_reasoning_level.dart';
import '../../../domain/plugins/installed_plugin.dart';
import '../../../domain/plugins/novel_plugin_models.dart';

Future<void> showNovelPluginPage(BuildContext context, String projectId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NovelPluginPage(projectId: projectId),
      ),
    );

class NovelPluginPage extends ConsumerStatefulWidget {
  const NovelPluginPage({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<NovelPluginPage> createState() => _NovelPluginPageState();
}

typedef _PluginState = ({
  InstalledPlugin plugin,
  NovelPluginBundle bundle,
  NovelPluginScopeState scope,
});

final _pluginStatesProvider = FutureProvider.autoDispose
    .family<List<_PluginState>, String>((ref, projectId) async {
      ref.watch(novelPluginChangesProvider);
      final store = ref.watch(novelPluginScopeStoreProvider);
      final installed = await ref.watch(installedPluginsProvider.future);
      return [
        for (final plugin in installed.where(NovelPluginBundleLoader.supports))
          (
            plugin: plugin,
            bundle: await const NovelPluginBundleLoader().load(plugin),
            scope: await store.resolve(plugin, projectId),
          ),
      ];
    });

class _NovelPluginPageState extends ConsumerState<NovelPluginPage> {
  var _busy = false;
  String get _id => widget.projectId;
  NovelPluginScopeStore get _store => ref.read(novelPluginScopeStoreProvider);

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) ref.invalidate(_pluginStatesProvider(_id));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(novelStoryBranchProvider(_id)).value;
    final plugins = ref.watch(_pluginStatesProvider(_id));
    return Scaffold(
      appBar: AppBar(title: const Text('小说插件')),
      body: plugins.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(_pluginStatesProvider(_id)),
            child: const Text('插件读取失败，点击重试'),
          ),
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          children: [
            if (items.isEmpty)
              const ListTile(
                title: Text('还没有安装小说插件'),
                subtitle: Text('可在插件管理中导入 NVWA 小说版。'),
              ),
            for (final item in items)
              ..._settings(item, branch?.parentId != null),
            ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('插件管理'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.plugins),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _settings(_PluginState item, bool canInherit) {
    final (:plugin, :bundle, :scope) = item;
    final settings = scope.settings;
    final request = {...bundle.preset.request, ...?settings['request'] as Map?};
    final groups = settings['groups'] as Map? ?? const {};
    final entries = settings['entries'] as Map? ?? const {};
    Future<void> set(String section, String key, Object? value) => _change(
      () => _store.setSetting(plugin, _id, bundle.preset, section, key, value),
    );
    return [
      Card(
        child: Column(
          children: [
            SwitchListTile(
              key: Key('novel-plugin-bind-${plugin.id}'),
              title: Text(plugin.manifest.name),
              subtitle: Text(!plugin.enabled ? '请先在插件管理中启用' : '对当前故事线生效'),
              value: scope.enabled,
              onChanged: _busy || !plugin.enabled
                  ? null
                  : (value) => _change(() async {
                      final available = await ref.read(
                        _pluginStatesProvider(_id).future,
                      );
                      if (value &&
                          available.any(
                            (other) =>
                                other.plugin.id != plugin.id &&
                                other.scope.enabled,
                          )) {
                        throw const FormatException('请先关闭当前绑定的提示词插件。');
                      }
                      await _store.enable(plugin, _id, value);
                      if (!value && mounted) {
                        ref.read(novelPluginMemoryProvider).cancel(_id);
                      }
                    }),
            ),
            if (canInherit)
              SwitchListTile(
                title: const Text('继承上级故事线设置'),
                value: scope.inherited,
                onChanged: _busy || !plugin.enabled
                    ? null
                    : (value) =>
                          _change(() => _store.inherit(plugin, _id, value)),
              ),
          ],
        ),
      ),
      if (scope.enabled) ...[
        ListTile(
          title: const Text('预设方案'),
          subtitle: const Text('切换文风，或保存当前配置'),
          trailing: const Icon(Icons.bookmarks_outlined),
          onTap: _busy ? null : () => _schemes(item),
        ),
        if (bundle.preset.schemes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in bundle.preset.schemes.entries)
                  ActionChip(
                    key: ValueKey('novel-plugin-scheme-${entry.key}'),
                    label: Text(entry.key),
                    onPressed: _busy
                        ? null
                        : () => _change(
                            () => _store.applyScheme(
                              plugin,
                              _id,
                              bundle.preset,
                              entry.value,
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ExpansionTile(
          title: Text('提示词条目 · ${bundle.preset.entries.length}'),
          children: [
            for (final group in bundle.preset.groups.entries)
              ListTile(
                title: Text(_groupLabel(group.key)),
                subtitle: Text(
                  _groupSelection(
                    bundle.preset,
                    group.value,
                    groups,
                    group.key,
                  ),
                ),
                onTap: _busy
                    ? null
                    : () async {
                        final choice = await showDialog<String>(
                          context: context,
                          builder: (dialog) => SimpleDialog(
                            title: Text(_groupLabel(group.key)),
                            children: [
                              SimpleDialogOption(
                                onPressed: () => Navigator.pop(dialog, ''),
                                child: const Text('关闭'),
                              ),
                              for (final id in group.value)
                                SimpleDialogOption(
                                  onPressed: () => Navigator.pop(dialog, id),
                                  child: Text(_label(bundle.preset, id)),
                                ),
                            ],
                          ),
                        );
                        if (choice != null && mounted) {
                          await set(
                            'groups',
                            group.key,
                            choice.isEmpty ? null : choice,
                          );
                        }
                      },
              ),
            for (final entry in bundle.preset.entries)
              if (!bundle.preset.groups.values.any(
                (ids) => ids.contains(entry.id),
              ))
                SwitchListTile(
                  title: Text(entry.name),
                  subtitle: Text(
                    '${entry.role.name} · ${entry.position.name} · ${entry.id}',
                  ),
                  value: entries[entry.id] as bool? ?? entry.enabled,
                  onChanged: _busy
                      ? null
                      : (value) => set('entries', entry.id, value),
                ),
          ],
        ),
        ExpansionTile(
          title: const Text('请求参数'),
          children: [
            for (final (key, name, integer) in [
              ('temperature', '温度', false),
              ('contextTokens', '上下文额度', true),
              ('outputTokens', '输出上限', true),
              ('top_p', 'Top P', false),
              ('frequency_penalty', '频率惩罚', false),
              ('presence_penalty', '存在惩罚', false),
              ('seed', '随机种子', true),
            ])
              ListTile(
                title: Text(name),
                subtitle: Text(request[key]?.toString() ?? '默认'),
                onTap: _busy
                    ? null
                    : () async {
                        final value = await _input(
                          name,
                          initial: request[key]?.toString() ?? '',
                          numeric: true,
                        );
                        if (value == null || !mounted) return;
                        final parsed = integer
                            ? int.tryParse(value)
                            : double.tryParse(value);
                        if (parsed == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请输入有效数字。')),
                          );
                          return;
                        }
                        await set('request', key, parsed);
                      },
              ),
            ListTile(
              title: const Text('推理等级'),
              subtitle: Text((request['reasoning'] ?? 'automatic').toString()),
              onTap: _busy
                  ? null
                  : () async {
                      final level = await showDialog<AiReasoningLevel>(
                        context: context,
                        builder: (dialog) => SimpleDialog(
                          title: const Text('推理等级'),
                          children: [
                            for (final value in AiReasoningLevel.values)
                              SimpleDialogOption(
                                onPressed: () => Navigator.pop(dialog, value),
                                child: Text(value.name),
                              ),
                          ],
                        ),
                      );
                      if (level != null && mounted) {
                        await set('request', 'reasoning', level.name);
                      }
                    },
            ),
            SwitchListTile(
              title: const Text('续写预填充'),
              subtitle: const Text('仅在接口支持时使用原文末尾作为预填充'),
              value: request['continuePrefill'] == true,
              onChanged: _busy
                  ? null
                  : (value) => set('request', 'continuePrefill', value),
            ),
            SwitchListTile(
              title: const Text('流式输出'),
              subtitle: const Text('同时遵循应用设置'),
              value: request['stream'] as bool? ?? true,
              onChanged: _busy
                  ? null
                  : (value) => set('request', 'stream', value),
            ),
          ],
        ),
        ListTile(
          title: const Text('作者与场景'),
          subtitle: const Text('设置小说专用的名字、人设和当前场景'),
          onTap: _busy ? null : () => _variables(item),
        ),
        ListTile(
          title: const Text('世界书引用'),
          subtitle: const Text('仅扫描本作品选用的世界书'),
          onTap: _busy ? null : () => _worldBooks(item),
        ),
        ListTile(
          key: const Key('novel-plugin-inspector'),
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('本轮提示词与实际参数'),
          onTap: () {
            final run = ref.read(novelPluginHostProvider).lastRun(_id);
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('提示词检查')),
                  body: run == null
                      ? const Center(child: Text('当前进程还没有本故事线的生成记录。'))
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            SelectableText(
                              const JsonEncoder.withIndent(
                                '  ',
                              ).convert(run.inspection()),
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
        if (plugin.manifest.capabilities.contains('novel-memory')) ...[
          SwitchListTile(
            title: const Text('自动整理记忆'),
            subtitle: Text('每 ${scope.batchSize} 段定稿后，使用本作模型整理'),
            value: scope.automaticMemory,
            onChanged: _busy
                ? null
                : (value) => _change(() async {
                    await _store.configureMemory(
                      plugin,
                      _id,
                      automatic: value,
                      batchSize: scope.batchSize,
                    );
                    if (!value && mounted) {
                      ref.read(novelPluginMemoryProvider).cancel(_id);
                    }
                  }),
          ),
          ListTile(
            title: const Text('记忆批次'),
            subtitle: Text('${scope.batchSize} 段'),
            onTap: _busy
                ? null
                : () async {
                    final value = await _input(
                      '记忆批次（1–50 段）',
                      initial: '${scope.batchSize}',
                      numeric: true,
                    );
                    final batch = int.tryParse(value ?? '');
                    if (batch != null && mounted) {
                      await _change(
                        () => _store.configureMemory(
                          plugin,
                          _id,
                          automatic: scope.automaticMemory,
                          batchSize: batch,
                        ),
                      );
                    }
                  },
          ),
          ListTile(
            leading: const Icon(Icons.psychology_outlined),
            title: const Text('记忆与后台任务'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    _NovelPluginMemoryPage(plugin: plugin, projectId: _id),
              ),
            ),
          ),
        ],
        if (plugin.manifest.permissions.contains('novel.session.end'))
          SwitchListTile(
            title: const Text('允许结束当前故事线'),
            subtitle: const Text('本轮回复完成后，可按结束标记关闭本条故事线。'),
            value: scope.allowEnd,
            onChanged: _busy
                ? null
                : (allowed) => _change(
                    () => _store.authorizeEnd(
                      plugin,
                      _id,
                      allowed,
                      userGesture: true,
                    ),
                  ),
          ),
      ],
      const Divider(),
    ];
  }

  String _label(NovelPluginPreset preset, String id) =>
      preset.entries.firstWhere((e) => e.id == id).name;

  String _groupSelection(
    NovelPluginPreset preset,
    List<String> ids,
    Map groups,
    String key,
  ) {
    final choice = groups.containsKey(key)
        ? groups[key] as String?
        : preset.entries
              .where((e) => e.enabled && ids.contains(e.id))
              .firstOrNull
              ?.id;
    return choice == null ? '关闭' : _label(preset, choice);
  }

  String _groupLabel(String key) => switch (key) {
    'tone' => '文风',
    'person' => '人称',
    'input' => '输入处理',
    'pace' => '节奏',
    'length' => '字数',
    'layout' => '版式',
    'lexicon' => '用词',
    _ => key,
  };

  Future<void> _schemes(_PluginState item) async {
    final saved = await _store.savedSchemes(item.plugin.id);
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('预设方案'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog, ''),
            child: const Text('保存当前配置'),
          ),
          for (final name in saved.keys)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, name),
              child: Text(name),
            ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice.isNotEmpty) {
      await _change(
        () => _store.applyScheme(
          item.plugin,
          _id,
          item.bundle.preset,
          saved[choice]!,
          complete: true,
        ),
      );
      return;
    }
    final name = await _input('方案名称');
    if (name != null && mounted) {
      await _change(
        () => _store.saveScheme(item.plugin, name, item.scope.settings),
      );
    }
  }

  Future<void> _variables(_PluginState item) async {
    final variables = Map<String, Object?>.from(
      item.scope.settings['variables'] as Map? ?? {},
    );
    final fields = <String, TextEditingController>{
      for (final field in ['user', 'persona', 'scenario'])
        field: TextEditingController(text: variables[field] as String? ?? ''),
    };
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('作者与场景'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (key, label) in [
              ('user', '作者名字'),
              ('persona', '作者人设'),
              ('scenario', '当前场景'),
            ])
              TextField(
                controller: fields[key],
                decoration: InputDecoration(labelText: label),
                maxLines: key == 'user' ? 1 : 3,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, {
              for (final e in fields.entries) e.key: e.value.text.trim(),
            }),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final field in fields.values) {
        field.dispose();
      }
    });
    if (result != null && mounted) {
      await _change(
        () => _store.saveSettings(item.plugin, _id, item.bundle.preset, {
          ...item.scope.settings,
          'variables': result,
        }),
      );
    }
  }

  Future<void> _worldBooks(_PluginState item) async {
    final books = await ref
        .read(worldRoleplayRepositoryProvider)
        .listWorldBookLibrary();
    if (!mounted) return;
    final ids = (item.scope.settings['worldBookIds'] as List? ?? [])
        .whereType<String>()
        .toSet();
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('世界书引用'),
          scrollable: true,
          content: books.isEmpty
              ? const Text('世界书库没有可选条目。')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final book in books)
                      CheckboxListTile(
                        value: ids.contains(book.id),
                        title: Text(book.name),
                        onChanged: (on) => setState(
                          () => on == true
                              ? ids.add(book.id)
                              : ids.remove(book.id),
                        ),
                      ),
                  ],
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, ids.toList()),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      await _change(
        () => _store.saveSettings(item.plugin, _id, item.bundle.preset, {
          ...item.scope.settings,
          'worldBookIds': selected,
        }),
      );
    }
  }

  Future<String?> _input(
    String title, {
    String initial = '',
    bool numeric = false,
  }) => showDialog<String>(
    context: context,
    builder: (dialog) {
      var value = initial;
      return AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initial,
          autofocus: true,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : TextInputType.text,
          onChanged: (text) => value = text.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, value),
            child: const Text('保存'),
          ),
        ],
      );
    },
  );
}

final _novelMemoryStateProvider = FutureProvider.autoDispose
    .family<
      ({String? status, List<NovelMemoryBlock> blocks}),
      (InstalledPlugin, String)
    >((ref, key) async {
      final (plugin, id) = key;
      ref.watch(
        novelPluginEventsProvider.select(
          (e) => e.value?.projectId == id ? e : null,
        ),
      );
      final host = ref.watch(novelPluginHostProvider);
      final memory = ref.watch(novelPluginMemoryProvider);
      final history = await host.repository.history(id);
      return (
        status: await memory.status(plugin, id),
        blocks: await host.memories(plugin, id, history),
      );
    });

class _NovelPluginMemoryPage extends ConsumerWidget {
  const _NovelPluginMemoryPage({required this.plugin, required this.projectId});
  final InstalledPlugin plugin;
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(novelPluginMemoryProvider);
    final data = ref.watch(_novelMemoryStateProvider((plugin, projectId)));
    final active = memory.isRunning(projectId);
    final ended =
        ref.watch(novelStoryBranchProvider(projectId)).value?.ended == true;
    return Scaffold(
      appBar: AppBar(title: const Text('插件记忆')),
      body: data.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('无法读取当前故事线记忆。')),
        data: (state) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.status != null) Text(state.status!),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: ended
                  ? null
                  : active
                  ? () => memory.cancel(projectId)
                  : () async {
                      try {
                        await memory.run(projectId, manual: true);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('整理未完成，请检查本作模型后重试。')),
                          );
                        }
                      }
                      if (context.mounted) {
                        ref.invalidate(
                          _novelMemoryStateProvider((plugin, projectId)),
                        );
                      }
                    },
              child: Text(active ? '停止整理' : '整理一批记忆'),
            ),
            if (state.blocks.isEmpty)
              const ListTile(title: Text('这条故事线还没有可用的插件记忆')),
            for (final block in state.blocks.reversed)
              ExpansionTile(
                title: Text('摘要 · ${block.coveredMessageIds.length} 段'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(block.content),
                  ),
                  SwitchListTile(
                    title: const Text('参与世界书扫描'),
                    value: block.scanForWorldInfo,
                    onChanged: active
                        ? null
                        : (value) async {
                            try {
                              await memory.setScan(
                                plugin,
                                projectId,
                                block.id,
                                value,
                              );
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('设置未保存，请重试。')),
                                );
                              }
                            }
                          },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
