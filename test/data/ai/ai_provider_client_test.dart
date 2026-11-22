import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ibukihome/core/network/ai_network_diagnostics.dart';
import 'package:ibukihome/core/network/ai_provider_exceptions.dart';
import 'package:ibukihome/data/ai/ai_provider_client.dart';
import 'package:ibukihome/data/ai/ai_provider_registry.dart';
import 'package:ibukihome/data/ai/gemini_provider_client.dart';
import 'package:ibukihome/data/ai/openai_compatible_provider_client.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';
import 'package:ibukihome/domain/ai/ai_generation.dart';

void main() {
  group('OpenAI-compatible clients', () {
    test('streams OpenAI-compatible text chunks', () async {
      final client = _openAi(
        _utf8Response(
          'data: {"choices":[{"delta":{"content":"first"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":" part"}}]}\n\n'
          'data: [DONE]\n\n',
          200,
        ),
      );

      expect(await client.streamGenerate(_request()).toList(), [
        'first',
        ' part',
      ]);
    });

    test('DeepSeek choices preserve normal response semantics', () async {
      final client = DeepSeekProviderClient(
        baseUri: Uri.parse('https://api.deepseek.test'),
        apiKey: 'deepseek-unit-secret',
        httpClient: MockClient(
          (_) async => _utf8Response(
            'data: {"choices":[{"delta":{"content":"正文"},"finish_reason":"stop"}]}\n\n'
            'data: [DONE]\n\n',
            200,
          ),
        ),
      );

      final events = await client.streamEvents(_request()).toList();
      expect(events.where((event) => !event.isTerminal).single.content, '正文');
      expect(events.last.finishReason, AiFinishReason.stop);
    });

    test(
      'builds a chat completions request without leaking request id',
      () async {
        late http.Request sent;
        final client = OpenAiProviderClient(
          baseUri: Uri.parse('https://example.test/v1'),
          apiKey: 'unit-test-secret',
          httpClient: MockClient((request) async {
            sent = request;
            return http.Response(_openAiSse('ok'), 200);
          }),
        );

        await client.streamGenerate(_request()).drain<void>();
        final body = jsonDecode(sent.body) as Map<String, dynamic>;
        expect(sent.url.path, '/v1/chat/completions');
        expect(body['model'], 'test-model');
        expect(body['stream'], isTrue);
        expect(body['temperature'], 0.4);
        expect(body['max_tokens'], 512);
        expect(sent.body, isNot(contains('request-test')));
      },
    );

    test('uses a real non-streaming chat completion request', () async {
      late http.Request sent;
      final client = OpenAiProviderClient(
        baseUri: Uri.parse('https://example.test/v1'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(
            '{"choices":[{"message":{"content":"OK"}}]}',
            200,
          );
        }),
      );

      expect(await client.generate(_request()), 'OK');
      expect(sent.url.path, '/v1/chat/completions');
      expect((jsonDecode(sent.body) as Map)['stream'], isFalse);
      expect(sent.headers['Accept'], 'application/json');
    });

    test('requests native JSON output only for structured requests', () async {
      late http.Request sent;
      final client = OpenAiProviderClient(
        baseUri: Uri.parse('https://example.test/v1'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(
            '{"choices":[{"message":{"content":"{}"},"finish_reason":"stop"}]}',
            200,
          );
        }),
      );
      await client.generate(_request(structuredJson: true));
      expect((jsonDecode(sent.body) as Map)['response_format'], {
        'type': 'json_object',
      });
    });

    test('does not treat reasoning truncated by length as final content', () {
      final client = _openAi(
        http.Response(
          '{"choices":[{"message":{"content":null,'
          '"reasoning_content":"unfinished"},"finish_reason":"length"}]}',
          200,
        ),
      );
      expect(
        client.generate(_request(structuredJson: true)),
        throwsA(isA<AiProviderInterruptedException>()),
      );
    });

    test('accepts structured non-stream response content', () async {
      final client = _openAi(
        http.Response(
          '{"choices":[{"message":{"content":[{"type":"text",'
          '"text":"structured"}]}}]}',
          200,
        ),
      );

      expect(await client.generate(_request()), 'structured');
    });

    test('accepts a reasoning-content-only non-stream response', () async {
      final client = _openAi(
        http.Response(
          '{"choices":[{"message":{"content":null,'
          '"reasoning_content":"reasoned"}}]}',
          200,
        ),
      );

      expect(await client.generate(_request()), 'reasoned');
    });

    test('sends system, user, and assistant messages in order', () async {
      late http.Request sent;
      final client = OpenAiProviderClient(
        baseUri: Uri.parse('https://example.test/v1'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(_openAiSse('ok'), 200);
        }),
      );

      await client.streamGenerate(_request()).drain<void>();
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      expect(messages.map((item) => item['role']), [
        'system',
        'user',
        'assistant',
      ]);
    });

    test('supports list-shaped OpenAI text deltas', () async {
      final client = _openAi(
        _utf8Response(
          'data: {"choices":[{"delta":{"content":[{"text":"piece"}]}}]}\n\n'
          'data: [DONE]\n\n',
          200,
        ),
      );
      expect(await client.streamGenerate(_request()).join(), 'piece');
    });

    test('preserves OpenAI length finish reason', () async {
      final client = _openAi(
        _utf8Response(
          'data: {"choices":[{"delta":{"content":"partial"},"finish_reason":"length"}]}\n\n',
          200,
        ),
      );
      final events = await client.streamEvents(_request()).toList();
      expect(events.first.content, 'partial');
      expect(events.last.finishReason, AiFinishReason.length);
    });

    test('OpenAI content without terminal signal is interrupted', () async {
      final client = _openAi(
        _utf8Response(
          'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
          200,
        ),
      );
      await expectLater(
        client.streamEvents(_request()).drain<void>(),
        throwsA(isA<AiProviderInterruptedException>()),
      );
    });

    test('OpenAI DONE with no text is a legal providerEmpty', () async {
      final client = _openAi(_utf8Response('data: [DONE]\n\n', 200));

      await expectLater(
        client.streamEvents(_request()).drain<void>(),
        throwsA(
          isA<AiProviderInvalidResponseException>()
              .having(
                (error) => error.emptyKind,
                'emptyKind',
                AiEmptyResponseKind.providerEmpty,
              )
              .having(
                (error) => error.responseDiagnostics?.streamClosedNormally,
                'streamClosedNormally',
                isTrue,
              ),
        ),
      );
    });

    test('OpenAI zero-event EOF is interrupted before content', () async {
      final client = _openAi(_utf8Response('', 200));

      await expectLater(
        client.streamEvents(_request()).drain<void>(),
        throwsA(
          isA<AiProviderInterruptedBeforeContentException>()
              .having(
                (error) => error.responseDiagnostics.httpStatus,
                'httpStatus',
                200,
              )
              .having(
                (error) => error.responseDiagnostics.streamEventCount,
                'streamEventCount',
                0,
              ),
        ),
      );
    });

    test('OpenAI idle timeout after content is an interruption', () async {
      final diagnostics = _RecordingDiagnostics();
      final client = OpenAiProviderClient(
        baseUri: Uri.parse('https://example.test/v1'),
        apiKey: 'unit-test-secret',
        timeout: const Duration(milliseconds: 20),
        diagnostics: diagnostics,
        httpClient: _DelayedChunkedClient([
          _DelayedChunk(
            Duration.zero,
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
            ),
          ),
          _DelayedChunk(
            const Duration(milliseconds: 50),
            utf8.encode('data: [DONE]\n\n'),
          ),
        ]),
      );

      await expectLater(
        client.streamEvents(_request()).drain<void>(),
        throwsA(
          isA<AiProviderInterruptedException>().having(
            (error) => error.timeoutType,
            'timeoutType',
            'idle',
          ),
        ),
      );
      final failed = diagnostics.events.last;
      expect(failed.exceptionType, 'TimeoutException');
      expect(failed.timeoutType, 'idle');
      expect(failed.receivedCharacterCount, 7);
      expect(failed.streamClosedNormally, isFalse);
    });

    test('rejects an empty generation stream', () async {
      final client = _openAi(http.Response('data: [DONE]\n\n', 200));
      expect(
        client.generate(_request()),
        throwsA(isA<AiProviderInvalidResponseException>()),
      );
    });

    test('rejects malformed generation JSON safely', () async {
      final client = _openAi(http.Response('data: {bad-json}\n\n', 200));
      expect(
        client.generate(_request()),
        throwsA(isA<AiProviderInvalidResponseException>()),
      );
    });

    test('maps generation rate limits', () async {
      final client = _openAi(http.Response('{"error":"slow down"}', 429));
      expect(
        client.generate(_request()),
        throwsA(isA<AiProviderRateLimitedException>()),
      );
    });

    test('maps generation authentication failures', () async {
      expect(
        _openAi(http.Response('{}', 401)).generate(_request()),
        throwsA(isA<AiProviderAuthenticationException>()),
      );
    });

    test('maps rejected generation requests', () async {
      expect(
        _openAi(http.Response('{}', 403)).generate(_request()),
        throwsA(isA<AiProviderRequestRejectedException>()),
      );
    });

    test('maps missing generation endpoints separately from models', () async {
      expect(
        _openAi(http.Response('{}', 404)).generate(_request()),
        throwsA(isA<AiProviderEndpointException>()),
      );
    });

    test('maps a rejected generation model from HTTP 400', () async {
      expect(
        _openAi(
          http.Response('{"error":"invalid model"}', 400),
        ).generate(_request()),
        throwsA(isA<AiProviderModelUnavailableException>()),
      );
    });

    test('maps generation server failures', () async {
      expect(
        _openAi(http.Response('{}', 503)).generate(_request()),
        throwsA(isA<AiProviderServerException>()),
      );
    });

    test('maps missing generation models', () async {
      final client = _openAi(http.Response('{"error":"model_not_found"}', 404));
      expect(
        client.generate(_request()),
        throwsA(isA<AiProviderModelUnavailableException>()),
      );
    });

    test('maps oversized generation context', () async {
      final client = _openAi(http.Response('{"error":"context length"}', 413));
      expect(
        client.generate(_request()),
        throwsA(isA<AiProviderContextTooLargeException>()),
      );
    });

    test('does not send an already cancelled request', () async {
      var calls = 0;
      final client = OpenAiProviderClient(
        baseUri: Uri.parse('https://example.test/v1'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient((_) async {
          calls += 1;
          return http.Response(_openAiSse('late'), 200);
        }),
      );
      final cancellation = AiRequestCancellation()..cancel();

      expect(
        client.generate(_request(), cancellation: cancellation),
        throwsA(isA<AiProviderCancelledException>()),
      );
      expect(calls, 0);
    });

    test('requests the models endpoint with bearer authentication', () async {
      late http.Request request;
      final client = OpenAiProviderClient(
        baseUri: Uri.parse('https://example.test/v1'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient((value) async {
          request = value;
          return http.Response(_models('model-a'), 200);
        }),
      );

      expect(await client.listModels(), ['model-a']);
      expect(request.url.toString(), 'https://example.test/v1/models');
      expect(request.headers['Authorization'], 'Bearer unit-test-secret');
    });

    test('sorts, trims, and deduplicates model identifiers', () async {
      final client = _openAi(
        _utf8Response(
          '{"data":[{"id":" z-model "},{"id":"a-model"},{"id":"a-model"}]}',
          200,
        ),
      );

      expect(await client.listModels(), ['a-model', 'z-model']);
    });

    test(
      'custom compatible client omits authorization when key is empty',
      () async {
        late http.Request request;
        final client = OpenAiCompatibleProviderClient(
          baseUri: Uri.parse('http://127.0.0.1:1234/v1'),
          apiKey: '',
          httpClient: MockClient((value) async {
            request = value;
            return http.Response(_models('local-model'), 200);
          }),
        );

        await client.listModels();
        expect(request.headers.containsKey('Authorization'), isFalse);
      },
    );

    test('maps 401 to an authentication error', () async {
      expect(
        _openAi(http.Response('{}', 401)).listModels(),
        throwsA(isA<AiProviderAuthenticationException>()),
      );
    });

    test('maps 403 to an authentication error', () async {
      expect(
        _openAi(http.Response('{}', 403)).listModels(),
        throwsA(isA<AiProviderRequestRejectedException>()),
      );
    });

    test('maps a missing models endpoint to an endpoint error', () async {
      expect(
        _openAi(http.Response('{}', 404)).listModels(),
        throwsA(isA<AiProviderEndpointException>()),
      );
    });

    test('maps models rate limits separately from network errors', () async {
      expect(
        _openAi(http.Response('{}', 429)).listModels(),
        throwsA(isA<AiProviderRateLimitedException>()),
      );
    });

    test('maps a server failure to a safe server error', () async {
      expect(
        _openAi(http.Response('server trace and secret', 503)).listModels(),
        throwsA(
          isA<AiProviderServerException>().having(
            (error) => error.toString(),
            'safe text',
            isNot(contains('server trace')),
          ),
        ),
      );
    });

    test('maps unexpected status to a protocol error', () async {
      expect(
        _openAi(http.Response('{}', 409)).listModels(),
        throwsA(isA<AiProviderProtocolException>()),
      );
    });

    test('rejects non-JSON responses', () async {
      expect(
        _openAi(http.Response('<html>bad gateway</html>', 200)).listModels(),
        throwsA(isA<AiProviderProtocolException>()),
      );
    });

    test('rejects malformed model payloads', () async {
      expect(
        _openAi(http.Response('{"models":[]}', 200)).listModels(),
        throwsA(isA<AiProviderProtocolException>()),
      );
    });

    test('rejects an empty model list', () async {
      expect(
        _openAi(http.Response('{"data":[]}', 200)).listModels(),
        throwsA(isA<AiProviderProtocolException>()),
      );
    });

    test('maps ClientException to a network error', () async {
      final client = OpenAiProviderClient(
        baseUri: Uri.parse('https://example.test/v1'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient(
          (_) async => throw http.ClientException('offline'),
        ),
      );

      expect(client.listModels(), throwsA(isA<AiProviderNetworkException>()));
    });

    test('maps TLS client failures to a handshake error', () async {
      final client = OpenAiProviderClient(
        baseUri: Uri.parse('https://example.test/v1'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient(
          (_) async => throw http.ClientException('HandshakeException'),
        ),
      );

      expect(client.listModels(), throwsA(isA<AiProviderHandshakeException>()));
    });

    test('maps a slow response to a timeout error', () async {
      final client = OpenAiProviderClient(
        baseUri: Uri.parse('https://example.test/v1'),
        apiKey: 'unit-test-secret',
        timeout: const Duration(milliseconds: 1),
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return http.Response(_models('late-model'), 200);
        }),
      );

      expect(client.listModels(), throwsA(isA<AiProviderTimeoutException>()));
    });

    test('fails clearly after close', () async {
      final client = _openAi(http.Response(_models('model-a'), 200));
      client.close();

      expect(client.listModels(), throwsA(isA<AiProviderNetworkException>()));
    });

    test('parses an SSE event split across byte chunks', () async {
      final client = OpenAiProviderClient(
        baseUri: Uri.parse('https://example.test/v1'),
        apiKey: 'unit-test-secret',
        httpClient: _ChunkedClient([
          utf8.encode('data: {"choices":[{"delta":{"cont'),
          utf8.encode('ent":"split"}}]}\n\ndata: [DO'),
          utf8.encode('NE]\n\n'),
        ]),
      );

      expect(await client.streamGenerate(_request()).toList(), ['split']);
    });

    test('parses multiple SSE events from one byte chunk', () async {
      final client = OpenAiProviderClient(
        baseUri: Uri.parse('https://example.test/v1'),
        apiKey: 'unit-test-secret',
        httpClient: _ChunkedClient([
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"one"}}]}\n\n'
            'data: {"choices":[{"delta":{"content":"two"}}]}\n\n'
            'data: [DONE]\n\n',
          ),
        ]),
      );

      expect(await client.streamGenerate(_request()).toList(), ['one', 'two']);
    });

    test(
      'treats DONE without a provider finish reason as a normal stop',
      () async {
        final client = OpenAiProviderClient(
          baseUri: Uri.parse('https://example.test/v1'),
          apiKey: 'unit-test-secret',
          httpClient: _ChunkedClient([
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"complete"}}]}\n\n'
              'data: [DONE]\n\n',
            ),
          ]),
        );

        final events = await client.streamEvents(_request()).toList();
        expect(events.last.finishReason, AiFinishReason.stop);
      },
    );

    test('diagnostics never contain authorization credentials', () async {
      final diagnostics = _RecordingDiagnostics();
      final client = OpenAiProviderClient(
        baseUri: Uri.parse('https://example.test/v1'),
        apiKey: 'unit-test-secret',
        diagnostics: diagnostics,
        httpClient: MockClient(
          (_) async => http.Response(_models('model-a'), 200),
        ),
      );

      await client.listModels();
      expect(diagnostics.events.single.apiKeyPresent, isTrue);
      expect(
        diagnostics.events.single.safeMessage,
        isNot(contains('unit-test-secret')),
      );
      expect(diagnostics.events.single.path, '/v1/models');
    });
  });

  group('Gemini client', () {
    test('streams Gemini candidate text chunks', () async {
      final client = _gemini(
        _utf8Response(
          'data: {"candidates":[{"content":{"parts":[{"text":"rain"}]}}]}\n\n'
          'data: {"candidates":[{"content":{"parts":[{"text":" sound"}]},"finishReason":"STOP"}]}\n\n',
          200,
        ),
      );
      expect(await client.streamGenerate(_request()).toList(), [
        'rain',
        ' sound',
      ]);
    });

    test('Gemini joins all text parts in one candidate', () async {
      final client = _gemini(
        _utf8Response(
          'data: {"candidates":[{"content":{"parts":[{"text":"rain"},{"text":" sound"}]},"finishReason":"STOP"}]}\n\n',
          200,
        ),
      );
      expect(await client.streamGenerate(_request()).join(), 'rain sound');
    });

    test(
      'Gemini handles UTF-8 and SSE boundaries with a final unpadded event',
      () async {
        final first = utf8.encode(
          'data: {"candidates":[{"content":{"parts":[{"text":"你好🙂"}]}}]}\n\n',
        );
        final finalEvent = utf8.encode(
          'data: {"candidates":[{"content":{"parts":[{"text":"世界"}]},"finishReason":"STOP"}]}',
        );
        final client = GeminiProviderClient(
          baseUri: Uri.parse('https://generative.test/v1beta'),
          apiKey: 'gemini-unit-secret',
          httpClient: _ChunkedClient([
            first.sublist(0, first.length - 2),
            [...first.sublist(first.length - 2), ...finalEvent.sublist(0, 11)],
            finalEvent.sublist(11),
          ]),
        );

        expect(await client.streamGenerate(_request()).join(), '你好🙂世界');
      },
    );

    test('Gemini preserves mixed delta and cumulative multi-part events', () async {
      final diagnostics = _RecordingDiagnostics();
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'gemini-unit-secret',
        diagnostics: diagnostics,
        httpClient: MockClient(
          (_) async => _utf8Response(
            'data: {"candidates":[{"content":{"parts":[{"text":"第一"},{"text":"段"}]}}]}\n\n'
            'data: {"candidates":[{"content":{"parts":[{"text":"第一段继续"}]}}]}\n\n'
            'data: {"candidates":[{"content":{"parts":[{"text":"，结束"}]},"finishReason":"STOP"}]}',
            200,
          ),
        ),
      );

      expect(await client.streamGenerate(_request()).join(), '第一段继续，结束');
      final completed = diagnostics.events.last;
      expect(completed.maxTextPartsPerEvent, 2);
      expect(completed.streamNormalization, 'mixed');
    });

    test('Gemini cumulative events append only the new suffix', () async {
      final client = _gemini(
        _utf8Response(
          'data: {"candidates":[{"content":{"parts":[{"text":"你"}]}}]}\n\n'
          'data: {"candidates":[{"content":{"parts":[{"text":"你好"}]},"finishReason":"STOP"}]}\n\n',
          200,
        ),
      );
      expect(await client.streamGenerate(_request()).join(), '你好');
    });

    test('Gemini max tokens maps to length finish reason', () async {
      final client = _gemini(
        _utf8Response(
          'data: {"candidates":[{"content":{"parts":[{"text":"partial"}]},"finishReason":"MAX_TOKENS"}]}\n\n',
          200,
        ),
      );
      final events = await client.streamEvents(_request()).toList();
      expect(events.last.finishReason, AiFinishReason.length);
    });

    test(
      'Gemini stream diagnostics report parts and authoritative buffer',
      () async {
        final diagnostics = _RecordingDiagnostics();
        final client = GeminiProviderClient(
          baseUri: Uri.parse('https://generative.test/v1beta'),
          apiKey: 'gemini-unit-secret',
          diagnostics: diagnostics,
          httpClient: MockClient(
            (_) async => _utf8Response(
              'data: {"candidates":[{"content":{"parts":[{"text":"你"},{"text":"好"}]}}]}\n\n'
              'data: {"candidates":[{"content":{"parts":[{"text":"你好呀"}]},"finishReason":"STOP"}]}\n\n',
              200,
            ),
          ),
        );

        expect(await client.streamGenerate(_request()).join(), '你好呀');
        final completed = diagnostics.events.lastWhere(
          (event) => event.stage == 'stream.response.completed',
        );
        expect(completed.streamEventCount, 2);
        expect(completed.candidateCount, 2);
        expect(completed.partCount, 3);
        expect(completed.textPartCount, 3);
        expect(completed.receivedCharacterCount, 3);
        expect(completed.authoritativeCharacterCount, 3);
        expect(completed.finishReason, 'stop');
        expect(completed.streamNormalization, 'mixed');
        expect(completed.safeMessage, isNot(contains('你好')));
      },
    );

    test(
      'Gemini response object without candidates is legal providerEmpty',
      () async {
        final client = _gemini(
          _utf8Response(
            'data: {"usageMetadata":{"promptTokenCount":4},"modelVersion":"gemini-test","responseId":"response-1"}\n\n',
            200,
          ),
        );

        await expectLater(
          client.streamEvents(_request()).drain<void>(),
          throwsA(
            isA<AiProviderInvalidResponseException>()
                .having(
                  (error) => error.emptyKind,
                  'emptyKind',
                  AiEmptyResponseKind.providerEmpty,
                )
                .having(
                  (error) => error.responseDiagnostics?.httpStatus,
                  'httpStatus',
                  200,
                )
                .having(
                  (error) => error.responseDiagnostics?.rawSseEventCount,
                  'rawSseEventCount',
                  1,
                )
                .having(
                  (error) =>
                      error.responseDiagnostics?.parsedResponseObjectCount,
                  'parsedResponseObjectCount',
                  1,
                )
                .having(
                  (error) => error.responseDiagnostics?.candidateEventCount,
                  'candidateEventCount',
                  0,
                )
                .having(
                  (error) => error.responseDiagnostics?.streamClosedNormally,
                  'streamClosedNormally',
                  isTrue,
                )
                .having(
                  (error) => error.responseDiagnostics?.abnormalEof,
                  'abnormalEof',
                  isFalse,
                ),
          ),
        );
      },
    );

    test('Gemini zero-event EOF is interrupted before content', () async {
      final client = _gemini(
        _utf8Response('', 200, headers: {'content-type': 'text/event-stream'}),
      );

      await expectLater(
        client.streamEvents(_request()).drain<void>(),
        throwsA(
          isA<AiProviderInterruptedBeforeContentException>()
              .having(
                (error) => error.causeType,
                'causeType',
                'responseBodyInterrupted',
              )
              .having(
                (error) => error.responseDiagnostics.httpStatus,
                'httpStatus',
                200,
              )
              .having(
                (error) => error.responseDiagnostics.streamEventCount,
                'streamEventCount',
                0,
              )
              .having(
                (error) => error.responseDiagnostics.rawSseEventCount,
                'rawSseEventCount',
                0,
              )
              .having(
                (error) => error.responseDiagnostics.parsedResponseObjectCount,
                'parsedResponseObjectCount',
                0,
              )
              .having(
                (error) => error.responseDiagnostics.firstByteReceived,
                'firstByteReceived',
                isFalse,
              )
              .having(
                (error) => error.responseDiagnostics.firstSseEventReceived,
                'firstSseEventReceived',
                isFalse,
              )
              .having(
                (error) => error.responseDiagnostics.responseContentType,
                'responseContentType',
                'text/event-stream',
              ),
        ),
      );
    });

    test('Gemini candidate with no parts is candidateEmpty', () async {
      final client = _gemini(
        _utf8Response(
          'data: {"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}\n\n',
          200,
        ),
      );

      await expectLater(
        client.streamEvents(_request()).drain<void>(),
        throwsA(
          isA<AiProviderInvalidResponseException>()
              .having(
                (error) => error.emptyKind,
                'emptyKind',
                AiEmptyResponseKind.candidateEmpty,
              )
              .having(
                (error) => error.responseDiagnostics?.partCount,
                'partCount',
                0,
              )
              .having(
                (error) => error.responseDiagnostics?.textPartCount,
                'textPartCount',
                0,
              ),
        ),
      );
    });

    test('Gemini candidate with non-text parts is candidateEmpty', () async {
      final client = _gemini(
        _utf8Response(
          'data: {"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"AA=="}}]},"finishReason":"STOP"}]}\n\n',
          200,
        ),
      );

      await expectLater(
        client.streamEvents(_request()).drain<void>(),
        throwsA(
          isA<AiProviderInvalidResponseException>()
              .having(
                (error) => error.emptyKind,
                'emptyKind',
                AiEmptyResponseKind.candidateEmpty,
              )
              .having(
                (error) => error.responseDiagnostics?.partCount,
                'partCount',
                1,
              )
              .having(
                (error) => error.responseDiagnostics?.textPartCount,
                'textPartCount',
                0,
              ),
        ),
      );
    });

    test('Gemini whitespace-only text is classified separately', () async {
      final client = _gemini(
        http.Response(
          '{"candidates":[{"content":{"parts":[{"text":"   \\n"}]},"finishReason":"STOP"}]}',
          200,
        ),
      );

      await expectLater(
        client.generate(_request()),
        throwsA(
          isA<AiProviderInvalidResponseException>().having(
            (error) => error.emptyKind,
            'emptyKind',
            AiEmptyResponseKind.whitespaceOnly,
          ),
        ),
      );
    });

    test('Gemini safety finish without text is filteredEmpty', () async {
      final client = _gemini(
        _utf8Response(
          'data: {"candidates":[{"finishReason":"SAFETY"}]}\n\n',
          200,
        ),
      );

      await expectLater(
        client.streamEvents(_request()).drain<void>(),
        throwsA(
          isA<AiProviderInvalidResponseException>()
              .having(
                (error) => error.emptyKind,
                'emptyKind',
                AiEmptyResponseKind.filteredEmpty,
              )
              .having(
                (error) => error.responseDiagnostics?.rawFinishReason,
                'rawFinishReason',
                'SAFETY',
              ),
        ),
      );
    });

    for (final reason in const [
      'SAFETY',
      'BLOCKLIST',
      'PROHIBITED_CONTENT',
      'OTHER',
    ]) {
      test('Gemini promptFeedback $reason is promptBlocked', () async {
        final client = _gemini(
          _utf8Response(
            'data: {"promptFeedback":{"blockReason":"$reason","safetyRatings":[{"category":"HARM_CATEGORY_DANGEROUS_CONTENT","probability":"HIGH","blocked":true}]},"usageMetadata":{"promptTokenCount":12},"modelVersion":"gemini-test","responseId":"response-1","modelStatus":{}}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        );

        await expectLater(
          client.streamEvents(_request()).drain<void>(),
          throwsA(
            isA<AiProviderInvalidResponseException>()
                .having(
                  (error) => error.emptyKind,
                  'emptyKind',
                  AiEmptyResponseKind.promptBlocked,
                )
                .having(
                  (error) => error.responseDiagnostics?.promptBlockReason,
                  'promptBlockReason',
                  reason,
                )
                .having(
                  (error) => error.responseDiagnostics?.rawSseEventCount,
                  'rawSseEventCount',
                  1,
                )
                .having(
                  (error) =>
                      error.responseDiagnostics?.parsedResponseObjectCount,
                  'parsedResponseObjectCount',
                  1,
                )
                .having(
                  (error) => error.responseDiagnostics?.candidateEventCount,
                  'candidateEventCount',
                  0,
                )
                .having(
                  (error) => error.responseDiagnostics?.textEventCount,
                  'textEventCount',
                  0,
                )
                .having(
                  (error) => error.responseDiagnostics?.promptFeedbackPresent,
                  'promptFeedbackPresent',
                  isTrue,
                )
                .having(
                  (error) =>
                      error.responseDiagnostics?.promptSafetyRatingsCount,
                  'promptSafetyRatingsCount',
                  1,
                )
                .having(
                  (error) => error.responseDiagnostics?.topLevelKeys,
                  'topLevelKeys',
                  contains('promptFeedback'),
                )
                .having(
                  (error) => error.responseDiagnostics?.usageMetadataPresent,
                  'usageMetadataPresent',
                  isTrue,
                )
                .having(
                  (error) => error.responseDiagnostics?.responseIdPresent,
                  'responseIdPresent',
                  isTrue,
                )
                .having(
                  (error) => error.responseDiagnostics?.streamClosedNormally,
                  'streamClosedNormally',
                  isTrue,
                )
                .having(
                  (error) => error.responseDiagnostics?.abnormalEof,
                  'abnormalEof',
                  isFalse,
                ),
          ),
        );
      });
    }

    test('Gemini content without finish reason is interrupted', () async {
      final client = _gemini(
        _utf8Response(
          'data: {"candidates":[{"content":{"parts":[{"text":"partial"}]}}]}\n\n',
          200,
        ),
      );
      await expectLater(
        client.streamEvents(_request()).drain<void>(),
        throwsA(isA<AiProviderInterruptedException>()),
      );
    });

    test(
      'Gemini abnormal EOF diagnostics retain part counters and hash',
      () async {
        final diagnostics = _RecordingDiagnostics();
        final client = GeminiProviderClient(
          baseUri: Uri.parse('https://generative.test/v1beta'),
          apiKey: 'gemini-unit-secret',
          diagnostics: diagnostics,
          httpClient: MockClient(
            (_) async => _utf8Response(
              'data: {"candidates":[{"content":{"parts":[{"text":"partial"},{"text":" data"}]}}]}\n\n',
              200,
            ),
          ),
        );

        await expectLater(
          client.streamEvents(_request()).drain<void>(),
          throwsA(isA<AiProviderInterruptedException>()),
        );
        final failed = diagnostics.events.last;
        expect(failed.statusCode, 200);
        expect(failed.streamEventCount, 1);
        expect(failed.candidateCount, 1);
        expect(failed.textPartCount, 2);
        expect(failed.maxTextPartsPerEvent, 2);
        expect(failed.rawReceivedCharacterCount, 12);
        expect(failed.adapterHash, isNotEmpty);
        expect(failed.streamClosedNormally, isFalse);
      },
    );

    test('Gemini malformed event after partial content is interrupted', () async {
      final client = _gemini(
        _utf8Response(
          'data: {"candidates":[{"content":{"parts":[{"text":"partial"}]}}]}\n\n'
          'data: {malformed}\n\n',
          200,
        ),
      );
      await expectLater(
        client.streamEvents(_request()).drain<void>(),
        throwsA(
          isA<AiProviderInterruptedException>().having(
            (error) => error.causeType,
            'causeType',
            'InvalidResponse',
          ),
        ),
      );
    });

    test('Gemini idle timeout after content is an interruption', () async {
      final diagnostics = _RecordingDiagnostics();
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'gemini-unit-secret',
        timeout: const Duration(milliseconds: 15),
        diagnostics: diagnostics,
        httpClient: _DelayedChunkedClient([
          _DelayedChunk(
            Duration.zero,
            utf8.encode(
              'data: {"candidates":[{"content":{"parts":[{"text":"partial"}]}}]}\n\n',
            ),
          ),
          _DelayedChunk(
            const Duration(milliseconds: 50),
            utf8.encode('data: {"candidates":[{"finishReason":"STOP"}]}\n\n'),
          ),
        ]),
      );

      await expectLater(
        client.streamEvents(_request()).drain<void>(),
        throwsA(
          isA<AiProviderInterruptedException>().having(
            (error) => error.timeoutType,
            'timeoutType',
            'idle',
          ),
        ),
      );
      expect(diagnostics.events, isNotEmpty);
      final failed = diagnostics.events.last;
      expect(failed.timeoutType, 'idle');
      expect(failed.streamClosedNormally, isFalse);
      expect(failed.receivedCharacterCount, 7);
      expect(failed.rawFinishReason, isNull);
    });

    test('Gemini SocketException after partial content is interrupted', () async {
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'gemini-unit-secret',
        httpClient: _ErrorAfterChunksClient(
          chunks: [
            utf8.encode(
              'data: {"candidates":[{"content":{"parts":[{"text":"partial"}]}}]}\n\n',
            ),
          ],
          error: const SocketException('synthetic disconnect'),
        ),
      );

      await expectLater(
        client.streamEvents(_request()).drain<void>(),
        throwsA(
          isA<AiProviderInterruptedException>().having(
            (error) => error.causeType,
            'causeType',
            'SocketException',
          ),
        ),
      );
    });

    test('Gemini ClientException after partial content is interrupted', () async {
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'gemini-unit-secret',
        httpClient: _ErrorAfterChunksClient(
          chunks: [
            utf8.encode(
              'data: {"candidates":[{"content":{"parts":[{"text":"partial"}]}}]}\n\n',
            ),
          ],
          error: http.ClientException('synthetic disconnect'),
        ),
      );

      await expectLater(
        client.streamEvents(_request()).drain<void>(),
        throwsA(
          isA<AiProviderInterruptedException>().having(
            (error) => error.causeType,
            'causeType',
            'ClientException',
          ),
        ),
      );
    });

    test(
      'Gemini SocketException before content is retryable transport',
      () async {
        final client = GeminiProviderClient(
          baseUri: Uri.parse('https://generative.test/v1beta'),
          apiKey: 'gemini-unit-secret',
          httpClient: _ErrorAfterChunksClient(
            chunks: const [],
            error: const SocketException('synthetic disconnect'),
          ),
        );

        await expectLater(
          client.streamEvents(_request()).drain<void>(),
          throwsA(
            isA<AiProviderInterruptedBeforeContentException>().having(
              (error) => error.causeType,
              'causeType',
              'SocketException',
            ),
          ),
        );
      },
    );

    test(
      'Gemini ClientException before content is retryable transport',
      () async {
        final client = GeminiProviderClient(
          baseUri: Uri.parse('https://generative.test/v1beta'),
          apiKey: 'gemini-unit-secret',
          httpClient: _ErrorAfterChunksClient(
            chunks: const [],
            error: http.ClientException('synthetic disconnect'),
          ),
        );

        await expectLater(
          client.streamEvents(_request()).drain<void>(),
          throwsA(
            isA<AiProviderInterruptedBeforeContentException>().having(
              (error) => error.causeType,
              'causeType',
              'ClientException',
            ),
          ),
        );
      },
    );

    test(
      'Gemini timeout before any response body does not create partial content',
      () async {
        final client = GeminiProviderClient(
          baseUri: Uri.parse('https://generative.test/v1beta'),
          apiKey: 'gemini-unit-secret',
          timeout: const Duration(milliseconds: 15),
          httpClient: _DelayedChunkedClient([
            _DelayedChunk(
              const Duration(milliseconds: 50),
              utf8.encode(
                'data: {"candidates":[{"content":{"parts":[{"text":"late"}]},"finishReason":"STOP"}]}\n\n',
              ),
            ),
          ]),
        );

        await expectLater(
          client.streamEvents(_request()).drain<void>(),
          throwsA(
            isA<AiProviderInterruptedBeforeContentException>()
                .having(
                  (error) => error.causeType,
                  'causeType',
                  'TimeoutException',
                )
                .having(
                  (error) => error.timeoutType,
                  'timeoutType',
                  'firstByte',
                ),
          ),
        );
      },
    );

    test('Gemini active chunks are not subject to an overall timeout', () async {
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'gemini-unit-secret',
        timeout: const Duration(milliseconds: 20),
        httpClient: _DelayedChunkedClient([
          for (final text in const ['a', 'b', 'c', 'd'])
            _DelayedChunk(
              const Duration(milliseconds: 12),
              utf8.encode(
                'data: {"candidates":[{"content":{"parts":[{"text":"$text"}]}}]}\n\n',
              ),
            ),
          _DelayedChunk(
            const Duration(milliseconds: 12),
            utf8.encode(
              'data: {"candidates":[{"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":4,"totalTokenCount":9}}\n\n',
            ),
          ),
        ]),
      );

      final stopwatch = Stopwatch()..start();
      final events = await client.streamEvents(_request()).toList();
      expect(stopwatch.elapsed, greaterThan(const Duration(milliseconds: 40)));
      expect(events.where((event) => !event.isTerminal).length, 4);
      expect(events.last.finishReason, AiFinishReason.stop);
    });

    test('builds Gemini roles and generation configuration', () async {
      late http.Request sent;
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'gemini-unit-secret',
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(_geminiResponse('ok'), 200);
        }),
      );
      await client.generate(_request());
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(sent.url.path, contains('test-model:generateContent'));
      expect(sent.url.queryParameters['alt'], isNull);
      expect(body['systemInstruction'], isA<Map>());
      expect((body['contents'] as List).map((item) => item['role']), [
        'user',
        'model',
      ]);
      expect((body['generationConfig'] as Map)['maxOutputTokens'], 512);
    });

    test('uses Gemini JSON response MIME for structured requests', () async {
      late http.Request sent;
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'gemini-unit-secret',
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(_geminiResponse('{}'), 200);
        }),
      );
      await client.generate(_request(structuredJson: true));
      expect(
        (jsonDecode(sent.body) as Map)['generationConfig'],
        containsPair('responseMimeType', 'application/json'),
      );
    });

    test('accepts a models-prefixed Gemini model id', () async {
      late http.Request sent;
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'gemini-unit-secret',
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(_geminiResponse('ok'), 200);
        }),
      );
      await client.generate(_request(model: 'models/gemini-test'));
      expect(sent.url.path, contains('/models/gemini-test:generateContent'));
    });

    test('rejects malformed Gemini stream content', () async {
      final client = _gemini(http.Response('data: {"data":[]}\n\n', 200));
      expect(
        client.generate(_request()),
        throwsA(isA<AiProviderInvalidResponseException>()),
      );
    });

    test('maps Gemini rate limits', () async {
      final client = _gemini(http.Response('{"error":"quota"}', 429));
      expect(
        client.generate(_request()),
        throwsA(isA<AiProviderRateLimitedException>()),
      );
    });

    test('maps Gemini context limits', () async {
      final client = _gemini(http.Response('{"error":"token limit"}', 413));
      expect(
        client.generate(_request()),
        throwsA(isA<AiProviderContextTooLargeException>()),
      );
    });

    test('uses the models endpoint and keeps the key out of the URL', () async {
      late http.Request request;
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'gemini-unit-secret',
        httpClient: MockClient((value) async {
          request = value;
          return http.Response(_geminiModels('gemini-test'), 200);
        }),
      );

      expect(await client.listModels(), ['gemini-test']);
      expect(request.url.path, '/v1beta/models');
      expect(request.url.queryParameters['pageSize'], '1000');
      expect(request.url.toString(), isNot(contains('gemini-unit-secret')));
      expect(request.headers['x-goog-api-key'], 'gemini-unit-secret');
    });

    test('sorts and deduplicates Gemini model names', () async {
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient(
          (_) async => http.Response(
            '{"models":['
            '{"name":"models/z","supportedGenerationMethods":["generateContent"]},'
            '{"name":"a","supportedGenerationMethods":["generateContent"]},'
            '{"name":"models/a","supportedGenerationMethods":["generateContent"]}'
            ']}',
            200,
          ),
        ),
      );

      expect(await client.listModels(), ['a', 'z']);
    });

    test('filters models that cannot generate content', () async {
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient(
          (_) async => http.Response(
            '{"models":['
            '{"name":"models/embed-only","supportedGenerationMethods":["embedContent"]},'
            '{"name":"models/gemini-generate","displayName":"Gemini Generate",'
            '"supportedGenerationMethods":["generateContent"],'
            '"inputTokenLimit":1000,"outputTokenLimit":100}'
            ']}',
            200,
          ),
        ),
      );

      expect(await client.listModels(), ['gemini-generate']);
    });

    test(
      'test connection selects a real model when none is configured',
      () async {
        final requests = <http.Request>[];
        final client = GeminiProviderClient(
          baseUri: Uri.parse('https://generative.test/v1beta'),
          apiKey: 'unit-test-secret',
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.method == 'GET') {
              return http.Response(_geminiModels('gemini-live'), 200);
            }
            return http.Response(_geminiResponse('OK'), 200);
          }),
        );

        final result = await client.testConnection();

        expect(result.models, ['gemini-live']);
        expect(result.verifiedModel, 'gemini-live');
        expect(requests, hasLength(2));
        expect(requests.last.url.path, contains('gemini-live:generateContent'));
        expect(requests.last.headers['x-goog-api-key'], 'unit-test-secret');
        expect(requests.last.headers.containsKey('Authorization'), isFalse);
        final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
        expect(body.keys, ['contents']);
        expect(body.containsKey('systemInstruction'), isFalse);
        expect(body.containsKey('generationConfig'), isFalse);
      },
    );

    test(
      'connection skips a declared model that only supports Interactions API',
      () async {
        final requests = <http.Request>[];
        final client = GeminiProviderClient(
          baseUri: Uri.parse('https://generative.test/v1beta'),
          apiKey: 'unit-test-secret',
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.method == 'GET') {
              return http.Response(
                '{"models":['
                '{"name":"models/antigravity-preview-05-2026",'
                '"supportedGenerationMethods":["generateContent"]},'
                '{"name":"models/gemini-2.0-flash-lite",'
                '"supportedGenerationMethods":["generateContent"]},'
                '{"name":"models/gemini-3.1-flash-lite",'
                '"supportedGenerationMethods":["generateContent"]}'
                ']}',
                200,
              );
            }
            if (request.url.path.contains('antigravity')) {
              return http.Response(
                '{"error":{"code":400,"status":"INVALID_ARGUMENT",'
                '"message":"This model only supports Interactions API."}}',
                400,
              );
            }
            return http.Response(_geminiResponse('OK'), 200);
          }),
        );

        final result = await client.testConnection(
          preferredModel: 'antigravity-preview-05-2026',
        );

        expect(result.verifiedModel, 'gemini-3.1-flash-lite');
        expect(result.verifiedModels, ['gemini-3.1-flash-lite']);
        expect(result.incompatibleModels, ['antigravity-preview-05-2026']);
        expect(requests.map((request) => request.url.path), [
          '/v1beta/models',
          '/v1beta/models/antigravity-preview-05-2026:generateContent',
          '/v1beta/models/gemini-3.1-flash-lite:generateContent',
        ]);
      },
    );

    test(
      'connection prefers a normal Gemini text model when unselected',
      () async {
        final requestedModels = <String>[];
        final client = GeminiProviderClient(
          baseUri: Uri.parse('https://generative.test/v1beta'),
          apiKey: 'unit-test-secret',
          httpClient: MockClient((request) async {
            if (request.method == 'GET') {
              return http.Response(
                '{"models":['
                '{"name":"models/antigravity-preview-05-2026",'
                '"supportedGenerationMethods":["generateContent"]},'
                '{"name":"models/gemini-3.1-flash-lite",'
                '"supportedGenerationMethods":["generateContent"]}'
                ']}',
                200,
              );
            }
            requestedModels.add(request.url.pathSegments.last);
            return http.Response(_geminiResponse('OK'), 200);
          }),
        );

        final result = await client.testConnection();

        expect(result.verifiedModel, 'gemini-3.1-flash-lite');
        expect(requestedModels.single, contains('gemini-3.1-flash-lite'));
      },
    );

    test(
      'connection failure preserves models and safe Google error details',
      () async {
        final diagnostics = _RecordingDiagnostics();
        final client = GeminiProviderClient(
          baseUri: Uri.parse('https://generative.test/v1beta'),
          apiKey: 'unit-test-secret',
          diagnostics: diagnostics,
          httpClient: MockClient((request) async {
            if (request.method == 'GET') {
              return http.Response(_geminiModels('gemini-live'), 200);
            }
            return http.Response(
              '{"error":{"code":400,"status":"INVALID_ARGUMENT",'
              '"message":"A request field is invalid.","details":['
              '{"@type":"type.googleapis.com/google.rpc.ErrorInfo",'
              '"reason":"MALFORMED_REQUEST"}]}}',
              400,
            );
          }),
        );

        await expectLater(
          client.testConnection(),
          throwsA(
            isA<AiProviderConnectionTestException>()
                .having((error) => error.availableModels, 'available models', [
                  'gemini-live',
                ])
                .having(
                  (error) => error.temporaryModel,
                  'temporary model',
                  'gemini-live',
                ),
          ),
        );
        final failed = diagnostics.events.lastWhere(
          (event) => event.stage == 'minimal_generate.request.failed',
        );
        expect(failed.statusCode, 400);
        expect(failed.providerErrorCode, 400);
        expect(failed.providerErrorStatus, 'INVALID_ARGUMENT');
        expect(failed.providerErrorMessage, 'A request field is invalid.');
        expect(failed.providerErrorReason, 'MALFORMED_REQUEST');
        expect(failed.safeMessage, isNot(contains('unit-test-secret')));
      },
    );

    test('maps Gemini authentication failures', () async {
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient((_) async => http.Response('{}', 401)),
      );

      expect(
        client.listModels(),
        throwsA(isA<AiProviderAuthenticationException>()),
      );
    });

    test('maps Gemini API_KEY_INVALID returned as HTTP 400', () async {
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient(
          (_) async => http.Response(
            '{"error":{"code":400,"status":"API_KEY_INVALID",'
            '"message":"API key not valid."}}',
            400,
          ),
        ),
      );

      expect(
        client.listModels(),
        throwsA(
          isA<AiProviderAuthenticationException>().having(
            (error) => error.message,
            'message',
            allOf(contains('HTTP 400'), contains('API_KEY_INVALID')),
          ),
        ),
      );
    });

    test('maps Gemini permission failures separately', () async {
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient(
          (_) async =>
              http.Response('{"error":{"status":"PERMISSION_DENIED"}}', 403),
        ),
      );

      expect(
        client.listModels(),
        throwsA(isA<AiProviderRequestRejectedException>()),
      );
    });

    test('maps Gemini endpoint failures separately', () async {
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient(
          (_) async => http.Response('{"error":{"status":"NOT_FOUND"}}', 404),
        ),
      );

      expect(client.listModels(), throwsA(isA<AiProviderEndpointException>()));
    });

    test('does not send a Gemini request when the key is missing', () async {
      var requestCount = 0;
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: '',
        httpClient: MockClient((_) async {
          requestCount += 1;
          return http.Response('{}', 200);
        }),
      );

      expect(
        client.listModels(),
        throwsA(isA<AiProviderValidationException>()),
      );
      expect(requestCount, 0);
    });

    test('rejects a malformed Gemini response', () async {
      final client = GeminiProviderClient(
        baseUri: Uri.parse('https://generative.test/v1beta'),
        apiKey: 'unit-test-secret',
        httpClient: MockClient((_) async => http.Response('{"data":[]}', 200)),
      );

      expect(client.listModels(), throwsA(isA<AiProviderProtocolException>()));
    });
  });

  group('provider registry and cancellation', () {
    test('creates a separate adapter for every provider identity', () {
      final registry = AiProviderRegistry(
        httpClientFactory: () =>
            MockClient((_) async => http.Response('{}', 200)),
      );

      expect(
        registry.create(_config(AiProviderType.openai), 'key'),
        isA<OpenAiProviderClient>(),
      );
      expect(
        registry.create(_config(AiProviderType.gemini), 'key'),
        isA<GeminiProviderClient>(),
      );
      expect(
        registry.create(_config(AiProviderType.deepseek), 'key'),
        isA<DeepSeekProviderClient>(),
      );
      expect(
        registry.create(_config(AiProviderType.kimi), 'key'),
        isA<KimiProviderClient>(),
      );
      expect(
        registry.create(_config(AiProviderType.custom), ''),
        isA<OpenAiCompatibleProviderClient>(),
      );
    });

    test('rejects unsupported URL schemes and embedded credentials', () {
      final registry = AiProviderRegistry(
        httpClientFactory: () =>
            MockClient((_) async => http.Response('{}', 200)),
      );
      for (final url in [
        'file:///tmp/models',
        'https://user:pass@example.test/v1',
      ]) {
        expect(
          () =>
              registry.create(_config(AiProviderType.custom, baseUrl: url), ''),
          throwsA(isA<AiProviderValidationException>()),
        );
      }
    });

    test('normalizes a saved DeepSeek endpoint back to its base URL', () async {
      final requests = <http.Request>[];
      final registry = AiProviderRegistry(
        diagnostics: const NoopAiNetworkDiagnostics(),
        httpClientFactory: () => MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response(_models('deepseek-v4-flash'), 200);
          }
          return http.Response(_openAiSse('ok'), 200);
        }),
      );
      final config = _config(
        AiProviderType.deepseek,
        baseUrl: 'https://api.deepseek.com/v1/chat/completions',
      );
      final client = registry.create(config, 'unit-test-secret');

      await client.listModels();
      await client.streamGenerate(_request()).drain<void>();

      expect(requests[0].url.toString(), 'https://api.deepseek.com/models');
      expect(
        requests[1].url.toString(),
        'https://api.deepseek.com/chat/completions',
      );
      expect(
        requests.every((request) => !request.url.path.contains('/v1/v1/')),
        isTrue,
      );
    });

    test('normalizes official Gemini compatibility URLs to native v1beta', () {
      for (final input in [
        'https://generativelanguage.googleapis.com',
        'https://generativelanguage.googleapis.com/v1beta/',
        'https://generativelanguage.googleapis.com/v1beta/openai/',
        'https://generativelanguage.googleapis.com/v1beta/models',
      ]) {
        expect(
          normalizeAiProviderBaseUri(
            AiProviderType.gemini,
            Uri.parse(input),
          ).toString(),
          'https://generativelanguage.googleapis.com/v1beta',
        );
      }
    });

    test('cancellation is idempotent and closes an attached request', () {
      var closeCount = 0;
      final cancellation = AiRequestCancellation()
        ..attach(() => closeCount += 1);

      cancellation.cancel();
      cancellation.cancel();

      expect(cancellation.isCancelled, isTrue);
      expect(closeCount, 1);
    });

    test('late cancellation attachment is closed immediately', () {
      var closed = false;
      final cancellation = AiRequestCancellation()..cancel();
      cancellation.attach(() => closed = true);
      expect(closed, isTrue);
    });
  });
}

