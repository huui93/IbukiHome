import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ibukihome/data/ai/ai_provider_registry.dart';
import 'package:ibukihome/data/ai/ai_usage_codec.dart';
import 'package:ibukihome/data/ai/ai_reasoning_parameters.dart';
import 'package:ibukihome/data/ai/claude_messages_protocol.dart';
import 'package:ibukihome/domain/ai/ai_reasoning_level.dart';
import 'package:ibukihome/domain/ai/ai_token_usage.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import 'provider_expansion_test.dart' as fixtures;

void main() {
  test(
    'usage accounts cached input, reasoning output, and incomplete reports honestly',
    () {
      final open = openAiUsage({
        'prompt_tokens': 100,
        'completion_tokens': 30,
        'prompt_tokens_details': {'cached_tokens': 20},
        'completion_tokens_details': {'reasoning_tokens': 10},
      })!;
      expect(open.isComplete, isTrue);
      expect(open.totalTokens, 130);
      expect(open.reasoningTokens, 10);
      expect(open.cachedInputTokens, 20);
      expect(openAiUsage({'prompt_tokens': 10})!.isComplete, isFalse);
      expect(
        openAiUsage({'prompt_tokens': -1, 'completion_tokens': 'bad'}),
        isNull,
      );
      final claude = claudeUsage({
        'input_tokens': 10,
        'cache_read_input_tokens': 40,
        'cache_creation_input_tokens': 20,
        'output_tokens': 5,
      }, isFinal: true)!;
      expect(claude.inputTokens, 70);
      expect(claude.totalTokens, 75);
      final gemini = geminiUsage({
        'promptTokenCount': 100,
        'candidatesTokenCount': 20,
        'thoughtsTokenCount': 30,
        'totalTokenCount': 150,
      }, isFinal: true)!;
      expect(gemini.outputTokens, 50);
      expect(gemini.totalTokens, 150);
    },
  );
  test(
    'Claude streaming usage merges cumulative counts and finalizes only at message_stop',
    () {
      final usages = <AiTokenUsage>[];
      final decoder = ClaudeMessageDecoder(onUsage: usages.add);
      decoder.add({
        'type': 'message_start',
        'message': {
          'usage': {
            'input_tokens': 10,
            'output_tokens': 1,
            'cache_read_input_tokens': 20,
          },
        },
      }).toList();
      expect(usages.last.isComplete, isFalse);
      decoder.add({
        'type': 'message_delta',
        'delta': {'stop_reason': 'end_turn'},
        'usage': {'output_tokens': 5},
      }).toList();
      expect(usages.last.isComplete, isFalse);
      decoder.add({'type': 'message_stop'}).toList();
      expect(usages.last.isComplete, isTrue);
      expect(usages.last.inputTokens, 30);
      expect(usages.last.outputTokens, 5);
    },
  );
  for (final item in [
    (AiProviderType.openai, 'gpt-5.2', 'reasoning_effort', 'high'),
    (AiProviderType.grok, 'grok-3-mini', 'reasoning_effort', 'high'),
    (AiProviderType.qwen, 'qwen3-plus', 'enable_thinking', true),
    (AiProviderType.glm, 'glm-5.3', 'reasoning_effort', 'high'),
    (AiProviderType.deepseek, 'deepseek-v4-pro', 'reasoning_effort', 'high'),
    (AiProviderType.kimi, 'kimi-k2.5', 'thinking', {'type': 'enabled'}),
    (
      AiProviderType.claude,
      'claude-sonnet-4-6',
      'thinking',
      {'type': 'adaptive'},
    ),
    (
      AiProviderType.gemini,
      'gemini-3.1-pro',
      'generationConfig',
      {
        'maxOutputTokens': 512,
        'temperature': .8,
        'thinkingConfig': {'thinkingLevel': 'HIGH'},
      },
    ),
  ]) {
    test(
      '${item.$1.name} serializes reasoning in the real request body',
      () async {
        late Map body;
        final client = AiProviderRegistry(
          httpClientFactory: () => MockClient((request) async {
            body = jsonDecode(request.body) as Map;
            return http.Response.bytes(
              utf8.encode(fixtures.nonStreaming(item.$1)),
              200,
            );
          }),
        ).create(fixtures.config(item.$1), 'synthetic');
        addTearDown(client.close);
        final level =
            [AiProviderType.qwen, AiProviderType.kimi].contains(item.$1)
            ? AiReasoningLevel.enabled
            : AiReasoningLevel.high;
        await client.generate(
          fixtures.request().copyWith(model: item.$2, reasoning: level),
        );
        expect(body[item.$3], item.$4);
        if (item.$1 == AiProviderType.glm) {
          expect(body.containsKey('thinking'), isFalse);
        }
      },
    );
  }

  for (final type in [
    AiProviderType.openai,
    AiProviderType.gemini,
    AiProviderType.claude,
  ]) {
    test(
      '${type.name} captures real streaming usage including trailing metadata',
      () async {
        final event = fixtures.event;
        final body = switch (type) {
          AiProviderType.openai =>
            '${event({
              'choices': [
                {
                  'delta': {'content': 'OK'},
                  'finish_reason': 'stop',
                },
              ],
            })}${event({
              'choices': [],
              'usage': {'prompt_tokens': 100, 'completion_tokens': 30},
            })}data: [DONE]\n\n',
          AiProviderType.gemini =>
            '${event({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'OK'},
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
            })}${event({
              'usageMetadata': {'promptTokenCount': 100, 'candidatesTokenCount': 20, 'thoughtsTokenCount': 10, 'totalTokenCount': 130},
            })}',
          _ =>
            '${event({
              'type': 'message_start',
              'message': {
                'usage': {'input_tokens': 100, 'output_tokens': 0},
              },
            })}${event({
              'type': 'content_block_delta',
              'delta': {'type': 'text_delta', 'text': 'OK'},
            })}${event({
              'type': 'message_delta',
              'delta': {'stop_reason': 'end_turn'},
              'usage': {'output_tokens': 30},
            })}${event({'type': 'message_stop'})}',
        };
        final usage = <AiTokenUsage>[];
        final client = AiProviderRegistry(
          httpClientFactory: () => fixtures.BytesClient(body),
        ).create(fixtures.config(type), 'synthetic');
        addTearDown(client.close);
        await client
            .streamEvents(fixtures.request().copyWith(onUsage: usage.add))
            .drain<void>();
        expect(usage.last.isComplete, isTrue);
        expect(usage.last.inputTokens, 100);
        expect(usage.last.outputTokens, 30);
      },
    );
  }
  test(
    'unknown models, unsupported levels and forced thinking models receive no invalid override',
    () {
      expect(
        reasoningParameters(
          provider: 'custom',
          model: 'any',
          level: AiReasoningLevel.high,
        ),
        isEmpty,
      );
      for (final provider in [
        'openai',
        'gemini',
        'claude',
        'qwen',
        'grok',
        'glm',
      ]) {
        expect(
          reasoningParameters(
            provider: provider,
            model: 'unknown',
            level: AiReasoningLevel.disabled,
          ),
          isEmpty,
        );
      }
      expect(
        reasoningLevels('glm', 'glm-5.3'),
        isNot(contains(AiReasoningLevel.disabled)),
      );
      expect(
        reasoningLevels('qwen', 'qwen3.7-max-preview'),
        isNot(contains(AiReasoningLevel.disabled)),
      );
      final legacy = reasoningParameters(
        provider: 'claude',
        model: 'claude-sonnet-4-5',
        level: AiReasoningLevel.high,
        maxTokens: 512,
      );
      expect(legacy['max_tokens'], 2048);
      expect((legacy['thinking'] as Map)['budget_tokens'], 1024);
    },
  );
}
