import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/chat_repository.dart';
import '../../domain/chat/chat_session.dart';

class RenameChatSession {
  const RenameChatSession(this._chats);

  final ChatRepository _chats;

  Future<ChatSession> call({
    required String sessionId,
    required String title,
    required DateTime nowUtc,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw const DataFormatException('会话标题不能为空。');
    }

    final session = await _chats.getSession(sessionId);
    if (session.deletedAt != null) {
      throw const DataConflictException('已删除会话不能重命名。');
    }
    if (session.title == trimmedTitle) {
      return session;
    }

    final now = nowUtc.toUtc();
    final renamed = session.copyWith(
      title: trimmedTitle,
      metadata: session.metadata.copyWith(
        updatedAt: now,
        revision: session.revision + 1,
      ),
    );
    await _chats.upsertSession(renamed);
    return renamed;
  }
}
