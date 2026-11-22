import 'package:flutter/material.dart';

import '../../../application/ai/card_completion.dart';
import '../../../domain/characters/character_card.dart';

class CardCompletionOptions {
  const CardCompletionOptions({required this.mode, required this.instruction});

  final CardCompletionMode mode;
  final String instruction;
}

Future<CardCompletionOptions?> showCardCompletionOptions(
  BuildContext context, {
  CharacterCardMode? characterMode,
  bool worldCard = false,
}) async {
  final availableModes = worldCard
      ? const [
          CardCompletionMode.fillBlank,
          CardCompletionMode.improveFromStory,
          CardCompletionMode.worldReference,
          CardCompletionMode.worldOriginalExpansion,
        ]
      : switch (characterMode) {
          CharacterCardMode.fanfic => const [
            CardCompletionMode.canonReference,
            CardCompletionMode.improveFromStory,
            CardCompletionMode.canonComparison,
          ],
          CharacterCardMode.original => const [
            CardCompletionMode.fillBlank,
            CardCompletionMode.improveFromStory,
            CardCompletionMode.partialRedesign,
          ],
          null => const [
            CardCompletionMode.fillBlank,
            CardCompletionMode.improveFromStory,
          ],
        };
  var mode = availableModes.first;
  var instruction = '';
  return showDialog<CardCompletionOptions>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        key: const Key('card-completion-options'),
        title: Text(worldCard ? '世界观 AI 完善' : '角色 AI 完善'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<CardCompletionMode>(
              key: const Key('card-completion-mode'),
              initialValue: mode,
              decoration: const InputDecoration(labelText: '模式'),
              items: [
                for (final item in availableModes)
                  DropdownMenuItem(value: item, child: Text(_modeLabel(item))),
              ],
              onChanged: (value) =>
                  setState(() => mode = value ?? CardCompletionMode.fillBlank),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('card-completion-instruction'),
              minLines: 2,
              maxLines: 4,
              onChanged: (value) => instruction = value,
              decoration: const InputDecoration(
                labelText: '本次要求（可选）',
                hintText: '例如：重点整理她与主角的关系。',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('start-card-completion'),
            onPressed: () => Navigator.pop(
              dialogContext,
              CardCompletionOptions(mode: mode, instruction: instruction),
            ),
            child: const Text('开始分析'),
          ),
        ],
      ),
    ),
  );
}

Future<Map<String, String>?> showCardCompletionPreview({
  required BuildContext context,
  required List<CardCompletionSuggestion> suggestions,
  required CardCompletionMode mode,
}) async {
  final comparisonOnly = mode == CardCompletionMode.canonComparison;
  final selected = <int>{};
  for (var index = 0; index < suggestions.length; index += 1) {
    final item = suggestions[index];
    if (!comparisonOnly &&
        !item.inferred &&
        item.currentValue.trim().isEmpty &&
        (item.source == CardSuggestionSource.canonReference ||
            item.source == CardSuggestionSource.storyEvidence ||
            item.source == CardSuggestionSource.creativeDraft)) {
      selected.add(index);
    }
  }
  return showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        key: const Key('card-completion-preview'),
        title: const Text('预览 AI 建议'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final item = suggestions[index];
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.currentValue.isNotEmpty)
                    Text('当前：${item.currentValue}'),
                  Text(
                    comparisonOnly
                        ? item.suggestedValue
                        : '建议：${item.suggestedValue}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '来源：${_sourceLabel(item.source)}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  if (item.referenceTitle?.trim().isNotEmpty == true)
                    Text('参考：${item.referenceTitle}'),
                  if (item.reason.isNotEmpty) Text('依据：${item.reason}'),
                  if (item.inferred)
                    const Text(
                      '推测建议 · 默认未选择',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                ],
              );
              if (comparisonOnly) {
                return ListTile(
                  key: Key('card-suggestion-${item.field}'),
                  title: Text(_fieldLabel(item.field)),
                  subtitle: details,
                );
              }
              return CheckboxListTile(
                key: Key('card-suggestion-${item.field}'),
                value: selected.contains(index),
                onChanged: (value) => setState(() {
                  if (value ?? false) {
                    selected.add(index);
                  } else {
                    selected.remove(index);
                  }
                }),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_fieldLabel(item.field)),
                subtitle: details,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          if (!comparisonOnly) ...[
            TextButton(
              key: const Key('select-all-card-suggestions'),
              onPressed: () => setState(() {
                selected
                  ..clear()
                  ..addAll(List.generate(suggestions.length, (index) => index));
              }),
              child: const Text('全部选中'),
            ),
            FilledButton(
              key: const Key('accept-selected-card-suggestions'),
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, {
                      for (final index in selected)
                        suggestions[index].field:
                            suggestions[index].suggestedValue,
                    }),
              child: const Text('应用所选'),
            ),
          ],
        ],
      ),
    ),
  );
}

String _fieldLabel(String field) => switch (field) {
  'name' => '名称',
  'title' => '标题',
  'content' => '内容',
  _ => field,
};

String _modeLabel(CardCompletionMode mode) => switch (mode) {
  CardCompletionMode.fillBlank => '补全空白',
  CardCompletionMode.improveFromStory => '根据当前小说完善',
  CardCompletionMode.canonReference => '按原作补充',
  CardCompletionMode.canonComparison => '对照原作检查',
  CardCompletionMode.originalDesignConservative => '保守设计',
  CardCompletionMode.originalDesignBalanced => '平衡设计',
  CardCompletionMode.originalDesignBold => '大胆设计',
  CardCompletionMode.partialRedesign => '重新设计部分设定',
  CardCompletionMode.worldReference => '已有作品参考',
  CardCompletionMode.worldOriginalExpansion => '原创世界观扩写',
};

String _sourceLabel(CardSuggestionSource source) => switch (source) {
  CardSuggestionSource.canonReference => '原作参考已核对',
  CardSuggestionSource.storyEvidence => '正文依据',
  CardSuggestionSource.modelKnowledge => 'AI 已有知识，建议确认',
  CardSuggestionSource.creativeDraft => 'AI 设计草案',
  CardSuggestionSource.inferred => '推测',
};
