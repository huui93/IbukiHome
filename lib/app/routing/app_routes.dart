import '../navigation/app_workspace_mode.dart';

class AppRoutes {
  const AppRoutes._();

  static const home = '/';
  static const novel = '/novel';
  static const novelCreation = '/novel?section=creation';
  static const novelSettings = '/novel?section=settings';
  static String novelEditor(String projectId) =>
      '/novel/write/${Uri.encodeComponent(projectId)}?section=creation';
  static const chat = '/chat';
  static const newChatSession = '/chat/new';
  static const deletedChatSessions = '/chat/deleted';
  static const newChatPersona = '/chat/personas/new';
  static const importChatPersona = '/chat/personas/import';
  static const deletedChatPersonas = '/chat/personas/deleted';
  static const settings = '/settings';
  static const chatMemorySettings = '/settings/chat-memory';
  static const personalProfile = '/settings/profile';
  static const chatPersonaPicker = '/chat/personas/select';
  static String selectChatPersona({bool edit = false}) =>
      '$chatPersonaPicker?intent=${edit ? 'edit' : 'new-session'}';
  static const aiSettings = '/settings/ai';
  static const aiProviders = '/settings/ai/providers';
  static const newCustomAiProvider = '/settings/ai/providers/custom/new';
  static const plugins = '/settings/plugins';
  static const sillyTavernImport = '/settings/import/sillytavern';
  static const backupRestore = '/settings/backup';
  static const worldBookLibrary = '/settings/world-books';
  static const projects = '/projects';
  static const newProject = '/projects/new';
  static const importTxtNovel = '/projects/import-txt';
  static const remoteConnect = '/remote/connect';
  static const remoteProjects = '/remote/projects';
  // Compatibility path only; the retired mode redirects to Tavern.
  static const world = '/world';
  static const tavern = '/tavern';
  static const newTavernStory = '/tavern/new';
  static String tavernStory(String id) =>
      '/tavern/stories/${Uri.encodeComponent(id)}';

  static const sourceQueryKey = 'from';

  static String chatSession(String sessionId) {
    return '/chat/${Uri.encodeComponent(sessionId)}';
  }

  static String chatPersona(String personaId) {
    return '/chat/personas/${Uri.encodeComponent(personaId)}';
  }

  static String editChatPersona(String personaId) {
    return '${chatPersona(personaId)}/edit';
  }

  @Deprecated('Use chatPersona; contacts are now ChatPersona entities.')
  static String chatContact(String personaId) {
    return chatPersona(personaId);
  }

  static String aiProvider(String providerId) {
    return '/settings/ai/providers/${Uri.encodeComponent(providerId)}';
  }

  static String plugin(String pluginId) {
    return '/settings/plugins/${Uri.encodeComponent(pluginId)}';
  }

  static String sillyTavernImportFor({
    String? kind,
    String? projectId,
    String? worldId,
    bool returnOnComplete = false,
    bool deferForStory = false,
  }) {
    final parameters = <String, String>{};
    if (kind != null) parameters['kind'] = kind;
    if (projectId != null) parameters['project'] = projectId;
    if (worldId != null) parameters['world'] = worldId;
    if (returnOnComplete) parameters['return'] = '1';
    if (deferForStory) parameters['story'] = '1';
    return Uri(
      path: sillyTavernImport,
      queryParameters: parameters.isEmpty ? null : parameters,
    ).toString();
  }

  static String sillyTavernCompatibility(String payloadId) {
    return '$sillyTavernImport/compatibility/${Uri.encodeComponent(payloadId)}';
  }

  static String project(String projectId) {
    return '/projects/${Uri.encodeComponent(projectId)}';
  }

  static String projectSegments(String projectId) {
    return '/projects/${Uri.encodeComponent(projectId)}/segments';
  }

  static String projectCreationSettings(String projectId) {
    return '/projects/${Uri.encodeComponent(projectId)}/creation-settings';
  }

  static String projectOutputLimits(String projectId) =>
      '${project(projectId)}/output-limits';

  static String projectOutline(String projectId) =>
      '${project(projectId)}/outline';
  static String projectLongMemory(String projectId) =>
      '${project(projectId)}/long-memory';

  static String chatPersonaMemory(String personaId) {
    return '${chatPersona(personaId)}/memory';
  }

  static String chatPersonaSessions(String personaId) {
    return '${chatPersona(personaId)}/sessions';
  }

  static String chatSessionUsage(String sessionId) =>
      '${chatSession(sessionId)}/usage';