class _ChunkedClient extends http.BaseClient {
  _ChunkedClient(this.chunks);

  final List<List<int>> chunks;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(Stream<List<int>>.fromIterable(chunks), 200);
  }
}

class _DelayedChunkedClient extends http.BaseClient {
  _DelayedChunkedClient(this.chunks);

  final List<_DelayedChunk> chunks;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(_stream(), 200);
  }

  Stream<List<int>> _stream() async* {
    for (final chunk in chunks) {
      await Future<void>.delayed(chunk.delay);
      yield chunk.bytes;
    }
  }
}

class _ErrorAfterChunksClient extends http.BaseClient {
  _ErrorAfterChunksClient({required this.chunks, required this.error});

  final List<List<int>> chunks;
  final Object error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(_stream(), 200);
  }

  Stream<List<int>> _stream() async* {
    for (final chunk in chunks) {
      yield chunk;
    }
    Error.throwWithStackTrace(error, StackTrace.current);
  }
}

class _DelayedChunk {
  const _DelayedChunk(this.delay, this.bytes);

  final Duration delay;
  final List<int> bytes;
}

class _RecordingDiagnostics extends AiNetworkDiagnostics {
  final events = <AiNetworkDiagnosticEvent>[];

  @override
  void record(AiNetworkDiagnosticEvent event) => events.add(event);
}

