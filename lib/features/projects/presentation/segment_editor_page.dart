import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../data/repositories/segment_repository.dart';
import '../../../domain/segments/segment.dart';
import '../../mascot/application/mascot_controller.dart';
import '../../mascot/domain/mascot_action.dart';
import 'project_flow_widgets.dart';
import 'segment_ai_dialog.dart';

class NewSegmentPage extends ConsumerStatefulWidget {
  const NewSegmentPage({
    required this.projectId,
    this.anchorSegmentId,
    this.insertBefore,
    this.returnToCreation = false,
    super.key,
  }) : assert(
         (anchorSegmentId == null && insertBefore == null) ||
             (anchorSegmentId != null && insertBefore != null),
       );

  final String projectId;
  final String? anchorSegmentId;
  final bool? insertBefore;
  final bool returnToCreation;

  @override
  ConsumerState<NewSegmentPage> createState() => _NewSegmentPageState();
}

class _NewSegmentPageState extends ConsumerState<NewSegmentPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  var _isSaving = false;

  bool get _hasUnsaved => _controller.text.isNotEmpty && !_isSaving;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_listenToInput);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectByIdProvider(widget.projectId));
    final anchor = widget.anchorSegmentId == null
        ? null
        : ref.watch(segmentByIdProvider(widget.anchorSegmentId!));
    return PopScope(
      canPop: !_hasUnsaved,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        if (await _confirmDiscard()) {
          if (context.mounted) {
            context.pop();
          }
        }
      },
      child: SafeArea(
        top: false,
        child: project.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ProjectFlowErrorView(
            title: '项目不存在',
            message: '没有找到这个项目，无法新增正文段落。',
            onAction: () => context.go(AppRoutes.projects),
          ),
          data: (project) {
            if (anchor == null) {
              return _buildForm(project.title);
            }
            return anchor.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => ProjectFlowErrorView(
                title: '插入位置不存在',
                message: '没有找到作为插入位置的正文段落。',
                onAction: () =>
                    context.go(AppRoutes.projectSegments(widget.projectId)),
              ),
              data: (anchor) {
                if (anchor.projectId != widget.projectId ||
                    anchor.deletedAt != null) {
                  return ProjectFlowErrorView(
                    title: '插入位置不可用',
                    message: '插入位置与当前项目不匹配，或该段落已经删除。',
                    onAction: () =>
                        context.go(AppRoutes.projectSegments(widget.projectId)),
                  );
                }
                return _buildForm(
                  '${project.title} · 第 ${anchor.orderIndex + 1} 段'
                  '${widget.insertBefore! ? '之前' : '之后'}',
                  anchorNumber: anchor.orderIndex + 1,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm(String subtitle, {int? anchorNumber}) {
    final isInsert = widget.anchorSegmentId != null;
    return _SegmentForm(
      key: Key(isInsert ? 'insert-segment-page' : 'new-segment-page'),
      title: isInsert
          ? '插入到第 ${anchorNumber ?? 1} 段'
                '${widget.insertBefore! ? '之前' : '之后'}'
          : '新增段落',
      subtitle: subtitle,
      controller: _controller,
      focusNode: _focusNode,
      isSaving: _isSaving,
      saveLabel: isInsert ? '插入段落' : '保存段落',
      onSave: _save,
    );
  }

  void _listenToInput() {
    if (!mounted || _isSaving) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.listen);
    setState(() {});
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }
    if (_controller.text.trim().isEmpty && !await _confirmEmptySegmentSave()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);

    try {
      final id = ref.read(entityIdGeneratorProvider).nextId('segment');
      final now = ref.read(utcClockProvider).now();
      final segment = widget.anchorSegmentId == null
          ? await ref.read(createSegmentProvider)(
              projectId: widget.projectId,
              content: _controller.text,
              id: id,
              nowUtc: now,
            )
          : await ref.read(insertSegmentProvider)(
              projectId: widget.projectId,
              anchorSegmentId: widget.anchorSegmentId!,
              position: widget.insertBefore!
                  ? SegmentInsertPosition.before
                  : SegmentInsertPosition.after,
              content: _controller.text,
              id: id,
              nowUtc: now,
            );
      if (!mounted) {
        return;
      }
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.segments]);
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      if (widget.returnToCreation) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.novelEditor(segment.projectId));
        }
      } else {
        context.go(AppRoutes.projectSegments(segment.projectId));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      _showSnack(_friendlyError(error));
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsaved) {
      return true;
    }
    return await showDiscardChangesDialog(context);
  }

  Future<bool> _confirmEmptySegmentSave() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('empty-segment-dialog'),
        title: const Text('保存空白段落？'),
        content: const Text('空正文可以保存，稍后仍然可以回来补写。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-empty-segment-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class SegmentEditorPage extends ConsumerStatefulWidget {
  const SegmentEditorPage({
    required this.projectId,
    required this.segmentId,
    super.key,
  });

  final String projectId;
  final String segmentId;

  @override
  ConsumerState<SegmentEditorPage> createState() => _SegmentEditorPageState();
}

