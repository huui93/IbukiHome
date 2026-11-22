import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:ibukihome/application/tavern/prompt/prompt_compiler.dart';
import 'package:ibukihome/application/tavern/prompt/prompt_models.dart';
import 'package:ibukihome/application/tavern/provider/tavern_provider_models.dart';
import 'package:ibukihome/application/tavern/tavern_generation_runtime.dart';
import 'package:ibukihome/data/ai/tavern_provider_adapter.dart';
import 'package:ibukihome/data/ai/tavern_sse.dart';
import 'package:ibukihome/domain/ai/ai_provider_config.dart';
import 'package:ibukihome/domain/ai/ai_provider_type.dart';

class FixtureTransport extends http.BaseClient {
  FixtureTransport(this.bytes, {this.status = 200, this.delay = Duration.zero});
  final List<int> bytes;
  final int status;
  final Duration delay;
  int sends = 0;
  bool closed = false;
  http.BaseRequest? request;
  Map<String, dynamic>? body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest incoming) async {
    sends++;
    request = incoming;
    body =
        jsonDecode(utf8.decode(await incoming.finalize().toBytes()))
            as Map<String, dynamic>;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return http.StreamedResponse(
      Stream.fromIterable(bytes.map((byte) => [byte])),
      status,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  @override
  void close() {
    closed = true;
  }
}

class _LoopbackTransport extends IOClient {
  _LoopbackTransport() : super(HttpClient()..findProxy = (_) => 'DIRECT');
  Object? failure;
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }

  @override
  Future<IOStreamedResponse> send(http.BaseRequest request) async {
    try {
      return await super.send(request);
    } catch (error) {
      failure = error;
      rethrow;
    }
  }
}

AiProviderConfig fixtureConfig(AiProviderType type) => AiProviderConfig(
  id: type.name,
  type: type,
  displayName: type.name,
  baseUrl: type == AiProviderType.custom
      ? 'https://fixture.invalid/v1'
      : type.defaultBaseUrl,
  apiKeyRef: 'fixture-ref',
  selectedModel: 'configured-model',
  enabled: true,
  connectionStatus: AiProviderConnectionStatus.untested,
  availableModels: const ['configured-model'],
  createdAtUtc: DateTime.utc(2026),
  updatedAtUtc: DateTime.utc(2026),
);

TavernProviderBinding fixtureBinding(
  AiProviderType type, {
  TavernProviderProtocol? protocol,
  TavernReasoningAvailability reasoning =
      TavernReasoningAvailability.unavailable,
  Duration timeout = const Duration(seconds: 2),
}) => TavernProviderBinding(
  config: fixtureConfig(type),
  model: 'configured-model',
  capabilities: TavernModelCapabilities(
    contextWindow: 4096,
    maximumOutput: 128,
    reasoning: reasoning,
  ),
  protocol:
      protocol ??
      (type == AiProviderType.gemini
          ? TavernProviderProtocol.geminiNative
          : TavernProviderProtocol.chatCompletions),
  outputTokens: 16,
  timeout: timeout,
);

CompiledPrompt fixturePrompt() =>
    const PromptCompiler(EstimatedPromptTokenCounter()).compile(
      const PromptCompileInput(
        sources: [
          PromptSource(
            id: 'core',
            type: PromptSourceType.system,
            origin: PromptOrigin('application', 'core'),
            role: PromptRoleIntent.systemLike,
            placement: PromptPlacement(PromptPlacementKind.beforeCharacter),
            atoms: [
              PromptAtom(
                id: 'core-t',
                kind: PromptAtomKind.text,
                text: 'Application rules',
              ),
            ],
            required: true,
          ),
          PromptSource(
            id: 'history',
            type: PromptSourceType.history,
            origin: PromptOrigin('turn', 'old'),
            role: PromptRoleIntent.assistantLike,
            placement: PromptPlacement(PromptPlacementKind.history),
            atoms: [
              PromptAtom(
                id: 'old-t',
                kind: PromptAtomKind.text,
                text: 'Previous reply',
              ),
            ],
            budgetClass: PromptBudgetClass.history,
          ),
          PromptSource(
            id: 'input',
            type: PromptSourceType.userInput,
            origin: PromptOrigin('turn', 'new'),
            role: PromptRoleIntent.userLike,
            placement: PromptPlacement(PromptPlacementKind.tail),
            atoms: [
              PromptAtom(
                id: 'new-t',
                kind: PromptAtomKind.text,
                text: 'Current action',
              ),
            ],
            required: true,
          ),
        ],
        constraints: PromptCompileConstraints(
          maxContextTokens: 4096,
          reservedOutputTokens: 16,
        ),
      ),
    );

