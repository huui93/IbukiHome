import 'dart:math' as math;

import '../../data/ai/ai_reasoning_parameters.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/ai/ai_reasoning_level.dart';
import '../../domain/projects/novel_output_limits.dart';
import '../plugins/novel_reply_markup.dart';
import 'ai_model_resolver.dart';

const novelDefaultOutputTokens = 2400;
const _maximumEstimatedTokens = 32768;

int? novelOutputTokenCeiling(NovelOutputLimits? limits) {
  final characters = limits?.maximum;
  return characters == null ? null : _tokenEstimate(characters);
}

// Reserve headroom for punctuation, whitespace, and tokenization variation.
// The endpoint limits tokens; the final visible manuscript is counted separately.
int _tokenEstimate(int characters) =>
    (characters.clamp(1, 16320) * 2 + 128).clamp(1, _maximumEstimatedTokens);

AiGenerationRequest applyNovelOutputSettings({
  required AiGenerationRequest request,
  required NovelOutputLimits? settings,
  required ResolvedAiModel? model,
  required bool applyLength,
  required bool structured,
  int? modelOutputLimit,
}) {
  final length = applyLength ? settings : null;
  var tokens = request.maxTokens ?? novelDefaultOutputTokens;
  if (novelOutputTokenCeiling(length) case final ceiling?) {
    tokens = ceiling;
  } else if (length?.minimum case final minimum?) {
    tokens = math.max(tokens, _tokenEstimate(minimum));
  }
  if (modelOutputLimit != null) {
    tokens = math.min(tokens, modelOutputLimit);
  }
  final temperature = settings?.temperature;
  final claude = structured
      ? null
      : novelClaudeTemperature(
          provider: model?.providerType,
          model: model?.model,
          temperature: temperature,
          reasoning: request.reasoning,
        );
  return request.copyWith(
    systemPrompt: '${request.systemPrompt}${length?.promptSuffix ?? ''}',
    maxTokens: tokens,
    temperature: temperature,
    sampling: {...request.sampling, 'temperature': ?claude},
  );
}

// The Claude transport consumes the canonical sampling map. Only explicitly
// configured novel temperatures are added, leaving other callers unchanged.
double? novelClaudeTemperature({
  required String? provider,
  required String? model,
  required double? temperature,
  required AiReasoningLevel reasoning,
}) {
  if (provider != 'claude' || model == null || temperature == null) {
    return null;
  }
  final valid = RegExp(
    r'^claude-(?:3(?:[.-]|$)|(?:opus|sonnet|haiku)-4(?:[-.][056](?:-|$)|-20\d{6}$|$))',
  ).hasMatch(model.toLowerCase());
  final thinking = reasoningParameters(
    provider: 'claude',
    model: model,
    level: reasoning,
  )['thinking'];
  if (!valid || (thinking is Map && thinking['type'] != 'disabled')) {
    return null;
  }
  return temperature.clamp(0, 1);
}

typedef NovelOutputResult = ({String text, bool trimmed, String? notice});

NovelOutputResult enforceNovelOutputLength(
  String content,
  NovelOutputLimits? limits, {
  required bool structured,
}) {
  if (limits == null || !limits.hasLengthLimits) {
    return (text: content, trimmed: false, notice: null);
  }
  final visible = structured
      ? NovelReplyMarkup.plainText(NovelReplyMarkup.parse(content).body)
      : content;
  final count = visible.replaceAll(_whiteSpace, '').runes.length;
  final maximum = limits.maximum;
  if (maximum != null && count > maximum) {
    final result = StringBuffer();
    var written = 0;
    for (final rune in visible.runes) {
      final char = String.fromCharCode(rune);
      if (!_whiteSpace.hasMatch(char) && ++written > maximum) break;
      result.write(char);
    }
    return (
      text: result.toString().trimRight(),
      trimmed: true,
      notice: '已按作品的最多字数保留正文。',
    );
  }
  final minimum = limits.minimum;
  return (
    text: content,
    trimmed: false,
    notice: minimum != null && count < minimum ? '本次正文未达到最少字数，已保留生成结果。' : null,
  );
}

final _whiteSpace = RegExp(r'\s', unicode: true);
