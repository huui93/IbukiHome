enum AppWorkspaceMode { home, novel, chat, tavern, settings }

extension AppWorkspaceModeLabel on AppWorkspaceMode {
  String get label => switch (this) {
    AppWorkspaceMode.home => '伊吹之家',
    AppWorkspaceMode.novel => '小说创作',
    AppWorkspaceMode.chat => '聊天',
    AppWorkspaceMode.tavern => 'Tavern',
    AppWorkspaceMode.settings => '设置',
  };
}
