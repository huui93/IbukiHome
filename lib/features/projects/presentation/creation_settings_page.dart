import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../app/widgets/ibuki_buttons.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../core/errors/data_exceptions.dart';
import '../../../domain/outline/outline_node.dart';
import '../../../domain/memory/memory_generation_status.dart';
import '../../../domain/memory/story_memory_digest.dart';
import '../../../domain/projects/project.dart';
import '../../ai/presentation/ai_ui_helpers.dart';
import 'project_flow_widgets.dart';
import 'novel_prompt_preset_sheet.dart';

class CreationSettingsPage extends StatelessWidget {
  const CreationSettingsPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('creation-settings-page'),
      child: _SystemPromptTab(projectId: projectId),
    );
  }
}

class NovelOutlinePage extends StatelessWidget {
  const NovelOutlinePage({required this.projectId, super.key});
  final String projectId;
  @override
  Widget build(BuildContext context) => _NovelSettingsOwner(
    projectId: projectId,
    child: _OutlineTab(projectId: projectId),
  );
}

class NovelLongMemoryPage extends StatelessWidget {
  const NovelLongMemoryPage({required this.projectId, super.key});
  final String projectId;
  @override
  Widget build(BuildContext context) => _NovelSettingsOwner(
    projectId: projectId,
    child: _LongTermMemoryTab(projectId: projectId),
  );
}

class _NovelSettingsOwner extends ConsumerWidget {
  const _NovelSettingsOwner({required this.projectId, required this.child});
  final String projectId;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(projectByIdProvider(projectId))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('无法读取这部作品。')),
        data: (project) => project.deletedAt == null
            ? child
            : const Center(child: Text('作品已删除。')),
      );
}

