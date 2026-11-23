import '../../domain/chat/chat_memory_entry.dart';
import '../../domain/chat/conversation_summary.dart';
import '../../domain/chat/chat_memory_state.dart';

class ChatMemoryContext {
  const ChatMemoryContext({
    this.pinned = const [],
    this.recent = const [],
    this.summaries = const [],
    this.sources = const [],
    this.history = const [],
    this.overview = '',
    this.excludedRawMessageIds = const {},
    this.continuityStartMessageId,
  });

  final List<ChatMemoryEntry> pinned;
  final List<ChatMemoryEntry> recent;
  final List<ConversationSummary> summaries;
  final List<ChatMemorySource> sources;
  final List<ChatMemorySource> history;
  final String overview;
  final Set<String> excludedRawMessageIds;
  final String? continuityStartMessageId;

  bool get isEmpty =>
      pinned.isEmpty &&
      recent.isEmpty &&
      summaries.isEmpty &&
      history.isEmpty &&
      overview.isEmpty;
}
