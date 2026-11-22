import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/chat_persona_repository.dart';
import '../../data/repositories/chat_repository.dart';
import '../../domain/chat/chat_session.dart';
import 'create_chat_session.dart';

class OpenPersonaChat {
  const OpenPersonaChat(this._personas, this._chats, this._createSession);

  final ChatPersonaRepository _personas;
  final ChatRepository _chats;
  final CreateChatSession _createSession;

  Future<ChatSession> call({
    required String personaId,
    required String newSessionId,
    required DateTime nowUtc,
  }) async {
    return continueLatest(
      personaId: personaId,
      newSessionId: newSessionId,
      nowUtc: nowUtc,
    );
  }

  Future<ChatSession> continueLatest({
    required String personaId,
    required String newSessionId,
    required DateTime nowUtc,
  }) async {
    final persona = await _personas.getPersona(personaId);
    if (persona.deletedAt != null) {
      throw const DataConflictException('已删除的聊天角色不能创建新聊天。');
    }
    final existing = await _chats.listSessions(personaId: personaId);
    if (existing.isNotEmpty) {
      return existing.first;
    }
    return _createSession(
      id: newSessionId,
      title: persona.name,
      projectId: null,
      personaId: persona.id,
      nowUtc: nowUtc,
    );
  }

  Future<ChatSession> createNew({
    required String personaId,
    required String newSessionId,
    required DateTime nowUtc,
    String? title,
  }) async {
    final persona = await _personas.getPersona(personaId);
    if (persona.deletedAt != null) {
      throw const DataConflictException('已删除的聊天角色不能创建新聊天。');
    }
    final existing = await _chats.listSessions(personaId: personaId);
    return _createSession(
      id: newSessionId,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : existing.isEmpty
          ? persona.name
          : '${persona.name}的聊天 ${existing.length + 1}',
      projectId: null,
      personaId: persona.id,
      nowUtc: nowUtc,
    );
  }
}
