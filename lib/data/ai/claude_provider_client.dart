import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../core/network/ai_network_diagnostics.dart';
import '../../core/network/ai_provider_exceptions.dart';
import '../../domain/ai/ai_generation.dart';
import 'ai_usage_codec.dart';
import 'ai_reasoning_parameters.dart';
import 'ai_provider_client.dart';
import 'claude_messages_protocol.dart';
import 'ai_image_content.dart';
import 'sse_decoder.dart';

class ClaudeProviderClient extends AiProviderClient {
  ClaudeProviderClient({
    required this.baseUri,
    required this.apiKey,
    required this.httpClient,
    this.timeout = const Duration(seconds: 90),
    this.diagnostics = const DeveloperAiNetworkDiagnostics(),
  });
  final Uri baseUri;
  final String apiKey;
  final http.Client httpClient;
  final Duration timeout;
  final AiNetworkDiagnostics diagnostics;
  bool _closed = false;
  Uri _uri(String path) => baseUri.replace(
    pathSegments: [...baseUri.pathSegments.where((p) => p.isNotEmpty), path],
  );
  Map<String, String> get _headers => {
    'x-api-key': apiKey,
    'anthropic-version': claudeApiVersion,
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  @override
  Future<List<String>> listModels() async {
    final models = <String>{}, cursors = <String>{};
    String? cursor;
    do {
      final uri = _uri(
        'models',
      ).replace(queryParameters: {'limit': '100', 'after_id': ?cursor});
      final response = await _send(
        http.Request('GET', uri)
          ..followRedirects = false
          ..headers.addAll(_headers),
        'models',
        '',
      );
      final body = await _readBody(response);
      _checkStatus(response.statusCode, body);
      final decoded = _decode(body);
      if (decoded['data'] is! List) throw const AiProviderProtocolException();
      for (final model in decoded['data'] as List) {
        if (model is Map &&
            model['id'] is String &&
            (model['id'] as String).trim().isNotEmpty &&
            model['lifecycle'] != 'retired') {
          models.add((model['id'] as String).trim());
        }
      }
      if (decoded['has_more'] != true) break;
      final next = decoded['last_id'];
      if (next is! String || next.isEmpty || !cursors.add(next)) {
        throw const AiProviderProtocolException('Claude 模型列表分页异常。');
      }
      cursor = next;
    } while (true);
    if (models.isEmpty) {
      throw const AiProviderProtocolException('模型列表为空，可手动填写模型 ID。');
    }
    return List.unmodifiable(models.toList()..sort());
  }

  http.Request _request(AiGenerationRequest request, bool stream) {
    if (request.model?.trim().isNotEmpty != true) {
      throw const AiProviderModelUnavailableException();
    }
    final body = claudeMessagesBody(
      model: request.model!.trim(),
      maxTokens: request.maxTokens ?? 8192,
      stream: stream,
      structuredJson: request.structuredJson,
      messages: [
        if (request.systemPrompt.trim().isNotEmpty)
          {'role': 'system', 'content': request.systemPrompt},
        for (final m in request.messages)
          {
            'role': m.role == AiMessageRole.user ? 'user' : 'assistant',
            'content': claudeMessageContent(m),
          },
      ],
    );
    // Text prefill is restricted by the compiler to supported legacy models.
    body.addAll(request.sampling);
    if (request.assistantPrefill case final prefix?) {
      (body['messages'] as List).add({'role': 'assistant', 'content': prefix});
    }
    body.addAll(
      reasoningParameters(
        provider: 'claude',
        model: request.model!,
        level: request.reasoning,
        maxTokens: request.maxTokens,
      ),
    );
    request.reportAppliedParameters({
      for (final e in body.entries)
        if (!const {'messages', 'model', 'system'}.contains(e.key))
          e.key: e.value,
    });
    return http.Request('POST', _uri('messages'))
      ..followRedirects = false
      ..headers.addAll({
        ..._headers,
        'Accept': stream ? 'text/event-stream' : 'application/json',
      })
      ..body = jsonEncode(body);
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async {
    _checkCancellation(cancellation);
    cancellation?.attach(close);
    try {
      final response = await _send(
        _request(request, false),
        request.requestId,
        request.model ?? '',
      );
      final body = await _readBody(response);
      _checkStatus(response.statusCode, body);
      _checkCancellation(cancellation);
      final decoded = _decode(body);
      if (decoded['usage'] case final Map usageMap) {
        final usage = claudeUsage(usageMap, isFinal: true);
        if (usage != null) request.reportUsage(usage);
      }
      final reason = claudeFinishReason(decoded['stop_reason']);
      if (reason == AiFinishReason.length) {
        throw const AiProviderInterruptedException();
      }
      if (reason == AiFinishReason.contentFiltered) {
        throw const AiProviderRequestRejectedException();
      }
      if (reason != AiFinishReason.stop || decoded['content'] is! List) {
        throw const AiProviderProtocolException();
      }
      for (final block in (decoded['content'] as List).whereType<Map>()) {
        if (block['type'] == 'thinking' && block['thinking'] is String) {
          request.reportNativeReasoning(block['thinking'] as String);
        }
      }
      final text = (decoded['content'] as List)
          .whereType<Map>()
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'] is String ? b['text'] as String : '')
          .join();
      if (text.trim().isEmpty) {
        throw const AiProviderProtocolException('Claude 没有返回可用正文。');
      }
      return text;
    } catch (error) {
      _checkCancellation(cancellation);
      throw _mapError(error);
    } finally {
      cancellation?.detach();
    }
  }

  @override
  Stream<String> streamGenerate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    await for (final event in streamEvents(
      request,
      cancellation: cancellation,
    )) {
      if (event.content.isNotEmpty) yield event.content;
    }
  }

  @override
  Stream<AiStreamEvent> streamEvents(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    _checkCancellation(cancellation);
    cancellation?.attach(close);
    var visible = false;
    final decoder = ClaudeMessageDecoder(
      onUsage: request.reportUsage,
      onReasoning: request.reportNativeReasoning,
    );
    try {
      final response = await _send(
        _request(request, true),
        request.requestId,
        request.model ?? '',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _checkStatus(response.statusCode, await _readBody(response));
      }
      await for (final data in decodeSseData(
        response.stream.timeout(timeout),
      )) {
        _checkCancellation(cancellation);
        for (final event in decoder.add(_decode(data))) {
          if (event.content.isNotEmpty) visible = true;
          if (event.isTerminal) {
            if (!visible &&
                event.finishReason != AiFinishReason.contentFiltered) {
              throw const AiProviderProtocolException('Claude 没有返回可用正文。');
            }
            yield event;
            return;
          }
          yield event;
        }
      }
      if (visible) {
        yield const AiStreamEvent.finished(AiFinishReason.interrupted);
      } else {
        throw const AiProviderInterruptedBeforeContentException(
          causeType: 'abnormal-eof',
        );
      }
    } catch (error) {
      if (cancellation?.isCancelled == true) {
        yield const AiStreamEvent.finished(AiFinishReason.cancelled);
        return;
      }
      final transportFailure =
          error is TimeoutException ||
          error is AiProviderTimeoutException ||
          error is SocketException ||
          error is AiProviderNetworkException ||
          error is http.ClientException;
      if (transportFailure && visible) {
        yield const AiStreamEvent.finished(AiFinishReason.interrupted);
      } else if (transportFailure) {
        throw AiProviderInterruptedBeforeContentException(
          causeType: error.runtimeType.toString(),
          timeoutType:
              error is TimeoutException || error is AiProviderTimeoutException
              ? 'first-byte'
              : 'none',
        );
      } else {
        throw _mapError(error);
      }
    } finally {
      cancellation?.detach();
    }
  }

  Future<http.StreamedResponse> _send(
    http.Request request,
    String id,
    String model,
  ) async {
    if (_closed) throw const AiProviderNetworkException('连接已关闭，请重新尝试。');
    final watch = Stopwatch()..start();
    int? status;
    String? failure;
    try {
      final response = await httpClient.send(request).timeout(timeout);
      status = response.statusCode;
      return response;
    } catch (error) {
      failure = error.runtimeType.toString();
      throw _mapError(error);
    } finally {
      diagnostics.record(
        AiNetworkDiagnosticEvent(
          requestId: id,
          providerType: 'claude',
          method: request.method,
          host: request.url.host,
          path: request.url.path,
          model: model,
          apiKeyPresent: apiKey.isNotEmpty,
          duration: watch.elapsed,
          statusCode: status,
          exceptionType: failure,
        ),
      );
    }
  }

  Future<String> _readBody(http.StreamedResponse response) async {
    try {
      return await response.stream.bytesToString().timeout(timeout);
    } catch (error) {
      throw _mapError(error);
    }
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final value = jsonDecode(body);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      throw const AiProviderProtocolException();
    }
    throw const AiProviderProtocolException();
  }

  void _checkStatus(int status, String body) {
    if (status >= 200 && status < 300) return;
    Map error = const {};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        error = decoded['error'] as Map;
      }
    } on FormatException {
      /* Non-JSON HTTP errors still retain their status. */
    }
    throw claudeHttpError(status, error);
  }

  AiProviderException _mapError(Object error) => switch (error) {
    AiProviderException e => e,
    TimeoutException() => const AiProviderTimeoutException(),
    HandshakeException() => const AiProviderHandshakeException(),
    SocketException() ||
    http.ClientException() => const AiProviderNetworkException(),
    _ => const AiProviderProtocolException(),
  };
  void _checkCancellation(AiRequestCancellation? cancellation) {
    if (cancellation?.isCancelled == true) {
      throw const AiProviderCancelledException();
    }
  }

  @override
  void close() {
    if (!_closed) {
      _closed = true;
      httpClient.close();
    }
  }
}
