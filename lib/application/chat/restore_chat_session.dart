import '../../data/repositories/chat_repository.dart';

class RestoreChatSession {
  const RestoreChatSession(this._chats);

  final ChatRepository _chats;

  Future<void> call({required String sessionId, required DateTime nowUtc}) {
    return _chats.restoreSession(sessionId, nowUtc.toUtc());
  }
}
