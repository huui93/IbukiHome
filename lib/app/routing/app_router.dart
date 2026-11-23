import '../../features/projects/presentation/novel_output_limits_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers/repository_providers.dart';
import '../../features/chat/presentation/chat_home_page.dart';
import '../../features/chat/presentation/simple_chat_pages.dart';
import '../../features/chat/presentation/chat_memory_page.dart';
import '../../features/chat/presentation/chat_usage_page.dart';
import '../../features/backup/presentation/backup_restore_page.dart';
import '../../features/characters/presentation/character_pages.dart';
import '../../features/import/presentation/sillytavern_import_pages.dart';
import '../../features/projects/presentation/new_project_page.dart';
import '../../features/projects/presentation/import_txt_novel_page.dart';
import '../../features/projects/presentation/creation_settings_page.dart';
import '../../features/projects/presentation/novel_reader_page.dart';
import '../../features/projects/presentation/project_overview_page.dart';
import '../../features/projects/presentation/projects_page.dart';
import '../../features/projects/presentation/segment_editor_page.dart';
import '../../features/projects/presentation/segment_list_page.dart';
import '../../features/projects/presentation/segment_management_pages.dart';
import '../../features/plugins/presentation/plugin_pages.dart';
import '../../features/remote/presentation/remote_connect_page.dart';
import '../../features/remote/presentation/remote_project_pages.dart';
import '../../features/settings/presentation/ai_settings_pages.dart';
import '../../features/settings/presentation/personal_profile_page.dart';
import '../../features/settings/presentation/chat_memory_settings_page.dart';
import '../../features/shell/presentation/global_page_scaffold.dart';
import '../../features/shell/presentation/shell_scaffold.dart';
import '../../features/shell/presentation/simple_primary_pages.dart';
import '../../features/shell/presentation/simple_primary_scaffold.dart';
import '../../features/shell/presentation/animated_workspace_container.dart';
import '../../features/world/presentation/world_card_pages.dart';
import '../../features/world_roleplay/presentation/world_book_library_page.dart';
import '../../features/tavern/presentation/tavern_home_page.dart';
import '../../features/tavern/presentation/tavern_creation_page.dart';
import '../../features/tavern/presentation/tavern_story_page.dart';
import '../../domain/import/sillytavern_models.dart';
import 'app_routes.dart';
import 'workspace_route_map.dart';
import '../navigation/novel_workspace_section.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.chat,
    redirect: (context, state) {
      final path = state.uri.path;
      if (path == AppRoutes.world || path.startsWith('${AppRoutes.world}/')) {
        return AppRoutes.tavern;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/projects/:projectId/outline',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.toString(),
          title: '故事大纲',
          showBackButton: true,
          backFallbackLocation: AppRoutes.novelSettings,
          child: NovelOutlinePage(
            projectId: state.pathParameters['projectId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/projects/:projectId/long-memory',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.toString(),
          title: '小说长期记忆',
          showBackButton: true,
          backFallbackLocation: AppRoutes.novelSettings,
          child: NovelLongMemoryPage(
            projectId: state.pathParameters['projectId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.importTxtNovel,
        builder: (context, state) => const ShellScaffold(
          currentLocation: AppRoutes.importTxtNovel,
          title: '导入 TXT 小说',
          showBackButton: true,
          backFallbackLocation: AppRoutes.novel,
          childHandlesPop: true,
          child: ImportTxtNovelPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        redirect: (context, state) => AppRoutes.chat,
      ),
      StatefulShellRoute(
        navigatorContainerBuilder: (context, shell, children) =>
            AnimatedWorkspaceContainer(
              currentIndex: shell.currentIndex,
              children: children,
            ),
        builder: (context, state, navigationShell) => PrimaryNavigationScope(
          navigationShell: navigationShell,
          child: PrimaryNavigationFrame(navigationShell: navigationShell),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.novel,
                name: 'novel-home',
                builder: (context, state) => NovelPrimaryPage(
                  section: NovelWorkspaceSection.fromQuery(
                    state.uri.queryParameters['section'],
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'write/:projectId',
                    builder: (context, state) => NovelPrimaryPage(
                      section: NovelWorkspaceSection.creation,
                      editingProjectId: state.pathParameters['projectId'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.chat,
                name: 'chat',
                builder: (context, state) => const ChatPrimaryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                name: 'settings',
                builder: (context, state) => const SettingsPrimaryPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.tavern,
        name: 'tavern-home',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.path,
          title: 'Tavern',
          showBackButton: true,
          backFallbackLocation: AppRoutes.settings,
          child: const TavernHomePage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.newTavernStory,
        builder: (context, state) => TavernCreationPage(
          from: state.uri.queryParameters['from'] ?? 'character',
        ),
      ),
      GoRoute(
        path: '/tavern/stories/:sessionId',
        builder: (context, state) =>
            TavernStoryPage(sessionId: state.pathParameters['sessionId'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.newChatSession,
        name: 'chat-new',
        redirect: (context, state) => AppRoutes.chatPersonaPicker,
      ),
      GoRoute(
        path: AppRoutes.deletedChatSessions,
        name: 'chat-deleted',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.path,
          title: '已删除会话',
          subtitle: '可恢复',
          showBackButton: true,
          backFallbackLocation: AppRoutes.chat,
          child: const DeletedChatSessionsPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.chatMemorySettings,
        builder: (context, state) => const ChatMemorySettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.personalProfile,
        builder: (context, state) => const PersonalProfilePage(),
      ),
      GoRoute(
        path: AppRoutes.chatPersonaPicker,
        builder: (context, state) => ChatPersonaPickerPage(
          purpose: state.uri.queryParameters['intent'] == 'edit'
              ? ChatPersonaPickerPurpose.edit
              : ChatPersonaPickerPurpose.newSession,
        ),
      ),
      GoRoute(
        path: AppRoutes.newChatPersona,
        name: 'chat-persona-new',
        builder: (context, state) => const ChatPersonaEditorPage(),
      ),
      GoRoute(
        path: AppRoutes.importChatPersona,
        name: 'chat-persona-import',
        redirect: (context, state) => AppRoutes.newChatPersona,
      ),
      GoRoute(
        path: AppRoutes.deletedChatPersonas,
        name: 'chat-persona-deleted',
        builder: (context, state) => const DeletedChatPersonasPage(),
      ),
      GoRoute(
        path: '/chat/personas/:personaId/edit',
        name: 'chat-persona-edit',
        builder: (context, state) => ChatPersonaEditorPage(
          personaId: state.pathParameters['personaId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/chat/personas/:personaId',
        name: 'chat-persona',
        builder: (context, state) => ChatPersonaProfilePage(
          personaId: state.pathParameters['personaId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/chat/:sessionId',
        name: 'chat-session',
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId'] ?? '';
          return SimpleChatSessionPage(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: AppRoutes.aiSettings,
        name: 'ai-settings',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.path,
          title: 'AI 与模型',
          subtitle: '共享模型与 API 配置',
          showBackButton: true,
          backFallbackLocation: AppRoutes.settings,
          child: const AiSettingsPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.aiProviders,
        name: 'ai-providers',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.path,
          title: 'API 配置',
          subtitle: 'Key 安全保存在本机',
          showBackButton: true,
          backFallbackLocation: AppRoutes.aiSettings,
          child: const AiProviderListPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.newCustomAiProvider,
        name: 'ai-provider-new-custom',
        builder: (context, state) => const AiProviderConfigPage(),
      ),
      GoRoute(
        path: AppRoutes.plugins,
        name: 'plugins',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.path,
          title: '插件',
          subtitle: '管理本地扩展',
          showBackButton: true,
          backFallbackLocation: AppRoutes.settings,
          child: const PluginManagementPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.backupRestore,
        name: 'backup-restore',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.path,
          title: '数据与备份',
          subtitle: '完整归档与安全恢复',
          showBackButton: true,
          backFallbackLocation: AppRoutes.settings,
          child: const BackupRestorePage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.sillyTavernImport,
        name: 'sillytavern-import',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.path,
          title: 'SillyTavern 导入',
          subtitle: '角色、我的角色与世界书',
          showBackButton: true,
          backFallbackLocation: AppRoutes.settings,
          child: SillyTavernImportPage(
            expectedKind: _sillyTavernAssetKind(
              state.uri.queryParameters['kind'],
            ),
            initialProjectId: state.uri.queryParameters['project'],
            initialWorldId: state.uri.queryParameters['world'],
            returnOnComplete: state.uri.queryParameters['return'] == '1',
            deferForStory: state.uri.queryParameters['story'] == '1',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.worldBookLibrary,
        name: 'world-book-library',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.path,
          title: '世界书库',
          subtitle: '可复用的世界设定',
          showBackButton: true,
          backFallbackLocation: AppRoutes.settings,
          child: const WorldBookLibraryPage(),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.sillyTavernImport}/compatibility/:payloadId',
        name: 'sillytavern-compatibility-detail',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.path,
          title: '兼容信息',
          subtitle: '按需查看来源与保留字段',
          showBackButton: true,
          backFallbackLocation: AppRoutes.sillyTavernImport,
          child: SillyTavernCompatibilityDetailPage(
            payloadId: state.pathParameters['payloadId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/settings/plugins/:pluginId',
        name: 'plugin-detail',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.path,
          title: '插件详情',
          showBackButton: true,
          backFallbackLocation: AppRoutes.plugins,
          child: PluginDetailPage(
            pluginId: state.pathParameters['pluginId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/settings/ai/providers/:providerId',
        name: 'ai-provider-config',
        builder: (context, state) => AiProviderConfigPage(
          providerId: state.pathParameters['providerId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.remoteConnect,
        name: 'remote-connect',
        builder: (context, state) {
          final source = WorkspaceRouteMap.sourceWorkspace(state.uri);
          return GlobalPageScaffold(
            title: '连接电脑',
            subtitle: '手动只读连接',
            fallbackLocation: WorkspaceRouteMap.rootFor(source),
            child: RemoteConnectPage(sourceWorkspace: source),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.remoteProjects,
        name: 'remote-projects',
        builder: (context, state) {
          final source = WorkspaceRouteMap.sourceWorkspace(state.uri);
          return GlobalPageScaffold(
            title: '电脑项目',
            subtitle: '只读浏览',
            fallbackLocation: AppRoutes.remoteConnectFor(source),
            child: RemoteProjectsPage(sourceWorkspace: source),
          );
        },
      ),
      GoRoute(
        path: '/remote/projects/:projectId',
        name: 'remote-project-detail',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final source = WorkspaceRouteMap.sourceWorkspace(state.uri);
          return GlobalPageScaffold(
            title: '电脑项目',
            subtitle: '只读详情',
            fallbackLocation: AppRoutes.remoteProjectsFor(source),
            child: RemoteProjectDetailPage(
              projectId: projectId,
              sourceWorkspace: source,
            ),
          );
        },
      ),
      GoRoute(
        path: '/remote/projects/:projectId/segments',
        name: 'remote-project-segments',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final source = WorkspaceRouteMap.sourceWorkspace(state.uri);
          return GlobalPageScaffold(
            title: '电脑正文',
            subtitle: '只读段落',
            fallbackLocation: AppRoutes.remoteProjectFor(projectId, source),
            child: RemoteSegmentListPage(
              projectId: projectId,
              sourceWorkspace: source,
            ),
          );
        },
      ),
      GoRoute(
        path: '/remote/projects/:projectId/segments/:segmentId',
        name: 'remote-segment-detail',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final segmentId = state.pathParameters['segmentId'] ?? '';
          final source = WorkspaceRouteMap.sourceWorkspace(state.uri);
          return GlobalPageScaffold(
            title: '电脑正文',
            subtitle: '只读正文',
            fallbackLocation: AppRoutes.remoteProjectSegmentsFor(
              projectId,
              source,
            ),
            child: RemoteSegmentDetailPage(
              projectId: projectId,
              segmentId: segmentId,
              sourceWorkspace: source,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.projects,
        name: 'projects',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.path,
          title: '选择作品',
          showBackButton: true,
          backFallbackLocation: AppRoutes.novel,
          child: const ProjectsPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.newProject,
        name: 'project-new',
        builder: (context, state) => ShellScaffold(
          currentLocation: state.uri.path,
          title: '新建项目',
          subtitle: '本地 SQLite 保存',
          showBackButton: true,
          backFallbackLocation: AppRoutes.projects,
          child: const NewProjectPage(),
        ),
      ),
      GoRoute(
        path: '/projects/:projectId',
        name: 'project-overview',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: '项目',
            subtitle: '作品设置',
            showBackButton: true,
            backFallbackLocation: AppRoutes.projects,
            child: ProjectOverviewPage(projectId: projectId),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/segments',
        name: 'project-segments',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: '正文工作台',
            subtitle: '连续正文',
            showBackButton: true,
            backFallbackLocation: AppRoutes.projects,
            child: SegmentListPage(projectId: projectId),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/output-limits',
        name: 'novel-output-limits',
        builder: (context, state) => NovelOutputLimitsPage(
          projectId: state.pathParameters['projectId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/projects/:projectId/creation-settings',
        name: 'project-creation-settings',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: '创作设定',
            showBackButton: true,
            backFallbackLocation: AppRoutes.novel,
            child: CreationSettingsPage(projectId: projectId),
          );
        },
      ),
      GoRoute(
        path: '/chat/personas/:personaId/memory',
        name: 'chat-persona-memory',
        builder: (context, state) =>
            ChatMemoryPage(personaId: state.pathParameters['personaId'] ?? ''),
      ),
      GoRoute(
        path: '/chat/personas/:personaId/sessions',
        name: 'chat-persona-sessions',
        builder: (context, state) => ChatPersonaSessionsPage(
          personaId: state.pathParameters['personaId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/chat/:sessionId/usage',
        name: 'chat-session-usage',
        builder: (context, state) =>
            ChatUsagePage(sessionId: state.pathParameters['sessionId'] ?? ''),
      ),
      GoRoute(
        path: '/chat/:sessionId/memory',
        name: 'chat-session-memory',
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId'] ?? '';
          return Consumer(
            builder: (context, ref, _) {
              final session = ref.watch(chatSessionByIdProvider(sessionId));
              return session.when(
                loading: () => const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) =>
                    const Scaffold(body: Center(child: Text('没有找到这个聊天。'))),
                data: (item) => ChatMemoryPage(
                  summaryView: state.uri.queryParameters['view'] == 'summary',
                  personaId: item.personaId ?? '',
                  sessionId: item.id,
                ),
              );
            },
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/reader',
        name: 'project-reader',
        builder: (context, state) =>
            NovelReaderPage(projectId: state.pathParameters['projectId'] ?? ''),
      ),
      GoRoute(
        path: '/projects/:projectId/segments/new',
        name: 'segment-new',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final anchorSegmentId = state.uri.queryParameters['anchor'];
          final position = state.uri.queryParameters['position'];
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: anchorSegmentId == null ? '新增段落' : '插入段落',
            subtitle: '本地 SQLite 保存',
            showBackButton: true,
            backFallbackLocation: AppRoutes.projectSegments(projectId),
            childHandlesPop: true,
            child: NewSegmentPage(
              returnToCreation:
                  state.uri.queryParameters['return'] == 'creation',
              projectId: projectId,
              anchorSegmentId: anchorSegmentId,
              insertBefore: anchorSegmentId == null
                  ? null
                  : position == 'before',
            ),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/segments/deleted',
        name: 'segments-deleted',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: '已删除正文',
            subtitle: '可以恢复',
            showBackButton: true,
            backFallbackLocation: AppRoutes.projectSegments(projectId),
            child: DeletedSegmentListPage(projectId: projectId),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/segments/:segmentId/edit',
        name: 'segment-edit',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final segmentId = state.pathParameters['segmentId'] ?? '';
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: '编辑段落',
            subtitle: '保存会生成历史',
            showBackButton: true,
            backFallbackLocation: AppRoutes.projectSegments(projectId),
            childHandlesPop: true,
            child: SegmentEditorPage(
              projectId: projectId,
              segmentId: segmentId,
            ),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/segments/:segmentId/history/:revisionId',
        name: 'segment-revision',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final segmentId = state.pathParameters['segmentId'] ?? '';
          final revisionId = state.pathParameters['revisionId'] ?? '';
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: '历史预览',
            subtitle: '只读版本',
            showBackButton: true,
            backFallbackLocation: AppRoutes.segmentHistory(
              projectId,
              segmentId,
            ),
            child: SegmentRevisionPreviewPage(
              projectId: projectId,
              segmentId: segmentId,
              revisionId: revisionId,
            ),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/segments/:segmentId/history',
        name: 'segment-history',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final segmentId = state.pathParameters['segmentId'] ?? '';
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: '历史版本',
            subtitle: '可预览和恢复',
            showBackButton: true,
            backFallbackLocation: AppRoutes.segment(projectId, segmentId),
            child: SegmentHistoryPage(
              projectId: projectId,
              segmentId: segmentId,
            ),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/segments/:segmentId',
        name: 'segment-detail',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final segmentId = state.pathParameters['segmentId'] ?? '';
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: '正文详情',
            subtitle: '本地正文',
            showBackButton: true,
            backFallbackLocation: AppRoutes.projectSegments(projectId),
            child: SegmentDetailPage(
              projectId: projectId,
              segmentId: segmentId,
            ),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/characters',
        name: 'project-characters',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final mode = WorkspaceRouteMap.resolve(state.uri);
          return ShellScaffold(
            currentLocation: state.uri.toString(),
            title: '角色',
            subtitle: '本地角色卡',
            showBackButton: true,
            backFallbackLocation: AppRoutes.project(projectId),
            child: CharacterListPage(projectId: projectId, workspaceMode: mode),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/characters/new',
        name: 'character-new',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final mode = WorkspaceRouteMap.resolve(state.uri);
          return ShellScaffold(
            currentLocation: state.uri.toString(),
            title: '新建角色',
            showAppBar: false,
            showBackButton: true,
            backFallbackLocation: AppRoutes.forWorkspace(
              AppRoutes.projectCharacters(projectId),
              mode,
            ),
            childHandlesPop: true,
            child: NewCharacterPage(
              projectId: projectId,
              workspaceMode: mode,
              returnOnComplete: state.uri.queryParameters['return'] == '1',
            ),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/characters/deleted',
        name: 'characters-deleted',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final mode = WorkspaceRouteMap.resolve(state.uri);
          return ShellScaffold(
            currentLocation: state.uri.toString(),
            title: '已删除角色',
            subtitle: '可恢复',
            showBackButton: true,
            backFallbackLocation: AppRoutes.forWorkspace(
              AppRoutes.projectCharacters(projectId),
              mode,
            ),
            child: DeletedCharacterListPage(
              projectId: projectId,
              workspaceMode: mode,
            ),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/characters/:characterId',
        name: 'character-detail',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final characterId = state.pathParameters['characterId'] ?? '';
          final mode = WorkspaceRouteMap.resolve(state.uri);
          return ShellScaffold(
            currentLocation: state.uri.toString(),
            title: '角色详情',
            subtitle: '本地角色卡',
            showBackButton: true,
            backFallbackLocation: AppRoutes.forWorkspace(
              AppRoutes.projectCharacters(projectId),
              mode,
            ),
            child: CharacterDetailPage(
              projectId: projectId,
              characterId: characterId,
              workspaceMode: mode,
            ),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/characters/:characterId/edit',
        name: 'character-edit',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final characterId = state.pathParameters['characterId'] ?? '';
          final mode = WorkspaceRouteMap.resolve(state.uri);
          return ShellScaffold(
            currentLocation: state.uri.toString(),
            title: '编辑角色',
            showAppBar: false,
            showBackButton: true,
            backFallbackLocation: AppRoutes.forWorkspace(
              AppRoutes.character(projectId, characterId),
              mode,
            ),
            childHandlesPop: true,
            child: EditCharacterPage(
              projectId: projectId,
              characterId: characterId,
              workspaceMode: mode,
            ),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/world',
        name: 'project-world',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: '世界观',
            subtitle: '本地世界观卡',
            showBackButton: true,
            backFallbackLocation: AppRoutes.project(projectId),
            child: WorldCardListPage(projectId: projectId),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/world/new',
        name: 'world-card-new',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: '新建世界观',
            subtitle: '本地 SQLite 保存',
            showBackButton: true,
            backFallbackLocation: AppRoutes.projectWorld(projectId),
            childHandlesPop: true,
            child: NewWorldCardPage(
              projectId: projectId,
              returnOnComplete: state.uri.queryParameters['return'] == '1',
            ),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/world/deleted',
        name: 'world-cards-deleted',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: '已删除世界观',
            subtitle: '可恢复',
            showBackButton: true,
            backFallbackLocation: AppRoutes.projectWorld(projectId),
            child: DeletedWorldCardListPage(projectId: projectId),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/world/:worldCardId',
        name: 'world-card-detail',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final worldCardId = state.pathParameters['worldCardId'] ?? '';
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: '世界观详情',
            subtitle: '本地世界观卡',
            showBackButton: true,
            backFallbackLocation: AppRoutes.projectWorld(projectId),
            child: WorldCardDetailPage(
              projectId: projectId,
              worldCardId: worldCardId,
            ),
          );
        },
      ),
      GoRoute(
        path: '/projects/:projectId/world/:worldCardId/edit',
        name: 'world-card-edit',
        builder: (context, state) {
          final projectId = state.pathParameters['projectId'] ?? '';
          final worldCardId = state.pathParameters['worldCardId'] ?? '';
          return ShellScaffold(
            currentLocation: state.uri.path,
            title: '编辑世界观',
            subtitle: '本地世界观卡',
            showBackButton: true,
            backFallbackLocation: AppRoutes.worldCard(projectId, worldCardId),
            childHandlesPop: true,
            child: EditWorldCardPage(
              projectId: projectId,
              worldCardId: worldCardId,
            ),
          );
        },
      ),
    ],
  );
});

SillyTavernAssetKind? _sillyTavernAssetKind(String? value) {
  for (final kind in SillyTavernAssetKind.values) {
    if (kind.name == value) return kind;
  }
  return null;
}
