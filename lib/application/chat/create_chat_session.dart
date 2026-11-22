import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/chat_persona_repository.dart';
import '../../domain/chat/chat_session.dart';
import '../../domain/common/entity_metadata.dart';

class CreateChatSession {
  const CreateChatSession(this._chats, [this._personas]);

  final ChatRepository _chats;
  final ChatPersonaRepository? _personas;

  Future<ChatSession> call({
    required String id,
    required String title,
    String? projectId,
    String? characterId,
    String? personaId,
    required DateTime nowUtc,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw const DataFormatException('会话标题不能为空。');
    }
    if (projectId != null || characterId != null) {
      throw const DataConflictException('聊天会话不能关联小说作品或角色，请选择聊天人格。');
    }
    if (personaId != null) {
      final personas = _personas;
      if (personas == null) {
        throw const DataConflictException('当前聊天服务无法读取聊天角色。');
      }
      final persona = await personas.getPersona(personaId);
      if (persona.deletedAt != null) {
        throw const DataConflictException('已删除的聊天角色不能创建新聊天。');
      }
    }

    final now = nowUtc.toUtc();
    final session = ChatSession(
      metadata: EntityMetadata(
        id: id,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      ),
      projectId: projectId,
      characterId: characterId,
      personaId: personaId,
      title: trimmedTitle,
    );
    await _chats.upsertSession(session);
    return session;
  }
}
