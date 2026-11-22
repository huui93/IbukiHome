import 'dart:convert';
import '../../domain/chat/chat_memory_state.dart';
import 'sqlite_value_codec.dart';

ChatMemoryState chatMemoryStateFromSql(Map<String, Object?> row) =>
    ChatMemoryState.fromData(
      metadata: metadataFromSql(row, 'ChatMemoryState'),
      sessionId: row['session_id']! as String,
      data: Map<String, dynamic>.from(
        jsonDecode(row['data_json']! as String) as Map,
      ),
    );

Map<String, Object?> chatMemoryStateToSql(ChatMemoryState state) => {
  ...metadataToSql(state.metadata),
  'session_id': state.sessionId,
  'data_json': jsonEncode(state.toData()),
};

ChatMemoryUsage chatMemoryUsageFromSql(Map<String, Object?> row) =>
    ChatMemoryUsage(
      id: row['id']! as String,
      sessionId: row['session_id']! as String,
      messageId: row['message_id']! as String,
      sourceKeys: List<String>.from(
        jsonDecode(row['source_keys_json']! as String) as List,
      ),
    );
