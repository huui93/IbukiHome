import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../application/projects/current_project_controller.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/world/world_card.dart';
import '../../mascot/application/mascot_controller.dart';
import '../../mascot/domain/mascot_action.dart';
import '../../projects/presentation/project_flow_widgets.dart';
import '../../ai/presentation/card_completion_dialog.dart';

class WorldCardListPage extends ConsumerWidget {
  const WorldCardListPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectByIdProvider(projectId));
    final cards = ref.watch(worldCardListProvider(projectId));
    return SafeArea(
      top: false,
      child: project.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _missingProject(context),
        data: (project) {
          if (project.deletedAt != null) {
            return _deletedProject(context);
          }
          _selectCurrentProject(ref, project.id);
          return cards.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ProjectFlowErrorView(
              title: '世界观读取失败',
              message: _friendlyError(error),
            ),
            data: (items) => ListView(
              key: const Key('world-card-list-page'),
              padding: const EdgeInsets.all(AppTokens.spacingM),
              children: [
                Text(
                  '世界观',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text('${project.title} · 世界观卡 ${items.length}'),
                const SizedBox(height: AppTokens.spacingS),
                Wrap(
                  spacing: AppTokens.spacingS,
                  runSpacing: AppTokens.spacingS,
                  children: [
                    FilledButton.icon(
                      key: const Key('new-world-card-button'),
                      onPressed: () =>
                          context.push(AppRoutes.newWorldCard(project.id)),
                      icon: const Icon(Icons.add),
                      label: const Text('新建世界观'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('deleted-world-cards-button'),
                      onPressed: () =>
                          context.push(AppRoutes.deletedWorldCards(project.id)),
                      icon: const Icon(Icons.restore_from_trash_outlined),
                      label: const Text('已删除'),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.spacingM),
                if (items.isEmpty)
                  const _WorldEmptyState(key: Key('empty-world-cards-state'))
                else
                  for (var index = 0; index < items.length; index += 1)
                    _WorldCardTile(
                      card: items[index],
                      index: index,
                      count: items.length,
                      onMove: (delta) =>
                          _move(context, ref, items, index, delta),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    List<WorldCard> items,
    int index,
    int delta,
  ) async {
    final target = index + delta;
    if (target < 0 || target >= items.length) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    final ordered = items.map((item) => item.id).toList();
    final moved = ordered.removeAt(index);
    ordered.insert(target, moved);
    try {
      await ref.read(reorderWorldCardsProvider)(
        projectId: projectId,
        orderedIds: ordered,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.worlds]);
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
    } catch (error) {
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      if (context.mounted) {
        _showSnack(context, _friendlyError(error));
      }
    }
  }
}

class NewWorldCardPage extends ConsumerStatefulWidget {
  const NewWorldCardPage({required this.projectId, super.key});

  final String projectId;

  @override
  ConsumerState<NewWorldCardPage> createState() => _NewWorldCardPageState();
}

class _NewWorldCardPageState extends ConsumerState<NewWorldCardPage> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  var _saving = false;
  String? _titleError;

  bool get _hasUnsaved =>
      !_saving && (_title.text.isNotEmpty || _content.text.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _title = TextEditingController()..addListener(_onInput);
    _content = TextEditingController()..addListener(_onInput);
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectByIdProvider(widget.projectId));
    return PopScope(
      canPop: !_hasUnsaved,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmDiscard() && context.mounted) {
          context.pop();
        }
      },
      child: SafeArea(
        top: false,
        child: project.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _missingProject(context),
          data: (project) => project.deletedAt != null
              ? _deletedProject(context)
              : _WorldCardForm(
                  pageKey: const Key('new-world-card-page'),
                  heading: '新建世界观',
                  projectTitle: project.title,
                  title: _title,
                  content: _content,
                  titleError: _titleError,
                  saving: _saving,
                  saveLabel: '创建世界观',
                  onSave: _save,
                ),
        ),
      ),
    );
  }

  void _onInput() {
    if (!mounted || _saving) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.listen);
    if (_titleError != null && _title.text.trim().isNotEmpty) {
      _titleError = null;
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = '世界观标题不能为空');
      return;
    }
    if (_content.text.trim().isEmpty && !await _confirmEmpty(context)) {
      return;
    }
    setState(() => _saving = true);
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      final card = await ref.read(createWorldCardProvider)(
        projectId: widget.projectId,
        title: _title.text,
        content: _content.text,
        id: ref.read(entityIdGeneratorProvider).nextId('world_card'),
        nowUtc: ref.read(utcClockProvider).now(),
      );
      if (!mounted) {
        return;
      }
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.worlds]);
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      context.go(AppRoutes.worldCard(widget.projectId, card.id));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      _showSnack(context, _friendlyError(error));
      setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsaved) {
      return true;
    }
    return _confirmDiscardChanges(context);
  }
}

