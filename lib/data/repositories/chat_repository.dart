import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_session.dart';

abstract class ChatRepository {
  Future<List<ChatSession>> listSessions({
    String? projectId,
    String? characterId,
    String? personaId,
    bool includeDeleted = false,
  });

  Future<ChatSession> getSession(String id);

  Future<void> upsertSession(ChatSession session);

  Future<void> softDeleteSession(String id, DateTime deletedAt);

  Future<void> restoreSession(String id, DateTime updatedAt);

  Future<List<ChatMessage>> listMessages(
    String sessionId, {
    bool includeDeleted = false,
  });

  Future<void> appendMessage(ChatMessage message);

  Future<void> upsertMessage(ChatMessage message);

  Future<ChatSession> appendMessageAndTouchSession(
    ChatMessage message,
    DateTime updatedAt,
  );

  Future<ChatMessage> getMessage(String id);

  Future<void> softDeleteMessage(String id, DateTime deletedAt);

  /// Compare the last active message and revision before a single deletion,
  /// replacement, or appended reply. Null replacement means deletion.
  Future<ChatMessage> mutateLatestMessage({
    required ChatMessage expected,
    required DateTime nowUtc,
    ChatMessage? replacement,
    bool append = false,
    String? expectedPersonaId,
  });
}
