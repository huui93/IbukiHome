import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/plugins/novel_plugin_providers.dart';
import '../../../application/plugins/novel_reply_markup.dart';
import '../../../domain/plugins/novel_history_fingerprint.dart';
import '../../../domain/segments/segment.dart';

class NovelReplyContent extends ConsumerWidget {
  const NovelReplyContent({
    super.key,
    required this.segment,
    required this.style,
    required this.textKey,
    this.onFillDraft,
    this.onOpenPanel,
  });
  final Segment segment;
  final TextStyle? style;
  final Key textKey;
  final ValueChanged<String>? onFillDraft;
  final VoidCallback? onOpenPanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final markup = NovelReplyMarkup.parse(segment.content);
    final persisted = ref
        .watch(
          novelReplyViewProvider((
            id: segment.id,
            hash: novelContentHash(segment.content),
          )),
        )
        .value;
    final savedSlots = persisted?['slots'] as Map? ?? const {};
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (markup.slots['timeBar'] case final time?)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    time,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SelectableText.rich(
          TextSpan(
            children: _dialogue(
              context,
              markup.body.isEmpty ? '空白段落' : markup.body,
            ),
          ),
          key: textKey,
          style: style,
        ),
        for (final (key, name, icon) in [
          ('secondSpace', '第二时空', Icons.public_outlined),
          ('interaction', '场景互动', Icons.touch_app_outlined),
          ('backstage', '幕后卡片', Icons.notes_outlined),
          ('templateReasoning', '模板思考', Icons.psychology_outlined),
          ('nativeReasoning', '模型原生推理', Icons.auto_awesome_outlined),
        ])
          if ((key == 'nativeReasoning'
                  ? (persisted?['nativeReasoning'] as String?)
                  : markup.slots[key] ?? savedSlots[key] as String?)
              case final content?)
            ExpansionTile(
              dense: true,
              tilePadding: EdgeInsets.zero,
              leading: Icon(icon, size: 18),
              title: Text(name),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    content,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (key == 'interaction' && onFillDraft != null)
                  _actions(markup),
              ],
            )
          else if (key == 'interaction' &&
              markup.drafts.isNotEmpty &&
              onFillDraft != null)
            _actions(markup),
      ],
    );
  }

  Widget _actions(NovelReplyMarkup markup) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final draft in markup.drafts)
        ActionChip(
          avatar: const Icon(Icons.edit_outlined, size: 16),
          label: Text(draft.label),
          onPressed: () => onFillDraft!(draft.text),
        ),
      if (onOpenPanel != null)
        ActionChip(label: const Text('打开插件面板'), onPressed: onOpenPanel),
    ],
  );

  List<InlineSpan> _dialogue(BuildContext context, String body) {
    final spans = <InlineSpan>[];
    final scheme = Theme.of(context).colorScheme;
    final colors = [scheme.primary, scheme.tertiary, scheme.secondary];
    var start = 0;
    for (final match in NovelReplyMarkup.dialogue.allMatches(body)) {
      if (start < match.start) {
        spans.add(TextSpan(text: body.substring(start, match.start)));
      }
      final name = match.group(1)!;
      final color =
          colors[name.codeUnits.fold<int>(0, (sum, item) => sum + item) %
              colors.length];
      spans.add(
        TextSpan(
          text: NovelReplyMarkup.plainText(match.group(2)!),
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
          semanticsLabel:
              '$name：${NovelReplyMarkup.plainText(match.group(2)!)}',
        ),
      );
      start = match.end;
    }
    if (start < body.length) spans.add(TextSpan(text: body.substring(start)));
    return spans;
  }
}
