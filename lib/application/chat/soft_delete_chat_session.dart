import '../../data/repositories/chat_repository.dart';

class SoftDeleteChatSession {
  const SoftDeleteChatSession(this._chats);

  final ChatRepository _chats;

  Future<void> call({required String sessionId, required DateTime nowUtc}) {
    return _chats.softDeleteSession(sessionId, nowUtc.toUtc());
  }
}
