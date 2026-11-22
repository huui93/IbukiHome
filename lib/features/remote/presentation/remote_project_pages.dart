import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_workspace_mode.dart';
import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../application/remote/remote_browser_controller.dart';
import '../../../application/remote/remote_connection_controller.dart';
import '../../../application/remote/remote_connection_state.dart';
import '../../../data/remote/dto/project_detail_dto.dart';
import '../../../data/remote/dto/project_summary_dto.dart';
import '../../../data/remote/dto/segment_dto.dart';
import '../../projects/presentation/project_flow_widgets.dart';

class RemoteProjectsPage extends ConsumerStatefulWidget {
  const RemoteProjectsPage({
    this.sourceWorkspace = AppWorkspaceMode.home,
    super.key,
  });

  final AppWorkspaceMode sourceWorkspace;

  @override
  ConsumerState<RemoteProjectsPage> createState() => _RemoteProjectsPageState();
}

class _RemoteProjectsPageState extends ConsumerState<RemoteProjectsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref
          .read(remoteConnectionControllerProvider.notifier)
          .loadSavedProfile();
      await ref.read(remoteBrowserControllerProvider.notifier).loadProjects();
    });
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(remoteConnectionControllerProvider);
    final browser = ref.watch(remoteBrowserControllerProvider);

    return RemotePageFrame(
      key: const Key('remote-projects-page'),
      title: '电脑项目 · 只读',
      connection: connection,
      isLoading: browser.isLoading,
      errorMessage: browser.errorMessage,
      staleMessage: browser.staleMessage,
      onRefresh: () =>
          ref.read(remoteBrowserControllerProvider.notifier).loadProjects(),
      child: browser.projects.isEmpty
          ? const _RemoteEmptyState()
          : Column(
              children: [
                for (final project in browser.projects)
                  _RemoteProjectTile(
                    project: project,
                    sourceWorkspace: widget.sourceWorkspace,
                  ),
              ],
            ),
    );
  }
}

class RemoteProjectDetailPage extends ConsumerStatefulWidget {
  const RemoteProjectDetailPage({
    required this.projectId,
    this.sourceWorkspace = AppWorkspaceMode.home,
    super.key,
  });

  final String projectId;
  final AppWorkspaceMode sourceWorkspace;

  @override
  ConsumerState<RemoteProjectDetailPage> createState() =>
      _RemoteProjectDetailPageState();
}

class _RemoteProjectDetailPageState
    extends ConsumerState<RemoteProjectDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(remoteBrowserControllerProvider.notifier)
          .loadProject(widget.projectId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(remoteConnectionControllerProvider);
    final browser = ref.watch(remoteBrowserControllerProvider);
    final project = browser.projectDetails[widget.projectId];

    return RemotePageFrame(
      key: const Key('remote-project-detail-page'),
      title: '电脑项目 · 只读',
      connection: connection,
      isLoading: browser.isLoading,
      errorMessage: project == null ? browser.errorMessage : null,
      staleMessage: browser.staleMessage,
      onRefresh: () => ref
          .read(remoteBrowserControllerProvider.notifier)
          .loadProject(widget.projectId),
      child: project == null
          ? const SizedBox.shrink()
          : _RemoteProjectDetail(
              project: project,
              sourceWorkspace: widget.sourceWorkspace,
            ),
    );
  }
}

class RemoteSegmentListPage extends ConsumerStatefulWidget {
  const RemoteSegmentListPage({
    required this.projectId,
    this.sourceWorkspace = AppWorkspaceMode.home,
    super.key,
  });

  final String projectId;
  final AppWorkspaceMode sourceWorkspace;

  @override
  ConsumerState<RemoteSegmentListPage> createState() =>
      _RemoteSegmentListPageState();
}

