import '../../domain/chat/chat_message.dart';
import '../../domain/segments/segment.dart';

String fingerprintSegments(Iterable<Segment> segments) => _fnv64(
  segments.map(
    (item) =>
        '${item.id}|${item.orderIndex}|${item.revision}|${item.updatedAt.toIso8601String()}|${item.content}',
  ),
);

String fingerprintMessages(Iterable<ChatMessage> messages) => _fnv64(
  messages.map(
    (item) =>
        '${item.id}|${item.revision}|${item.updatedAt.toIso8601String()}|${item.role.name}|${item.content}',
  ),
);

String fingerprintStrings(Iterable<String> values) => _fnv64(values);

String _fnv64(Iterable<String> values) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final value in values) {
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * prime) & 0x7fffffffffffffff;
    }
    hash ^= 10;
    hash = (hash * prime) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