String frame(Object value) => 'data: ${jsonEncode(value)}\n\n';
String chatFixture({String finish = 'stop', bool reasoning = false}) =>
    ': keepalive\n\n${frame({
      'choices': [
        {
          'delta': {'role': 'assistant', 'content': ''},
          'finish_reason': null,
        },
      ],
    })}'
    '${reasoning ? frame({
            'choices': [
              {
                'delta': {'reasoning_content': '思考'},
                'finish_reason': null,
              },
            ],
          }) : ''}'
    '${frame({
      'choices': [
        {
          'delta': {'content': '你好'},
          'finish_reason': null,
        },
      ],
    })}'
    '${frame({
      'choices': [
        {'delta': {}, 'finish_reason': finish},
      ],
    })}'
    '${frame({
      'choices': [],
      'usage': {'prompt_tokens': 12, 'completion_tokens': 2},
    })}data: [DONE]\n\n';
String responsesFixture({bool reasoning = false}) =>
    '${reasoning ? frame({'type': 'response.reasoning_summary_text.delta', 'delta': '摘要'}) : ''}'
    '${frame({'type': 'response.output_text.delta', 'delta': '你好'})}'
    '${frame({
      'type': 'response.completed',
      'response': {
        'status': 'completed',
        'usage': {'input_tokens': 12, 'output_tokens': 2},
      },
    })}';
String geminiFixture({String finish = 'STOP', bool reasoning = false}) =>
    frame({
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              if (reasoning) {'text': '摘要', 'thought': true},
              {'text': '你好'},
            ],
          },
          'finishReason': finish,
        },
      ],
      'usageMetadata': {'promptTokenCount': 12, 'candidatesTokenCount': 2},
    });

Matcher failure(TavernProviderErrorKind kind) =>
    isA<TavernProviderFailure>().having((e) => e.kind, 'kind', kind);