class _SegmentEditorPageState extends ConsumerState<SegmentEditorPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Segment? _loadedSegment;
  var _originalContent = '';
  var _isSaving = false;
  var _isSyncingController = false;

  bool get _hasUnsaved => _controller.text != _originalContent && !_isSaving;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_listenToInput);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectByIdProvider(widget.projectId));
    final segment = ref.watch(segmentByIdProvider(widget.segmentId));
    final historyCount = ref.watch(
      segmentRevisionCountProvider(widget.segmentId),
    );

    return PopScope(
      canPop: !_hasUnsaved,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        if (await _confirmDiscard()) {
          if (context.mounted) {
            context.pop();
          }
        }
      },
      child: SafeArea(
        top: false,
        child: project.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ProjectFlowErrorView(
            title: '项目不存在',
            message: '没有找到这个项目，请返回项目列表重新选择。',
            onAction: () => context.go(AppRoutes.projects),
          ),
          data: (project) => segment.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => ProjectFlowErrorView(
              title: '段落不存在',
              message: '没有找到这个正文段落，请返回正文列表重新选择。',
              onAction: () => context.go(AppRoutes.projectSegments(project.id)),
            ),
            data: (segment) {
              if (segment.projectId != widget.projectId) {
                return ProjectFlowErrorView(
                  title: '段落不属于当前项目',
                  message: '这个段落与当前项目不匹配，请返回正文列表重新选择。',
                  onAction: () =>
                      context.go(AppRoutes.projectSegments(project.id)),
                );
              }
              _syncLoadedSegment(segment);
              final count = historyCount.maybeWhen(
                data: (value) => value,
                orElse: () => 0,
              );
              return _SegmentForm(
                key: const Key('edit-segment-page'),
                title: '编辑段落',
                subtitle: project.title,
                controller: _controller,
                focusNode: _focusNode,
                isSaving: _isSaving,
                saveLabel: '保存修改',
                revisionText:
                    'revision ${_loadedSegment?.revision ?? segment.revision}',
                historyText: '历史 $count',
                onSave: () => _save(segment),
                onAiSelection: () => _openSelectionAi(segment),
              );
            },
          ),
        ),
      ),
    );
  }

  void _syncLoadedSegment(Segment segment) {
    if (_loadedSegment?.id == segment.id) {
      return;
    }
    _loadedSegment = segment;
    _originalContent = segment.content;
    _isSyncingController = true;
    try {
      _controller.text = segment.content;
    } finally {
      _isSyncingController = false;
    }
  }

  void _listenToInput() {
    if (!mounted || _isSaving || _isSyncingController) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.listen);
    setState(() {});
  }

  Future<void> _save(Segment segment) async {
    if (_isSaving) {
      return;
    }
    if (_controller.text.trim().isEmpty &&
        _controller.text != _originalContent &&
        !await _confirmEmptySegmentSave()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);

    try {
      final updated = await ref.read(saveSegmentProvider)(
        currentSegment: segment,
        newContent: _controller.text,
        now: ref.read(utcClockProvider).now(),
        revisionId: ref
            .read(entityIdGeneratorProvider)
            .nextId('segment_revision'),
        note: '手机端手动编辑',
        mode: 'mobile_edit',
      );
      if (!mounted) {
        return;
      }
      _loadedSegment = updated;
      _originalContent = updated.content;
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.segments]);
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      setState(() {
        _isSaving = false;
      });
      _showSnack(updated.revision == segment.revision ? '正文没有变化。' : '正文已保存。');
    } catch (error) {
      if (!mounted) {
        return;
      }
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      _showSnack(_friendlyError(error));
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _openSelectionAi(Segment segment) async {
    if (_hasUnsaved) {
      _showSnack('请先保存当前手动修改，再使用 AI 选择性修改。');
      return;
    }
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      _showSnack('请先在正文输入框中选择需要修改的文字。');
      return;
    }
    final start = selection.start.clamp(0, segment.content.length);
    final end = selection.end.clamp(start, segment.content.length);
    final applied = await showSegmentAiDialog(
      context,
      segment: segment,
      operation: SegmentAiUiOperation.selectionModify,
      selectionStart: start,
      selectionEnd: end,
    );
    if (!applied || !mounted) {
      return;
    }
    final updated = await ref
        .read(segmentRepositoryProvider)
        .getSegment(segment.id);
    if (!mounted) {
      return;
    }
    _loadedSegment = updated;
    _originalContent = updated.content;
    _isSyncingController = true;
    try {
      _controller.text = updated.content;
    } finally {
      _isSyncingController = false;
    }
    setState(() {});
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsaved) {
      return true;
    }
    return await showDiscardChangesDialog(context);
  }

  Future<bool> _confirmEmptySegmentSave() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('empty-segment-dialog'),
        title: const Text('保存空白段落？'),
        content: const Text('空正文可以保存，稍后仍然可以回来补写。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-empty-segment-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SegmentForm extends StatelessWidget {
  const _SegmentForm({
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.focusNode,
    required this.isSaving,
    required this.saveLabel,
    required this.onSave,
    this.revisionText,
    this.historyText,
    this.onAiSelection,
    super.key,
  });

  final String title;
  final String subtitle;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSaving;
  final String saveLabel;
  final VoidCallback onSave;
  final String? revisionText;
  final String? historyText;
  final VoidCallback? onAiSelection;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppTokens.spacingM),
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppTokens.spacingXs),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTokens.spacingS),
              const MemoryDataNotice(),
              if (revisionText != null || historyText != null) ...[
                const SizedBox(height: AppTokens.spacingS),
                Wrap(
                  spacing: AppTokens.spacingS,
                  children: [
                    if (revisionText != null)
                      Chip(
                        key: const Key('editor-revision-label'),
                        label: Text(revisionText!),
                      ),
                    if (historyText != null)
                      Chip(
                        key: const Key('editor-history-count-label'),
                        label: Text(historyText!),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppTokens.spacingM),
              TextField(
                key: const Key('segment-content-field'),
                controller: controller,
                focusNode: focusNode,
                enabled: !isSaving,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 10,
                maxLines: 18,
                decoration: const InputDecoration(
                  labelText: '正文',
                  hintText: '写下一段正文，也可以先保存一个空白段落。',
                  alignLabelWithHint: true,
                ),
              ),
              if (onAiSelection != null) ...[
                const SizedBox(height: AppTokens.spacingS),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('ai-modify-selection-button'),
                    onPressed: isSaving ? null : onAiSelection,
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: const Text('AI 修改选中文字'),
                  ),
                ),
              ],
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
                key: const Key('save-segment-button'),
                onPressed: isSaving ? null : onSave,
                icon: isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(isSaving ? '保存中' : saveLabel),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<bool> showDiscardChangesDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('discard-changes-dialog'),
      title: const Text('放弃未保存内容？'),
      content: const Text('当前修改还没有保存，离开后会丢失。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('继续编辑'),
        ),
        FilledButton(
          key: const Key('confirm-discard-button'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('放弃'),
        ),
      ],
    ),
  );
  return result ?? false;
}

String _friendlyError(Object error) {
  final text = error.toString();
  if (text.contains('not found') || text.contains('not be found')) {
    return '目标不存在，请返回后重新选择。';
  }
  if (text.contains('already exists')) {
    return '保存冲突，请重新尝试。';
  }
  if (text.contains('不匹配') || text.contains('does not match')) {
    return '项目和段落不匹配，请返回后重新选择。';
  }
  return '保存失败，请稍后重试。';
}
