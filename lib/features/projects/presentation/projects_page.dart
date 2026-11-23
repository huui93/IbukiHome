import '../../../application/plugins/novel_plugin_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../application/projects/current_project_controller.dart';
import '../../../application/providers/repository_providers.dart';
import '../../../domain/projects/project.dart';
import 'project_flow_widgets.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../app/widgets/ibuki_motion_widgets.dart';
import '../../../app/localization/app_localizations.dart';

enum ProjectsPageMode { selector, bookshelf, creation }

final _rootNovelListProvider = FutureProvider.autoDispose<List<Project>>((
  ref,
) async {
  final repository = ref.watch(novelPluginRepositoryProvider);
  final projects = await ref.watch(projectListProvider.future);
  final branches = await repository.childProjectIds();
  return projects.where((project) => !branches.contains(project.id)).toList();
});

class ProjectsPage extends ConsumerWidget {
  const ProjectsPage({this.mode = ProjectsPageMode.selector, super.key});
  final ProjectsPageMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(_rootNovelListProvider);
    final currentProjectId = ref.watch(currentProjectControllerProvider);
    final bookshelf = mode == ProjectsPageMode.bookshelf;
    final selector = mode == ProjectsPageMode.selector;

    return SafeArea(
      top: false,
      child: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ProjectFlowErrorView(
          title: context.tr("项目读取失败"),
          message: _friendlyError(error),
          actionLabel: context.tr("重试"),
          onAction: () {
            ref.invalidate(projectListProvider);
            ref.invalidate(_rootNovelListProvider);
          },
        ),
        data: (items) {
          if (bookshelf && items.isEmpty) return const _EmptyBookshelfState();
          return ListView(
            key: switch (mode) {
              ProjectsPageMode.bookshelf => const PageStorageKey(
                'novel-bookshelf-page',
              ),
              ProjectsPageMode.creation => const PageStorageKey(
                'novel-creation-list',
              ),
              ProjectsPageMode.selector => const Key('projects-page'),
            },
            padding: const EdgeInsets.all(AppTokens.spacingM),
            children: [
              if (selector)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        context.tr("项目"),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key('new-project-button'),
                      onPressed: () => context.push(AppRoutes.newProject),
                      icon: const Icon(Icons.add),
                      label: Text(context.tr("新建")),
                    ),
                  ],
                ),
              if (selector) const SizedBox(height: AppTokens.spacingM),
              if (items.isEmpty && selector)
                const _EmptyProjectsState()
              else
                for (final project in items)
                  _ProjectListItem(
                    project: project,
                    isCurrent: !bookshelf && project.id == currentProjectId,
                    mode: mode,
                  ),
              if (mode == ProjectsPageMode.creation)
                IbukiGlassSurface(
                  child: IbukiPressMotion(
                    child: Material(
                      color: Colors.transparent,
                      child: ListTile(
                        key: const Key('novel-create-new'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.spacingM,
                          vertical: AppTokens.spacingM,
                        ),
                        leading: Icon(
                          Icons.add_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(context.tr("创作新的小说")),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push(AppRoutes.newProject),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyBookshelfState extends StatelessWidget {
  const _EmptyBookshelfState();
  @override
  Widget build(BuildContext context) => Center(
    key: const Key('empty-novel-bookshelf'),
    child: IbukiEntrance(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              context.tr("还没有创作的作品"),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyProjectsState extends StatelessWidget {
  const _EmptyProjectsState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key('empty-projects-state'),
      padding: EdgeInsets.symmetric(vertical: AppTokens.spacingXl),
      child: Column(
        children: [
          Icon(Icons.folder_open_outlined, size: 36),
          SizedBox(height: AppTokens.spacingM),
          Text(context.tr("还没有作品")),
          SizedBox(height: AppTokens.spacingS),
          Text(context.tr("新建作品后即可进入正文创作工作台。")),
        ],
      ),
    );
  }
}

class _ProjectListItem extends ConsumerWidget {
  const _ProjectListItem({
    required this.project,
    required this.isCurrent,
    required this.mode,
  });

  final Project project;
  final bool isCurrent;
  final ProjectsPageMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segmentCount = ref
        .watch(segmentListProvider(project.id))
        .maybeWhen(data: (segments) => segments.length, orElse: () => 0);
    final scheme = Theme.of(context).colorScheme;
    final bookshelf = mode == ProjectsPageMode.bookshelf;
    final modernList = mode != ProjectsPageMode.selector;

    final tile = Material(
      color: Colors.transparent,
      child: ListTile(
        key: Key('project-tile-${project.id}'),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spacingM,
          vertical: AppTokens.spacingS,
        ),
        leading: modernList
            ? Container(
                width: 44,
                height: 58,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.menu_book_outlined, color: scheme.primary),
              )
            : null,
        title: Text(
          project.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppTokens.spacingXs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (project.description.isNotEmpty)
                Text(
                  project.description,
                  key: Key('project-description-${project.id}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: AppTokens.spacingXs),
              Wrap(
                spacing: AppTokens.spacingS,
                runSpacing: AppTokens.spacingXs,
                children: [
                  Text(context.tr("正文 {count} 段", {"count": segmentCount})),
                  Text(
                    context.tr("更新 {date}", {
                      "date": formatLocalDateTime(project.updatedAt),
                    }),
                  ),
                  if (isCurrent)
                    Text(
                      modernList ? context.tr("当前创作") : context.tr("当前项目"),
                      key: Key('current-project-${project.id}'),
                      style: TextStyle(color: scheme.primary),
                    ),
                ],
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          String id;
          try {
            id = await ref
                .read(novelPluginRepositoryProvider)
                .activeProject(project.id);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(context.tr("作品已不可用。"))));
            }
            return;
          }
          if (!context.mounted) return;
          if (bookshelf) {
            context.push(AppRoutes.projectReader(id));
            return;
          }
          ref.read(currentProjectControllerProvider.notifier).selectProject(id);
          if (mode == ProjectsPageMode.creation) {
            context.push(AppRoutes.novelEditor(id));
          } else {
            context.go(AppRoutes.novelEditor(id));
          }
        },
      ),
    );
    return modernList
        ? IbukiGlassSurface(
            margin: const EdgeInsets.only(bottom: 12),
            child: IbukiPressMotion(child: tile),
          )
        : tile;
  }
}

String _friendlyError(Object error) {
  final message = error.toString();
  if (message.trim().isEmpty) {
    return '请稍后重试。';
  }
  return message;
}
