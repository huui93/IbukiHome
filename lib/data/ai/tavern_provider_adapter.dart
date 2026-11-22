import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../application/tavern/provider/tavern_provider_models.dart';
import '../../application/tavern/prompt/prompt_models.dart';
import '../../application/tavern/tavern_generation_runtime.dart';
import '../../domain/ai/ai_provider_type.dart';
import 'ai_provider_registry.dart';
import 'chat_completion_parameters.dart';
import 'claude_messages_protocol.dart';
import '../../domain/ai/ai_generation.dart';
import '../../core/network/ai_provider_exceptions.dart';
import 'tavern_sse.dart';

class TavernProviderAdapter {
  TavernProviderAdapter(this.clientFactory);
  final http.Client Function() clientFactory;

  Uri endpoint(TavernProviderBinding binding) {
    final uri = Uri.tryParse(binding.config.baseUrl);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                binding.allowLocalHttp &&
                _localHost(uri.host)))) {
      throw const TavernProviderFailure(TavernProviderErrorKind.permission);
    }
    final base = normalizeAiProviderBaseUri(binding.config.type, uri);
    final path = base.pathSegments.where((s) => s.isNotEmpty).toList();
    if (binding.protocol == TavernProviderProtocol.geminiNative) {
      final model = binding.model.replaceFirst(RegExp(r'^models/'), '');
      return base.replace(
        pathSegments: [...path, 'models', '$model:streamGenerateContent'],
        queryParameters: {'alt': 'sse'},
      );
    }
    return base.replace(
      pathSegments: [
        ...path,
        ...switch (binding.protocol) {
          TavernProviderProtocol.responses => ['responses'],
          TavernProviderProtocol.claudeMessages => ['messages'],
          _ => ['chat', 'completions'],
        },
      ],
    );
  }

  Map<String, Object?> requestBody(TavernProviderRequest request) {
    final binding = request.binding;
    final cap = binding.capabilities;
    endpoint(binding);
    if (!cap.streaming || cap.tokenAccuracy != TavernTokenAccuracy.estimated) {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.unsupportedCapability,
      );
    }
    if (!binding.config.enabled ||
        binding.model.trim().isEmpty ||
        !cap.streaming ||
        cap.contextWindow <= 0 ||
        cap.maximumOutput <= 0 ||
        binding.outputTokens <= 0 ||
        binding.outputTokens > cap.maximumOutput ||
        binding.timeout <= Duration.zero ||
        request.prompt.trace.maxContextTokens > cap.contextWindow ||
        request.prompt.trace.reservedOutputTokens < binding.outputTokens ||
        request.prompt.trace.usedInputTokens + binding.outputTokens >
            cap.contextWindow) {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.contextExceeded,
      );
    }
    final expected = switch (binding.config.type) {
      AiProviderType.gemini => TavernProviderProtocol.geminiNative,
      AiProviderType.claude => TavernProviderProtocol.claudeMessages,
      AiProviderType.openai || AiProviderType.grok => binding.protocol,
      _ => TavernProviderProtocol.chatCompletions,
    };
    if (expected != binding.protocol ||
        ({
              AiProviderType.openai,
              AiProviderType.grok,
            }.contains(binding.config.type) &&
            !{
              TavernProviderProtocol.chatCompletions,
              TavernProviderProtocol.responses,
            }.contains(binding.protocol)) ||
        (cap.developerRole &&
            !{
              AiProviderType.openai,
              AiProviderType.grok,
              AiProviderType.custom,
            }.contains(binding.config.type)) ||
        (binding.protocol == TavernProviderProtocol.claudeMessages &&
            cap.reasoning != TavernReasoningAvailability.unavailable)) {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.unsupportedCapability,
      );
    }
    if (binding.protocol == TavernProviderProtocol.geminiNative &&
        (cap.reasoning == TavernReasoningAvailability.native ||
            cap.continuation == TavernContinuation.deepSeekPrefix)) {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.unsupportedCapability,
      );
    }
    const safeParameters = {
      'temperature',
      'top_p',
      'top_k',
      'frequency_penalty',
      'presence_penalty',
      'reasoning_effort',
      'thinking',
      'thinkingConfig',
      'enable_thinking',
      'reasoning',
    };
    if (binding.parameters.keys.any(
      (key) =>
          !safeParameters.contains(key) || !cap.allowedParameters.contains(key),
    )) {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.unsupportedCapability,
      );
    }
    final protocolParameters = switch (binding.protocol) {
      TavernProviderProtocol.claudeMessages => const <String>{},
      TavernProviderProtocol.geminiNative => const {
        'temperature',
        'top_p',
        'top_k',
        'thinkingConfig',
      },
      TavernProviderProtocol.responses => const {
        'temperature',
        'top_p',
        'reasoning',
      },
      TavernProviderProtocol.chatCompletions => const {
        'temperature',
        'top_p',
        'frequency_penalty',
        'presence_penalty',
        'thinking',
        'reasoning_effort',
        'enable_thinking',
      },
    };
    for (final item in binding.parameters.entries) {
      if (!protocolParameters.contains(item.key)) {
        throw const TavernProviderFailure(
          TavernProviderErrorKind.unsupportedCapability,
        );
      }
      final value = item.value;
      var valid = true;
      if ({
        'temperature',
        'top_p',
        'frequency_penalty',
        'presence_penalty',
      }.contains(item.key)) {
        final lower = item.key.endsWith('penalty') ? -2 : 0;
        final upper = item.key == 'top_p' ? 1 : 2;
        valid =
            value is num && value.isFinite && value >= lower && value <= upper;
      } else if (item.key == 'enable_thinking') {
        valid = value is bool;
      } else if (item.key == 'top_k') {
        valid = value is int && value > 0;
      } else if (item.key == 'thinking') {
        valid =
            value is Map &&
            value.keys.every((key) => key == 'type') &&
            {'enabled', 'disabled'}.contains(value['type']);
      } else if (item.key == 'reasoning') {
        valid =
            value is Map &&
            value.keys.every((key) => key == 'effort' || key == 'summary') &&
            value.values.every((v) => v is String);
      } else if (item.key == 'thinkingConfig') {
        valid =
            value is Map &&
            value.keys.every(
              (key) => {
                'includeThoughts',
                'thinkingBudget',
                'thinkingLevel',
              }.contains(key),
            ) &&
            (value['includeThoughts'] == null ||
                value['includeThoughts'] is bool) &&
            (value['thinkingBudget'] == null ||
                value['thinkingBudget'] is int &&
                    (value['thinkingBudget'] as int) >= -1) &&
            (value['thinkingLevel'] == null ||
                value['thinkingLevel'] is String);
      } else if (item.key == 'reasoning_effort') {
        valid = value is String;
      }
      if (!valid) {
        throw const TavernProviderFailure(
          TavernProviderErrorKind.unsupportedCapability,
        );
      }
    }
    final messages = <Map<String, Object?>>[];
    for (final segment in request.prompt.segments) {
      if (segment.atoms.any(
        (atom) =>
            atom.kind != PromptAtomKind.text &&
            atom.kind != PromptAtomKind.event,
      )) {
        throw const TavernProviderFailure(
          TavernProviderErrorKind.unsupportedCapability,
        );
      }
      final text = segment.atoms.map((atom) => atom.text ?? '').join('\n');
      if (text.isEmpty) continue;
      if (segment.role == PromptRoleIntent.systemLike && !cap.systemRole) {
        throw const TavernProviderFailure(
          TavernProviderErrorKind.unsupportedCapability,
        );
      }
      final role = switch (segment.role) {
        PromptRoleIntent.systemLike =>
          cap.developerRole ? 'developer' : 'system',
        PromptRoleIntent.assistantLike => 'assistant',
        _ => 'user',
      };
      messages.add({'role': role, 'content': text});
      if (segment.continuation &&
          cap.continuation == TavernContinuation.unsupported) {
        throw const TavernProviderFailure(
          TavernProviderErrorKind.unsupportedCapability,
        );
      }
      if (segment.continuation &&
          cap.continuation == TavernContinuation.deepSeekPrefix) {
        if (binding.config.type != AiProviderType.deepseek ||
            !endpoint(binding).pathSegments.contains('beta')) {
          throw const TavernProviderFailure(
            TavernProviderErrorKind.unsupportedCapability,
          );
        }
        messages.last['prefix'] = true;
      }
    }
    if (request.prompt.mode == PromptCompileMode.continueTurn &&
        cap.continuation == TavernContinuation.instruction &&
        (request.prompt.segments.lastOrNull?.origin.id != 'continue-v1' ||
            request.prompt.segments.lastOrNull?.role !=
                PromptRoleIntent.userLike)) {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.unsupportedCapability,
      );
    }
    if (request.prompt.mode == PromptCompileMode.continueTurn &&
        cap.continuation == TavernContinuation.deepSeekPrefix &&
        messages.lastOrNull?['role'] != 'assistant') {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.unsupportedCapability,
      );
    }
    if (binding.protocol == TavernProviderProtocol.geminiNative) {
      final system = <Map<String, Object?>>[];
      final contents = <Map<String, Object?>>[];
      var hasHistory = false;
      for (final message in messages) {
        if (message['role'] == 'system' || message['role'] == 'developer') {
          if (hasHistory) {
            throw const TavernProviderFailure(
              TavernProviderErrorKind.unsupportedCapability,
            );
          }
          system.add({'text': message['content']});
        } else {
          hasHistory = true;
          contents.add({
            'role': message['role'] == 'assistant' ? 'model' : 'user',
            'parts': [
              {'text': message['content']},
            ],
          });
        }
      }
      final parameters = Map<String, Object?>.of(binding.parameters);
      if (parameters.containsKey('top_p')) {
        parameters['topP'] = parameters.remove('top_p');
      }
      if (parameters.containsKey('top_k')) {
        parameters['topK'] = parameters.remove('top_k');
      }
      return {
        'contents': contents,
        if (system.isNotEmpty) 'systemInstruction': {'parts': system},
        'generationConfig': {
          'maxOutputTokens': binding.outputTokens,
          ...parameters,
        },
      };
    }
    if (binding.protocol == TavernProviderProtocol.claudeMessages) {
      try {
        return claudeMessagesBody(
          model: binding.model,
          messages: messages,
          maxTokens: binding.outputTokens,
          stream: true,
        );
      } on AiProviderException {
        throw const TavernProviderFailure(
          TavernProviderErrorKind.unsupportedCapability,
        );
      }
    }
    if (binding.protocol == TavernProviderProtocol.responses) {
      return {
        'model': binding.model,
        'input': messages,
        'stream': true,
        'store': false,
        'truncation': 'disabled',
        'max_output_tokens': binding.outputTokens,
        ...binding.parameters,
      };
    }
    return {
      'model': binding.model,
      'messages': messages,
      'stream': true,
      if (cap.streamUsage) 'stream_options': {'include_usage': true},
      ...chatCompletionParameters(
        provider: binding.config.type.name,
        model: binding.model,
        maxTokens: binding.outputTokens,
        preferCompletionTokens: binding.config.type == AiProviderType.openai,
      ),
      ...binding.parameters,
    };
  }

  Stream<TavernProviderEvent> generate(
    TavernProviderRequest request,
    String credential,
    TavernGenerationCancellation cancellation, {
    String? expectedFingerprint,
  }) async* {
    final body = requestBody(request);
    final encodedBody = jsonEncode(body);
    if (expectedFingerprint != null &&
        sha256.convert(utf8.encode(encodedBody)).toString() !=
            expectedFingerprint) {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.malformedResponse,
      );
    }
    if (credential.isEmpty && request.binding.config.type.requiresApiKey) {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.missingCredential,
      );
    }
    if (cancellation.isCancelled) {
      throw const TavernProviderFailure(TavernProviderErrorKind.cancelled);
    }
    final client = clientFactory();
    var closed = false;
    var timedOut = false;
    final deadline = Timer(request.binding.timeout, () {
      timedOut = true;
      if (!closed) client.close();
    });
    unawaited(
      cancellation.whenCancelled.then((_) {
        if (!closed) client.close();
      }),
    );
    try {
      final outgoing =
          http.AbortableRequest(
              'POST',
              endpoint(request.binding),
              abortTrigger: cancellation.whenCancelled,
            )
            ..followRedirects = false
            ..headers['Content-Type'] = 'application/json'
            ..headers['Accept'] = 'text/event-stream'
            ..body = encodedBody;
      if (request.binding.protocol == TavernProviderProtocol.claudeMessages) {
        outgoing.headers['anthropic-version'] = claudeApiVersion;
        outgoing.headers['x-api-key'] = credential;
      } else if (credential.isNotEmpty) {
        outgoing.headers[request.binding.protocol ==
                    TavernProviderProtocol.geminiNative
                ? 'x-goog-api-key'
                : 'Authorization'] =
            request.binding.protocol == TavernProviderProtocol.geminiNative
            ? credential
            : 'Bearer $credential';
      }
      final response = await client
          .send(outgoing)
          .timeout(request.binding.timeout);
      if (response.statusCode != 200) {
        // Error payloads are classified in memory and never copied to diagnostics.
        final bytes = <int>[];
        await for (final chunk in response.stream.timeout(
          request.binding.timeout,
        )) {
          bytes.addAll(chunk.take(16384 - bytes.length));
          if (bytes.length >= 16384) break;
        }
        throw _httpFailure(
          response.statusCode,
          utf8.decode(bytes, allowMalformed: true),
        );
      }
      final claudeDecoder = ClaudeMessageDecoder();
      var stopped = false;
      var visible = false;
      await for (final frame in decodeTavernSse(
        response.stream.timeout(request.binding.timeout),
      )) {
        if (cancellation.isCancelled) {
          throw const TavernProviderFailure(TavernProviderErrorKind.cancelled);
        }
        if (frame.data == '[DONE]') {
          if (request.binding.protocol !=
              TavernProviderProtocol.chatCompletions) {
            throw const TavernProviderFailure(
              TavernProviderErrorKind.malformedResponse,
            );
          }
          if (!stopped || !visible) {
            throw const TavernProviderFailure(
              TavernProviderErrorKind.incompleteStream,
            );
          }
          yield const TavernProviderFinished();
          return;
        }
        final value = jsonDecode(frame.data);
        if (value is! Map<String, dynamic>) throw const FormatException();
        if (value['error'] != null) throw _httpFailure(200, frame.data);
        final events = switch (request.binding.protocol) {
          TavernProviderProtocol.claudeMessages => _claude(
            value,
            claudeDecoder,
          ),
          TavernProviderProtocol.chatCompletions => _chat(
            value,
            request.binding.capabilities,
          ),
          TavernProviderProtocol.responses => _responses(
            value,
            request.binding.capabilities,
          ),
          TavernProviderProtocol.geminiNative => _gemini(
            value,
            request.binding.capabilities,
          ),
        };
        for (final event in events) {
          if (stopped && event is TavernProviderText && event.text.isNotEmpty) {
            throw const TavernProviderFailure(
              TavernProviderErrorKind.malformedResponse,
            );
          }
          if (event is TavernProviderText && event.text.isNotEmpty) {
            visible = true;
          }
          if (event is TavernProviderFinished) {
            if (!visible) {
              throw const TavernProviderFailure(
                TavernProviderErrorKind.malformedResponse,
              );
            }
            if (request.binding.protocol != TavernProviderProtocol.responses &&
                request.binding.protocol !=
                    TavernProviderProtocol.claudeMessages) {
              stopped = true;
            } else {
              yield event;
              return;
            }
          } else {
            yield event;
          }
        }
      }
      if (timedOut) {
        throw const TavernProviderFailure(TavernProviderErrorKind.timeout);
      }
      if (cancellation.isCancelled) {
        throw const TavernProviderFailure(TavernProviderErrorKind.cancelled);
      }
      if (request.binding.protocol == TavernProviderProtocol.geminiNative &&
          stopped &&
          visible) {
        yield const TavernProviderFinished();
        return;
      }
      throw const TavernProviderFailure(
        TavernProviderErrorKind.incompleteStream,
      );
    } on TavernProviderFailure {
      if (cancellation.isCancelled) {
        throw const TavernProviderFailure(TavernProviderErrorKind.cancelled);
      }
      if (timedOut) {
        throw const TavernProviderFailure(TavernProviderErrorKind.timeout);
      }
      rethrow;
    } on TimeoutException {
      throw const TavernProviderFailure(TavernProviderErrorKind.timeout);
    } on FormatException {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.malformedResponse,
      );
    } on TypeError {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.malformedResponse,
      );
    } catch (_) {
      throw TavernProviderFailure(
        timedOut
            ? TavernProviderErrorKind.timeout
            : cancellation.isCancelled
            ? TavernProviderErrorKind.cancelled
            : TavernProviderErrorKind.transport,
      );
    } finally {
      deadline.cancel();
      closed = true;
      client.close();
    }
  }

  static Iterable<TavernProviderEvent> _claude(
    Map<String, dynamic> json,
    ClaudeMessageDecoder decoder,
  ) sync* {
    final message = json['message'];
    final usage = json['type'] == 'message_start' && message is Map
        ? message['usage']
        : json['usage'];
    if (usage is Map) {
      yield TavernProviderUsage(
        inputTokens: usage['input_tokens'] as int?,
        outputTokens: usage['output_tokens'] as int?,
      );
    }
    try {
      for (final event in decoder.add(json)) {
        if (!event.isTerminal) {
          yield TavernProviderText(event.content);
          continue;
        }
        switch (event.finishReason) {
          case AiFinishReason.stop:
            yield const TavernProviderFinished();
          case AiFinishReason.length:
            throw const TavernProviderFailure(
              TavernProviderErrorKind.outputLimit,
            );
          case AiFinishReason.contentFiltered:
            throw const TavernProviderFailure(
              TavernProviderErrorKind.contentFiltered,
            );
          default:
            throw const TavernProviderFailure(
              TavernProviderErrorKind.unsupportedCapability,
            );
        }
      }
    } on AiProviderException {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.malformedResponse,
      );
    }
  }

  static Iterable<TavernProviderEvent> _chat(
    Map<String, dynamic> json,
    TavernModelCapabilities cap,
  ) sync* {
    final usage = json['usage'];
    if (usage is Map) {
      yield TavernProviderUsage(
        inputTokens: usage['prompt_tokens'] as int?,
        outputTokens: usage['completion_tokens'] as int?,
      );
    }
    final choices = json['choices'];
    if (choices is! List) throw const FormatException();
    if (choices.isEmpty) return;
    if (choices.length != 1 || choices.single is! Map) {
      throw const FormatException();
    }
    final choice = choices.single as Map;
    final delta = choice['delta'];
    if (delta is! Map) throw const FormatException();
    if ((delta['content'] != null && delta['content'] is! String) ||
        (delta['reasoning_content'] != null &&
            delta['reasoning_content'] is! String)) {
      throw const FormatException();
    }
    if (delta['tool_calls'] != null || delta['function_call'] != null) {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.unsupportedCapability,
      );
    }
    if (delta['refusal'] != null) {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.contentFiltered,
      );
    }
    if (delta['content'] is String && (delta['content'] as String).isNotEmpty) {
      yield TavernProviderText(delta['content'] as String);
    }
    if (delta['reasoning_content'] is String &&
        (delta['reasoning_content'] as String).isNotEmpty) {
      if (cap.reasoning != TavernReasoningAvailability.native) {
        throw const TavernProviderFailure(
          TavernProviderErrorKind.unsupportedCapability,
        );
      }
      yield TavernProviderReasoning(
        delta['reasoning_content'] as String,
        TavernReasoningAvailability.native,
      );
    }
    final finish = choice['finish_reason'];
    if (finish != null) {
      _checkFinish(finish.toString(), natural: 'stop');
      yield const TavernProviderFinished();
    }
  }

  static Iterable<TavernProviderEvent> _responses(
    Map<String, dynamic> json,
    TavernModelCapabilities cap,
  ) sync* {
    final type = json['type'];
    if (type == 'response.output_text.delta') {
      yield TavernProviderText(json['delta'] as String);
    }
    if (type == 'response.reasoning_summary_text.delta' ||
        type == 'response.reasoning_text.delta') {
      final kind = type == 'response.reasoning_text.delta'
          ? TavernReasoningAvailability.native
          : TavernReasoningAvailability.summary;
      final delta = json['delta'] as String;
      if (delta.isEmpty) return;
      if (cap.reasoning != kind) {
        throw const TavernProviderFailure(
          TavernProviderErrorKind.unsupportedCapability,
        );
      }
      yield TavernProviderReasoning(delta, kind);
    }
    if (type == 'response.refusal.delta') {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.contentFiltered,
      );
    }
    if (type == 'response.output_item.added' ||
        type == 'response.output_item.done') {
      final item = json['item'];
      if (item is Map &&
          item['type'] != 'message' &&
          item['type'] != 'reasoning') {
        throw const TavernProviderFailure(
          TavernProviderErrorKind.unsupportedCapability,
        );
      }
    }
    if (type == 'response.failed' || type == 'error') {
      throw _httpFailure(200, jsonEncode(json));
    }
    if (type == 'response.incomplete') {
      final response = json['response'] as Map?;
      final details = response?['incomplete_details'] as Map?;
      throw TavernProviderFailure(
        details?['reason'] == 'max_output_tokens'
            ? TavernProviderErrorKind.outputLimit
            : TavernProviderErrorKind.contentFiltered,
      );
    }
    if (type == 'response.completed') {
      final response = json['response'];
      if (response is! Map || response['status'] != 'completed') {
        throw const FormatException();
      }
      final output = response['output'];
      if (output is List &&
          output.any(
            (item) =>
                item is! Map ||
                (item['type'] != 'message' && item['type'] != 'reasoning'),
          )) {
        throw const TavernProviderFailure(
          TavernProviderErrorKind.unsupportedCapability,
        );
      }
      final usage = response['usage'];
      if (usage is Map) {
        yield TavernProviderUsage(
          inputTokens: usage['input_tokens'] as int?,
          outputTokens: usage['output_tokens'] as int?,
        );
      }
      yield const TavernProviderFinished();
    }
  }

  static Iterable<TavernProviderEvent> _gemini(
    Map<String, dynamic> json,
    TavernModelCapabilities cap,
  ) sync* {
    final feedback = json['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw const TavernProviderFailure(
        TavernProviderErrorKind.contentFiltered,
      );
    }
    final usage = json['usageMetadata'];
    if (usage is Map) {
      yield TavernProviderUsage(
        inputTokens: usage['promptTokenCount'] as int?,
        outputTokens: usage['candidatesTokenCount'] as int?,
      );
    }
    final candidates = json['candidates'];
    if (candidates == null && usage != null) return;
    if (candidates is! List ||
        candidates.length != 1 ||
        candidates.single is! Map) {
      throw const FormatException();
    }
    final candidate = candidates.single as Map;
    final content = candidate['content'];
    if (content is Map) {
      final parts = content['parts'];
      if (parts is! List) throw const FormatException();
      for (final part in parts) {
        if (part is! Map) throw const FormatException();
        if (part['functionCall'] != null ||
            part['inlineData'] != null ||
            part['fileData'] != null) {
          throw const TavernProviderFailure(
            TavernProviderErrorKind.unsupportedCapability,
          );
        }
        if (part['text'] != null && part['text'] is! String) {
          throw const FormatException();
        }
        if (part['text'] is String && (part['text'] as String).isNotEmpty) {
          if (part['thought'] == true) {
            if (cap.reasoning != TavernReasoningAvailability.summary) {
              throw const TavernProviderFailure(
                TavernProviderErrorKind.unsupportedCapability,
              );
            }
            yield TavernProviderReasoning(
              part['text'] as String,
              TavernReasoningAvailability.summary,
            );
          } else {
            yield TavernProviderText(part['text'] as String);
          }
        }
      }
    }
    if (candidate['finishReason'] != null) {
      _checkFinish(candidate['finishReason'].toString(), natural: 'STOP');
      yield const TavernProviderFinished();
    }
  }

  static void _checkFinish(String reason, {required String natural}) {
    if (reason == natural) return;
    throw TavernProviderFailure(switch (reason) {
      'length' || 'MAX_TOKENS' => TavernProviderErrorKind.outputLimit,
      'tool_calls' ||
      'function_call' => TavernProviderErrorKind.unsupportedCapability,
      'content_filter' ||
      'SAFETY' ||
      'RECITATION' ||
      'BLOCKLIST' ||
      'PROHIBITED_CONTENT' ||
      'SPII' => TavernProviderErrorKind.contentFiltered,
      _ => TavernProviderErrorKind.serverAbort,
    });
  }

  static TavernProviderFailure _httpFailure(int status, String raw) {
    var text = '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final response = decoded['response'];
        final error =
            decoded['error'] ?? (response is Map ? response['error'] : null);
        if (error is Map) {
          text = ['code', 'type', 'status', 'message']
              .map((key) => error[key] is String ? error[key] : '')
              .join(' ')
              .toLowerCase();
        }
        if (error is String) text = error.toLowerCase();
      }
    } catch (_) {}
    if (text.contains('quota') ||
        text.contains('billing') ||
        text.contains('insufficient')) {
      return TavernProviderFailure(
        TavernProviderErrorKind.quota,
        httpStatus: status,
      );
    }
    if (text.contains('invalid_api_key') || text.contains('authentication')) {
      return TavernProviderFailure(
        TavernProviderErrorKind.authentication,
        httpStatus: status,
      );
    }
    if (text.contains('permission_error')) {
      return TavernProviderFailure(
        TavernProviderErrorKind.permission,
        httpStatus: status,
      );
    }
    if (text.contains('overloaded_error') || text.contains('api_error')) {
      return TavernProviderFailure(
        TavernProviderErrorKind.serverAbort,
        httpStatus: status,
      );
    }
    if (text.contains('rate_limit') || text.contains('resource_exhausted')) {
      return TavernProviderFailure(
        TavernProviderErrorKind.rateLimited,
        httpStatus: status,
      );
    }
    final kind = switch (status) {
      401 => TavernProviderErrorKind.authentication,
      403 => TavernProviderErrorKind.permission,
      404 => TavernProviderErrorKind.unknownModel,
      402 => TavernProviderErrorKind.quota,
      429 =>
        text.contains('quota') ||
                text.contains('billing') ||
                text.contains('insufficient')
            ? TavernProviderErrorKind.quota
            : TavernProviderErrorKind.rateLimited,
      _ =>
        text.contains('context') || text.contains('token limit')
            ? TavernProviderErrorKind.contextExceeded
            : text.contains('model') && text.contains('not found')
            ? TavernProviderErrorKind.unknownModel
            : text.contains('parameter') || text.contains('unsupported')
            ? TavernProviderErrorKind.unsupportedCapability
            : TavernProviderErrorKind.serverAbort,
    };
    return TavernProviderFailure(kind, httpStatus: status);
  }

  static bool _localHost(String host) {
    if (host == 'localhost' || host == '::1') return true;
    final parts = host.split('.').map(int.tryParse).toList();
    if (parts.length != 4 ||
        parts.any((part) => part == null || part < 0 || part > 255)) {
      return false;
    }
    return parts[0] == 127 ||
        parts[0] == 10 ||
        parts[0] == 192 && parts[1] == 168 ||
        parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31;
  }
}
