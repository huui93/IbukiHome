/// Recognizes the declarative NVWA formats. Values are displayed as plain text.
class NovelReplyMarkup {
  const NovelReplyMarkup(this.body, this.slots, this.drafts);
  final String body;
  final Map<String, String> slots;
  final List<({String label, String text})> drafts;

  static final _time = RegExp(
    r'^—{4}([^—\n]+•[^—\n]+•[^—\n]+)—{4}[ \t]*$',
    multiLine: true,
  );
  static final dialogue = RegExp(
    r'''<span\s+data-char\s*=\s*["']([^"']{1,80})["']\s*>([\s\S]*?)</span>''',
    caseSensitive: false,
  );
  static final _interaction = RegExp(
    r'''<div\s+data-nvwa-ui(?:\s*=\s*(?:"[^"]*"|'[^']*'))?[^>]*>''',
    caseSensitive: false,
  );
  static final _div = RegExp(r'</?div\b[^>]*>', caseSensitive: false);
  static final _button = RegExp(
    r'''<button\b[^>]*\bdata-nvwa-draft\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>([\s\S]*?)</button>''',
    caseSensitive: false,
  );
  static final _block = RegExp(
    r'<(second_space|nvwa_notes|think|nvwa_think)\b[^>]*>([\s\S]*?)</\1>',
    caseSensitive: false,
  );
  static final _end = RegExp(
    r'''^<div\s+data-nvwa-end(?:\s*=\s*(?:""|''))?\s*>([^<>\r\n]{1,300})</div>[ \t]*$''',
    caseSensitive: false,
  );

  /// Only a final top-level line in the newly received raw reply can act.
  static String? endingReason(String raw) {
    final lines = raw.trimRight().split('\n');
    if (lines.length < 2) return null;
    final finalLine = lines.last.replaceFirst(RegExp(r'\r$'), '');
    final marker = _end.firstMatch(finalLine);
    if (marker == null) return null;
    String? fence;
    var depth = 0;
    for (final line in lines.take(lines.length - 1)) {
      final codeFence = RegExp(r'^ {0,3}([\x60~]{3,})').firstMatch(line);
      if (codeFence != null) {
        final start = codeFence.group(1)!;
        if (fence == null) {
          fence = start;
        } else if (start[0] == fence[0] && start.length >= fence.length) {
          fence = null;
        }
        continue;
      }
      if (fence != null || line.trimLeft().startsWith('>')) continue;
      for (final tag in RegExp(
        r'</?(?:div|blockquote|pre|code|think|nvwa_think|second_space|nvwa_notes)\b[^>]*>',
        caseSensitive: false,
      ).allMatches(line)) {
        depth = (depth + (tag.group(0)!.startsWith('</') ? -1 : 1)).clamp(
          0,
          10000,
        );
      }
    }
    final reason = marker.group(1)!.trim();
    return fence == null && depth == 0 && reason.isNotEmpty ? reason : null;
  }

  static NovelReplyMarkup parse(String text) {
    final slots = <String, String>{};
    final drafts = <({String label, String text})>[];
    var body = text.replaceAllMapped(_block, (match) {
      final key = switch (match.group(1)!.toLowerCase()) {
        'second_space' => 'secondSpace',
        'nvwa_notes' => 'backstage',
        _ => 'templateReasoning',
      };
      final value = plainText(match.group(2)!);
      if (value.isNotEmpty) slots[key] = value;
      return '';
    });
    final time = _time.firstMatch(body);
    if (time != null) {
      slots['timeBar'] = time.group(1)!;
      body = body.replaceRange(time.start, time.end, '');
    }
    for (var count = 0; count < 8; count++) {
      final start = _interaction.firstMatch(body);
      if (start == null) break;
      var level = 1;
      Match? end;
      for (final tag in _div.allMatches(body, start.end)) {
        level += tag.group(0)!.startsWith('</') ? -1 : 1;
        if (level == 0) {
          end = tag;
          break;
        }
      }
      if (end == null) break;
      final content = body.substring(start.end, end.start);
      for (final item in _button.allMatches(content).take(12 - drafts.length)) {
        final label = plainText(item.group(3)!);
        final draft = _decode(item.group(1) ?? item.group(2) ?? '').trim();
        if (label.isNotEmpty &&
            label.length <= 80 &&
            draft.isNotEmpty &&
            draft.length <= 2000) {
          drafts.add((label: label, text: draft));
        }
      }
      final description = plainText(content.replaceAll(_button, ''));
      if (description.isNotEmpty) {
        slots['interaction'] = [
          ?slots['interaction'],
          description,
        ].join('\n\n');
      }
      body = body.replaceRange(start.start, end.end, '');
    }
    if (endingReason(body) != null) {
      body = body.substring(0, body.trimRight().lastIndexOf('\n'));
    }
    return NovelReplyMarkup(body.trim(), slots, drafts);
  }

  static String withoutTemplateReasoning(String text) => text
      .replaceAll(
        RegExp(
          r'<(?:think|nvwa_think)\b[^>]*>[\s\S]*?</(?:think|nvwa_think)>',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  static String plainText(String text) => _decode(
    text
        .replaceAll(
          RegExp(r'<(?:br\s*/?|/p|/div|/li)\s*>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]*>'), ''),
  ).trim();

  static String _decode(String text) => text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}
