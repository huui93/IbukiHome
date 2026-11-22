import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/chat_repository.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_message_role.dart';
import '../../domain/chat/chat_image.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/common/entity_metadata.dart';

class SendChatMessage {
  const SendChatMessage(this._chats);

  final ChatRepository _chats;

  Future<ChatMessage> call({
    required String sessionId,
    required String messageId,
    required ChatMessageRole role,
    required String content,
    required DateTime nowUtc,
    AiFinishReason? finishReason,
    ChatImage? image,
  }) async {
    final trimmed = content.trim().isEmpty && image != null
        ? '[图片]'
        : content.trim();
    if (image != null && role != ChatMessageRole.user) {
      throw const DataFormatException('只有用户消息可以发送图片。');
    }
    if (trimmed.isEmpty) {
      throw const DataFormatException('消息内容不能为空。');
    }

    final session = await _chats.getSession(sessionId);
    if (session.deletedAt != null) {
      throw const DataConflictException('已删除会话不能发送消息。');
    }
    final now = nowUtc.toUtc();
    final message = ChatMessage(
      metadata: EntityMetadata(
        id: messageId,
        createdAt: now,
        updatedAt: now,
        revision: 1,
      ),
      sessionId: session.id,
      projectId: null,
      role: role,
      content: trimmed,
      finishReason: finishReason,
      image: image?.withUserText(content.trim()),
    );
    await _chats.appendMessageAndTouchSession(message, now);
    return message;
  }
}
