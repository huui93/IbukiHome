import 'dart:convert';

import '../../core/network/ai_provider_exceptions.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/characters/character_card.dart';
import '../../domain/world/world_card.dart';
import 'ai_generation_service.dart';
import 'ai_model_resolver.dart';
import 'clean_ai_text.dart';
import 'character_reference_lookup.dart';
import 'novel_context_loader.dart';

enum CardCompletionMode {
  fillBlank,
  improveFromStory,
  canonReference,
  canonComparison,
  originalDesignConservative,
  originalDesignBalanced,
  originalDesignBold,
  partialRedesign,
  worldReference,
  worldOriginalExpansion,
}

enum CardSuggestionSource {
  canonReference,
  storyEvidence,
  modelKnowledge,
  creativeDraft,
  inferred,
}

class CardCompletionSuggestion {
  const CardCompletionSuggestion({
    required this.field,
    required this.currentValue,
    required this.suggestedValue,
    required this.reason,
    required this.inferred,
    this.source = CardSuggestionSource.inferred,
    this.referenceTitle,
  });

  final String field;
  final String currentValue;
  final String suggestedValue;
  final String reason;
  final bool inferred;
  final CardSuggestionSource source;
  final String? referenceTitle;

  CardCompletionSuggestion copyWith({String? suggestedValue}) {
    return CardCompletionSuggestion(
      field: field,
      currentValue: currentValue,
      suggestedValue: suggestedValue ?? this.suggestedValue,
      reason: reason,
      inferred: inferred,
      source: source,
      referenceTitle: referenceTitle,
    );
  }
}

// ignore_for_file: prefer_initializing_formals

class CardCompletionService {
  const CardCompletionService({
    required NovelContextLoader contextLoader,
    required AiGenerationRuntime runtime,
    required AiModelResolver modelResolver,
    CharacterReferenceLookupService referenceLookup =
        const NoopCharacterReferenceLookupService(),
  }) : _contextLoader = contextLoader,
       _runtime = runtime,
       _modelResolver = modelResolver,
       _referenceLookup = referenceLookup;

  final NovelContextLoader _contextLoader;
  final AiGenerationRuntime _runtime;
  final AiModelResolver _modelResolver;
  final CharacterReferenceLookupService _referenceLookup;

  Future<List<CardCompletionSuggestion>> completeCharacter({
    required CharacterCard card,
    required CardCompletionMode mode,
    required String instruction,
    required String requestId,
  }) async {
    final context = await _contextLoader.load(
      projectId: card.projectId,
      selectedCharacterIds: const {},
      selectedWorldCardIds: const {},
    );
    final references =
        card.mode == CharacterCardMode.fanfic &&
            (mode == CardCompletionMode.canonReference ||
                mode == CardCompletionMode.canonComparison)
        ? await _referenceLookup.lookup(
            workTitle: card.sourceWorkTitle,
            characterName: card.sourceCharacterName,
            versionHint: card.sourceVersionHint,
          )
        : const <CharacterReferenceEvidence>[];
    final fallbackSource = _sourceForMode(
      mode,
      hasEvidence: references.isNotEmpty,
    );
    return _complete(
      projectId: card.projectId,
      requestId: requestId,
      systemPrompt: const CharacterCardCompletionPromptBuilder().build(
        context: context,
        card: card,
        mode: mode,
        instruction: instruction,
        references: references,
      ),
      current: {'name': card.name, 'content': card.content},
      allowedFields: const {'name', 'content'},
      fallbackSource: fallbackSource,
      hasVerifiedReference: references.isNotEmpty,
      preserveExistingContent:
          mode == CardCompletionMode.canonReference &&
          card.content.trim().isNotEmpty,
    );
  }

  Future<List<CardCompletionSuggestion>> completeWorld({
    required WorldCard card,
    required CardCompletionMode mode,
    required String instruction,
    required String requestId,
  }) async {
    final context = await _contextLoader.load(
      projectId: card.projectId,
      selectedCharacterIds: const {},
      selectedWorldCardIds: {card.id},
    );
    return _complete(
      projectId: card.projectId,
      requestId: requestId,
      systemPrompt: const WorldCardCompletionPromptBuilder().build(
        context: context,
        card: card,
        mode: mode,
        instruction: instruction,
      ),
      current: {'title': card.title, 'content': card.content},
      allowedFields: const {'title', 'content'},
      fallbackSource: _sourceForMode(mode, hasEvidence: false),
    );
  }

