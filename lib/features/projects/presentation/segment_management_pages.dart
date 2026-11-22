import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/segments/segment.dart';
import '../../../domain/segments/segment_revision.dart';
import '../../mascot/application/mascot_controller.dart';
import '../../mascot/domain/mascot_action.dart';
import 'project_flow_widgets.dart';

class SegmentDetailPage extends ConsumerWidget {
  const SegmentDetailPage({
    required this.projectId,
    required this.segmentId,
    super.key,
  });

  final String projectId;
  final String segmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectByIdProvider(projectId));
    final segment = ref.watch(segmentByIdProvider(segmentId));
    final history = ref.watch(
      segmentHistoryProvider((projectId: projectId, segmentId: segmentId)),
    );
    return SafeArea(
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
            onAction: () => context.go(AppRoutes.projectSegments(projectId)),
          ),
          data: (segment) {
            if (segment.projectId != projectId) {
              return ProjectFlowErrorView(
                title: '段落不属于当前项目',
                message: '这个段落与当前项目不匹配。',
                onAction: () =>
                    context.go(AppRoutes.projectSegments(projectId)),
              );
            }
            if (segment.deletedAt != null) {
              return ProjectFlowErrorView(
                title: '段落已删除',
                message: '请从“已删除正文”恢复后再查看。',
                onAction: () =>
                    context.go(AppRoutes.deletedSegments(projectId)),
                actionLabel: '查看已删除正文',
              );
            }
            final historyCount = history.maybeWhen(
              data: (items) => items.length,
              orElse: () => 0,
            );
            return ListView(
              key: const Key('segment-detail-page'),
              padding: const EdgeInsets.all(AppTokens.spacingM),
              children: [
                Text(
                  '第 ${segment.orderIndex + 1} 段',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppTokens.spacingXs),
                Text(
                  project.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTokens.spacingM),
                Wrap(
                  spacing: AppTokens.spacingS,
                  runSpacing: AppTokens.spacingS,
                  children: [
                    Chip(label: Text('revision ${segment.revision}')),
                    Chip(
                      key: const Key('segment-detail-history-count'),
                      label: Text('历史 $historyCount'),
                    ),
                    Chip(
                      label: Text(
                        '更新 ${formatLocalDateTime(segment.updatedAt)}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.spacingM),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTokens.radiusM),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.spacingM),
                    child: SelectableText(
                      segment.content.isEmpty ? '空白段落' : segment.content,
                      key: const Key('segment-detail-content'),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.spacingM),
                Wrap(
                  spacing: AppTokens.spacingS,
                  runSpacing: AppTokens.spacingS,
                  children: [
                    FilledButton.icon(
                      key: const Key('edit-segment-detail-button'),
                      onPressed: () => context.push(
                        AppRoutes.editSegment(projectId, segmentId),
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('编辑'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('segment-history-button'),
                      onPressed: () => context.push(
                        AppRoutes.segmentHistory(projectId, segmentId),
                      ),
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('历史版本'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('insert-before-detail-button'),
                      onPressed: () => context.push(
                        AppRoutes.insertSegment(
                          projectId,
                          segmentId,
                          before: true,
                        ),
                      ),
                      icon: const Icon(Icons.vertical_align_top_rounded),
                      label: const Text('在前插入'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('insert-after-detail-button'),
                      onPressed: () => context.push(
                        AppRoutes.insertSegment(
                          projectId,
                          segmentId,
                          before: false,
                        ),
                      ),
                      icon: const Icon(Icons.vertical_align_bottom_rounded),
                      label: const Text('在后插入'),
                    ),
                    TextButton.icon(
                      key: const Key('delete-segment-detail-button'),
                      onPressed: () => _delete(context, ref, segment),
                      icon: const Icon(Icons.delete_outline_rounded),
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
    Segment segment,
  ) async {
    if (!await showSegmentDeleteDialog(context)) {
      return;
    }
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      await ref.read(softDeleteSegmentProvider)(
        projectId: projectId,
        segmentId: segment.id,
        deletedAt: ref.read(utcClockProvider).now(),
      );
      if (!context.mounted) {
        return;
      }
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.segments]);
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      context.go(AppRoutes.projectSegments(projectId));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      showSegmentSnack(context, friendlySegmentError(error));
    }
  }
}

class DeletedSegmentListPage extends ConsumerWidget {
  const DeletedSegmentListPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectByIdProvider(projectId));
    final deleted = ref.watch(deletedSegmentListProvider(projectId));
    return SafeArea(
      top: false,
      child: project.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ProjectFlowErrorView(
          title: '项目不存在',
          message: '没有找到这个项目。',
          onAction: () => context.go(AppRoutes.projects),
        ),
        data: (project) => deleted.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ProjectFlowErrorView(
            title: '已删除正文读取失败',
            message: '暂时无法读取已删除正文，请稍后重试。',
            onAction: () => context.go(AppRoutes.projectSegments(projectId)),
          ),
          data: (items) => ListView(
            key: const Key('deleted-segment-list-page'),
            padding: const EdgeInsets.all(AppTokens.spacingM),
            children: [
              Text(
                '已删除正文',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppTokens.spacingXs),
              Text('${project.title} · ${items.length} 段'),
              const SizedBox(height: AppTokens.spacingM),
              if (items.isEmpty)
                const _DeletedEmptyState()
              else
                for (final segment in items)
                  Card(
                    child: ListTile(
                      key: Key('deleted-segment-${segment.id}'),
                      title: Text('原第 ${segment.orderIndex + 1} 段'),
                      subtitle: Text(
                        '${segmentPreview(segment.content)}\n'
                        '删除 ${formatLocalDateTime(segment.deletedAt!)} · '
                        'revision ${segment.revision}',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: FilledButton.tonal(
                        key: Key('restore-segment-${segment.id}'),
                        onPressed: () => _restore(context, ref, segment),
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
    Segment segment,
  ) async {
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      await ref.read(restoreSegmentProvider)(
        projectId: projectId,
        segmentId: segment.id,
        restoredAt: ref.read(utcClockProvider).now(),
      );
      if (!context.mounted) {
        return;
      }
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.segments]);
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      context.go(AppRoutes.projectSegments(projectId));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      showSegmentSnack(context, friendlySegmentError(error));
    }
  }
}

class _DeletedEmptyState extends StatelessWidget {
  const _DeletedEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: Key('deleted-segments-empty-state'),
      child: Padding(
        padding: EdgeInsets.all(AppTokens.spacingL),
        child: Text('没有已删除的正文段落。'),
      ),
    );
  }
}

class SegmentHistoryPage extends ConsumerWidget {
  const SegmentHistoryPage({
    required this.projectId,
    required this.segmentId,
    super.key,
  });

  final String projectId;
  final String segmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segment = ref.watch(segmentByIdProvider(segmentId));
    final history = ref.watch(
      segmentHistoryProvider((projectId: projectId, segmentId: segmentId)),
    );
    return SafeArea(
      top: false,
      child: segment.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ProjectFlowErrorView(
          title: '段落不存在',
          message: '没有找到这个正文段落。',
          onAction: () => context.go(AppRoutes.projectSegments(projectId)),
        ),
        data: (segment) {
          if (segment.projectId != projectId) {
            return ProjectFlowErrorView(
              title: '段落不属于当前项目',
              message: '这个段落与当前项目不匹配。',
              onAction: () => context.go(AppRoutes.projectSegments(projectId)),
            );
          }
          return history.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => ProjectFlowErrorView(
              title: '历史版本读取失败',
              message: '暂时无法读取这段正文的历史。',
              onAction: () =>
                  context.go(AppRoutes.segment(projectId, segmentId)),
            ),
            data: (items) => ListView(
              key: const Key('segment-history-page'),
              padding: const EdgeInsets.all(AppTokens.spacingM),
              children: [
                Text(
                  '历史版本',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppTokens.spacingXs),
                Text('当前 revision ${segment.revision} · ${items.length} 条历史'),
                const SizedBox(height: AppTokens.spacingM),
                if (items.isEmpty)
                  const Center(
                    key: Key('segment-history-empty-state'),
                    child: Padding(
                      padding: EdgeInsets.all(AppTokens.spacingL),
                      child: Text('这段正文还没有旧版本。'),
                    ),
                  )
                else
                  for (final revision in items)
                    Card(
                      child: ListTile(
                        key: Key('segment-revision-${revision.id}'),
                        title: Text('版本 ${revision.revisionNumber}'),
                        subtitle: Text(
                          '${segmentPreview(revision.content)}\n'
                          '${formatLocalDateTime(revision.createdAt)}',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push(
                          AppRoutes.segmentRevision(
                            projectId,
                            segmentId,
                            revision.id,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class SegmentRevisionPreviewPage extends ConsumerStatefulWidget {
  const SegmentRevisionPreviewPage({
    required this.projectId,
    required this.segmentId,
    required this.revisionId,
    super.key,
  });

  final String projectId;
  final String segmentId;
  final String revisionId;

  @override
  ConsumerState<SegmentRevisionPreviewPage> createState() =>
      _SegmentRevisionPreviewPageState();
}

class _SegmentRevisionPreviewPageState
    extends ConsumerState<SegmentRevisionPreviewPage> {
  var _isRestoring = false;

  @override
  Widget build(BuildContext context) {
    final segment = ref.watch(segmentByIdProvider(widget.segmentId));
    final revision = ref.watch(segmentRevisionByIdProvider(widget.revisionId));
    return SafeArea(
      top: false,
      child: segment.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ProjectFlowErrorView(
          title: '段落不存在',
          message: '没有找到这个正文段落。',
          onAction: () =>
              context.go(AppRoutes.projectSegments(widget.projectId)),
        ),
        data: (segment) {
          if (segment.projectId != widget.projectId) {
            return ProjectFlowErrorView(
              title: '段落不属于当前项目',
              message: '这个段落与当前项目不匹配。',
              onAction: () =>
                  context.go(AppRoutes.projectSegments(widget.projectId)),
            );
          }
          return revision.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => ProjectFlowErrorView(
              title: '历史版本不存在',
              message: '没有找到这个历史版本。',
              onAction: () => context.go(
                AppRoutes.segmentHistory(widget.projectId, widget.segmentId),
              ),
            ),
            data: (revision) {
              if (revision.projectId != widget.projectId ||
                  revision.segmentId != widget.segmentId) {
                return ProjectFlowErrorView(
                  title: '历史版本不匹配',
                  message: '这个历史版本不属于当前段落。',
                  onAction: () => context.go(
                    AppRoutes.segmentHistory(
                      widget.projectId,
                      widget.segmentId,
                    ),
                  ),
                );
              }
              return _buildPreview(context, segment, revision);
            },
          );
        },
      ),
    );
  }

  Widget _buildPreview(
    BuildContext context,
    Segment segment,
    SegmentRevision revision,
  ) {
    return Column(
      key: const Key('segment-revision-preview-page'),
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppTokens.spacingM),
            children: [
              Text(
                '版本 ${revision.revisionNumber}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppTokens.spacingXs),
              Text('创建 ${formatLocalDateTime(revision.createdAt)}'),
              const SizedBox(height: AppTokens.spacingM),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppTokens.radiusM),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.spacingM),
                  child: SelectableText(
                    revision.content.isEmpty ? '空白段落' : revision.content,
                    key: const Key('segment-revision-full-content'),
                  ),
                ),
              ),
              if (revision.note.isNotEmpty) ...[
                const SizedBox(height: AppTokens.spacingM),
                Text('说明：${revision.note}'),
              ],
              if (revision.mode.isNotEmpty) Text('模式：${revision.mode}'),
              if (revision.userInstruction.isNotEmpty)
                Text('要求：${revision.userInstruction}'),
              const SizedBox(height: AppTokens.spacingM),
              const Text('恢复不会删除之后的历史；当前正文会先保存为一个新历史版本。'),
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
                key: const Key('restore-segment-revision-button'),
                onPressed: _isRestoring
                    ? null
                    : () => _confirmAndRestore(segment, revision),
                icon: _isRestoring
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restore_rounded),
                label: Text(_isRestoring ? '恢复中' : '恢复为当前版本'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmAndRestore(
    Segment segment,
    SegmentRevision revision,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('restore-segment-revision-dialog'),
        title: const Text('恢复这个历史版本？'),
        content: const Text('当前正文会先保存为一个新历史版本，然后恢复所选内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-restore-segment-revision-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || _isRestoring) {
      return;
    }
    setState(() {
      _isRestoring = true;
    });
    ref.read(mascotControllerProvider.notifier).perform(MascotAction.think);
    try {
      final restored = await ref.read(restoreSegmentRevisionProvider)(
        projectId: widget.projectId,
        segmentId: widget.segmentId,
        segmentRevisionId: revision.id,
        newRevisionId: ref
            .read(entityIdGeneratorProvider)
            .nextId('segment_revision'),
        nowUtc: ref.read(utcClockProvider).now(),
      );
      if (!mounted) {
        return;
      }
      notifyRepositoryChanged(ref, areas: const [RepositoryDataArea.segments]);
      ref
          .read(mascotControllerProvider.notifier)
          .perform(MascotAction.celebrate);
      showSegmentSnack(
        context,
        restored.revision == segment.revision ? '当前正文与该历史版本相同。' : '历史版本已恢复。',
      );
      context.go(AppRoutes.segment(widget.projectId, widget.segmentId));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ref.read(mascotControllerProvider.notifier).perform(MascotAction.settle);
      showSegmentSnack(context, friendlySegmentError(error));
      setState(() {
        _isRestoring = false;
      });
    }
  }
}

Future<bool> showSegmentDeleteDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('delete-segment-dialog'),
      title: const Text('删除正文段落？'),
      content: const Text('删除后可以从已删除正文中恢复。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('confirm-delete-segment-button'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showSegmentSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String friendlySegmentError(Object error) {
  final text = error.toString();
  if (text.contains('not found') || text.contains('not be found')) {
    return '目标不存在，请返回后重新选择。';
  }
  if (text.contains('already exists')) {
    return '保存冲突，请重新尝试。';
  }
  if (text.contains('不属于') ||
      text.contains('不匹配') ||
      text.contains('does not match')) {
    return '项目、段落或历史版本不匹配。';
  }
  if (text.contains('已删除')) {
    return '目标已删除，当前操作无法完成。';
  }
  return '操作失败，请稍后重试。';
}
