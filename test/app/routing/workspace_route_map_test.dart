import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/app/navigation/app_workspace_mode.dart';
import 'package:ibukihome/app/routing/app_routes.dart';
import 'package:ibukihome/app/routing/workspace_route_map.dart';

void main() {
  final routeCases = <({String location, AppWorkspaceMode mode})>[
    (location: '/', mode: AppWorkspaceMode.home),
    (location: '/novel', mode: AppWorkspaceMode.novel),
    (location: '/chat', mode: AppWorkspaceMode.chat),
    (location: '/chat/new', mode: AppWorkspaceMode.chat),
    (location: '/chat/deleted', mode: AppWorkspaceMode.chat),
    (location: '/chat/session-1', mode: AppWorkspaceMode.chat),
    (location: '/world', mode: AppWorkspaceMode.tavern),
    (location: '/tavern', mode: AppWorkspaceMode.tavern),
    (location: '/tavern/stories/s1', mode: AppWorkspaceMode.tavern),
    (location: '/world/projects', mode: AppWorkspaceMode.tavern),
    (location: '/projects', mode: AppWorkspaceMode.novel),
    (location: '/projects/project-1', mode: AppWorkspaceMode.novel),
    (location: '/projects/project-1/segments', mode: AppWorkspaceMode.novel),
    (location: '/projects/project-1/characters', mode: AppWorkspaceMode.novel),
    (
      location: '/projects/project-1/characters?workspace=world',
      mode: AppWorkspaceMode.novel,
    ),
    (location: '/projects/project-1/world', mode: AppWorkspaceMode.novel),
    (location: '/settings', mode: AppWorkspaceMode.settings),
    (location: '/settings?from=novel', mode: AppWorkspaceMode.settings),
    (location: '/remote/connect?from=chat', mode: AppWorkspaceMode.chat),
    (
      location: '/remote/projects/project-1?from=world',
      mode: AppWorkspaceMode.tavern,
    ),
  ];

  for (final routeCase in routeCases) {
    test('maps ${routeCase.location} to ${routeCase.mode.name}', () {
      expect(
        WorkspaceRouteMap.resolve(Uri.parse(routeCase.location)),
        routeCase.mode,
      );
    });
  }

  for (final mode in AppWorkspaceMode.values) {
    test('rootFor returns the root for ${mode.name}', () {
      final expected = switch (mode) {
        AppWorkspaceMode.home => '/',
        AppWorkspaceMode.novel => '/novel',
        AppWorkspaceMode.chat => '/chat',
        AppWorkspaceMode.tavern => '/tavern',
        AppWorkspaceMode.settings => '/settings',
      };
      expect(WorkspaceRouteMap.rootFor(mode), expected);
    });

    test('isWorkspaceRoot recognizes ${mode.name}', () {
      expect(
        WorkspaceRouteMap.isWorkspaceRoot(
          Uri.parse(WorkspaceRouteMap.rootFor(mode)),
        ),
        isTrue,
      );
    });
  }

  final sessionCases = <({String location, String? id})>[
    (location: '/chat', id: null),
    (location: '/chat/new', id: null),
    (location: '/chat/deleted', id: null),
    (location: '/chat/session%20one', id: 'session one'),
  ];
  for (final sessionCase in sessionCases) {
    test('extracts chat session from ${sessionCase.location}', () {
      expect(
        WorkspaceRouteMap.chatSessionId(Uri.parse(sessionCase.location)),
        sessionCase.id,
      );
    });
  }

  test('settingsFor carries the source workspace', () {
    expect(AppRoutes.settingsFor(AppWorkspaceMode.chat), '/settings?from=chat');
  });

  test('remoteConnectFor carries the source workspace', () {
    expect(
      AppRoutes.remoteConnectFor(AppWorkspaceMode.tavern),
      '/remote/connect?from=tavern',
    );
  });

  test('remote project detail keeps the source workspace', () {
    expect(
      AppRoutes.remoteProjectFor('project-1', AppWorkspaceMode.novel),
      '/remote/projects/project-1?from=novel',
    );
  });

  test('remote segment list keeps the source workspace', () {
    expect(
      AppRoutes.remoteProjectSegmentsFor('project-1', AppWorkspaceMode.chat),
      '/remote/projects/project-1/segments?from=chat',
    );
  });

  test('remote segment detail keeps the source workspace', () {
    expect(
      AppRoutes.remoteSegmentFor(
        'project-1',
        'segment-1',
        AppWorkspaceMode.tavern,
      ),
      '/remote/projects/project-1/segments/segment-1?from=tavern',
    );
  });
}
