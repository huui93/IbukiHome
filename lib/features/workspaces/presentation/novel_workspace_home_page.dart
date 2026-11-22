import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/navigation/novel_workspace_section.dart';
import '../../../app/routing/app_routes.dart';
import '../../../application/providers/repository_providers.dart';
import '../../projects/presentation/projects_page.dart';
import '../../projects/presentation/segment_list_page.dart';
import '../../shell/presentation/animated_workspace_container.dart';
import 'novel_work_settings.dart';

// Keep manuscript positions when an editor is reopened from the creation list.
final _novelPageStorageProvider = Provider((ref) => PageStorageBucket());

class NovelWorkspaceHomePage extends ConsumerStatefulWidget {
  const NovelWorkspaceHomePage({
    this.section = NovelWorkspaceSection.bookshelf,
    this.editingProjectId,
    super.key,
  });
  final NovelWorkspaceSection section;
  final String? editingProjectId;
  @override
  ConsumerState<NovelWorkspaceHomePage> createState() =>
      _NovelWorkspaceHomePageState();
}

class _NovelWorkspaceHomePageState
    extends ConsumerState<NovelWorkspaceHomePage> {
  final _visited = <NovelWorkspaceSection>{};
  @override
  Widget build(BuildContext context) {
    _visited.add(widget.section);
    return PageStorage(
      bucket: ref.watch(_novelPageStorageProvider),
      child: KeyedSubtree(
        key: const Key('novel-workspace-home'),
        child: AnimatedWorkspaceContainer(
          currentIndex: widget.section.index,
          children: [
            const ProjectsPage(mode: ProjectsPageMode.bookshelf),
            if (_visited.contains(NovelWorkspaceSection.creation))
              _NovelCreationWorkspace(projectId: widget.editingProjectId)
            else
              const SizedBox.shrink(),
            if (_visited.contains(NovelWorkspaceSection.settings))
              const KeyedSubtree(
                key: Key('novel-work-settings'),
                child: NovelWorkSettings(),
              )
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

class _NovelCreationWorkspace extends ConsumerWidget {
  const _NovelCreationWorkspace({this.projectId});
  final String? projectId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = projectId;
    if (id == null) {
      return const ProjectsPage(mode: ProjectsPageMode.creation);
    }
    return ref
        .watch(projectByIdProvider(id))
        .when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => context.go(AppRoutes.novelCreation),
              child: const Text('作品已不可用，返回创作列表'),
            ),
          ),
          data: (project) => project.deletedAt != null
              ? Center(
                  child: TextButton(
                    onPressed: () => context.go(AppRoutes.novelCreation),
                    child: const Text('作品已删除，返回创作列表'),
                  ),
                )
              : SegmentListPage(
                  key: ValueKey(project.id),
                  projectId: project.id,
                ),
        );
  }
}
