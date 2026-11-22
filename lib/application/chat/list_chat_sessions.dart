import '../../data/repositories/chat_repository.dart';
import '../../domain/chat/chat_session.dart';

class ListChatSessions {
  const ListChatSessions(this._chats);

  final ChatRepository _chats;

  Future<List<ChatSession>> call({
    String? projectId,
    bool includeDeleted = false,
    bool onlyDeleted = false,
  }) async {
    final sessions = await _chats.listSessions(
      projectId: projectId,
      includeDeleted: includeDeleted || onlyDeleted,
    );
    if (!onlyDeleted) {
      return sessions;
    }
    final deleted =
        sessions.where((session) => session.deletedAt != null).toList()
          ..sort(_compareDeletedSessions);
    return List.unmodifiable(deleted);
  }

  int _compareDeletedSessions(ChatSession left, ChatSession right) {
    final leftDeleted =
        left.deletedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final rightDeleted =
        right.deletedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final time = rightDeleted.compareTo(leftDeleted);
    return time != 0 ? time : left.id.compareTo(right.id);
  }
}