class _SystemPromptTab extends ConsumerStatefulWidget {
  const _SystemPromptTab({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_SystemPromptTab> createState() => _SystemPromptTabState();
}

class _SystemPromptTabState extends ConsumerState<_SystemPromptTab> {
  final _controller = TextEditingController();
  String? _loadedProjectId;
  bool _saving = false;
  String? _notice;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectByIdProvider(widget.projectId));
    return project.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ProjectFlowErrorView(
        title: '无法打开系统提示词',
        message: '无法读取创作设定。',
        onAction: () => ref.invalidate(projectByIdProvider(widget.projectId)),
      ),
      data: (value) {
        if (value.deletedAt != null) return const Center(child: Text('作品已删除。'));
        _loadOnce(value);
        return SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(AppTokens.spacingM),
                  children: [
                    Text(
                      '系统提示词',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '这里的要求会持续用于小说生成、重写和修改。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spacingM),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('choose-novel-preset'),
                          onPressed: _saving
                              ? null
                              : () async {
                                  final preset = await showNovelPromptPresets(
                                    context,
                                  );
                                  if (preset == null || !mounted) return;
                                  _controller.text = preset.content;
                                  _showMessage(
                                    '已载入“${preset.name}”，保存后用于这部小说。',
                                  );
                                },
                          icon: const Icon(Icons.library_books_outlined),
                          label: const Text('选用方案'),
                        ),
                        TextButton.icon(
                          key: const Key('save-as-novel-preset'),
                          onPressed: _saving
                              ? null
                              : () async {
                                  final preset = await editNovelPromptPreset(
                                    context,
                                    content: _controller.text,
                                    name: '${value.title} 的提示词',
                                  );
                                  if (preset != null && mounted) {
                                    _showMessage('提示词方案已保存。');
                                  }
                                },
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('保存为方案'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_notice != null) ...[
                      Text(
                        _notice!,
                        key: const Key('novel-prompt-notice'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    IbukiGlassSurface(
                      strong: true,
                      padding: const EdgeInsets.all(AppTokens.spacingM),
                      child: TextField(
                        key: const Key('project-system-prompt-field'),
                        controller: _controller,
                        minLines: 12,
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: '告诉伊吹，这部作品应该怎么写……',
                          border: InputBorder.none,
                          filled: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IbukiPrimaryButton(
                    key: const Key('save-system-prompt-button'),
                    label: '保存',
                    icon: Icons.save_outlined,
                    loading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _loadOnce(Project project) {
    if (_loadedProjectId == project.id) return;
    _loadedProjectId = project.id;
    _notice = null;
    _controller.text = project.systemPrompt;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(saveProjectSystemPromptProvider)(
        projectId: widget.projectId,
        systemPrompt: _controller.text,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      if (!mounted) return;
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.projects]);
      _showMessage('系统提示词已保存。');
    } catch (error) {
      if (mounted) {
        final detail = describeAiError(error, stage: 'project-save');
        _showError(detail);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    setState(() => _notice = message);
  }

  void _showError(AiUiErrorPresentation error) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(error.summary),
          action: SnackBarAction(
            label: '详情',
            onPressed: () => showAiErrorDetails(context, error),
          ),
        ),
      );
  }
}

class _LongTermMemoryTab extends ConsumerStatefulWidget {
  const _LongTermMemoryTab({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_LongTermMemoryTab> createState() => _LongTermMemoryTabState();
}

class _LongTermMemoryTabState extends ConsumerState<_LongTermMemoryTab> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final digest = ref.watch(storyMemoryDigestProvider(widget.projectId));
    final chunks = ref.watch(novelSummaryChunkListProvider(widget.projectId));
    return SafeArea(
      top: false,
      child: digest.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('无法读取长期记忆。')),
        data: (digestValue) => chunks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text('无法读取摘要块。')),
          data: (items) => ListView(
            key: const Key('novel-long-memory-page'),
            padding: const EdgeInsets.all(AppTokens.spacingM),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      items.isEmpty
                          ? '较远前文会在达到完整分块后自动整理。'
                          : '已覆盖至第 ${items.map((item) => item.sourceEndOrder).reduce((a, b) => a > b ? a : b) + 1} 段',
                    ),
                  ),
                  IbukiSecondaryButton(
                    key: const Key('refresh-novel-memory'),
                    label: _refreshing ? '刷新中' : '刷新',
                    icon: Icons.refresh_rounded,
                    onPressed: _refreshing ? null : _refresh,
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spacingM),
              IbukiGlassSurface(
                key: const Key('story-memory-digest'),
                strong: true,
                padding: const EdgeInsets.all(AppTokens.spacingM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '故事记忆',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (digestValue?.isPinned == true)
                          const Icon(Icons.push_pin_rounded, size: 18),
                        IconButton(
                          key: const Key('edit-story-memory'),
                          tooltip: '编辑长期记忆',
                          onPressed: () => _editDigest(digestValue),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                    Text(
                      digestValue?.content.trim().isNotEmpty == true
                          ? digestValue!.content
                          : '还没有故事长期摘要。原始正文始终完整保留。',
                    ),
                    if (digestValue?.isProtected == true)
                      TextButton.icon(
                        key: const Key('restore-automatic-digest'),
                        onPressed: _restoreAutomatic,
                        icon: const Icon(Icons.auto_fix_high_outlined),
                        label: const Text('恢复自动摘要'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.spacingL),
              Text('摘要块', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppTokens.spacingS),
              if (items.isEmpty)
                const Text('尚未达到自动压缩阈值。近期正文会继续以原文进入 AI 上下文。')
              else
                for (final chunk in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTokens.spacingS),
                    child: IbukiGlassSurface(
                      key: Key('summary-chunk-${chunk.id}'),
                      padding: const EdgeInsets.all(AppTokens.spacingM),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(_statusIcon(chunk.status), size: 20),
                          const SizedBox(width: AppTokens.spacingM),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${chunk.sourceStartOrder + 1}-${chunk.sourceEndOrder + 1} 段 · ${_statusLabel(chunk.status)}',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                if (chunk.summary.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    chunk.summary,
                                    maxLines: 5,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
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
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await ref.read(novelMemoryServiceProvider).refresh(widget.projectId);
      notifyRepositoryChanged(
        ref,
        areas: const [RepositoryDataArea.novelMemory],
      );
      if (mounted) _message('长期记忆已刷新。');
    } catch (_) {
      if (mounted) _message('摘要刷新失败，正文不受影响，可以稍后重试。');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _editDigest(StoryMemoryDigest? digest) async {
    final controller = TextEditingController(text: digest?.content ?? '');
    var pinned = digest?.isPinned ?? false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            AppTokens.spacingM,
            0,
            AppTokens.spacingM,
            MediaQuery.viewInsetsOf(context).bottom + AppTokens.spacingM,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('story-memory-editor'),
                controller: controller,
                minLines: 8,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: '故事长期记忆',
                  hintText: '修正对后续创作仍然重要的事实……',
                ),
              ),
              SwitchListTile(
                title: const Text('固定人工修正'),
                subtitle: const Text('自动整理不会覆盖这份内容。'),
                value: pinned,
                onChanged: (value) => setSheetState(() => pinned = value),
              ),
              IbukiPrimaryButton(
                key: const Key('save-story-memory'),
                label: '保存',
                icon: Icons.save_outlined,
                expand: true,
                onPressed: () async {
                  await ref
                      .read(novelMemoryServiceProvider)
                      .saveUserDigest(
                        projectId: widget.projectId,
                        content: controller.text,
                        pinned: pinned,
                        nowUtc: ref.read(utcClockProvider).now(),
                      );
                  notifyRepositoryChanged(
                    ref,
                    areas: const [RepositoryDataArea.novelMemory],
                  );
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _restoreAutomatic() async {
    await ref
        .read(novelMemoryServiceProvider)
        .restoreAutomaticDigest(
          widget.projectId,
          ref.read(utcClockProvider).now(),
        );
    notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.novelMemory]);
  }

  void _message(String value) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  IconData _statusIcon(MemoryGenerationStatus status) => switch (status) {
    MemoryGenerationStatus.valid => Icons.check_circle_outline_rounded,
    MemoryGenerationStatus.stale => Icons.update_rounded,
    MemoryGenerationStatus.generating => Icons.hourglass_top_rounded,
    MemoryGenerationStatus.failed => Icons.error_outline_rounded,
  };

  String _statusLabel(MemoryGenerationStatus status) => switch (status) {
    MemoryGenerationStatus.valid => '已完成',
    MemoryGenerationStatus.stale => '需要更新',
    MemoryGenerationStatus.generating => '正在整理',
    MemoryGenerationStatus.failed => '生成失败',
  };
}

class _OutlineTab extends ConsumerWidget {
  const _OutlineTab({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outline = ref.watch(outlineListProvider(projectId));
    return outline.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ProjectFlowErrorView(
        title: '无法打开大纲',
        message: '无法读取大纲。',
        onAction: () => ref.invalidate(outlineListProvider(projectId)),
      ),
      data: (nodes) => SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spacingM,
                AppTokens.spacingM,
                AppTokens.spacingM,
                AppTokens.spacingS,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '由你控制剧情阶段，AI 不会自动改变状态。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('add-outline-node-button'),
                    tooltip: '新建大纲节点',
                    onPressed: () => _editNode(context, ref, null),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: nodes.isEmpty
                  ? _OutlineEmptyState(
                      onCreate: () => _editNode(context, ref, null),
                    )
                  : ReorderableListView.builder(
                      key: const Key('outline-node-list'),
                      padding: const EdgeInsets.fromLTRB(
                        AppTokens.spacingM,
                        AppTokens.spacingS,
                        AppTokens.spacingM,
                        AppTokens.spacingXl,
                      ),
                      itemCount: nodes.length,
                      onReorderItem: (oldIndex, newIndex) =>
                          _reorder(context, ref, nodes, oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final node = nodes[index];
                        return Padding(
                          key: ValueKey('outline-${node.id}'),
                          padding: const EdgeInsets.only(
                            bottom: AppTokens.spacingS,
                          ),
                          child: _OutlineNodeCard(
                            node: node,
                            onEdit: () => _editNode(context, ref, node),
                            onStatus: (status) =>
                                _setStatus(context, ref, node, status),
                            onDelete: () => _delete(context, ref, node),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNode(
    BuildContext context,
    WidgetRef ref,
    OutlineNode? node,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OutlineEditorSheet(projectId: projectId, node: node),
    );
  }

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    OutlineNode node,
    OutlineNodeStatus status,
  ) async {
    try {
      await ref.read(setOutlineNodeStatusProvider)(
        projectId: projectId,
        outlineNodeId: node.id,
        status: status,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.outlines]);
    } catch (_) {
      if (context.mounted) _message(context, '状态更新失败，请稍后重试。');
    }
  }

  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    List<OutlineNode> nodes,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) return;
    final ordered = nodes.map((item) => item.id).toList();
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);
    try {
      await ref.read(reorderOutlineNodesProvider)(
        projectId: projectId,
        orderedIds: ordered,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.outlines]);
    } catch (_) {
      if (context.mounted) _message(context, '排序失败，请稍后重试。');
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    OutlineNode node,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除大纲节点？'),
        content: Text('“${node.title}”将从当前大纲中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(softDeleteOutlineNodeProvider)(
        projectId: projectId,
        outlineNodeId: node.id,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.outlines]);
    } catch (_) {
      if (context.mounted) _message(context, '删除失败，请稍后重试。');
    }
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _OutlineEditorSheet extends ConsumerStatefulWidget {
  const _OutlineEditorSheet({required this.projectId, required this.node});

  final String projectId;
  final OutlineNode? node;

  @override
  ConsumerState<_OutlineEditorSheet> createState() =>
      _OutlineEditorSheetState();
}

class _OutlineEditorSheetState extends ConsumerState<_OutlineEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _summary;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.node?.title ?? '');
    _summary = TextEditingController(text: widget.node?.summary ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppTokens.spacingM,
          0,
          AppTokens.spacingM,
          MediaQuery.viewInsetsOf(context).bottom + AppTokens.spacingM,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.node == null ? '新建大纲节点' : '编辑大纲节点',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppTokens.spacingM),
            TextField(
              key: const Key('outline-title-field'),
              controller: _title,
              maxLength: 120,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            const SizedBox(height: AppTokens.spacingS),
            TextField(
              key: const Key('outline-summary-field'),
              controller: _summary,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: '简要描述'),
            ),
            const SizedBox(height: AppTokens.spacingM),
            IbukiPrimaryButton(
              key: const Key('save-outline-node-button'),
              label: '保存',
              icon: Icons.save_outlined,
              expand: true,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final node = widget.node;
      if (node == null) {
        await ref.read(createOutlineNodeProvider)(
          projectId: widget.projectId,
          title: _title.text,
          summary: _summary.text,
          id: ref.read(entityIdGeneratorProvider).nextId('outline'),
          nowUtc: ref.read(utcClockProvider).now(),
        );
      } else {
        await ref.read(saveOutlineNodeProvider)(
          projectId: widget.projectId,
          outlineNodeId: node.id,
          title: _title.text,
          summary: _summary.text,
          nowUtc: ref.read(utcClockProvider).now(),
        );
      }
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.outlines]);
      if (mounted) Navigator.pop(context);
    } on DataException catch (error) {
      if (mounted) _message(context, error.message);
    } catch (_) {
      if (mounted) _message(context, '保存失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _OutlineNodeCard extends StatelessWidget {
  const _OutlineNodeCard({
    required this.node,
    required this.onEdit,
    required this.onStatus,
    required this.onDelete,
  });

  final OutlineNode node;
  final VoidCallback onEdit;
  final ValueChanged<OutlineNodeStatus> onStatus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final status = switch (node.status) {
      OutlineNodeStatus.completed => ('已完成', Icons.check_circle_rounded),
      OutlineNodeStatus.current => ('当前', Icons.radio_button_checked_rounded),
      OutlineNodeStatus.planned => (
        '未开始',
        Icons.radio_button_unchecked_rounded,
      ),
    };
    return IbukiGlassSurface(
      padding: const EdgeInsets.all(AppTokens.spacingM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            status.$2,
            size: 22,
            color: node.status == OutlineNodeStatus.current
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppTokens.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  status.$1,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (node.summary.isNotEmpty) ...[
                  const SizedBox(height: AppTokens.spacingS),
                  Text(
                    node.summary,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<_OutlineAction>(
            key: Key('outline-menu-${node.id}'),
            tooltip: '更多',
            onSelected: (action) {
              switch (action) {
                case _OutlineAction.edit:
                  onEdit();
                case _OutlineAction.current:
                  onStatus(OutlineNodeStatus.current);
                case _OutlineAction.completed:
                  onStatus(OutlineNodeStatus.completed);
                case _OutlineAction.planned:
                  onStatus(OutlineNodeStatus.planned);
                case _OutlineAction.delete:
                  onDelete();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: _OutlineAction.edit, child: Text('编辑')),
              PopupMenuDivider(),
              PopupMenuItem(value: _OutlineAction.current, child: Text('设为当前')),
              PopupMenuItem(
                value: _OutlineAction.completed,
                child: Text('标记完成'),
              ),
              PopupMenuItem(
                value: _OutlineAction.planned,
                child: Text('重新设为未开始'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(value: _OutlineAction.delete, child: Text('删除')),
            ],
          ),
          const SizedBox(width: 4),
          const Icon(Icons.drag_handle_rounded, size: 20),
        ],
      ),
    );
  }
}

class _OutlineEmptyState extends StatelessWidget {
  const _OutlineEmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.route_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppTokens.spacingM),
            Text('还没有大纲节点', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.spacingS),
            const Text('从当前剧情目标开始，逐步安排作品接下来的方向。'),
            const SizedBox(height: AppTokens.spacingM),
            IbukiSecondaryButton(
              label: '新建节点',
              icon: Icons.add_rounded,
              onPressed: onCreate,
            ),
          ],
        ),
      ),
    );
  }
}

enum _OutlineAction { edit, current, completed, planned, delete }
