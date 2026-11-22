import '../../data/repositories/chat_repository.dart';
import '../../domain/chat/chat_message.dart';

class ListChatMessages {
  const ListChatMessages(this._chats);

  final ChatRepository _chats;

  Future<List<ChatMessage>> call(String sessionId) {
    return _chats.listMessages(sessionId);
  }
}
