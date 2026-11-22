import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ibukihome/core/network/ai_provider_exceptions.dart';
import 'package:ibukihome/data/ai/ai_provider_client.dart';
import 'package:ibukihome/data/ai/ai_provider_registry.dart';
import 'package:ibukihome/data/ai/claude_provider_client.dart';
import 'package:ibukihome/data/ai/chat_completion_parameters.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';

void main() {
  for (final type in AiProviderType.values) {
    test(
      '${type.name}: non-streaming uses the correct endpoint and protocol',
      () async {
        late http.Request sent;
        final client = AiProviderRegistry(
          httpClientFactory: () => MockClient((request) async {
            sent = request;
            return http.Response.bytes(utf8.encode(nonStreaming(type)), 200);
          }),
        ).create(config(type), 'synthetic-key');
        addTearDown(client.close);
        expect(await client.generate(request()), '你好');
        final body = jsonDecode(sent.body) as Map;
        if (type == AiProviderType.claude) {
          expect(sent.url.path, '/v1/messages');
          expect(sent.headers['x-api-key'], 'synthetic-key');
          expect(sent.headers['anthropic-version'], '2023-06-01');
          expect(sent.headers.containsKey('Authorization'), isFalse);
          expect(body['system'], 'private application prompt');
          expect((body['messages'] as List).single['role'], 'user');
          expect(body.containsKey('temperature'), isFalse);
          expect(sent.followRedirects, isFalse);
        } else if (type == AiProviderType.gemini) {
          expect(
            sent.url.path,
            endsWith('/models/configured-model:generateContent'),
          );
          expect(sent.headers['x-goog-api-key'], 'synthetic-key');
          expect(body['systemInstruction'], isNotNull);
        } else {
          expect(sent.url.path, endsWith('/chat/completions'));
          expect(sent.headers['Authorization'], 'Bearer synthetic-key');
          expect(body['messages'], [
            {'role': 'system', 'content': 'private application prompt'},
            {'role': 'user', 'content': '你好'},
          ]);
          if (type == AiProviderType.grok) {
            expect(body['max_completion_tokens'], 512);
          }
        }
      },
    );

    test(
      '${type.name}: streaming preserves split UTF8, ignores reasoning, and terminates',
      () async {
        final transport = BytesClient(streaming(type));
        final client = AiProviderRegistry(
          httpClientFactory: () => transport,
        ).create(config(type), 'synthetic-key');
        addTearDown(client.close);
        final events = await client.streamEvents(request()).toList();
        expect(
          events.where((e) => !e.isTerminal).map((e) => e.content).join(),
          '你好',
        );
        expect(events.last.finishReason, AiFinishReason.stop);
        expect(events.where((e) => e.isTerminal), hasLength(1));
        expect(transport.calls, 1);
      },
    );
  }

  test('modern OpenAI reasoning, Kimi and Grok use supported parameters', () {
    final openai = chatCompletionParameters(
      provider: 'openai',
      model: 'gpt-5.2',
      temperature: 0.8,
      maxTokens: 2048,
    );
    expect(openai['max_completion_tokens'], 2048);
    expect(openai.containsKey('temperature'), isFalse);
    expect(openai.containsKey('max_tokens'), isFalse);
    expect(
      chatCompletionParameters(
        provider: 'openai',
        model: 'o3',
        temperature: 0.8,
        maxTokens: 2048,
      ).containsKey('temperature'),
      isFalse,
    );
    for (final model in ['kimi-k2.6', 'kimi-k2.7-code', 'kimi-k3.1-pro']) {
      final parameters = chatCompletionParameters(
        provider: 'kimi',
        model: model,
        temperature: 0.8,
        maxTokens: 2048,
      );
      expect(parameters.containsKey('temperature'), isFalse);
      if (model == 'kimi-k2.6') {
        expect(parameters['thinking'], {'type': 'disabled'});
      } else {
        expect(parameters.containsKey('thinking'), isFalse);
      }
    }
    expect(
      chatCompletionParameters(
        provider: 'grok',
        model: 'grok-model',
        maxTokens: 2048,
      )['max_completion_tokens'],
      2048,
    );
    expect(
      chatCompletionParameters(
        provider: 'qwen',
        model: 'qwen3-model',
      )['enable_thinking'],
      isFalse,
    );
    expect(
      chatCompletionParameters(
        provider: 'qwen',
        model: 'qwen2.5-model',
      ).containsKey('enable_thinking'),
      isFalse,
    );
    expect(
      chatCompletionParameters(
        provider: 'glm',
        model: 'glm-5-model',
        temperature: 1.5,
      )['temperature'],
      1,
    );
  });

  test(
    'connection verification proves an actual reply and does not send business context',
    () async {
      final calls = <http.Request>[];
      final client = AiProviderRegistry(
        httpClientFactory: () => MockClient((req) async {
          calls.add(req);
          return jsonResponse(
            req.method == 'GET'
                ? '{"data":[{"id":"configured-model"}]}'
                : nonStreaming(AiProviderType.openai),
            200,
          );
        }),
      ).create(config(AiProviderType.openai), 'synthetic-key');
      addTearDown(client.close);
      final result = await client.testConnection(
        preferredModel: 'configured-model',
      );
      expect(result.verifiedModels, ['configured-model']);
      expect(calls.map((r) => r.method), ['GET', 'POST']);
      expect(calls.last.body, isNot(contains('private application prompt')));
      expect(calls.last.body, isNot(contains('你好')));
      expect(jsonDecode(calls.last.body)['messages'], [
        {'role': 'system', 'content': 'Reply only OK.'},
        {'role': 'user', 'content': 'Hi'},
      ]);
    },
  );

  test(
    'a model list alone is not a successful generation verification',
    () async {
      var calls = 0;
      final client = AiProviderRegistry(
        httpClientFactory: () => MockClient((req) async {
          calls++;
          return jsonResponse('{"data":[{"id":"configured-model"}]}', 200);
        }),
      ).create(config(AiProviderType.openai), 'synthetic-key');
      addTearDown(client.close);
      final result = await client.testConnection();
      expect(result.models, ['configured-model']);
      expect(result.verifiedModel, isNull);
      expect(result.verifiedModels, isEmpty);
      expect(calls, 1);
    },
  );

  test(
    'GLM and private gateways without a models endpoint allow an explicit model probe',
    () async {
      final client = AiProviderRegistry(
        httpClientFactory: () => MockClient(
          (req) async => jsonResponse(
            req.method == 'GET' ? '{}' : nonStreaming(AiProviderType.glm),
            req.method == 'GET' ? 404 : 200,
          ),
        ),
      ).create(config(AiProviderType.glm), 'synthetic-key');
      addTearDown(client.close);
      final result = await client.testConnection(
        preferredModel: 'configured-model',
      );
      expect(result.verifiedModel, 'configured-model');
    },
  );

  test(
    'a rejected generation is never promoted to a successful connection',
    () async {
      final client = AiProviderRegistry(
        httpClientFactory: () => MockClient(
          (req) async => jsonResponse(
            req.method == 'GET'
                ? '{"data":[{"id":"configured-model"}]}'
                : '{"error":{"code":"model_not_found"}}',
            req.method == 'GET' ? 200 : 404,
          ),
        ),
      ).create(config(AiProviderType.openai), 'synthetic-key');
      addTearDown(client.close);
      await expectLater(
        client.testConnection(preferredModel: 'configured-model'),
        throwsA(isA<AiProviderConnectionTestException>()),
      );
    },
  );

  test(
    'invalid_request_error for context overflow remains a context error',
    () async {
      final client = AiProviderRegistry(
        httpClientFactory: () => MockClient(
          (_) async => jsonResponse(
            '{"error":{"type":"invalid_request_error","code":"context_length_exceeded"}}',
            400,
          ),
        ),
      ).create(config(AiProviderType.openai), 'synthetic-key');
      addTearDown(client.close);
      await expectLater(
        client.generate(request()),
        throwsA(isA<AiProviderContextTooLargeException>()),
      );
    },
  );

  for (final (status, type) in [
    (401, 'authentication_error'),
    (403, 'permission_error'),
    (429, 'rate_limit_error'),
    (529, 'overloaded_error'),
  ]) {
    test(
      'Claude HTTP $status is typed and never exposes private errors',
      () async {
        final client = ClaudeProviderClient(
          baseUri: Uri.parse('https://claude.test/v1'),
          apiKey: 'synthetic-key',
          httpClient: MockClient(
            (_) async => jsonResponse(
              jsonEncode({
                'error': {
                  'type': type,
                  'message': 'private-server-data synthetic-key',
                },
              }),
              status,
            ),
          ),
        );
        addTearDown(client.close);
        try {
          await client.generate(request());
          fail('Expected a provider failure');
        } on AiProviderException catch (error) {
          expect(error.toString(), isNot(contains('synthetic-key')));
          expect(error.toString(), isNot(contains('private-server-data')));
          expect(error, switch (status) {
            401 => isA<AiProviderAuthenticationException>(),
            403 => isA<AiProviderRequestRejectedException>(),
            429 => isA<AiProviderRateLimitedException>(),
            _ => isA<AiProviderServerException>(),
          });
        }
      },
    );
  }
  test(
    'Claude stream timeout before content follows the existing bounded recovery contract',
    () async {
      final client = ClaudeProviderClient(
        baseUri: Uri.parse('https://claude.test/v1'),
        apiKey: 'synthetic-key',
        timeout: const Duration(milliseconds: 2),
        httpClient: SlowClient(),
      );
      addTearDown(client.close);
      await expectLater(
        client.streamEvents(request()).toList(),
        throwsA(isA<AiProviderInterruptedBeforeContentException>()),
      );
    },
  );
  test('Claude SSE overload errors never become completed replies', () async {
    final client = ClaudeProviderClient(
      baseUri: Uri.parse('https://claude.test/v1'),
      apiKey: 'synthetic-key',
      httpClient: BytesClient(
        event({
          'type': 'error',
          'error': {'type': 'overloaded_error', 'message': 'private data'},
        }),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.streamEvents(request()).toList(),
      throwsA(isA<AiProviderServerException>()),
    );
  });

  test('Claude paginates its real model catalogue', () async {
    var calls = 0;
    final client = AiProviderRegistry(
      httpClientFactory: () => MockClient((req) async {
        calls++;
        if (calls == 1) {
          return jsonResponse(
            '{"data":[{"id":"one"}],"has_more":true,"last_id":"one"}',
            200,
          );
        }
        expect(req.url.queryParameters['after_id'], 'one');
        return jsonResponse('{"data":[{"id":"two"}],"has_more":false}', 200);
      }),
    ).create(config(AiProviderType.claude), 'synthetic-key');
    addTearDown(client.close);
    expect(await client.listModels(), ['one', 'two']);
  });

  for (final (ending, reason) in [
    ('end_turn', AiFinishReason.stop),
    ('max_tokens', AiFinishReason.length),
    ('refusal', AiFinishReason.contentFiltered),
  ]) {
    test('Claude $ending keeps its own finish meaning', () async {
      final client = ClaudeProviderClient(
        baseUri: Uri.parse('https://claude.test/v1'),
        apiKey: 'synthetic-key',
        httpClient: BytesClient(claudeStream(ending: ending)),
      );
      addTearDown(client.close);
      expect(
        (await client.streamEvents(request()).toList()).last.finishReason,
        reason,
      );
    });
  }
  test('Claude requires message_stop, not just message_delta', () async {
    final client = ClaudeProviderClient(
      baseUri: Uri.parse('https://claude.test/v1'),
      apiKey: 'synthetic-key',
      httpClient: BytesClient(
        claudeStream().replaceAll(event({'type': 'message_stop'}), ''),
      ),
    );
    addTearDown(client.close);
    expect(
      (await client.streamEvents(request()).toList()).last.finishReason,
      AiFinishReason.interrupted,
    );
  });
  test(
    'Claude accepts cropped assistant-first history without dropping messages',
    () async {
      late Map body;
      final client = AiProviderRegistry(
        httpClientFactory: () => MockClient((req) async {
          body = jsonDecode(req.body) as Map;
          return http.Response.bytes(
            utf8.encode(nonStreaming(AiProviderType.claude)),
            200,
          );
        }),
      ).create(config(AiProviderType.claude), 'synthetic-key');
      addTearDown(client.close);
      await client.generate(
        request().copyWith(
          messages: const [
            AiGenerationMessage(
              role: AiMessageRole.assistant,
              content: 'Earlier answer',
            ),
            AiGenerationMessage(role: AiMessageRole.user, content: 'Continue'),
          ],
        ),
      );
      expect((body['messages'] as List).map((m) => m['content']), [
        'Continue the following conversation.',
        'Earlier answer',
        'Continue',
      ]);
    },
  );
  test(
    'Claude structured requests use a native JSON instruction, without OpenAI-only fields',
    () async {
      late Map body;
      final client = AiProviderRegistry(
        httpClientFactory: () => MockClient((req) async {
          body = jsonDecode(req.body) as Map;
          return http.Response.bytes(
            utf8.encode(nonStreaming(AiProviderType.claude)),
            200,
          );
        }),
      ).create(config(AiProviderType.claude), 'synthetic-key');
      addTearDown(client.close);
      await client.generate(
        AiGenerationRequest(
          requestId: 'json',
          systemPrompt: 'Return JSON',
          messages: request().messages,
          model: 'configured-model',
          structuredJson: true,
        ),
      );
      expect(body['system'], contains('valid JSON object'));
      expect(body.containsKey('response_format'), isFalse);
    },
  );
  test('Claude cancellation before a request sends nothing', () async {
    final transport = BytesClient(claudeStream());
    final client = ClaudeProviderClient(
      baseUri: Uri.parse('https://claude.test/v1'),
      apiKey: 'synthetic-key',
      httpClient: transport,
    );
    addTearDown(client.close);
    await expectLater(
      client
          .streamEvents(
            request(),
            cancellation: AiRequestCancellation()..cancel(),
          )
          .toList(),
      throwsA(isA<AiProviderCancelledException>()),
    );
    expect(transport.calls, 0);
  });
  test(
    'Claude cancellation after a text chunk stops before the rest',
    () async {
      final transport = BytesClient(claudeStream());
      final cancellation = AiRequestCancellation();
      final client = ClaudeProviderClient(
        baseUri: Uri.parse('https://claude.test/v1'),
        apiKey: 'synthetic-key',
        httpClient: transport,
      );
      final events = <AiStreamEvent>[];
      await for (final event in client.streamEvents(
        request(),
        cancellation: cancellation,
      )) {
        events.add(event);
        if (event.content.isNotEmpty) cancellation.cancel();
      }
      expect(events.last.finishReason, AiFinishReason.cancelled);
      expect(
        events.where((e) => !e.isTerminal).map((e) => e.content).join(),
        '你',
      );
      expect(transport.closed, isTrue);
    },
  );
}

AiProviderConfig config(AiProviderType type) => AiProviderConfig(
  id: type.name,
  type: type,
  displayName: type.displayName,
  baseUrl: type == AiProviderType.custom
      ? 'https://custom.test/v1'
      : type.defaultBaseUrl,
  apiKeyRef: 'test-key',
  selectedModel: 'configured-model',
  enabled: true,
  connectionStatus: AiProviderConnectionStatus.untested,
  availableModels: const [],
  createdAtUtc: DateTime.utc(2026),
  updatedAtUtc: DateTime.utc(2026),
);
AiGenerationRequest request() => const AiGenerationRequest(
  requestId: 'test',
  systemPrompt: 'private application prompt',
  messages: [AiGenerationMessage(role: AiMessageRole.user, content: '你好')],
  model: 'configured-model',
  maxTokens: 512,
  temperature: 0.8,
);
String event(Map body) => 'data: ${jsonEncode(body)}\n\n';
String claudeStream({String ending = 'end_turn'}) =>
    ': ping\n\n${event({
      'type': 'message_start',
      'message': {'role': 'assistant'},
    })}${event({
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'thinking_delta', 'thinking': 'private reasoning'},
    })}${event({
      'type': 'content_block_delta',
      'index': 1,
      'delta': {'type': 'text_delta', 'text': '你'},
    })}${event({
      'type': 'content_block_delta',
      'index': 1,
      'delta': {'type': 'text_delta', 'text': '好'},
    })}${event({
      'type': 'message_delta',
      'delta': {'stop_reason': ending},
    })}${event({'type': 'message_stop'})}';