  Future<List<CardCompletionSuggestion>> _complete({
    required String projectId,
    required String requestId,
    required String systemPrompt,
    required Map<String, String> current,
    required Set<String> allowedFields,
    required CardSuggestionSource fallbackSource,
    bool hasVerifiedReference = false,
    bool preserveExistingContent = false,
  }) async {
    final selected = await _modelResolver.resolveForProject(projectId);
    final output = await _runtime.generate(
      AiGenerationRequest(
        requestId: requestId,
        providerConfigId: selected.providerConfigId,
        model: selected.model,
        systemPrompt: systemPrompt,
        messages: const [
          AiGenerationMessage(
            role: AiMessageRole.user,
            content: '请仅输出约定的 JSON。',
          ),
        ],
        temperature: 0.2,
        maxTokens: 3000,
        structuredJson: true,
      ),
    );
    var parsed = parseCardCompletionSuggestions(
      output,
      current: current,
      allowedFields: allowedFields,
      fallbackSource: fallbackSource,
    );
    if (!hasVerifiedReference) {
      parsed = List.unmodifiable(
        parsed.map(
          (item) => item.source == CardSuggestionSource.canonReference
              ? CardCompletionSuggestion(
                  field: item.field,
                  currentValue: item.currentValue,
                  suggestedValue: item.suggestedValue,
                  reason: item.reason,
                  inferred: item.inferred,
                  source: CardSuggestionSource.modelKnowledge,
                  referenceTitle: null,
                )
              : item,
        ),
      );
    }
    if (!preserveExistingContent) return parsed;
    final existing = current['content']?.trim() ?? '';
    return List.unmodifiable(
      parsed.map((item) {
        if (item.field != 'content' ||
            existing.isEmpty ||
            item.suggestedValue.contains(existing)) {
          return item;
        }
        return item.copyWith(
          suggestedValue: '$existing\n\n原作参考补充（待作者确认）：\n${item.suggestedValue}',
        );
      }),
    );
  }
}

class CharacterCardCompletionPromptBuilder {
  const CharacterCardCompletionPromptBuilder();

  String build({
    required NovelAiContext context,
    required CharacterCard card,
    required CardCompletionMode mode,
    required String instruction,
    List<CharacterReferenceEvidence> references = const [],
  }) => _buildPrompt(
    cardType: '小说角色卡',
    fields: {'name': card.name, 'content': card.content},
    authorContext:
        '''角色类型：${card.mode?.name ?? 'legacy'}
原作信息：${card.sourceWorkTitle} / ${card.sourceCharacterName}
版本或形态：${card.sourceVersionHint}
二创设定（高优先级）：${card.fanficAdaptationNotes}
原创构想：${card.originalIdea}''',
    context: context,
    mode: mode,
    instruction: instruction,
    relatedCards: context.worldCards
        .map((item) => '${item.title}: ${item.content}')
        .join('\n'),
    references: references,
  );
}

class WorldCardCompletionPromptBuilder {
  const WorldCardCompletionPromptBuilder();

  String build({
    required NovelAiContext context,
    required WorldCard card,
    required CardCompletionMode mode,
    required String instruction,
  }) => _buildPrompt(
    cardType: '小说世界观卡',
    fields: {'title': card.title, 'content': card.content},
    authorContext: '（无额外作者来源字段）',
    context: context,
    mode: mode,
    instruction: instruction,
    relatedCards: context.characters
        .map((item) => '${item.name}: ${item.content}')
        .join('\n'),
  );
}

