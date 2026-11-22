import '../ai/ai_token_usage.dart';

class ChatUsageRecord {
  const ChatUsageRecord({
    required this.id,
    required this.sessionId,
    required this.operation,
    required this.providerId,
    required this.model,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.estimatedInputTokens,
    required this.estimatedOutputTokens,
    this.usage,
  });
  final String id;
  final String sessionId;
  final String operation;
  final String providerId;
  final String model;
  final String status;
  final DateTime startedAt;
  final DateTime endedAt;
  final int estimatedInputTokens;
  final int estimatedOutputTokens;
  final AiTokenUsage? usage;
  bool get hasCompleteReport => usage?.isComplete == true;
  Map<String, Object?> toJson() => {
    'id': id,
    'session_id': sessionId,
    'operation': operation,
    'provider_id': providerId,
    'model': model,
    'status': status,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
    'estimated_input_tokens': estimatedInputTokens,
    'estimated_output_tokens': estimatedOutputTokens,
    'input_tokens': usage?.inputTokens,
    'output_tokens': usage?.outputTokens,
    'total_tokens': usage?.totalTokens,
    'cached_input_tokens': usage?.cachedInputTokens,
    'cache_write_tokens': usage?.cacheWriteTokens,
    'reasoning_tokens': usage?.reasoningTokens,
    'reported_complete': hasCompleteReport ? 1 : 0,
  };
  factory ChatUsageRecord.fromJson(Map<String, Object?> value) =>
      ChatUsageRecord(
        id: value['id']! as String,
        sessionId: value['session_id']! as String,
        operation: value['operation']! as String,
        providerId: value['provider_id']! as String,
        model: value['model']! as String,
        status: value['status']! as String,
        startedAt: DateTime.parse(value['started_at']! as String).toUtc(),
        endedAt: DateTime.parse(value['ended_at']! as String).toUtc(),
        estimatedInputTokens: value['estimated_input_tokens']! as int,
        estimatedOutputTokens: value['estimated_output_tokens']! as int,
        usage: AiTokenUsage(
          inputTokens: value['input_tokens'] as int?,
          outputTokens: value['output_tokens'] as int?,
          totalTokens: value['total_tokens'] as int?,
          cachedInputTokens: value['cached_input_tokens'] as int?,
          cacheWriteTokens: value['cache_write_tokens'] as int?,
          reasoningTokens: value['reasoning_tokens'] as int?,
          isFinal: value['reported_complete'] == 1,
        ),
      );
}