class _RemoteSegmentListPageState extends ConsumerState<RemoteSegmentListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(remoteBrowserControllerProvider.notifier)
          .loadSegments(widget.projectId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(remoteConnectionControllerProvider);
    final browser = ref.watch(remoteBrowserControllerProvider);
    final segments = browser.segmentsByProject[widget.projectId] ?? const [];

    return RemotePageFrame(
      key: const Key('remote-segment-list-page'),
      title: '电脑正文 · 只读',
      connection: connection,
      isLoading: browser.isLoading,
      errorMessage: segments.isEmpty ? browser.errorMessage : null,
      staleMessage: browser.staleMessage,
      onRefresh: () => ref
          .read(remoteBrowserControllerProvider.notifier)
          .loadSegments(widget.projectId),
      child: segments.isEmpty
          ? const _RemoteEmptyState(message: '电脑项目暂时没有正文段落。')
          : Column(
              children: [
                for (final segment in segments)
                  _RemoteSegmentTile(
                    segment: segment,
                    sourceWorkspace: widget.sourceWorkspace,
                  ),
              ],
            ),
    );
  }
}

class RemoteSegmentDetailPage extends ConsumerStatefulWidget {
  const RemoteSegmentDetailPage({
    required this.projectId,
    required this.segmentId,
    this.sourceWorkspace = AppWorkspaceMode.home,
    super.key,
  });

  final String projectId;
  final String segmentId;
  final AppWorkspaceMode sourceWorkspace;

  @override
  ConsumerState<RemoteSegmentDetailPage> createState() =>
      _RemoteSegmentDetailPageState();
}

class _RemoteSegmentDetailPageState
    extends ConsumerState<RemoteSegmentDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(remoteBrowserControllerProvider.notifier)
          .loadSegment(widget.projectId, widget.segmentId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(remoteConnectionControllerProvider);
    final browser = ref.watch(remoteBrowserControllerProvider);
    final segment = browser.segmentDetails[widget.segmentId];

    return RemotePageFrame(
      key: const Key('remote-segment-detail-page'),
      title: '电脑正文 · 只读',
      connection: connection,
      isLoading: browser.isLoading,
      errorMessage: segment == null ? browser.errorMessage : null,
      staleMessage: browser.staleMessage,
      onRefresh: () => ref
          .read(remoteBrowserControllerProvider.notifier)
          .loadSegment(widget.projectId, widget.segmentId),
      child: segment == null
          ? const SizedBox.shrink()
          : _RemoteSegmentDetail(segment: segment),
    );
  }
}

class RemotePageFrame extends StatelessWidget {
  const RemotePageFrame({
    required this.title,
    required this.connection,
    required this.child,
    this.isLoading = false,
    this.errorMessage,
    this.staleMessage,
    this.onRefresh,
    super.key,
  });

  final String title;
  final RemoteConnectionState connection;
  final Widget child;
  final bool isLoading;
  final String? errorMessage;
  final String? staleMessage;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(AppTokens.spacingM),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('remote-refresh-button'),
                onPressed: isLoading ? null : onRefresh,
                icon: isLoading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: const Text('刷新'),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spacingS),
          _RemoteSourceNotice(connection: connection),
          if (staleMessage != null) ...[
            const SizedBox(height: AppTokens.spacingS),
            _MessageBanner(
              key: const Key('remote-stale-banner'),
              icon: Icons.cloud_off_outlined,
              message: staleMessage!,
            ),
          ],
          if (errorMessage != null) ...[
            const SizedBox(height: AppTokens.spacingS),
            _MessageBanner(
              key: const Key('remote-error-banner'),
              icon: Icons.error_outline_rounded,
              message: errorMessage!,
            ),
          ],
          const SizedBox(height: AppTokens.spacingM),
          child,
        ],
      ),
    );
  }
}

class _RemoteSourceNotice extends StatelessWidget {
  const _RemoteSourceNotice({required this.connection});

  final RemoteConnectionState connection;

