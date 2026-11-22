import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'novel_plugin_models.dart';

String novelContentHash(String content) =>
    sha256.convert(utf8.encode(content)).toString();
List<Map<String, String>> novelSourceRefs(
  Iterable<NovelHistoryMessage> messages,
) => [
  for (final m in messages)
    {
      'id': m.id,
      'candidateId': m.candidateId,
      'contentHash': novelContentHash(m.content),
    },
];
String novelRefsFingerprint(List<Map<String, String>> refs) => novelContentHash(
  jsonEncode([
    for (final ref in refs)
      {
        'id': ref['id'],
        'candidateId': ref['candidateId'],
        'contentHash': ref['contentHash'],
      },
  ]),
);
bool novelMemorySourcesCurrent(
  NovelMemoryBlock block,
  List<NovelHistoryMessage> history,
) {
  if (block.coveredMessageIds.isEmpty) {
    return block.sourceRefs.isEmpty && block.sourceFingerprint.isEmpty;
  }
  if (block.sourceRefs.isEmpty ||
      block.sourceRefs.length != block.coveredMessageIds.length ||
      block.coveredMessageIds.toSet().length !=
          block.coveredMessageIds.length ||
      block.sourceRefs.map((r) => r['id']).join('\u0000') !=
          block.coveredMessageIds.join('\u0000') ||
      novelRefsFingerprint(block.sourceRefs) != block.sourceFingerprint) {
    return false;
  }
  final ids = block.coveredMessageIds.toSet();
  final current = novelSourceRefs(history.where((m) => ids.contains(m.id)));
  return current.length == ids.length &&
      novelRefsFingerprint(current) == block.sourceFingerprint;
}