void main() {
  for (final type in [AiProviderType.deepseek, AiProviderType.gemini]) {
    test(
      '${type.name} rejects a developer role not offered by its native protocol',
      () {
        final binding = TavernProviderBinding(
          config: fixtureConfig(type),
          model: 'configured-model',
          protocol: type == AiProviderType.gemini
              ? TavernProviderProtocol.geminiNative
              : TavernProviderProtocol.chatCompletions,
          capabilities: const TavernModelCapabilities(developerRole: true),
          outputTokens: 16,
        );
        expect(
          () => TavernProviderAdapter(
            () => FixtureTransport([]),
          ).requestBody(TavernProviderRequest(binding, fixturePrompt())),
          throwsA(failure(TavernProviderErrorKind.unsupportedCapability)),
        );
      },
    );
  }
  for (final type in [
    AiProviderType.custom,
    AiProviderType.deepseek,
    AiProviderType.gemini,
  ]) {
    test(
      '${type.name} rejects unknown finish reason rather than accepting EOF',
      () async {
        final payload = type == AiProviderType.gemini
            ? geminiFixture(finish: 'FUTURE_UNKNOWN')
            : chatFixture(finish: 'FUTURE_UNKNOWN');
        final transport = FixtureTransport(utf8.encode(payload));
        await expectLater(
          TavernProviderAdapter(() => transport)
              .generate(
                TavernProviderRequest(fixtureBinding(type), fixturePrompt()),
                'synthetic-credential',
                TavernGenerationCancellation(),
              )
              .toList(),
          throwsA(failure(TavernProviderErrorKind.serverAbort)),
        );
        expect(transport.sends, 1);
        expect(transport.closed, isTrue);
      },
    );
  }
  for (final type in [AiProviderType.deepseek, AiProviderType.gemini]) {
    test(
      '${type.name} does not borrow the other protocol natural finish reason',
      () async {
        final payload = type == AiProviderType.gemini
            ? geminiFixture(finish: 'stop')
            : chatFixture(finish: 'STOP');
        final transport = FixtureTransport(utf8.encode(payload));
        await expectLater(
          TavernProviderAdapter(() => transport)
              .generate(
                TavernProviderRequest(fixtureBinding(type), fixturePrompt()),
                'synthetic-credential',
                TavernGenerationCancellation(),
              )
              .toList(),
          throwsA(failure(TavernProviderErrorKind.serverAbort)),
        );
      },
    );
  }
  for (final field in ['content', 'reasoning_content']) {
    test(
      'Chat rejects non-text $field instead of silently dropping it',
      () async {
        final transport = FixtureTransport(
          utf8.encode(
            frame({
              'choices': [
                {
                  'delta': {field: 42},
                  'finish_reason': null,
                },
              ],
            }),
          ),
        );
        await expectLater(
          TavernProviderAdapter(() => transport)
              .generate(
                TavernProviderRequest(
                  fixtureBinding(AiProviderType.custom),
                  fixturePrompt(),
                ),
                '',
                TavernGenerationCancellation(),
              )
              .toList(),
          throwsA(failure(TavernProviderErrorKind.malformedResponse)),
        );
      },
    );
  }
  test(
    'empty Responses summary does not claim reasoning availability',
    () async {
      final payload =
          frame({
            'type': 'response.reasoning_summary_text.delta',
            'delta': '',
          }) +
          responsesFixture();
      final transport = FixtureTransport(utf8.encode(payload));
      final events = await TavernProviderAdapter(() => transport)
          .generate(
            TavernProviderRequest(
              fixtureBinding(
                AiProviderType.openai,
                protocol: TavernProviderProtocol.responses,
              ),
              fixturePrompt(),
            ),
            'synthetic-credential',
            TavernGenerationCancellation(),
          )
          .toList();
      expect(events.whereType<TavernProviderReasoning>(), isEmpty);
      expect(events.whereType<TavernProviderText>().single.text, '你好');
    },
  );
  test(
    'real loopback HTTP streaming Stop closes transport without any external request',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.autoCompress = false;
      int requests = 0;
      var flushed = false;
      final serverSubscription = server.listen((request) async {
        requests++;
        await request.drain<void>();
        request.response.bufferOutput = false;
        request.response.headers.chunkedTransferEncoding = true;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          frame({
            'choices': [
              {
                'delta': {'content': 'partial'},
                'finish_reason': null,
              },
            ],
          }),
        );
        await request.response.flush();
        flushed = true;
      });
      final binding = TavernProviderBinding(
        config: fixtureConfig(
          AiProviderType.custom,
        ).copyWith(baseUrl: 'http://127.0.0.1:${server.port}/v1'),
        model: 'configured-model',
        protocol: TavernProviderProtocol.chatCompletions,
        capabilities: const TavernModelCapabilities(),
        outputTokens: 16,
        allowLocalHttp: true,
      );
      final cancellation = TavernGenerationCancellation();
      final received = Completer<void>();
      final client = _LoopbackTransport();
      try {
        final result = TavernProviderAdapter(() => client)
            .generate(
              TavernProviderRequest(binding, fixturePrompt()),
              '',
              cancellation,
            )
            .map((event) {
              if (event is TavernProviderText && !received.isCompleted) {
                received.complete();
              }
              return event;
            })
            .toList();
        final rejected = expectLater(
          result,
          throwsA(failure(TavernProviderErrorKind.cancelled)),
        );
        await Future.any([
          received.future,
          result.then<void>((_) {}, onError: (Object _) {}),
        ]).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw StateError(
              'Loopback requests=$requests flushed=$flushed sendFailure=${client.failure?.runtimeType}',
            );
          },
        );
        expect(client.failure, isNull);
        expect(received.isCompleted, isTrue);
        cancellation.cancel();
        await rejected;
        expect(client.closed, isTrue);
        expect(requests, 1);
      } finally {
        await serverSubscription.cancel();
        await server.close(force: true);
      }
    },
  );
  test(
    'stream error retains real HTTP status instead of inventing a server 500',
    () async {
      final transport = FixtureTransport(
        utf8.encode(
          frame({
            'error': {
              'type': 'rate_limit_exceeded',
              'message': 'synthetic error',
            },
          }),
        ),
      );
      await expectLater(
        TavernProviderAdapter(() => transport)
            .generate(
              TavernProviderRequest(
                fixtureBinding(AiProviderType.deepseek),
                fixturePrompt(),
              ),
              'synthetic-credential',
              TavernGenerationCancellation(),
            )
            .toList(),
        throwsA(
          isA<TavernProviderFailure>()
              .having(
                (e) => e.kind,
                'kind',
                TavernProviderErrorKind.rateLimited,
              )
              .having((e) => e.httpStatus, 'HTTP status', 200),
        ),
      );
    },
  );
  test(
    'DeepSeek prefix continuation is explicit and requires configured beta endpoint',
    () {
      final prompt = const PromptCompiler(EstimatedPromptTokenCounter())
          .compile(
            const PromptCompileInput(
              mode: PromptCompileMode.continueTurn,
              sources: [
                PromptSource(
                  id: 'prefix',
                  type: PromptSourceType.continuation,
                  origin: PromptOrigin('turn', 'reply'),
                  role: PromptRoleIntent.assistantLike,
                  placement: PromptPlacement(PromptPlacementKind.tail),
                  atoms: [
                    PromptAtom(
                      id: 'prefix-t',
                      kind: PromptAtomKind.text,
                      text: 'Existing reply',
                    ),
                  ],
                  required: true,
                ),
              ],
              constraints: PromptCompileConstraints(
                maxContextTokens: 4096,
                reservedOutputTokens: 16,
              ),
            ),
          );
      TavernProviderBinding binding(String url) => TavernProviderBinding(
        config: fixtureConfig(AiProviderType.deepseek).copyWith(baseUrl: url),
        model: 'configured-model',
        outputTokens: 16,
        protocol: TavernProviderProtocol.chatCompletions,
        capabilities: const TavernModelCapabilities(
          continuation: TavernContinuation.deepSeekPrefix,
        ),
      );
      final adapter = TavernProviderAdapter(() => FixtureTransport([]));
      final body = adapter.requestBody(
        TavernProviderRequest(binding('https://api.deepseek.com/beta'), prompt),
      );
      expect((body['messages'] as List).last['prefix'], true);
      expect(
        () => adapter.requestBody(
          TavernProviderRequest(binding('https://api.deepseek.com'), prompt),
        ),
        throwsA(failure(TavernProviderErrorKind.unsupportedCapability)),
      );
    },
  );
  test(
    'compiled-request fingerprint mismatch prevents any HTTP request',
    () async {
      final transport = FixtureTransport(utf8.encode(chatFixture()));
      await expectLater(
        TavernProviderAdapter(() => transport)
            .generate(
              TavernProviderRequest(
                fixtureBinding(AiProviderType.deepseek),
                fixturePrompt(),
              ),
              'synthetic-credential',
              TavernGenerationCancellation(),
              expectedFingerprint: 'wrong-compiled-identity',
            )
            .toList(),
        throwsA(failure(TavernProviderErrorKind.malformedResponse)),
      );
      expect(transport.sends, 0);
    },
  );
  test(
    'unknown custom capabilities never enable unsupported inputs or parameters',
    () {
      final adapter = TavernProviderAdapter(() => FixtureTransport([]));
      final config = fixtureConfig(AiProviderType.custom);
      final binding = TavernProviderBinding(
        config: config,
        model: 'configured-model',
        capabilities: const TavernModelCapabilities(),
        protocol: TavernProviderProtocol.chatCompletions,
        outputTokens: 16,
        parameters: const {'temperature': 0.5},
      );
      expect(
        () => adapter.requestBody(
          TavernProviderRequest(binding, fixturePrompt()),
        ),
        throwsA(failure(TavernProviderErrorKind.unsupportedCapability)),
      );
      final spoof = TavernProviderBinding(
        config: config.copyWith(baseUrl: 'http://10.attacker.invalid'),
        model: 'configured-model',
        capabilities: const TavernModelCapabilities(),
        protocol: TavernProviderProtocol.chatCompletions,
        allowLocalHttp: true,
      );
      expect(
        () => adapter.endpoint(spoof),
        throwsA(failure(TavernProviderErrorKind.permission)),
      );
    },
  );
  test('invalid UTF8 is classified without retaining response body', () async {
    final transport = FixtureTransport([0xff, 0xfe, 0x0a, 0x0a]);
    await expectLater(
      TavernProviderAdapter(() => transport)
          .generate(
            TavernProviderRequest(
              fixtureBinding(AiProviderType.deepseek),
              fixturePrompt(),
            ),
            'synthetic-credential',
            TavernGenerationCancellation(),
          )
          .toList(),
      throwsA(failure(TavernProviderErrorKind.malformedResponse)),
    );
  });
  test('empty native reasoning delta does not fabricate reasoning', () async {
    final data =
        frame({
          'choices': [
            {
              'delta': {'reasoning_content': ''},
              'finish_reason': null,
            },
          ],
        }) +
        chatFixture();
    final transport = FixtureTransport(utf8.encode(data));
    final events = await TavernProviderAdapter(() => transport)
        .generate(
          TavernProviderRequest(
            fixtureBinding(
              AiProviderType.deepseek,
              reasoning: TavernReasoningAvailability.native,
            ),
            fixturePrompt(),
          ),
          'synthetic-credential',
          TavernGenerationCancellation(),
        )
        .toList();
    expect(events.whereType<TavernProviderReasoning>(), isEmpty);
  });
  for (final (type, protocol) in [
    (AiProviderType.deepseek, TavernProviderProtocol.chatCompletions),
    (AiProviderType.openai, TavernProviderProtocol.chatCompletions),
    (AiProviderType.openai, TavernProviderProtocol.responses),
    (AiProviderType.gemini, TavernProviderProtocol.geminiNative),
    (AiProviderType.custom, TavernProviderProtocol.chatCompletions),
    (AiProviderType.kimi, TavernProviderProtocol.chatCompletions),
    (AiProviderType.qwen, TavernProviderProtocol.chatCompletions),
    (AiProviderType.grok, TavernProviderProtocol.chatCompletions),
    (AiProviderType.glm, TavernProviderProtocol.chatCompletions),
    (AiProviderType.claude, TavernProviderProtocol.claudeMessages),
  ]) {
    final label = '${type.name}/${protocol.name}';
    String stream() => switch (protocol) {
      TavernProviderProtocol.chatCompletions => chatFixture(),
      TavernProviderProtocol.responses => responsesFixture(),
      TavernProviderProtocol.geminiNative => geminiFixture(),
      TavernProviderProtocol.claudeMessages =>
        frame({
              'type': 'message_start',
              'message': {
                'usage': {'input_tokens': 12, 'output_tokens': 2},
              },
            }) +
            frame({
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'text_delta', 'text': '你好'},
            }) +
            frame({
              'type': 'message_delta',
              'delta': {'stop_reason': 'end_turn'},
            }) +
            frame({'type': 'message_stop'}),
    };
    test(
      '$label preserves request history and decodes split UTF8/usage/finish',
      () async {
        final transport = FixtureTransport(utf8.encode(stream()));
        final adapter = TavernProviderAdapter(() => transport);
        final events = await adapter
            .generate(
              TavernProviderRequest(
                fixtureBinding(type, protocol: protocol),
                fixturePrompt(),
              ),
              'synthetic-credential',
              TavernGenerationCancellation(),
            )
            .toList();
        expect(
          events.whereType<TavernProviderText>().map((e) => e.text).join(),
          '你好',
        );
        expect(events.whereType<TavernProviderFinished>(), hasLength(1));
        expect(events.whereType<TavernProviderUsage>().single.inputTokens, 12);
        expect(transport.sends, 1);
        expect(transport.closed, isTrue);
        if (protocol == TavernProviderProtocol.geminiNative) {
          expect(transport.body!['systemInstruction'], {
            'parts': [
              {'text': 'Application rules'},
            ],
          });
          expect((transport.body!['contents'] as List).map((m) => m['role']), [
            'model',
            'user',
          ]);
          expect(
            transport.request!.headers.containsKey('x-goog-api-key'),
            isTrue,
          );
        } else if (protocol == TavernProviderProtocol.claudeMessages) {
          expect(transport.body!['system'], 'Application rules');
          expect((transport.body!['messages'] as List).map((m) => m['role']), [
            'user',
            'assistant',
            'user',
          ]);
          expect(
            transport.request!.headers['x-api-key'],
            'synthetic-credential',
          );
          expect(transport.request!.headers['anthropic-version'], '2023-06-01');
          expect(transport.body!.containsKey('temperature'), isFalse);
        } else {
          final messages =
              transport.body![protocol == TavernProviderProtocol.responses
                      ? 'input'
                      : 'messages']
                  as List;
          expect(messages.map((m) => m['role']), [
            'system',
            'assistant',
            'user',
          ]);
          expect(transport.body!['model'], 'configured-model');
        }
      },
    );
    for (final (status, kind) in [
      (401, TavernProviderErrorKind.authentication),
      (403, TavernProviderErrorKind.permission),
      (404, TavernProviderErrorKind.unknownModel),
      (429, TavernProviderErrorKind.rateLimited),
    ]) {
      test(
        '$label classifies HTTP $status without exposing response secrets',
        () async {
          final transport = FixtureTransport(
            utf8.encode('{"error":{"message":"synthetic private response"}}'),
            status: status,
          );
          final future = TavernProviderAdapter(() => transport)
              .generate(
                TavernProviderRequest(
                  fixtureBinding(type, protocol: protocol),
                  fixturePrompt(),
                ),
                'synthetic-credential',
                TavernGenerationCancellation(),
              )
              .toList();
          await expectLater(future, throwsA(failure(kind)));
          expect(transport.sends, 1);
        },
      );
    }
    test('$label rejects malformed and premature EOF streams', () async {
      for (final data in [
        'data: {broken}\n\n',
        frame(
          protocol == TavernProviderProtocol.responses
              ? {'type': 'response.output_text.delta', 'delta': 'partial'}
              : protocol == TavernProviderProtocol.geminiNative
              ? {
                  'candidates': [
                    {
                      'content': {
                        'parts': [
                          {'text': 'partial'},
                        ],
                      },
                    },
                  ],
                }
              : {
                  'choices': [
                    {
                      'delta': {'content': 'partial'},
                      'finish_reason': null,
                    },
                  ],
                },
        ),
      ]) {
        final transport = FixtureTransport(utf8.encode(data));
        await expectLater(
          TavernProviderAdapter(() => transport)
              .generate(
                TavernProviderRequest(
                  fixtureBinding(type, protocol: protocol),
                  fixturePrompt(),
                ),
                'synthetic-credential',
                TavernGenerationCancellation(),
              )
              .toList(),
          throwsA(
            isA<TavernProviderFailure>().having(
              (e) => e.kind,
              'protocol failure',
              isIn([
                TavernProviderErrorKind.malformedResponse,
                TavernProviderErrorKind.incompleteStream,
              ]),
            ),
          ),
        );
        expect(transport.sends, 1);
      }
    });
    test('$label timeout closes HTTP client without automatic retry', () async {
      final transport = FixtureTransport(
        utf8.encode(stream()),
        delay: const Duration(milliseconds: 20),
      );
      await expectLater(
        TavernProviderAdapter(() => transport)
            .generate(
              TavernProviderRequest(
                fixtureBinding(
                  type,
                  protocol: protocol,
                  timeout: const Duration(milliseconds: 2),
                ),
                fixturePrompt(),
              ),
              'synthetic-credential',
              TavernGenerationCancellation(),
            )
            .toList(),
        throwsA(failure(TavernProviderErrorKind.timeout)),
      );
      expect(transport.closed, isTrue);
      expect(transport.sends, 1);
    });
    test('$label cancellation before request never charges', () async {
      final transport = FixtureTransport(utf8.encode(stream()));
      final cancel = TavernGenerationCancellation()..cancel();
      await expectLater(
        TavernProviderAdapter(() => transport)
            .generate(
              TavernProviderRequest(
                fixtureBinding(type, protocol: protocol),
                fixturePrompt(),
              ),
              'synthetic-credential',
              cancel,
            )
            .toList(),
        throwsA(failure(TavernProviderErrorKind.cancelled)),
      );
      expect(transport.sends, 0);
    });
  }
  test(
    'DeepSeek native reasoning is distinct from Gemini and Responses summary',
    () async {
      for (final (type, protocol, kind, data) in [
        (
          AiProviderType.deepseek,
          TavernProviderProtocol.chatCompletions,
          TavernReasoningAvailability.native,
          chatFixture(reasoning: true),
        ),
        (
          AiProviderType.openai,
          TavernProviderProtocol.responses,
          TavernReasoningAvailability.summary,
          responsesFixture(reasoning: true),
        ),
        (
          AiProviderType.gemini,
          TavernProviderProtocol.geminiNative,
          TavernReasoningAvailability.summary,
          geminiFixture(reasoning: true),
        ),
      ]) {
        final transport = FixtureTransport(utf8.encode(data));
        final events = await TavernProviderAdapter(() => transport)
            .generate(
              TavernProviderRequest(
                fixtureBinding(type, protocol: protocol, reasoning: kind),
                fixturePrompt(),
              ),
              'synthetic-credential',
              TavernGenerationCancellation(),
            )
            .toList();
        expect(events.whereType<TavernProviderReasoning>().single.kind, kind);
        expect(events.whereType<TavernProviderText>().single.text, '你好');
      }
    },
  );
  test(
    'SSE multiline data, CRLF and consecutive frames respect event boundaries',
    () async {
      final data =
          ': ping\r\nevent: answer\r\ndata: {"a":\r\ndata: 1}\r\n\r\ndata: {}\r\n\r\n';
      final result = await decodeTavernSse(
        Stream.fromIterable(utf8.encode(data).map((b) => [b])),
      ).toList();
      expect(result, hasLength(2));
      expect(result.first.event, 'answer');
      expect(jsonDecode(result.first.data), {'a': 1});
    },
  );
  test(
    'output limit, filter and tool finish remain explicit failures',
    () async {
      for (final (reason, kind) in [
        ('length', TavernProviderErrorKind.outputLimit),
        ('content_filter', TavernProviderErrorKind.contentFiltered),
        ('tool_calls', TavernProviderErrorKind.unsupportedCapability),
      ]) {
        final transport = FixtureTransport(
          utf8.encode(chatFixture(finish: reason)),
        );
        await expectLater(
          TavernProviderAdapter(() => transport)
              .generate(
                TavernProviderRequest(
                  fixtureBinding(AiProviderType.deepseek),
                  fixturePrompt(),
                ),
                'synthetic-credential',
                TavernGenerationCancellation(),
              )
              .toList(),
          throwsA(failure(kind)),
        );
      }
    },
  );
  test(
    'credentials cannot follow redirects or enter arbitrary HTTP hosts',
    () async {
      final transport = FixtureTransport([], status: 302);
      await expectLater(
        TavernProviderAdapter(() => transport)
            .generate(
              TavernProviderRequest(
                fixtureBinding(AiProviderType.custom),
                fixturePrompt(),
              ),
              'synthetic-credential',
              TavernGenerationCancellation(),
            )
            .toList(),
        throwsA(isA<TavernProviderFailure>()),
      );
      expect(transport.request!.followRedirects, isFalse);
      final unsafe = TavernProviderBinding(
        config: fixtureConfig(
          AiProviderType.custom,
        ).copyWith(baseUrl: 'http://remote.invalid'),
        model: 'configured-model',
        capabilities: const TavernModelCapabilities(),
        protocol: TavernProviderProtocol.chatCompletions,
      );
      expect(
        () => TavernProviderAdapter(
          () => transport,
        ).requestBody(TavernProviderRequest(unsafe, fixturePrompt())),
        throwsA(failure(TavernProviderErrorKind.permission)),
      );
    },
  );
}
