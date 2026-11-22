import '../../domain/chat/chat_memory_entry.dart';
import '../../domain/chat/conversation_summary.dart';
import '../../domain/chat/chat_memory_state.dart';

abstract class ChatMemoryRepository {
  Future<ChatMemoryState?> getState(String sessionId);

  /// Compare and swap the state and derived changes in one transaction.
  /// Revision 0 denotes an absent state. No model call runs in this transaction.
  Future<bool> commitSessionMemory(
    ChatMemoryState state, {
    required int expectedRevision,
    List<ChatMemoryEntry> entries = const [],
    List<ConversationSummary> summaries = const [],
  });
  Future<void> saveUsage(ChatMemoryUsage usage);
  Future<ChatMemoryUsage?> getUsage(String sessionId, String messageId);
  Future<List<ChatMemoryEntry>> listEntries(
    String personaId, {
    bool includeDeleted = false,
  });

  Future<List<ChatMemoryEntry>> listEntriesForSession(
    String sessionId, {
    bool includeDeleted = false,
  });

  Future<ChatMemoryEntry> getEntry(String id);

  Future<void> upsertEntry(ChatMemoryEntry entry);

  Future<void> softDeleteEntry(String id, DateTime deletedAt);

  Future<void> restoreEntry(String id, DateTime updatedAt);

  Future<List<ConversationSummary>> listSummaries(String sessionId);

  Future<void> upsertSummary(ConversationSummary summary);
}
