import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routing/app_routes.dart';
import '../../../application/tavern/tavern_presentation_providers.dart';
import '../../../application/tavern/tavern_story_service.dart';

class TavernAvatar extends StatelessWidget {
  const TavernAvatar(this.name, {this.path, this.size = 36, super.key});
  final String name;
  final String? path;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ClipOval(
      child: path != null && path!.isNotEmpty && !path!.startsWith('http')
          ? Image.file(
              File(path!),
              fit: BoxFit.cover,
              cacheWidth: 128,
              errorBuilder: (_, _, _) => _fallback(context),
            )
          : _fallback(context),
    ),
  );
  Widget _fallback(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Center(child: Text(name.isEmpty ? '?' : name.characters.first)),
  );
}

Future<T?> tavernSheet<T>(
  BuildContext context,
  String title,
  Widget child,
) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          Expanded(child: child),
        ],
      ),
    ),
  ),
);

Future<String?> tavernNameDialog(
  BuildContext context,
  String title, {
  String initial = '',
}) async {
  final input = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: input,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(labelText: '名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (input.text.trim().isNotEmpty) {
              Navigator.pop(context, input.text.trim());
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  // Dialog exit animation may still refer to its controller.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  input.dispose();
  return value;
}

Future<bool> tavernConfirm(
  BuildContext context,
  String title,
  String message,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class TavernModelPicker extends ConsumerStatefulWidget {
  const TavernModelPicker({required this.onSelected, super.key});
  final ValueChanged<Map<String, Object?>> onSelected;
  @override
  ConsumerState<TavernModelPicker> createState() => _TavernModelPickerState();
}

class _TavernModelPickerState extends ConsumerState<TavernModelPicker> {
  bool compatibility = true, local = false;
  late final configs = ref
      .read(tavernStoryServiceProvider)
      .configs
      .listConfigs();
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: configs,
    builder: (context, snapshot) => ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        SwitchListTile(
          title: const Text('兼容续写'),
          subtitle: const Text('不支持原生续写时，采用续写指令。'),
          value: compatibility,
          onChanged: (v) => setState(() => compatibility = v),
        ),
        SwitchListTile(
          title: const Text('允许本地 HTTP 服务'),
          value: local,
          onChanged: (v) => setState(() => local = v),
        ),
        if (!snapshot.hasData) const Center(child: CircularProgressIndicator()),
        for (final config in snapshot.data ?? [])
          if (config.enabled) ...[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                config.displayName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final model in {
              ...config.availableModels,
              if (config.selectedModel.isNotEmpty) config.selectedModel,
            })
              ListTile(
                title: Text(model),
                leading: const Icon(Icons.auto_awesome_outlined),
                onTap: () async {
                  final settings = await ref
                      .read(tavernStoryServiceProvider)
                      .modelSettings(
                        config,
                        model,
                        compatibleContinue: compatibility,
                        localHttp: local,
                      );
                  if (!context.mounted) return;
                  widget.onSelected(settings);
                  Navigator.pop(context);
                },
              ),
          ],
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('打开 API 设置'),
          onTap: () {
            Navigator.pop(context);
            context.push(AppRoutes.aiProviders);
          },
        ),
        ListTile(
          title: const Text('稍后配置'),
          onTap: () {
            widget.onSelected({});
            Navigator.pop(context);
          },
        ),
      ],
    ),
  );
}

String tavernWorldName(TavernAssetCatalog? assets, String? type, String? id) =>
    assets?.worlds
        .where((w) => w.type == type && w.id == id)
        .firstOrNull
        ?.name ??
    (id == null ? '自由故事' : '关联世界暂不可用');