  @override
  Widget build(BuildContext context) {
    final baseUri = connection.baseUri?.toString() ?? '未连接';
    return Chip(
      key: const Key('remote-readonly-chip'),
      avatar: const Icon(Icons.visibility_outlined, size: 18),
      label: Text('电脑项目 · 只读 · $baseUri'),
    );
  }
}

class _RemoteProjectTile extends StatelessWidget {
  const _RemoteProjectTile({
    required this.project,
    required this.sourceWorkspace,
  });

  final ProjectSummaryDto project;
  final AppWorkspaceMode sourceWorkspace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spacingS),
      child: Material(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusM),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: ListTile(
          key: Key('remote-project-tile-${project.id}'),
          leading: const Icon(Icons.folder_open_outlined),
          title: Text(
            project.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${project.description}\n正文 ${project.segmentCount} 段 · revision ${project.revision} · 更新 ${formatLocalDateTime(project.updatedAt)}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(
            AppRoutes.remoteProjectFor(project.id, sourceWorkspace),
          ),
        ),
      ),
    );
  }
}

class _RemoteProjectDetail extends StatelessWidget {
  const _RemoteProjectDetail({
    required this.project,
    required this.sourceWorkspace,
  });

  final ProjectDetailDto project;
  final AppWorkspaceMode sourceWorkspace;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(project.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppTokens.spacingS),
        Text(project.description.isEmpty ? '没有项目说明。' : project.description),
        const SizedBox(height: AppTokens.spacingS),
        Wrap(
          spacing: AppTokens.spacingS,
          children: [
            Chip(label: Text('revision ${project.revision}')),
            Chip(label: Text('正文 ${project.segmentCount} 段')),
            Chip(label: Text('更新 ${formatLocalDateTime(project.updatedAt)}')),
          ],
        ),
        const SizedBox(height: AppTokens.spacingM),
        FilledButton.icon(
          key: const Key('remote-open-segments-button'),
          onPressed: () => context.push(
            AppRoutes.remoteProjectSegmentsFor(project.id, sourceWorkspace),
          ),
          icon: const Icon(Icons.article_outlined),
          label: const Text('查看正文段落'),
        ),
      ],
    );
  }
}

class _RemoteSegmentTile extends StatelessWidget {
  const _RemoteSegmentTile({
    required this.segment,
    required this.sourceWorkspace,
  });

  final SegmentDto segment;
  final AppWorkspaceMode sourceWorkspace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spacingS),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: Key('remote-segment-tile-${segment.id}'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusM),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          title: Text('第 ${segment.orderIndex + 1} 段'),
          subtitle: Text(
            '${segmentPreview(segment.content)}\nrevision ${segment.revision} · 更新 ${formatLocalDateTime(segment.updatedAt)}',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.visibility_outlined),
          onTap: () => context.push(
            AppRoutes.remoteSegmentFor(
              segment.projectId,
              segment.id,
              sourceWorkspace,
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteSegmentDetail extends StatelessWidget {
  const _RemoteSegmentDetail({required this.segment});

  final SegmentDto segment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppTokens.spacingS,
          children: [
            Chip(label: Text('revision ${segment.revision}')),
            Chip(label: Text('更新 ${formatLocalDateTime(segment.updatedAt)}')),
            const Chip(label: Text('只读')),
          ],
        ),
        const SizedBox(height: AppTokens.spacingM),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(AppTokens.radiusM),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spacingM),
            child: SelectableText(
              segment.content.isEmpty ? '空白段落' : segment.content,
              key: const Key('remote-segment-content'),
            ),
          ),
        ),
        const SizedBox(height: AppTokens.spacingM),
        OutlinedButton.icon(
          key: const Key('remote-copy-segment-button'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: segment.content));
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('已复制正文。')));
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('复制文本'),
        ),
      ],
    );
  }
}

class _RemoteEmptyState extends StatelessWidget {
  const _RemoteEmptyState({this.message = '连接后可以在这里浏览电脑项目。'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('remote-empty-state'),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spacingL),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTokens.radiusS),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spacingS),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: AppTokens.spacingS),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