  static String chatSessionMemory(String sessionId) {
    return '${chatSession(sessionId)}/memory';
  }

  static String projectReader(String projectId) {
    return '/projects/${Uri.encodeComponent(projectId)}/reader';
  }

  static String newSegment(String projectId) {
    return '/projects/${Uri.encodeComponent(projectId)}/segments/new';
  }

  static String insertSegment(
    String projectId,
    String anchorSegmentId, {
    required bool before,
  }) {
    return '${newSegment(projectId)}?anchor=${Uri.encodeQueryComponent(anchorSegmentId)}'
        '&position=${before ? 'before' : 'after'}';
  }

  static String deletedSegments(String projectId) {
    return '${projectSegments(projectId)}/deleted';
  }

  static String segment(String projectId, String segmentId) {
    return '${projectSegments(projectId)}/${Uri.encodeComponent(segmentId)}';
  }

  static String editSegment(String projectId, String segmentId) {
    return '${segment(projectId, segmentId)}/edit';
  }

  static String segmentHistory(String projectId, String segmentId) {
    return '${segment(projectId, segmentId)}/history';
  }

  static String segmentRevision(
    String projectId,
    String segmentId,
    String revisionId,
  ) {
    return '${segmentHistory(projectId, segmentId)}/'
        '${Uri.encodeComponent(revisionId)}';
  }

  static String projectCharacters(String projectId) {
    return '/projects/${Uri.encodeComponent(projectId)}/characters';
  }

  static String newCharacter(
    String projectId, {
    bool returnOnComplete = false,
  }) {
    final path = '${projectCharacters(projectId)}/new';
    return returnOnComplete ? '$path?return=1' : path;
  }

  static String deletedCharacters(String projectId) {
    return '${projectCharacters(projectId)}/deleted';
  }

  static String character(String projectId, String characterId) {
    return '${projectCharacters(projectId)}/${Uri.encodeComponent(characterId)}';
  }

  static String editCharacter(String projectId, String characterId) {
    return '${character(projectId, characterId)}/edit';
  }

  static String projectWorld(String projectId) {
    return '/projects/${Uri.encodeComponent(projectId)}/world';
  }

  static String newWorldCard(String projectId) {
    return '${projectWorld(projectId)}/new';
  }

  static String deletedWorldCards(String projectId) {
    return '${projectWorld(projectId)}/deleted';
  }

  static String worldCard(String projectId, String worldCardId) {
    return '${projectWorld(projectId)}/${Uri.encodeComponent(worldCardId)}';
  }

  static String editWorldCard(String projectId, String worldCardId) {
    return '${worldCard(projectId, worldCardId)}/edit';
  }

  static String remoteProject(String projectId) {
    return '/remote/projects/${Uri.encodeComponent(projectId)}';
  }

  static String remoteProjectSegments(String projectId) {
    return '/remote/projects/${Uri.encodeComponent(projectId)}/segments';
  }

  static String remoteSegment(String projectId, String segmentId) {
    return '/remote/projects/${Uri.encodeComponent(projectId)}/segments/'
        '${Uri.encodeComponent(segmentId)}';
  }

  static String settingsFor(AppWorkspaceMode source) {
    return _withQuery(settings, sourceQueryKey, source.name);
  }

  static String remoteConnectFor(AppWorkspaceMode source) {
    return _withQuery(remoteConnect, sourceQueryKey, source.name);
  }

  static String remoteProjectsFor(AppWorkspaceMode source) {
    return _withQuery(remoteProjects, sourceQueryKey, source.name);
  }

  static String remoteProjectFor(String projectId, AppWorkspaceMode source) {
    return _withQuery(remoteProject(projectId), sourceQueryKey, source.name);
  }

  static String remoteProjectSegmentsFor(
    String projectId,
    AppWorkspaceMode source,
  ) {
    return _withQuery(
      remoteProjectSegments(projectId),
      sourceQueryKey,
      source.name,
    );
  }

  static String remoteSegmentFor(
    String projectId,
    String segmentId,
    AppWorkspaceMode source,
  ) {
    return _withQuery(
      remoteSegment(projectId, segmentId),
      sourceQueryKey,
      source.name,
    );
  }

  static String forWorkspace(String path, AppWorkspaceMode workspace) => path;

  static String _withQuery(String path, String key, String value) {
    final uri = Uri.parse(path);
    return uri
        .replace(
          queryParameters: <String, String>{...uri.queryParameters, key: value},
        )
        .toString();
  }
}
