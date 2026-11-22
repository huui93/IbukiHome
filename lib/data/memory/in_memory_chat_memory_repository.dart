import '../../core/errors/data_exceptions.dart';
import '../../domain/chat/chat_memory_entry.dart';
import '../../domain/chat/conversation_summary.dart';
import '../../domain/chat/chat_memory_state.dart';
import '../repositories/chat_memory_repository.dart';
import 'in_memory_ibuki_store.dart';

class InMemoryChatMemoryRepository implements ChatMemoryRepository {
  InMemoryChatMemoryRepository(this.store);

  final InMemoryIbukiStore store;

  @override
  Future<ChatMemoryState?> getState(String sessionId) async =>
      store.chatMemoryStates[sessionId];

  @override
  Future<bool> commitSessionMemory(
    ChatMemoryState state, {
    required int expectedRevision,
    List<ChatMemoryEntry> entries = const [],
    List<ConversationSummary> summaries = const [],
  }) async {
    final old = store.chatMemoryStates[state.sessionId];
    if ((old?.metadata.revision ?? 0) != expectedRevision) return false;
    if (state.metadata.revision != expectedRevision + 1 ||
        (old != null && old.metadata.id != state.metadata.id)) {
      throw const DataConflictException('记忆设置版本无效。');
    }
    final session = store.chatSession(state.sessionId);
    if (session == null || session.deletedAt != null) return false;
    for (final entry in entries) {
      final oldEntry = store.chatMemoryEntry(entry.id);
      if (oldEntry != null && entry.revision != oldEntry.revision + 1) {
        throw const DataConflictException('这条记忆刚刚发生更改，请重新读取。');
      }
      if (entry.sessionId != state.sessionId ||
          entry.personaId != session.personaId ||
          (entry.sourceSessionId != null &&
              entry.sourceSessionId != state.sessionId) ||
          (store.chatMemoryEntry(entry.id) != null &&
              store.chatMemoryEntry(entry.id)!.sessionId != state.sessionId)) {
        throw const DataConflictException('记忆只能属于当前会话。');
      }
      _validateSource(
        state.sessionId,
        entry.sourceStartMessageId,
        entry.sourceEndMessageId,
      );
    }
    if (summaries.any((item) => item.sessionId != state.sessionId)) {
      throw const DataConflictException('摘要会话不匹配。');
    }
    for (final summary in summaries) {
      _validateSource(
        state.sessionId,
        summary.sourceStartMessageId,
        summary.sourceEndMessageId,
      );
    }
    for (final entry in entries) {
      store.putChatMemoryEntry(entry);
    }
    for (final summary in summaries) {
      store.putConversationSummary(summary);
    }
    store.chatMemoryStates[state.sessionId] = state;
    return true;
  }

  void _validateSource(String sessionId, String? first, String? last) {
    for (final id in {?first, ?last}) {
      if (store.chatMessage(id)?.sessionId != sessionId) {
        throw const DataConflictException('记忆来源必须属于当前会话。');
      }
    }
  }

  @override
  Future<void> saveUsage(ChatMemoryUsage usage) async {
    if (store.chatMessage(usage.messageId)?.sessionId != usage.sessionId) {
      throw const DataConflictException('记忆来源会话不匹配。');
    }
    store.chatMemoryUsage[usage.messageId] = usage;
  }

  @override
  Future<ChatMemoryUsage?> getUsage(String sessionId, String messageId) async {
    final usage = store.chatMemoryUsage[messageId];
    return usage?.sessionId == sessionId ? usage : null;
  }

  @override
  Future<List<ChatMemoryEntry>> listEntries(
    String personaId, {
    bool includeDeleted = false,
  }) async {
    final items =
        store.chatMemoryEntries
            .where(
              (item) =>
                  item.personaId == personaId &&
                  (includeDeleted || item.deletedAt == null),
            )
            .toList()
          ..sort((a, b) {
            if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
            return b.updatedAt.compareTo(a.updatedAt);
          });
    return List.unmodifiable(items);
  }

  @override
  Future<ChatMemoryEntry> getEntry(String id) async =>
      store.chatMemoryEntry(id) ??
      (throw EntityNotFoundException('ChatMemoryEntry', id));

  @override
  Future<List<ChatMemoryEntry>> listEntriesForSession(
    String sessionId, {
    bool includeDeleted = false,
  }) async {
    final items =
        store.chatMemoryEntries
            .where(
              (item) =>
                  item.sessionId == sessionId &&
                  (includeDeleted || item.deletedAt == null),
            )
            .toList()
          ..sort((a, b) {
            if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
            return b.updatedAt.compareTo(a.updatedAt);
          });
    return List.unmodifiable(items);
  }

  @override
  Future<void> upsertEntry(ChatMemoryEntry entry) async {
    store.putChatMemoryEntry(entry);
  }

  @override
  Future<void> softDeleteEntry(String id, DateTime deletedAt) async {
    final current = await getEntry(id);
    if (current.deletedAt != null) return;
    final at = deletedAt.toUtc();
    store.putChatMemoryEntry(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: at,
          revision: current.revision + 1,
          deletedAt: at,
        ),
      ),
    );
  }

  @override
  Future<void> restoreEntry(String id, DateTime updatedAt) async {
    final current = await getEntry(id);
    if (current.deletedAt == null) return;
    final at = updatedAt.toUtc();
    store.putChatMemoryEntry(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: at,
          revision: current.revision + 1,
          deletedAt: null,
        ),
      ),
    );
  }

  @override
  Future<List<ConversationSummary>> listSummaries(String sessionId) async {
    final items =
        store.conversationSummaries
            .where((item) => item.sessionId == sessionId)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(items);
  }

  @override
  Future<void> upsertSummary(ConversationSummary summary) async {
    store.putConversationSummary(summary);
  }
}
