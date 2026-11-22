import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/projects/novel_prompt_presets.dart';
import '../../../domain/projects/novel_prompt_preset.dart';

Future<NovelPromptPreset?> showNovelPromptPresets(BuildContext context) =>
    showModalBottomSheet<NovelPromptPreset>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _PromptPresetSheet(),
    );

Future<NovelPromptPreset?> editNovelPromptPreset(
  BuildContext context, {
  NovelPromptPreset? previous,
  String content = '',
  String name = '',
}) => showDialog<NovelPromptPreset>(
  context: context,
  builder: (_) => _PresetEditor(
    previous: previous,
    initialContent: previous?.content ?? content,
    initialName: previous?.name ?? name,
  ),
);

class _PromptPresetSheet extends ConsumerWidget {
  const _PromptPresetSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(
        key: const Key('novel-prompt-preset-sheet'),
        children: [
          Text('提示词方案', style: Theme.of(context).textTheme.titleLarge),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('选择后载入当前小说，保存即可使用。'),
          ),
          Expanded(
            child: ref
                .watch(novelPromptPresetsProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Center(
                    child: TextButton(
                      onPressed: () =>
                          ref.invalidate(novelPromptPresetsProvider),
                      child: const Text('读取失败，点击重试'),
                    ),
                  ),
                  data: (items) => items.isEmpty
                      ? const Center(child: Text('还没有提示词方案'))
                      : ListView(
                          children: [
                            for (final preset in items)
                              ListTile(
                                key: Key('novel-preset-${preset.id}'),
                                title: Text(preset.name),
                                subtitle: Text(
                                  preset.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => Navigator.of(context).pop(preset),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: Key(
                                        'edit-novel-preset-${preset.id}',
                                      ),
                                      tooltip: '编辑方案',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => editNovelPromptPreset(
                                        context,
                                        previous: preset,
                                      ),
                                    ),
                                    IconButton(
                                      key: Key(
                                        'delete-novel-preset-${preset.id}',
                                      ),
                                      tooltip: '删除方案',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        final confirmed =
                                            await showDialog<bool>(
                                              context: context,
                                              builder: (dialog) => AlertDialog(
                                                title: const Text('删除提示词方案？'),
                                                content: Text(preset.name),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          dialog,
                                                          false,
                                                        ),
                                                    child: const Text('取消'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          dialog,
                                                          true,
                                                        ),
                                                    child: const Text('删除'),
                                                  ),
                                                ],
                                              ),
                                            );
                                        if (confirmed != true ||
                                            !context.mounted) {
                                          return;
                                        }
                                        try {
                                          await ref
                                              .read(
                                                novelPromptPresetServiceProvider,
                                              )
                                              .delete(preset);
                                        } catch (_) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  '删除失败，请重新打开方案库后重试。',
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
          ),
        ],
      ),
    ),
  );
}

class _PresetEditor extends ConsumerStatefulWidget {
  const _PresetEditor({
    this.previous,
    required this.initialContent,
    required this.initialName,
  });
  final NovelPromptPreset? previous;
  final String initialContent;
  final String initialName;
  @override
  ConsumerState<_PresetEditor> createState() => _PresetEditorState();
}

class _PresetEditorState extends ConsumerState<_PresetEditor> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _content = TextEditingController(text: widget.initialContent);
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      key: const Key('novel-preset-editor'),
      scrollable: true,
      title: Text(widget.previous == null ? '保存为提示词方案' : '编辑提示词方案'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('novel-preset-name'),
              controller: _name,
              enabled: !_saving,
              decoration: InputDecoration(labelText: '方案名称', errorText: _error),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('novel-preset-content'),
              controller: _content,
              enabled: !_saving,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: '系统提示词',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('save-novel-preset'),
          onPressed: _saving
              ? null
              : () async {
                  if (_name.text.trim().isEmpty) {
                    setState(() => _error = '请填写方案名称。');
                    return;
                  }
                  setState(() {
                    _saving = true;
                    _error = null;
                  });
                  try {
                    final preset = await ref
                        .read(novelPromptPresetServiceProvider)
                        .save(
                          name: _name.text,
                          content: _content.text,
                          previous: widget.previous,
                        );
                    if (context.mounted) Navigator.pop(context, preset);
                  } catch (_) {
                    if (mounted) {
                      setState(() {
                        _saving = false;
                        _error = '保存失败，请重新打开后重试。';
                      });
                    }
                  }
                },
          child: Text(_saving ? '保存中' : '保存方案'),
        ),
      ],
    ),
  );
}
