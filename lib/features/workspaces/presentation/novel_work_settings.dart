import '../../projects/presentation/novel_plugin_page.dart';
import '../../projects/presentation/novel_branch_sheet.dart';
import '../../../application/projects/novel_output_limits_providers.dart';
import '../../../application/plugins/novel_plugin_providers.dart';
import '../../../application/ai/ai_runtime_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routing/app_routes.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/widgets/ibuki_glass_surface.dart';
import '../../../app/widgets/ibuki_motion_widgets.dart';
import '../../../application/projects/current_project_controller.dart';
import '../../../application/providers/repository_providers.dart';
import '../../ai/presentation/ai_model_binding_sheet.dart';

class NovelWorkSettings extends ConsumerWidget {
  const NovelWorkSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = ref.watch(currentProjectControllerProvider);
    if (projectId == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('从创作页选择作品后，在这里管理它的创作设置。', textAlign: TextAlign.center),
        ),
      );
    }
    return ref
        .watch(projectByIdProvider(projectId))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => context.go(AppRoutes.novel),
              child: const Text('作品已不可用，返回书架'),
            ),
          ),
          data: (project) => project.deletedAt != null
              ? Center(
                  child: TextButton(
                    onPressed: () => context.go(AppRoutes.novel),
                    child: const Text('作品已删除，返回书架'),
                  ),
                )
              : ListView(
                  key: const PageStorageKey('novel-settings-scroll'),
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spacingM,
                    AppTokens.spacingM,
                    AppTokens.spacingM,
                    AppTokens.primaryNavigationHeight + AppTokens.spacingXl,
                  ),
                  children: [
                    IbukiGlassSurface(
                      strong: true,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '当前作品',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            project.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          TextButton.icon(
                            key: const Key('novel-settings-switch-project'),
                            onPressed: () =>
                                context.go(AppRoutes.novelCreation),
                            icon: const Icon(Icons.swap_horiz),
                            label: const Text('切换作品'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    IbukiGlassSurface(
                      child: Column(
                        children: [
                          _entry(
                            context,
                            '创作设定',
                            Icons.tune_rounded,
                            AppRoutes.projectCreationSettings(projectId),
                            subtitle: '本作系统提示词与提示词方案',
                            key: const Key('novel-creation-settings-entry'),
                          ),
                          _entry(
                            context,
                            '输出字数',
                            Icons.format_size_rounded,
                            AppRoutes.projectOutputLimits(projectId),
                            subtitle:
                                ref
                                    .watch(novelOutputLimitsProvider(projectId))
                                    .value
                                    ?.label ??
                                '默认',
                            key: const Key('novel-output-limits-entry'),
                          ),
                          _entry(
                            context,
                            '故事大纲',
                            Icons.format_list_bulleted_rounded,
                            AppRoutes.projectOutline(projectId),
                            key: const Key('novel-outline-entry'),
                          ),
                          ListTile(
                            key: const Key('novel-plugin-entry'),
                            leading: const Icon(Icons.extension_outlined),
                            title: const Text('小说插件'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                showNovelPluginPage(context, projectId),
                          ),
                          ListTile(
                            key: const Key('novel-storylines-entry'),
                            leading: const Icon(Icons.alt_route),
                            title: const Text('故事线'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                showNovelBranches(context, ref, projectId),
                          ),
                          _entry(
                            context,
                            '长期记忆',
                            Icons.psychology_outlined,
                            AppRoutes.projectLongMemory(projectId),
                            key: const Key('novel-long-memory-entry'),
                          ),
                          _entry(
                            context,
                            '角色卡',
                            Icons.people_outline,
                            AppRoutes.projectCharacters(projectId),
                          ),
                          _entry(
                            context,
                            '世界观',
                            Icons.auto_stories_outlined,
                            AppRoutes.projectWorld(projectId),
                          ),
                          ListTile(
                            key: const Key('novel-settings-model'),
                            leading: const Icon(Icons.auto_awesome_outlined),
                            title: const Text('本作品模型'),
                            subtitle: const Text('选择小说使用的模型'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => showAiModelBindingSheet(
                              context: context,
                              ref: ref,
                              scope: AiModelBindingScope.project,
                              entityId: projectId,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    IbukiGlassSurface(
                      child: Column(
                        children: [
                          _entry(
                            context,
                            '阅读',
                            Icons.chrome_reader_mode_outlined,
                            AppRoutes.projectReader(projectId),
                            key: const Key('novel-reader-entry'),
                          ),
                          _entry(
                            context,
                            '已删除内容',
                            Icons.delete_outline,
                            AppRoutes.deletedSegments(projectId),
                          ),
                          _entry(
                            context,
                            '作品信息',
                            Icons.info_outline,
                            AppRoutes.project(projectId),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    IbukiGlassSurface(
                      child: _DeleteCurrentNovel(
                        projectId: project.id,
                        title: project.title,
                      ),
                    ),
                  ],
                ),
        );
  }

  Widget _entry(
    BuildContext context,
    String title,
    IconData icon,
    String route, {
    String? subtitle,
    Key? key,
  }) => IbukiPressMotion(
    child: ListTile(
      key: key,
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    ),
  );
}

class _DeleteCurrentNovel extends ConsumerStatefulWidget {
  const _DeleteCurrentNovel({required this.projectId, required this.title});
  final String projectId;
  final String title;
  @override
  ConsumerState<_DeleteCurrentNovel> createState() =>
      _DeleteCurrentNovelState();
}

class _DeleteCurrentNovelState extends ConsumerState<_DeleteCurrentNovel> {
  var _deleting = false;
  @override
  Widget build(BuildContext context) => ListTile(
    key: const Key('novel-delete-current-project'),
    enabled: !_deleting,
    leading: Icon(
      Icons.delete_forever_outlined,
      color: Theme.of(context).colorScheme.error,
    ),
    title: Text(
      _deleting ? '正在删除…' : '删除当前作品',
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
    onTap: _delete,
  );

  Future<void> _delete() async {
    if (_deleting) return;
    final id = widget.projectId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        key: const Key('novel-delete-current-dialog'),
        title: const Text('删除当前作品？'),
        content: Text('确认删除《${widget.title}》及其全部故事线？\n删除后，这部作品将从书架和创作列表移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('novel-confirm-delete-project'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialog).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      final repository = ref.read(novelPluginRepositoryProvider);
      final branch = await repository.branch(id);
      final branches = await repository.branches(branch.storyId);
      if (!mounted) return;
      for (final item in branches) {
        ref.read(autoStoryRunnerProvider).stop(projectId: item.projectId);
        ref.read(aiRequestCoordinatorProvider).cancelScope(item.projectId);
        ref.read(novelPluginMemoryProvider).cancel(item.projectId);
      }
      await repository.deleteStory(id, ref.read(utcClockProvider).now());
      if (!mounted) return;
      if (branches.any(
        (item) => item.projectId == ref.read(currentProjectControllerProvider),
      )) {
        ref.read(currentProjectControllerProvider.notifier).clearProject();
      }
      invalidateNovelBranchCaches(ref);
      context.go(AppRoutes.novel);
    } catch (_) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('作品删除未完成，请重试。')));
      }
    }
  }
}
