import 'dart:math' as math;
import '../../domain/chat/chat_memory_state.dart';
import 'source_fingerprint.dart';

/// Local lexical retrieval. Chinese bigrams and Latin words need no remote
/// embedding service. Documents are rebuilt from current local rows so deleted
/// or edited sources cannot remain in an obsolete search index.
class LocalChatMemorySearch {
  const LocalChatMemorySearch();

  List<ChatMemorySource> search({
    required String sessionId,
    required String query,
    required List<ChatMemorySource> documents,
    Set<String> pinnedKeys = const {},
    int limit = 8,
    int characterBudget = 6000,
    bool fallback = false,
  }) {
    final docs = documents
        .where((d) => d.sessionId == sessionId && d.content.trim().isNotEmpty)
        .toList();
    if (docs.isEmpty) return const [];
    final terms = tokenize(_expandQuery(query)).toSet();
    final tokens = docs.map((d) => tokenize(d.content)).toList();
    final frequencies = <String, int>{};
    for (final words in tokens) {
      for (final word in words.toSet()) {
        frequencies.update(word, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final average = tokens.fold<int>(0, (n, t) => n + t.length) / docs.length;
    final ranked = <ChatMemorySource>[];
    for (var i = 0; i < docs.length; i++) {
      final doc = docs[i];
      final counts = <String, int>{};
      for (final term in tokens[i]) {
        counts.update(term, (n) => n + 1, ifAbsent: () => 1);
      }
      var score = 0.0;
      for (final term in terms) {
        final tf = counts[term] ?? 0;
        if (tf == 0) continue;
        final df = frequencies[term] ?? 0;
        score +=
            math.log(1 + (docs.length - df + .5) / (df + .5)) *
            tf *
            2.2 /
            (tf + 1.2 * (.25 + .75 * tokens[i].length / math.max(1, average)));
      }
      if (pinnedKeys.contains(doc.key)) score += 4;
      if (score == 0 && (!fallback || terms.isNotEmpty)) continue;
      if (doc.kind == ChatMemorySourceKind.saved) score *= 1.3;
      ranked.add(
        ChatMemorySource(
          kind: doc.kind,
          id: doc.id,
          sessionId: sessionId,
          content: doc.content,
          updatedAt: doc.updatedAt,
          score: score,
          version: fingerprintStrings([doc.content]),
        ),
      );
    }
    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byDate = b.updatedAt.compareTo(a.updatedAt);
      return byDate != 0 ? byDate : a.key.compareTo(b.key);
    });
    final selected = <ChatMemorySource>[];
    final seen = <String>{};
    var remaining = characterBudget;
    for (final doc in ranked) {
      if (selected.length >= limit || remaining < 80) break;
      final content = excerpt(doc.content, terms, math.min(1400, remaining));
      if (!seen.add(normalize(content))) continue;
      selected.add(
        ChatMemorySource(
          kind: doc.kind,
          id: doc.id,
          sessionId: sessionId,
          content: content,
          updatedAt: doc.updatedAt,
          score: doc.score,
          version: doc.version,
        ),
      );
      remaining -= content.length;
    }
    return List.unmodifiable(selected);
  }

  static String normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\s+|[，。！？、,.!?：:；;]'), '');

  static List<String> tokenize(String text) {
    final result = <String>[];
    for (final match in RegExp(
      r'[a-z0-9_]+|[\u3400-\u9fff]+',
      caseSensitive: false,
    ).allMatches(text.toLowerCase())) {
      final word = match.group(0)!;
      if (RegExp(r'^[a-z0-9_]').hasMatch(word)) {
        if (!{'the', 'and', 'is', 'a', 'of', 'to', 'i', 'my'}.contains(word)) {
          result.add(word);
        }
      } else if (word.length == 1) {
        if (!'的了是在吗呢啊我你他她它'.contains(word)) result.add(word);
      } else {
        for (final char in word.split('')) {
          if (!'的了是在吗呢啊我你他她它个和与就也都这那什么用户'.contains(char)) result.add(char);
        }
        for (var i = 0; i < word.length - 1; i++) {
          result.add(word.substring(i, i + 2));
        }
      }
    }
    return result;
  }

  static String _expandQuery(String query) {
    final additions = <String>[];
    if (RegExp(r'名字|姓名|叫什么|称呼|name', caseSensitive: false).hasMatch(query)) {
      additions.add('名字 姓名 称呼 叫 name');
    }
    if (RegExp(r'偏好|喜欢|最爱|喜好|prefer', caseSensitive: false).hasMatch(query)) {
      additions.add('偏好 喜欢 最爱 喜好');
    }
    if (RegExp(r'约定|答应|说好|约好').hasMatch(query)) additions.add('约定 答应 说好 约好');
    return '$query ${additions.join(' ')}';
  }

  static String excerpt(String text, Set<String> terms, int maxLength) {
    if (text.length <= maxLength) return text;
    var position = -1;
    final lower = text.toLowerCase();
    for (final term in terms) {
      final index = lower.indexOf(term);
      if (index >= 0 && (position < 0 || index < position)) position = index;
    }
    final start = math.max(0, position - 120).toInt();
    final end = math
        .min(text.length, start + math.max(0, maxLength - 2))
        .toInt();
    return '${start > 0 ? '…' : ''}${text.substring(start, end)}${end < text.length ? '…' : ''}';
  }
}
