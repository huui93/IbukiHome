import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/world_roleplay_repository.dart';

class SaveProjectAiBinding {
  const SaveProjectAiBinding(this._projects);

  final ProjectRepository _projects;

  Future<void> call({
    required String projectId,
    required String? providerConfigId,
    required String? model,
    required DateTime nowUtc,
  }) async {
    _validatePair(providerConfigId, model);
    final project = await _projects.getProject(projectId);
    await _projects.upsertProject(
      project.copyWith(
        metadata: project.metadata.copyWith(
          updatedAt: nowUtc.toUtc(),
          revision: project.revision + 1,
        ),
        aiProviderConfigId: _emptyToNull(providerConfigId),
        aiModel: _emptyToNull(model),
      ),
    );
  }
}

class SaveChatSessionAiBinding {
  const SaveChatSessionAiBinding(this._chats);

  final ChatRepository _chats;

  Future<void> call({
    required String sessionId,
    required String? providerConfigId,
    required String? model,
    required DateTime nowUtc,
  }) async {
    _validatePair(providerConfigId, model);
    final session = await _chats.getSession(sessionId);
    await _chats.upsertSession(
      session.copyWith(
        metadata: session.metadata.copyWith(
          updatedAt: nowUtc.toUtc(),
          revision: session.revision + 1,
        ),
        aiProviderConfigId: _emptyToNull(providerConfigId),
        aiModel: _emptyToNull(model),
      ),
    );
  }
}

class SaveWorldSessionAiBinding {
  const SaveWorldSessionAiBinding(this._worlds);

  final WorldRoleplayRepository _worlds;

  Future<void> call({
    required String sessionId,
    required String? providerConfigId,
    required String? model,
    required DateTime nowUtc,
  }) async {
    _validatePair(providerConfigId, model);
    final session = await _worlds.getSession(sessionId);
    await _worlds.upsertSession(
      session.copyWith(
        entity: session.entity.copyWith(
          updatedAt: nowUtc.toUtc(),
          revision: session.revision + 1,
        ),
        aiProviderConfigId: _emptyToNull(providerConfigId),
        aiModel: _emptyToNull(model),
      ),
    );
  }
}

void _validatePair(String? providerConfigId, String? model) {
  final provider = _emptyToNull(providerConfigId);
  final selectedModel = _emptyToNull(model);
  if ((provider == null) != (selectedModel == null)) {
    throw const DataFormatException('Provider 与模型必须同时选择。');
  }
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
