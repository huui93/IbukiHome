import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../application/projects/current_project_controller.dart';
import '../../../application/providers/repository_providers.dart';
import 'project_flow_widgets.dart';

class ProjectOverviewPage extends ConsumerWidget {
  const ProjectOverviewPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectByIdProvider(projectId));
    final segments = ref.watch(segmentListProvider(projectId));
    final characters = ref.watch(characterListProvider(projectId));
    final worldCards = ref.watch(worldCardListProvider(projectId));

    return SafeArea(
      top: false,
      child: project.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ProjectFlowErrorView(
          title: '项目不存在',
          message: '没有找到这个项目，请返回项目列表重新选择。',
          onAction: () => context.go(AppRoutes.projects),
        ),
        data: (project) {
          final segmentCount = segments.maybeWhen(
            data: (items) => items.length,
            orElse: () => 0,
          );
          final characterCount = characters.maybeWhen(
            data: (items) => items.length,
            orElse: () => 0,
          );
          final worldCardCount = worldCards.maybeWhen(
            data: (items) => items.length,
            orElse: () => 0,
          );
          return ListView(
            key: const Key('project-overview-page'),
            padding: const EdgeInsets.all(AppTokens.spacingM),
            children: [
              Text(
                project.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (project.description.isNotEmpty) ...[
                const SizedBox(height: AppTokens.spacingS),
                Text(project.description),
              ],
              const SizedBox(height: AppTokens.spacingM),
              const MemoryDataNotice(),
              const SizedBox(height: AppTokens.spacingM),
              Material(
                color: Colors.transparent,
                child: ListTile(
                  key: const Key('project-overview-open-segments'),
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('正文段落'),
                  subtitle: Text('$segmentCount 段'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    ref
                        .read(currentProjectControllerProvider.notifier)
                        .selectProject(project.id);
                    context.push(AppRoutes.projectSegments(project.id));
                  },
                ),
              ),
              Material(
                color: Colors.transparent,
                child: ListTile(
                  key: const Key('project-overview-open-characters'),
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('角色'),
                  subtitle: Text('$characterCount 个角色'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    ref
                        .read(currentProjectControllerProvider.notifier)
                        .selectProject(project.id);
                    context.push(AppRoutes.projectCharacters(project.id));
                  },
                ),
              ),
              Material(
                color: Colors.transparent,
                child: ListTile(
                  key: const Key('project-overview-open-world'),
                  leading: const Icon(Icons.public_outlined),
                  title: const Text('世界观'),
                  subtitle: Text('$worldCardCount 张世界观卡'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    ref
                        .read(currentProjectControllerProvider.notifier)
                        .selectProject(project.id);
                    context.push(AppRoutes.projectWorld(project.id));
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
