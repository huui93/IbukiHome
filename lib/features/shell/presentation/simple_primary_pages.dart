import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/app_workspace_mode.dart';
import '../../../app/routing/app_routes.dart';
import '../../chat/presentation/chat_home_page.dart';
import '../../chat/presentation/simple_chat_pages.dart';
import '../../../application/profile/local_user_profile.dart';
import '../../settings/presentation/local_user_avatar.dart';
import '../../settings/presentation/settings_page.dart';
import '../../workspaces/presentation/novel_workspace_home_page.dart';
import 'simple_primary_scaffold.dart';
import '../../../app/navigation/novel_workspace_section.dart';
import '../../workspaces/presentation/novel_section_tabs.dart';

class NovelPrimaryPage extends ConsumerWidget {
  const NovelPrimaryPage({
    this.section = NovelWorkspaceSection.bookshelf,
    this.editingProjectId,
    super.key,
  });
  final NovelWorkspaceSection section;
  final String? editingProjectId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SimplePrimaryScaffold(
    selectedIndex: 0,
    title: '',
    titleWidget: NovelSectionTabs(
      selected: section,
      onSelected: (value) {
        if (value == section && editingProjectId == null) return;
        FocusManager.instance.primaryFocus?.unfocus();
        context.go(switch (value) {
          NovelWorkspaceSection.bookshelf => AppRoutes.novel,
          NovelWorkspaceSection.creation => AppRoutes.novelCreation,
          NovelWorkspaceSection.settings => AppRoutes.novelSettings,
        });
      },
    ),
    onBack: editingProjectId == null
        ? null
        : () => context.go(AppRoutes.novelCreation),
    actions: [
      if (editingProjectId != null)
        IconButton(
          key: const Key('novel-back-to-creation-list'),
          tooltip: '返回创作列表',
          onPressed: () => context.go(AppRoutes.novelCreation),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      if (editingProjectId == null && section != NovelWorkspaceSection.settings)
        IconButton(
          key: const Key('novel-import-txt'),
          tooltip: '导入 TXT 小说',
          onPressed: () => context.push(AppRoutes.importTxtNovel),
          icon: const Icon(Icons.file_upload_outlined),
        ),
      const SizedBox(width: 8),
    ],
    body: NovelWorkspaceHomePage(
      section: section,
      editingProjectId: editingProjectId,
    ),
  );
}

class ChatPrimaryPage extends ConsumerWidget {
  const ChatPrimaryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile =
        ref.watch(localUserProfileProvider).value ?? const LocalUserProfile();
    return SimplePrimaryScaffold(
      selectedIndex: 1,
      title: '',
      titleWidget: InkWell(
        key: const Key('chat-self-profile'),
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.push(AppRoutes.personalProfile),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LocalUserAvatar(profile: profile, radius: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                profile.name,
                key: const Key('chat-self-name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          key: const Key('chat-add-menu'),
          tooltip: '添加或修改聊天对象',
          onPressed: () => showChatCreationMenu(context),
          icon: const Icon(Icons.add_rounded),
        ),
        const SizedBox(width: 8),
      ],
      body: const ChatHomePage(),
    );
  }
}

class SettingsPrimaryPage extends StatelessWidget {
  const SettingsPrimaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimplePrimaryScaffold(
      selectedIndex: 2,
      title: '',
      showAppBar: false,
      body: SettingsPage(sourceWorkspace: AppWorkspaceMode.settings),
    );
  }
}
