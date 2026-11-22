import '../../domain/ai/ai_reasoning_level.dart';
import '../../domain/chat/chat_usage_record.dart';

abstract interface class ChatControlsRepository {
  Future<AiReasoningLevel> getReasoning(String sessionId);
  Future<void> setReasoning(
    String sessionId,
    AiReasoningLevel level,
    DateTime now,
  );
  Future<List<ChatUsageRecord>> listUsage(String sessionId);

  /// Request IDs are idempotent and may never move to another session.
  Future<void> recordUsage(ChatUsageRecord record);
}
