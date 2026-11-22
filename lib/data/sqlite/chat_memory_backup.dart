import 'dart:convert';
import '../../application/memory/source_fingerprint.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_message_role.dart';
import 'sqlite_value_codec.dart';

/// Rewrite references hidden inside local memory JSON on conflict merge.
/// Only fingerprints that matched the original source are rebased.
Map<String, List<Map<String, Object?>>> rewriteChatMemoryBackup(
  Map<String, List<Map<String, Object?>>> collections,
  Map<String, Map<String, String>> mappings,
) {
  final result = {
    for (final e in collections.entries)
      e.key: e.value.map((r) => Map<String, Object?>.from(r)).toList(),
  };
  String mapped(String collection, String id) =>
      mappings[collection]?[id] ?? id;
  String sourceKey(String key) {
    final colon = key.indexOf(':');
    if (colon < 0) return key;
    final kind = key.substring(0, colon);
    final suffix = key.indexOf('|', colon);
    final id = key.substring(colon + 1, suffix < 0 ? key.length : suffix);
    final collection = switch (kind) {
      'saved' => 'chatMemoryEntries',
      'summary' => 'conversationSummaries',
      'message' => 'chatMessages',
      'overview' => 'chatMemoryStates',
      _ => '',
    };
    return '$kind:${mapped(collection, id)}${suffix < 0 ? '' : key.substring(suffix)}';
  }

  final messages =
      (collections['chatMessages'] ?? const [])
          .map(chatMessageFromSql)
          .where(
            (m) =>
                m.deletedAt == null &&
                m.role != ChatMessageRole.system &&
                m.content.trim().isNotEmpty,
          )
          .toList()
        ..sort((a, b) {
          final c = a.createdAt.compareTo(b.createdAt);
          return c != 0 ? c : a.id.compareTo(b.id);
        });
  List<ChatMessage> range(String? sessionId, String? first, String? last) {
    final own = messages.where((m) => m.sessionId == sessionId).toList();
    final start = own.indexWhere((m) => m.id == first);
    final end = own.indexWhere((m) => m.id == last);
    return start < 0 || end < start ? const [] : own.sublist(start, end + 1);
  }

  List<ChatMessage> rebase(List<ChatMessage> source) => source
      .map(
        (m) => m.copyWith(
          metadata: m.metadata.copyWith(id: mapped('chatMessages', m.id)),
        ),
      )
      .toList();
  for (final collection in ['chatMemoryEntries', 'conversationSummaries']) {
    for (final row in result[collection] ?? <Map<String, Object?>>[]) {
      final source = range(
        row['session_id'] as String?,
        row['source_start_message_id'] as String?,
        row['source_end_message_id'] as String?,
      );
      if (source.isNotEmpty &&
          row['source_fingerprint'] == fingerprintMessages(source)) {
        row['source_fingerprint'] = fingerprintMessages(rebase(source));
      }
      for (final field in [
        'source_start_message_id',
        'source_end_message_id',
      ]) {
        if (row[field] is String) {
          row[field] = mapped('chatMessages', row[field]! as String);
        }
      }
    }
  }
  for (final row in result['chatMemoryStates'] ?? <Map<String, Object?>>[]) {
    final data = Map<String, dynamic>.from(
      jsonDecode(row['data_json']! as String) as Map,
    );
    final own = messages
        .where((m) => m.sessionId == row['session_id'])
        .toList();
    final cursor = data['cursor'];
    final end = own.indexWhere((m) => m.id == cursor);
    if (end >= 0) {
      final prefix = own.take(end + 1).toList();
      if (data['processedFingerprint'] == fingerprintMessages(prefix)) {
        data['processedFingerprint'] = fingerprintMessages(rebase(prefix));
      }
    }
    if (cursor is String) data['cursor'] = mapped('chatMessages', cursor);
    data['excludedSources'] = (data['excludedSources'] as List? ?? [])
        .cast<String>()
        .map(sourceKey)
        .toList();
    row['data_json'] = jsonEncode(data);
  }
  for (final row in result['chatMemoryUsage'] ?? <Map<String, Object?>>[]) {
    row['source_keys_json'] = jsonEncode(
      (jsonDecode(row['source_keys_json']! as String) as List)
          .cast<String>()
          .map(sourceKey)
          .toList(),
    );
  }
  return result;
}