String _buildPrompt({
  required String cardType,
  required Map<String, String> fields,
  required String authorContext,
  required NovelAiContext context,
  required CardCompletionMode mode,
  required String instruction,
  required String relatedCards,
  List<CharacterReferenceEvidence> references = const [],
}) {
  final raw = context.segments
      .skip((context.segments.length - 12).clamp(0, context.segments.length))
      .map((item) => item.content)
      .join('\n');
  final outline =
      [
            context.outline.recentCompleted,
            context.outline.current,
            context.outline.nextPlanned,
          ]
          .where((item) => item != null)
          .map((item) => '${item!.title}: ${item.summary}')
          .join('\n');
  final summaries = context.memory.recentChunks
      .map((item) => item.summary)
      .join('\n');
  final referenceText = references.isEmpty
      ? '（未接入联网参考；如需原作信息，只能根据模型已有知识整理，必须标记为 modelKnowledge）'
      : references
            .map(
              (item) =>
                  '${item.title} [${item.sourceType.name}, confidence=${item.confidence.toStringAsFixed(2)}]\n${item.summary}',
            )
            .join('\n\n');
  final modeRules = _modeRules(mode);
  return '''你在帮助用户整理$cardType。只能根据提供内容提出建议，不得创造正文未确认的重大事实。
模式：$modeRules
当前字段：${jsonEncode(fields)}
作者提供的来源与改设：$authorContext
本次要求：${instruction.trim().isEmpty ? '无额外要求' : instruction.trim()}
作品长期指导：${context.project.systemPrompt}
相关大纲：$outline
故事长期记忆：${context.memory.digest?.content ?? ''}
近期摘要：$summaries
近期正文：$raw
相关设定：$relatedCards
参考证据：$referenceText

信息优先级是硬规则：作者当前角色卡 > 作者二创设定 > 作者其它说明 > 可靠原作参考 > 模型已有知识 > AI 推测。
任何原作参考都不得覆盖作者已填写的内容或二创改设。没有真实参考证据时，只能标记 modelKnowledge，不得标记 canonReference。

只返回 JSON：{"suggestions":[{"field":"${fields.keys.first}","value":"建议完整值","reason":"正文依据或原因","source":"storyEvidence","inferred":false,"referenceTitle":"可选来源名"}]}
field 只允许从 ${fields.keys.join('、')} 中选择；source 只允许 canonReference、storyEvidence、modelKnowledge、creativeDraft、inferred。
空白的 content 字段应汇总正文中所有直接、明确描述该卡主体且仍然有效的事实，不要只挑选其中一条。
若内容只是暗示而非确定事实，inferred 必须为 true。不要输出 id、projectId、metadata、时间、删除状态、模型绑定或任何未知字段。''';
}

String _modeRules(CardCompletionMode mode) => switch (mode) {
  CardCompletionMode.fillBlank => '补全空白；非空字段不要主动覆盖。',
  CardCompletionMode.improveFromStory => '根据本作正文、大纲与长期记忆整理已发生的变化；本作事实高于原作参考。',
  CardCompletionMode.canonReference =>
    '按原作补充同人角色的身份、性格与具体视觉辨识点。保留用户现有内容及二创设定，不得用原作覆盖改设。无可靠证据的内容标记 modelKnowledge 或 inferred。外貌应优先包含发型轮廓、发色、眼睛、体型、服装配色、标志饰品、非人特征与武器；不确定就明示不确定。',
  CardCompletionMode.canonComparison =>
    '只列出当前角色卡与原作参考的明显差异，不要要求恢复原作，不得生成可自动覆盖的指令。',
  CardCompletionMode.originalDesignConservative =>
    '原创角色保守设计：紧贴用户构想补空，保留 2-4 个核心记忆点。',
  CardCompletionMode.originalDesignBalanced =>
    '原创角色平衡设计：在用户构想上适度增加鲜明创意，保留 2-4 个核心记忆点。',
  CardCompletionMode.originalDesignBold =>
    '原创角色大胆设计：可提出鲜明但易写、易画的创意，仍限制为 2-4 个核心记忆点。',
  CardCompletionMode.partialRedesign => '只重新设计用户指定的部分，其他已有设定必须原样保留。',
  CardCompletionMode.worldReference =>
    '根据已有作品知识整理设定的性质、地点、组织、规则、历史、视觉特征和与本作相关的注意事项；模型知识不得伪装成联网核对。',
  CardCompletionMode.worldOriginalExpansion =>
    '原创世界观扩写：只增加真正会影响故事的规则，避免无关的设定百科。',
};

