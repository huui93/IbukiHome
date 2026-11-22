import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/world_roleplay_repository.dart';
import 'ai_generation_service.dart';

enum AiModelSelectionSource {
  globalDefault,
  projectOverride,
  sessionOverride,
  worldSessionOverride,
}

class ResolvedAiModel {
  const ResolvedAiModel({
    required this.providerConfigId,
    required this.providerType,
    required this.model,
    required this.displayLabel,
    required this.source,
  });

  final String providerConfigId;
  final String providerType;
  final String model;
  final String displayLabel;
  final AiModelSelectionSource source;
}

class AiModelResolver {
  const AiModelResolver({
    ProjectRepository? projects,
    ChatRepository? chats,
    required AiGenerationRuntime runtime,
    WorldRoleplayRepository? worlds,
  }) : _projects = projects,
       _chats = chats,
       _worlds = worlds,
       _runtime = runtime;

  final ProjectRepository? _projects;
  final ChatRepository? _chats;
  final WorldRoleplayRepository? _worlds;
  final AiGenerationRuntime _runtime;

  Future<ResolvedAiModel> resolveForProject(String projectId) async {
    final projects = _projects;
    if (projects == null) {
      throw StateError('Novel model resolution is not configured.');
    }
    final project = await projects.getProject(projectId);
    final explicit = project.aiProviderConfigId?.trim();
    final model = project.aiModel?.trim();
    final resolved = await _resolve(explicit, model);
    return ResolvedAiModel(
      providerConfigId: resolved.config.id,
      providerType: resolved.config.type.name,
      model: resolved.selection.modelId,
      displayLabel: resolved.displayLabel,
      source: explicit?.isNotEmpty == true && model?.isNotEmpty == true
          ? AiModelSelectionSource.projectOverride
          : AiModelSelectionSource.globalDefault,
    );
  }

  Future<ResolvedAiModel> resolveForChatSession(String sessionId) async {
    final chats = _chats;
    if (chats == null) {
      throw StateError('Chat model resolution is not configured.');
    }
    final session = await chats.getSession(sessionId);
    final explicit = session.aiProviderConfigId?.trim();
    final model = session.aiModel?.trim();
    final resolved = await _resolve(explicit, model);
    return ResolvedAiModel(
      providerConfigId: resolved.config.id,
      providerType: resolved.config.type.name,
      model: resolved.selection.modelId,
      displayLabel: resolved.displayLabel,
      source: explicit?.isNotEmpty == true && model?.isNotEmpty == true
          ? AiModelSelectionSource.sessionOverride
          : AiModelSelectionSource.globalDefault,
    );
  }

  Future<ResolvedAiModel> resolveForWorldSession(String sessionId) async {
    final worlds = _worlds;
    if (worlds == null) {
      throw StateError('WorldRoleplayRepository is not configured.');
    }
    final session = await worlds.getSession(sessionId);
    final explicit = session.aiProviderConfigId?.trim();
    final model = session.aiModel?.trim();
    final resolved = await _resolve(explicit, model);
    return ResolvedAiModel(
      providerConfigId: resolved.config.id,
      providerType: resolved.config.type.name,
      model: resolved.selection.modelId,
      displayLabel: resolved.displayLabel,
      source: explicit?.isNotEmpty == true && model?.isNotEmpty == true
          ? AiModelSelectionSource.worldSessionOverride
          : AiModelSelectionSource.globalDefault,
    );
  }

  Future<AiResolvedProvider> _resolve(String? providerId, String? model) {
    final runtime = _runtime;
    if (runtime is AiDetailedGenerationRuntime) {
      return runtime.resolveSelection(
        providerConfigId: providerId,
        model: model,
      );
    }
    return runtime.resolveDefault();
  }
}

// ignore_for_file: prefer_initializing_formals
