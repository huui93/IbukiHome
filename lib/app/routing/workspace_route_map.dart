import '../navigation/app_workspace_mode.dart';
import 'app_routes.dart';

class WorkspaceRouteMap {
  const WorkspaceRouteMap._();

  static AppWorkspaceMode resolve(Uri uri) {
    final path = uri.path;
    if (path == AppRoutes.home) {
      return AppWorkspaceMode.home;
    }
    if (path == AppRoutes.novel || path.startsWith('${AppRoutes.novel}/')) {
      return AppWorkspaceMode.novel;
    }
    if (path == AppRoutes.chat || path.startsWith('${AppRoutes.chat}/')) {
      return AppWorkspaceMode.chat;
    }
    if (path == AppRoutes.world || path.startsWith('${AppRoutes.world}/')) {
      return AppWorkspaceMode.tavern;
    }
    if (path == AppRoutes.tavern || path.startsWith('${AppRoutes.tavern}/')) {
      return AppWorkspaceMode.tavern;
    }
    if (path == AppRoutes.settings) {
      return AppWorkspaceMode.settings;
    }
    if (path == AppRoutes.projects ||
        path.startsWith('${AppRoutes.projects}/')) {
      return AppWorkspaceMode.novel;
    }
    if (isGlobalPath(path)) {
      return sourceWorkspace(uri);
    }
    return AppWorkspaceMode.home;
  }

  static AppWorkspaceMode sourceWorkspace(Uri uri) {
    final raw = uri.queryParameters[AppRoutes.sourceQueryKey];
    if (raw == 'world') return AppWorkspaceMode.tavern;
    return AppWorkspaceMode.values
            .where((mode) => mode.name == raw)
            .firstOrNull ??
        AppWorkspaceMode.home;
  }

  static String rootFor(AppWorkspaceMode mode) => switch (mode) {
    AppWorkspaceMode.home => AppRoutes.home,
    AppWorkspaceMode.novel => AppRoutes.novel,
    AppWorkspaceMode.chat => AppRoutes.chat,
    AppWorkspaceMode.tavern => AppRoutes.tavern,
    AppWorkspaceMode.settings => AppRoutes.settings,
  };

  static bool isWorkspaceRoot(Uri uri) => uri.path == rootFor(resolve(uri));

  static bool isGlobalPath(String path) {
    return path == AppRoutes.settings ||
        path == AppRoutes.remoteConnect ||
        path == AppRoutes.remoteProjects ||
        path.startsWith('${AppRoutes.remoteProjects}/');
  }

  static bool isProjectList(Uri uri) => uri.path == AppRoutes.projects;

  static bool isProjectOverview(Uri uri) {
    final parts = uri.pathSegments;
    return parts.length == 2 && parts.first == 'projects';
  }

  static bool isSegmentPath(Uri uri) => uri.pathSegments.contains('segments');

  static bool isCharacterPath(Uri uri) =>
      uri.pathSegments.contains('characters');

  static bool isWorldCardPath(Uri uri) => _isWorldCardPath(uri.path);

  static bool isChatList(Uri uri) => uri.path == AppRoutes.chat;

  static bool isNewChat(Uri uri) => uri.path == AppRoutes.newChatSession;

  static bool isDeletedChats(Uri uri) =>
      uri.path == AppRoutes.deletedChatSessions;

  static String? chatSessionId(Uri uri) {
    final parts = uri.pathSegments;
    if (parts.length != 2 || parts.first != 'chat') {
      return null;
    }
    final value = parts.last;
    if (value == 'new' || value == 'deleted') {
      return null;
    }
    return Uri.decodeComponent(value);
  }

  static bool _isWorldCardPath(String path) {
    final parts = Uri.parse(path).pathSegments;
    return parts.length >= 3 &&
        parts.first == 'projects' &&
        parts[2] == 'world';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