CardSuggestionSource _sourceForMode(
  CardCompletionMode mode, {
  required bool hasEvidence,
}) => switch (mode) {
  CardCompletionMode.improveFromStory => CardSuggestionSource.storyEvidence,
  CardCompletionMode.canonReference || CardCompletionMode.canonComparison =>
    hasEvidence
        ? CardSuggestionSource.canonReference
        : CardSuggestionSource.modelKnowledge,
  CardCompletionMode.originalDesignConservative ||
  CardCompletionMode.originalDesignBalanced ||
  CardCompletionMode.originalDesignBold ||
  CardCompletionMode.partialRedesign ||
  CardCompletionMode.worldOriginalExpansion =>
    CardSuggestionSource.creativeDraft,
  CardCompletionMode.worldReference => CardSuggestionSource.modelKnowledge,
  CardCompletionMode.fillBlank => CardSuggestionSource.storyEvidence,
};

List<CardCompletionSuggestion> parseCardCompletionSuggestions(
  String raw, {
  required Map<String, String> current,
  required Set<String> allowedFields,
  CardSuggestionSource fallbackSource = CardSuggestionSource.inferred,
}) {
  final cleaned = cleanAiText(raw)
      .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s*```$'), '')
      .trim();
  var candidateCount = 0;
  var decodedCount = 0;
  final observedFields = <String>{};
  final observedValueTypes = <String>{};
  for (final candidate in _jsonCandidates(cleaned)) {
    candidateCount += 1;
    try {
      final root = jsonDecode(candidate);
      decodedCount += 1;
      final values = switch (root) {
        {'suggestions': final List suggestions} => suggestions,
        final List suggestions => suggestions,
        _ => null,
      };
      if (values == null) continue;
      final result = <CardCompletionSuggestion>[];
      for (final value in values) {
        if (value is! Map) continue;
        final field = value['field'];
        final suggestion = value['value'] ?? value['suggestedValue'];
        if (field is String) observedFields.add(field);
        observedValueTypes.add(suggestion.runtimeType.toString());
        if (field is! String ||
            suggestion is! String ||
            !allowedFields.contains(field) ||
            suggestion.trim().isEmpty) {
          continue;
        }
        result.add(
          CardCompletionSuggestion(
            field: field,
            currentValue: current[field] ?? '',
            suggestedValue: suggestion.trim(),
            reason: value['reason'] is String ? value['reason'] as String : '',
            inferred: value['inferred'] == true,
            source: value['inferred'] == true
                ? CardSuggestionSource.inferred
                : _parseSuggestionSource(value['source']) ?? fallbackSource,
            referenceTitle: value['referenceTitle'] is String
                ? value['referenceTitle'] as String
                : null,
          ),
        );
      }
      if (result.isNotEmpty) return List.unmodifiable(result);
    } on FormatException {
      continue;
    }
  }
  throw AiProviderInvalidResponseException(
    'chars=${cleaned.length},candidates=$candidateCount,decoded=$decodedCount,'
    'hasSuggestions=${cleaned.contains('suggestions')},'
    'startsJson=${cleaned.startsWith('{') || cleaned.startsWith('[')},'
    'endsJson=${cleaned.endsWith('}') || cleaned.endsWith(']')},'
    'fields=${observedFields.toList()..sort()},'
    'valueTypes=${observedValueTypes.toList()..sort()}',
  );
}

Iterable<String> _jsonCandidates(String value) sync* {
  if (value.isEmpty) return;
  yield value;
  var start = -1;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var index = 0; index < value.length; index += 1) {
    final character = value.codeUnitAt(index);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (character == 0x5c) {
        escaped = true;
      } else if (character == 0x22) {
        inString = false;
      }
      continue;
    }
    if (character == 0x22) {
      inString = true;
      continue;
    }
    if (character == 0x7b || character == 0x5b) {
      if (depth == 0) start = index;
      depth += 1;
      continue;
    }
    if (character != 0x7d && character != 0x5d) continue;
    if (depth == 0) continue;
    depth -= 1;
    if (depth == 0 && start >= 0) {
      final candidate = value.substring(start, index + 1);
      if (candidate != value) yield candidate;
      start = -1;
    }
  }
}

CardSuggestionSource? _parseSuggestionSource(Object? value) => switch (value) {
  'canonReference' => CardSuggestionSource.canonReference,
  'storyEvidence' => CardSuggestionSource.storyEvidence,
  'modelKnowledge' => CardSuggestionSource.modelKnowledge,
  'creativeDraft' => CardSuggestionSource.creativeDraft,
  'inferred' => CardSuggestionSource.inferred,
  _ => null,
};