String streaming(AiProviderType type) => type == AiProviderType.claude
    ? claudeStream()
    : type == AiProviderType.gemini
    ? event({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'private reasoning', 'thought': true},
                {'text': '你好'},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      })
    : '${event({
        'choices': [
          {
            'delta': {'reasoning_content': 'private reasoning'},
            'finish_reason': null,
          },
        ],
      })}${event({
        'choices': [
          {
            'delta': {'content': '你好'},
            'finish_reason': 'stop',
          },
        ],
      })}data: [DONE]\n\n';
String nonStreaming(AiProviderType type) => jsonEncode(
  type == AiProviderType.claude
      ? {
          'type': 'message',
          'content': [
            {'type': 'thinking', 'thinking': 'private reasoning'},
            {'type': 'text', 'text': '你好'},
          ],
          'stop_reason': 'end_turn',
        }
      : type == AiProviderType.gemini
      ? {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': '你好'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        }
      : {
          'choices': [
            {
              'message': {'content': '你好'},
              'finish_reason': 'stop',
            },
          ],
        },
);

class BytesClient extends http.BaseClient {
  BytesClient(this.body);
  final String body;
  int calls = 0;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    return http.StreamedResponse(
      Stream.fromIterable(utf8.encode(body).map((b) => [b])),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  @override
  void close() {
    closed = true;
  }
}

http.Response jsonResponse(String body, int status) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class SlowClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return http.StreamedResponse(const Stream.empty(), 200);
  }
}