OpenAiProviderClient _openAi(http.Response response) {
  return OpenAiProviderClient(
    baseUri: Uri.parse('https://example.test/v1'),
    apiKey: 'unit-test-secret',
    httpClient: MockClient((_) async => response),
  );
}

String _models(String id) => '{"data":[{"id":"$id"}]}';

String _openAiSse(String text) =>
    'data: {"choices":[{"delta":{"content":"$text"}}]}\n\n'
    'data: [DONE]\n\n';

String _geminiResponse(String text) =>
    '{"candidates":[{"content":{"parts":[{"text":"$text"}]},"finishReason":"STOP"}]}';

String _geminiModels(String id) =>
    '{"models":[{"name":"models/$id","displayName":"$id",'
    '"supportedGenerationMethods":["generateContent"],'
    '"inputTokenLimit":1000,"outputTokenLimit":100}]}';

http.Response _utf8Response(
  String body,
  int statusCode, {
  Map<String, String>? headers,
}) {
  return http.Response.bytes(
    utf8.encode(body),
    statusCode,
    headers:
        headers ?? const {'content-type': 'text/event-stream; charset=utf-8'},
  );
}

GeminiProviderClient _gemini(http.Response response) {
  return GeminiProviderClient(
    baseUri: Uri.parse('https://generative.test/v1beta'),
    apiKey: 'gemini-unit-secret',
    httpClient: MockClient((_) async => response),
  );
}

AiGenerationRequest _request({
  String model = 'test-model',
  bool structuredJson = false,
}) {
  return AiGenerationRequest(
    requestId: 'request-test',
    model: model,
    systemPrompt: 'system rules',
    messages: const [
      AiGenerationMessage(role: AiMessageRole.user, content: 'hello'),
      AiGenerationMessage(role: AiMessageRole.assistant, content: 'hi'),
    ],
    temperature: 0.4,
    maxTokens: 512,
    structuredJson: structuredJson,
  );
}

AiProviderConfig _config(AiProviderType type, {String? baseUrl}) {
  final now = DateTime.utc(2026, 8, 10);
  return AiProviderConfig(
    id: type.name,
    type: type,
    displayName: type.displayName,
    baseUrl:
        baseUrl ??
        (type == AiProviderType.custom
            ? 'https://example.test/v1'
            : type.defaultBaseUrl),
    apiKeyRef: 'ai.api_key.${type.name}',
    selectedModel: 'test-model',
    enabled: true,
    connectionStatus: AiProviderConnectionStatus.untested,
    availableModels: const [],
    createdAtUtc: now,
    updatedAtUtc: now,
  );
}
