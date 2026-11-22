import '../../core/errors/data_exceptions.dart';
import '../../domain/ai/ai_reasoning_level.dart';
import '../../domain/chat/chat_usage_record.dart';
import '../repositories/chat_controls_repository.dart';
import 'in_memory_ibuki_store.dart';

class InMemoryChatControlsRepository implements ChatControlsRepository {
  InMemoryChatControlsRepository(this.store);
  final InMemoryIbukiStore store;
  final _levels = <String, AiReasoningLevel>{};
  final _usage = <String, ChatUsageRecord>{};
  void _requireSession(String id) {
    final session = store.chatSession(id);
    if (session == null || session.deletedAt != null) {
      throw const DataConflictException('会话不存在或已删除。');
    }
  }

  @override
  Future<AiReasoningLevel> getReasoning(String sessionId) async {
    _requireSession(sessionId);
    return _levels[sessionId] ?? AiReasoningLevel.automatic;
  }

  @override
  Future<void> setReasoning(
    String sessionId,
    AiReasoningLevel level,
    DateTime now,
  ) async {
    _requireSession(sessionId);
    _levels[sessionId] = level;
  }

  @override
  Future<List<ChatUsageRecord>> listUsage(String sessionId) async =>
      List.unmodifiable(
        _usage.values.where((r) => r.sessionId == sessionId).toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
      );
  @override
  Future<void> recordUsage(ChatUsageRecord record) async {
    _requireSession(record.sessionId);
    final old = _usage[record.id];
    if (old != null && old.sessionId != record.sessionId) {
      throw const DataConflictException('用量记录不属于这个会话。');
    }
    _usage.putIfAbsent(record.id, () => record);
  }
}
