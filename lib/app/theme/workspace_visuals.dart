import 'package:flutter/material.dart';

import '../navigation/app_workspace_mode.dart';
import 'app_tokens.dart';

class WorkspaceVisuals {
  const WorkspaceVisuals._();

  static Color accent(AppWorkspaceMode mode) => switch (mode) {
    AppWorkspaceMode.home => AppTokens.accentPink,
    AppWorkspaceMode.novel => AppTokens.accentBlue,
    AppWorkspaceMode.chat => AppTokens.accentChat,
    AppWorkspaceMode.tavern => AppTokens.accentPink,
    AppWorkspaceMode.settings => AppTokens.accentBlue,
  };

  static IconData icon(AppWorkspaceMode mode) => switch (mode) {
    AppWorkspaceMode.home => Icons.home_outlined,
    AppWorkspaceMode.novel => Icons.auto_stories_outlined,
    AppWorkspaceMode.chat => Icons.forum_outlined,
    AppWorkspaceMode.tavern => Icons.auto_stories_outlined,
    AppWorkspaceMode.settings => Icons.settings_outlined,
  };

  static String description(AppWorkspaceMode mode) => switch (mode) {
    AppWorkspaceMode.home => '选择今天要进入的工作空间',
    AppWorkspaceMode.novel => '项目、正文与角色',
    AppWorkspaceMode.chat => '本地会话与消息',
    AppWorkspaceMode.tavern => '角色、世界与正在继续的故事',
    AppWorkspaceMode.settings => '外观、连接与本地状态',
  };
}
