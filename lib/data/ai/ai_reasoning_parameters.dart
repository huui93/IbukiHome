import '../../domain/ai/ai_reasoning_level.dart';

/// Only expose settings with an explicit mapping for this provider/model.
List<AiReasoningLevel> reasoningLevels(String provider, String model) {
  final id = model.toLowerCase().replaceFirst('models/', '');
  const defaults = [AiReasoningLevel.automatic];
  const toggle = [
    ...defaults,
    AiReasoningLevel.disabled,
    AiReasoningLevel.enabled,
  ];
  const effort = [
    ...defaults,
    AiReasoningLevel.low,
    AiReasoningLevel.medium,
    AiReasoningLevel.high,
  ];
  switch (provider) {
    case 'openai':
      if (id.contains('chat') || id.contains('pro')) return defaults;
      if (RegExp(r'^(o[134](?:-|$)|gpt-[5-9])').hasMatch(id)) return effort;
    case 'grok':
      if (id.startsWith('grok-3-mini')) {
        return [...defaults, AiReasoningLevel.low, AiReasoningLevel.high];
      }
      if (id.startsWith('grok-4.5') || id.startsWith('grok-4.6')) return effort;
    case 'qwen':
      if (id.contains('omni') ||
          id.contains('vl') ||
          id.contains('coder') ||
          id.contains('instruct')) {
        return defaults;
      }
      if (id.contains('thinking') ||
          id.startsWith('qwen3.7-max') ||
          id.startsWith('qwen3.8-')) {
        return defaults;
      }
      if (id.startsWith('qwen3') || id.startsWith('qwen4')) return toggle;
    case 'kimi':
      if (id.startsWith('kimi-k2.5') || id.startsWith('kimi-k2.6')) {
        return toggle;
      }
    case 'glm':
      if (id.startsWith('glm-5.3')) {
        return [
          ...defaults,
          AiReasoningLevel.low,
          AiReasoningLevel.high,
          AiReasoningLevel.max,
        ];
      }
      if (id.startsWith('glm-5.2')) {
        return [...defaults, AiReasoningLevel.high, AiReasoningLevel.max];
      }
      if (RegExp(r'^glm-(4\.[5-9]|5(?:\.[01])?(?:-|$))').hasMatch(id)) {
        return toggle;
      }
    case 'deepseek':
      if (id.startsWith('deepseek-v4') || id == 'deepseek-flash') {
        return [
          ...toggle,
          AiReasoningLevel.low,
          AiReasoningLevel.high,
          AiReasoningLevel.max,
        ];
      }
    case 'claude':
      if (RegExp(r'claude-(opus|sonnet)-4[-.]6').hasMatch(id)) {
        return [...effort, AiReasoningLevel.disabled];
      }
      if (RegExp(r'claude-(opus|sonnet|haiku)-4[-.][05]').hasMatch(id) ||
          id.startsWith('claude-3-7')) {
        return [...effort, AiReasoningLevel.disabled];
      }
    case 'gemini':
      if (id.startsWith('gemini-2.5-pro')) return effort;
      if (id.startsWith('gemini-2.5-flash')) {
        return [...effort, AiReasoningLevel.disabled];
      }
      if (id.startsWith('gemini-3-pro')) {
        return [...defaults, AiReasoningLevel.low, AiReasoningLevel.high];
      }
      if (id.startsWith('gemini-3.1-pro') ||
          id.startsWith('gemini-3-flash') ||
          id.startsWith('gemini-3.5-flash') ||
          id.startsWith('gemini-3.6-flash') ||
          id.startsWith('gemini-3.8-flash')) {
        return effort;
      }
  }
  return defaults;
}

Map<String, Object?> reasoningParameters({
  required String provider,
  required String model,
  required AiReasoningLevel level,
  int? maxTokens,
}) {
  if (level == AiReasoningLevel.automatic ||
      !reasoningLevels(provider, model).contains(level)) {
    return const {};
  }
  final id = model.toLowerCase();
  final off = level == AiReasoningLevel.disabled;
  switch (provider) {
    case 'openai':
    case 'grok':
      return {'reasoning_effort': level.name};
    case 'qwen':
      return {'enable_thinking': !off};
    case 'kimi':
      return {
        'thinking': {'type': off ? 'disabled' : 'enabled'},
      };
    case 'glm':
      return {
        if (!id.startsWith('glm-5.3'))
          'thinking': {'type': off ? 'disabled' : 'enabled'},
        if (id.startsWith('glm-5.2') || id.startsWith('glm-5.3'))
          'reasoning_effort': level.name,
      };
    case 'deepseek':
      return {
        'thinking': {'type': off ? 'disabled' : 'enabled'},
        if (level != AiReasoningLevel.enabled && !off)
          'reasoning_effort': level.name,
      };
    case 'claude':
      if (off) {
        return const {
          'thinking': {'type': 'disabled'},
        };
      }
      if (RegExp(r'claude-(opus|sonnet)-4[-.]6').hasMatch(id)) {
        return {
          'thinking': const {'type': 'adaptive'},
          'output_config': {'effort': level.name},
        };
      }
      final requested = switch (level) {
        AiReasoningLevel.low => 1024,
        AiReasoningLevel.high => 8192,
        _ => 4096,
      };
      final output = maxTokens ?? 8192;
      // Legacy extended thinking requires at least 1024 tokens and output headroom.
      final budget = requested.clamp(
        1024,
        output > 2048 ? output - 1024 : 1024,
      );
      return {
        'thinking': {'type': 'enabled', 'budget_tokens': budget},
        'max_tokens': output < 2048 ? 2048 : output,
      };
    case 'gemini':
      if (id.startsWith('gemini-2.5')) {
        final requested = switch (level) {
          AiReasoningLevel.low => 1024,
          AiReasoningLevel.high => 8192,
          _ => 4096,
        };
        final available = ((maxTokens ?? 32768) - 1024).clamp(128, 32768);
        return {
          'thinkingConfig': {
            'thinkingBudget': off ? 0 : requested.clamp(128, available),
          },
        };
      }
      return {
        'thinkingConfig': {'thinkingLevel': level.name.toUpperCase()},
      };
  }
  return const {};
}