class WorldCardDetailPage extends ConsumerWidget {
  const WorldCardDetailPage({
    required this.projectId,
    required this.worldCardId,
    super.key,
  });

  final String projectId;
  final String worldCardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectByIdProvider(projectId));
    final card = ref.watch(worldCardByIdProvider(worldCardId));
    return SafeArea(
      top: false,
      child: project.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _missingProject(context),
        data: (project) => project.deletedAt != null
            ? _deletedProject(context)
            : card.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => _missingWorldCard(context, projectId),
                data: (card) {
                  if (card.projectId != projectId || card.deletedAt != null) {
                    return _missingWorldCard(context, projectId);
                  }
                  return ListView(
                    key: const Key('world-card-detail-page'),
                    padding: const EdgeInsets.all(AppTokens.spacingM),
                    children: [
                      Text(
                        card.title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: AppTokens.spacingXs),
                      Text('所属项目：${project.title}'),
                      const SizedBox(height: AppTokens.spacingS),
                      Wrap(
                        spacing: AppTokens.spacingM,
                        children: [
                          Text('revision ${card.revision}'),
                          Text('更新 ${formatLocalDateTime(card.updatedAt)}'),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spacingM),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppTokens.spacingM),
                          child: SelectableText(
                            card.content.trim().isEmpty
                                ? '还没有填写世界观内容。'
                                : card.content,
                            key: const Key('world-card-detail-content'),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacingM),
                      Wrap(
                        spacing: AppTokens.spacingS,
                        runSpacing: AppTokens.spacingS,
                        children: [
                          FilledButton.icon(
                            key: const Key('edit-world-card-button'),
                            onPressed: () => context.push(
                              AppRoutes.editWorldCard(projectId, card.id),
                            ),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('编辑'),
                          ),
                          OutlinedButton.icon(
                            key: const Key('delete-world-card-button'),
                            onPressed: () => _delete(context, ref, card),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('删除'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    WorldCard card,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('delete-world-card-dialog'),
        title: const Text('删除世界观卡？'),
        content: Text('“${card.title}”会移到已删除世界观中，之后仍可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-delete-world-card-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      await ref.read(softDeleteWorldCardProvider)(
        projectId: projectId,
        worldCardId: card.id,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      if (!context.mounted) {
        return;
      }
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.worlds]);
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      context.go(AppRoutes.projectWorld(projectId));
    } catch (error) {
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      if (context.mounted) {
        _showSnack(context, _friendlyError(error));
      }
    }
  }
}

class EditWorldCardPage extends ConsumerStatefulWidget {
  const EditWorldCardPage({
    required this.projectId,
    required this.worldCardId,
    super.key,
  });

  final String projectId;
  final String worldCardId;

  @override
  ConsumerState<EditWorldCardPage> createState() => _EditWorldCardPageState();
}

class _EditWorldCardPageState extends ConsumerState<EditWorldCardPage> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  WorldCard? _loaded;
  var _originalTitle = '';
  var _originalContent = '';
  var _saving = false;
  var _syncing = false;
  String? _titleError;

  bool get _hasUnsaved =>
      !_saving &&
      (_title.text != _originalTitle || _content.text != _originalContent);

  @override
  void initState() {
    super.initState();
    _title = TextEditingController()..addListener(_onInput);
    _content = TextEditingController()..addListener(_onInput);
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectByIdProvider(widget.projectId));
    final card = ref.watch(worldCardByIdProvider(widget.worldCardId));
    return PopScope(
      canPop: !_hasUnsaved,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop &&
            await _confirmDiscardChanges(context) &&
            context.mounted) {
          context.pop();
        }
      },
      child: SafeArea(
        top: false,
        child: project.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _missingProject(context),
          data: (project) => project.deletedAt != null
              ? _deletedProject(context)
              : card.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => _missingWorldCard(context, widget.projectId),
                  data: (card) {
                    if (card.projectId != widget.projectId ||
                        card.deletedAt != null) {
                      return _missingWorldCard(context, widget.projectId);
                    }
                    _sync(card);
                    return _WorldCardForm(
                      pageKey: const Key('edit-world-card-page'),
                      heading: '编辑世界观',
                      projectTitle: project.title,
                      title: _title,
                      content: _content,
                      titleError: _titleError,
                      saving: _saving,
                      saveLabel: '保存修改',
                      revisionText:
                          'revision ${_loaded?.revision ?? card.revision}',
                      onAiComplete: () => _completeWithAi(card),
                      onSave: _save,
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _sync(WorldCard card) {
    if (_loaded?.id == card.id) {
      return;
    }
    _loaded = card;
    _originalTitle = card.title;
    _originalContent = card.content;
    _syncing = true;
    _title.text = card.title;
    _content.text = card.content;
    _syncing = false;
  }

  void _onInput() {
    if (!mounted || _saving || _syncing) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.listen);
    if (_titleError != null && _title.text.trim().isNotEmpty) {
      _titleError = null;
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = '世界观标题不能为空');
      return;
    }
    setState(() => _saving = true);
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      final updated = await ref.read(saveWorldCardProvider)(
        projectId: widget.projectId,
        worldCardId: widget.worldCardId,
        title: _title.text,
        content: _content.text,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      if (!mounted) {
        return;
      }
      _loaded = updated;
      _originalTitle = updated.title;
      _originalContent = updated.content;
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.worlds]);
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      setState(() => _saving = false);
      _showSnack(context, '世界观卡已保存。');
    } catch (error) {
      if (!mounted) {
        return;
      }
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      _showSnack(context, _friendlyError(error));
      setState(() => _saving = false);
    }
  }

  Future<void> _completeWithAi(WorldCard card) async {
    final options = await showCardCompletionOptions(context, worldCard: true);
    if (options == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final suggestions = await ref
          .read(cardCompletionServiceProvider)
          .completeWorld(
            card: card.copyWith(title: _title.text, content: _content.text),
            mode: options.mode,
            instruction: options.instruction,
            requestId: ref
                .read(entityIdGeneratorProvider)
                .nextId('card_completion'),
          );
      if (!mounted) return;
      final accepted = await showCardCompletionPreview(
        context: context,
        suggestions: suggestions,
        mode: options.mode,
      );
      if (accepted == null || !mounted) return;
      _syncing = true;
      if (accepted['title'] != null) _title.text = accepted['title']!;
      if (accepted['content'] != null) _content.text = accepted['content']!;
      _syncing = false;
      setState(() {});
    } catch (error) {
      if (mounted) _showSnack(context, _friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class DeletedWorldCardListPage extends ConsumerWidget {
  const DeletedWorldCardListPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectByIdProvider(projectId));
    final cards = ref.watch(deletedWorldCardListProvider(projectId));
    return SafeArea(
      top: false,
      child: project.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _missingProject(context),
        data: (project) => project.deletedAt != null
            ? _deletedProject(context)
            : cards.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ProjectFlowErrorView(
                  title: '已删除世界观读取失败',
                  message: _friendlyError(error),
                ),
                data: (items) => ListView(
                  key: const Key('deleted-world-card-list-page'),
                  padding: const EdgeInsets.all(AppTokens.spacingM),
                  children: [
                    Text(
                      '已删除世界观',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text('${project.title} · ${items.length} 张'),
                    const SizedBox(height: AppTokens.spacingM),
                    if (items.isEmpty)
                      const _WorldEmptyState(
                        key: Key('empty-deleted-world-cards'),
                        deleted: true,
                      )
                    else
                      for (final card in items)
                        Card(
                          child: ListTile(
                            key: Key('deleted-world-card-${card.id}'),
                            title: Text(card.title),
                            subtitle: Text(
                              '${_preview(card.content)}\n'
                              '删除 ${formatLocalDateTime(card.deletedAt!)}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            trailing: FilledButton.tonal(
                              key: Key('restore-world-card-${card.id}'),
                              onPressed: () => _restore(context, ref, card),
                              child: const Text('恢复'),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    WorldCard card,
  ) async {
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      await ref.read(restoreWorldCardProvider)(
        projectId: projectId,
        worldCardId: card.id,
        nowUtc: ref.read(utcClockProvider).now(),
      );
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.worlds]);
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      if (context.mounted) {
        _showSnack(context, '世界观卡已恢复。');
      }
    } catch (error) {
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      if (context.mounted) {
        _showSnack(context, _friendlyError(error));
      }
    }
  }
}

class _WorldCardForm extends StatelessWidget {
  const _WorldCardForm({
    required this.pageKey,
    required this.heading,
    required this.projectTitle,
    required this.title,
    required this.content,
    required this.titleError,
    required this.saving,
    required this.saveLabel,
    required this.onSave,
    this.onAiComplete,
    this.revisionText,
  });

  final Key pageKey;
  final String heading;
  final String projectTitle;
  final TextEditingController title;
  final TextEditingController content;
  final String? titleError;
  final bool saving;
  final String saveLabel;
  final VoidCallback onSave;
  final VoidCallback? onAiComplete;
  final String? revisionText;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: pageKey,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppTokens.spacingM),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Text(
                heading,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(projectTitle),
              if (revisionText != null) Text(revisionText!),
              const SizedBox(height: AppTokens.spacingM),
              TextField(
                key: const Key('world-card-title-field'),
                controller: title,
                enabled: !saving,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '标题',
                  errorText: titleError,
                ),
              ),
              if (onAiComplete != null) ...[
                const SizedBox(height: AppTokens.spacingM),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('world-ai-completion'),
                    onPressed: saving ? null : onAiComplete,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('AI 帮我补充'),
                  ),
                ),
              ],
              const SizedBox(height: AppTokens.spacingM),
              TextField(
                key: const Key('world-card-content-field'),
                controller: content,
                enabled: !saving,
                keyboardType: TextInputType.multiline,
                minLines: 10,
                maxLines: null,
                decoration: const InputDecoration(
                  labelText: '世界观内容',
                  hintText: '地点、组织、规则，或者一段历史',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spacingM,
              AppTokens.spacingS,
              AppTokens.spacingM,
              AppTokens.spacingM,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('save-world-card-button'),
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(saving ? '保存中' : saveLabel),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WorldCardTile extends StatelessWidget {
  const _WorldCardTile({
    required this.card,
    required this.index,
    required this.count,
    required this.onMove,
  });

  final WorldCard card;
  final int index;
  final int count;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        key: Key('world-card-tile-${card.id}'),
        title: Text(card.title),
        subtitle: Text(
          '${_preview(card.content)}\n'
          'revision ${card.revision} · '
          '更新 ${formatLocalDateTime(card.updatedAt)}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        onTap: () => context.push(AppRoutes.worldCard(card.projectId, card.id)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('move-world-card-up-${card.id}'),
              tooltip: '上移',
              onPressed: index == 0 ? null : () => onMove(-1),
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
            IconButton(
              key: Key('move-world-card-down-${card.id}'),
              tooltip: '下移',
              onPressed: index == count - 1 ? null : () => onMove(1),
              icon: const Icon(Icons.arrow_downward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorldEmptyState extends StatelessWidget {
  const _WorldEmptyState({this.deleted = false, super.key});

  final bool deleted;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spacingL),
        child: Column(
          children: [
            Icon(
              deleted
                  ? Icons.restore_from_trash_outlined
                  : Icons.public_outlined,
              size: 36,
            ),
            const SizedBox(height: AppTokens.spacingM),
            Text(deleted ? '没有已删除世界观卡。' : '这个项目还没有世界观卡。'),
            const SizedBox(height: AppTokens.spacingS),
            Text(
              deleted ? '删除的世界观卡会保留在这里，方便之后恢复。' : '可以从地点、组织、规则，或者一段历史开始。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _missingProject(BuildContext context) {
  return ProjectFlowErrorView(
    title: '项目不存在',
    message: '没有找到这个项目，请返回项目列表重新选择。',
    onAction: () => context.go(AppRoutes.projects),
  );
}

Widget _deletedProject(BuildContext context) {
  return ProjectFlowErrorView(
    title: '项目已删除',
    message: '这个项目已被删除，不能继续编辑世界观。',
    onAction: () => context.go(AppRoutes.projects),
  );
}

Widget _missingWorldCard(BuildContext context, String projectId) {
  return ProjectFlowErrorView(
    title: '世界观卡不存在',
    message: '没有找到这张世界观卡，或它不属于当前项目。',
    onAction: () => context.go(AppRoutes.projectWorld(projectId)),
    actionLabel: '返回世界观列表',
  );
}

void _selectCurrentProject(WidgetRef ref, String projectId) {
  if (ref.read(currentProjectControllerProvider) == projectId) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref
        .read(currentProjectControllerProvider.notifier)
        .selectProject(projectId);
  });
}

Future<bool> _confirmDiscardChanges(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('discard-world-card-changes-dialog'),
      title: const Text('放弃未保存的修改？'),
      content: const Text('返回后，这次输入的内容不会保留。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('继续编辑'),
        ),
        FilledButton(
          key: const Key('confirm-discard-world-card-changes'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('放弃修改'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<bool> _confirmEmpty(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('empty-world-card-content-dialog'),
      title: const Text('创建空内容世界观卡？'),
      content: const Text('可以先保存标题，之后再补充世界观内容。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('继续填写'),
        ),
        FilledButton(
          key: const Key('confirm-empty-world-card'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  return result ?? false;
}

String _preview(String content) {
  final value = content.trim();
  return value.isEmpty ? '内容为空' : value.replaceAll(RegExp(r'\s+'), ' ');
}

String _friendlyError(Object error) {
  final text = error.toString();
  if (text.contains('标题不能为空')) {
    return '世界观标题不能为空。';
  }
  if (text.contains('不属于当前项目')) {
    return '世界观卡不属于当前项目。';
  }
  if (text.contains('已删除')) {
    return '该项目或世界观卡已删除。';
  }
  return '操作失败，请稍后重试。';
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
