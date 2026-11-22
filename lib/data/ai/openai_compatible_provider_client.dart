// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/network/ai_network_diagnostics.dart';
import '../../core/network/ai_provider_exceptions.dart';
import '../../core/diagnostics/safe_content_fingerprint.dart';
import '../../domain/ai/ai_generation.dart';
import 'ai_usage_codec.dart';
import 'ai_image_content.dart';
import 'ai_provider_client.dart';
import 'sse_decoder.dart';
import 'chat_completion_parameters.dart';

class OpenAiCompatibleProviderClient extends AiProviderClient {
  OpenAiCompatibleProviderClient({
    required Uri baseUri,
    required String apiKey,
    required http.Client httpClient,
    this.providerType = 'custom',
    this.timeout = const Duration(seconds: 10),
    this.diagnostics = const DeveloperAiNetworkDiagnostics(),
  }) : _baseUri = baseUri,
       _apiKey = apiKey,
       _httpClient = httpClient;

  final Uri _baseUri;
  final String _apiKey;
  final http.Client _httpClient;
  final String providerType;
  final Duration timeout;
  final AiNetworkDiagnostics diagnostics;
  bool _closed = false;

  Duration get firstByteTimeout => timeout;
  Duration get streamIdleTimeout => timeout;

  @override
  Future<List<String>> listModels() async {
    _ensureOpen();
    final uri = _appendPath(_baseUri, 'models');
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _httpClient
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
            },
          )
          .timeout(timeout);
      _record(
        requestId: 'models',
        method: 'GET',
        uri: uri,
        model: '',
        stopwatch: stopwatch,
        statusCode: response.statusCode,
      );
      _throwForStatus(response.statusCode);
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) {
        throw const AiProviderProtocolException();
      }
      final models = <String>{};
      for (final item in decoded['data'] as List) {
        if (item is Map && item['id'] is String) {
          final id = (item['id'] as String).trim();
          if (id.isNotEmpty) {
            models.add(id);
          }
        }
      }
      if (models.isEmpty) {
        throw const AiProviderProtocolException('模型列表为空，可以稍后手动填写模型 ID。');
      }
      final result = models.toList()..sort();
      return List.unmodifiable(result);
    } on AiProviderException catch (error) {
      _recordException('models', 'GET', uri, '', stopwatch, error);
      rethrow;
    } on TimeoutException catch (error) {
      _recordException(
        'models',
        'GET',
        uri,
        '',
        stopwatch,
        error,
        timeoutStage: 'response',
      );
      throw const AiProviderTimeoutException();
    } on HandshakeException catch (error) {
      _recordException('models', 'GET', uri, '', stopwatch, error);
      throw const AiProviderHandshakeException();
    } on SocketException catch (error) {
      _recordException('models', 'GET', uri, '', stopwatch, error);
      throw const AiProviderNetworkException();
    } on http.ClientException catch (error) {
      _recordException('models', 'GET', uri, '', stopwatch, error);
      throw _mapClientException(error);
    } on FormatException catch (error) {
      _recordException('models', 'GET', uri, '', stopwatch, error);
      throw const AiProviderProtocolException();
    }
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async {
    _ensureOpen();
    final model = _validatedModel(request, cancellation);
    final uri = _appendPath(_baseUri, 'chat/completions');
    final stopwatch = Stopwatch()..start();
    final httpRequest = _generationRequest(
      uri: uri,
      request: request,
      model: model,
      stream: false,
    );
    cancellation?.attach(close);
    try {
      final response = await _httpClient.send(httpRequest).timeout(timeout);
      final body = await response.stream.bytesToString().timeout(timeout);
      _record(
        requestId: request.requestId,
        method: 'POST',
        uri: uri,
        model: model,
        stopwatch: stopwatch,
        statusCode: response.statusCode,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _throwForGenerationStatus(response.statusCode, body);
      }
      if (cancellation?.isCancelled ?? false) {
        throw const AiProviderCancelledException();
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const AiProviderInvalidResponseException(
          'openai-compatible response root parse failed',
        );
      }
      final usage = openAiUsage(decoded['usage']);
      if (usage != null) request.reportUsage(usage);
      final finishReason = _openAiNonStreamFinishReason(decoded);
      if (finishReason == AiFinishReason.length) {
        throw const AiProviderInterruptedException();
      }
      final choices = decoded['choices'];
      if (choices is List && choices.firstOrNull is Map) {
        final message = (choices.first as Map)['message'];
        if (message is Map) {
          request.reportNativeReasoning(
            _openAiContent(message['reasoning_content']),
          );
        }
      }
      final content = _openAiResponseText(decoded);
      if (content.trim().isEmpty) {
        throw _openAiEmptyResponseException(
          provider: providerType,
          model: model,
          httpStatus: response.statusCode,
          decoded: decoded,
          content: content,
          finishReason: finishReason,
          streamEventCount: 1,
        );
      }
      return content;
    } on AiProviderException catch (error) {
      _recordException(request.requestId, 'POST', uri, model, stopwatch, error);
      rethrow;
    } on TimeoutException catch (error) {
      if (cancellation?.isCancelled ?? false) {
        throw const AiProviderCancelledException();
      }
      _recordException(
        request.requestId,
        'POST',
        uri,
        model,
        stopwatch,
        error,
        timeoutStage: 'response',
      );
      throw const AiProviderTimeoutException();
    } on HandshakeException catch (error) {
      _recordException(request.requestId, 'POST', uri, model, stopwatch, error);
      throw const AiProviderHandshakeException();
    } on SocketException catch (error) {
      _recordException(request.requestId, 'POST', uri, model, stopwatch, error);
      throw const AiProviderNetworkException();
    } on http.ClientException catch (error) {
      if (cancellation?.isCancelled ?? false) {
        throw const AiProviderCancelledException();
      }
      _recordException(request.requestId, 'POST', uri, model, stopwatch, error);
      throw _mapClientException(error);
    } on FormatException catch (error) {
      _recordException(request.requestId, 'POST', uri, model, stopwatch, error);
      throw const AiProviderInvalidResponseException(
        'openai-compatible response json parse failed',
      );
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
    _ensureOpen();
    final model = _validatedModel(request, cancellation);
    final uri = _appendPath(_baseUri, 'chat/completions');
    final generationStartedAt = DateTime.now().toUtc();
    final stopwatch = Stopwatch()..start();
    final httpRequest = _generationRequest(
      uri: uri,
      request: request,
      model: model,
      stream: true,
    );

    cancellation?.attach(close);
    var receivedContent = false;
    var receivedDone = false;
    AiFinishReason? finishReason;
    String? rawProviderFinishReason;
    DateTime? firstByteAt;
    DateTime? httpResponseAt;
    DateTime? lastChunkAt;
    var streamEventCount = 0;
    var candidateCount = 0;
    var partCount = 0;
    var textPartCount = 0;
    var receivedCharacterCount = 0;
    final accumulated = StringBuffer();
    var responseStatus = 0;
    String? responseContentType;
    try {
      final response = await _httpClient
          .send(httpRequest)
          .timeout(firstByteTimeout);
      responseStatus = response.statusCode;
      responseContentType = response.headers['content-type'];
      httpResponseAt = DateTime.now().toUtc();
      _record(
        requestId: request.requestId,
        method: 'POST',
        uri: uri,
        model: model,
        stopwatch: stopwatch,
        statusCode: response.statusCode,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorBody = await response.stream.bytesToString().timeout(
          timeout,
        );
        _throwForGenerationStatus(response.statusCode, errorBody);
      }
      final trackedBytes = response.stream.map((bytes) {
        if (bytes.isNotEmpty) {
          final chunkAt = DateTime.now().toUtc();
          firstByteAt ??= chunkAt;
          lastChunkAt = chunkAt;
        }
        return bytes;
      });
      await for (final data in decodeSseData(
        trackedBytes.timeout(streamIdleTimeout),
      )) {
        if (cancellation?.isCancelled ?? false) {
          throw const AiProviderCancelledException();
        }
        final trimmed = data.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        if (trimmed == '[DONE]') {
          receivedDone = true;
          break;
        }
        final decoded = jsonDecode(trimmed);
        streamEventCount += 1;
        if (decoded is Map) {
          final usage = openAiUsage(decoded['usage']);
          if (usage != null) request.reportUsage(usage);
          if (usage != null && decoded['choices'] == null) continue;
        }
        if (decoded is! Map || decoded['choices'] is! List) {
          throw const AiProviderInvalidResponseException(
            'openai-compatible stream choices parse failed',
          );
        }
        final choices = decoded['choices'] as List;
        candidateCount += choices.length;
        if (choices.isEmpty || choices.first is! Map) {
          continue;
        }
        final choice = choices.first as Map;
        final rawFinishReason = choice['finish_reason'];
        if (rawFinishReason is String && rawFinishReason.isNotEmpty) {
          rawProviderFinishReason = rawFinishReason;
          finishReason = _openAiFinishReason(rawFinishReason);
        }
        final delta = choice['delta'];
        if (delta is! Map) {
          continue;
        }
        request.reportNativeReasoning(
          _openAiContent(delta['reasoning_content']),
        );
        final stats = _openAiContentStats(delta['content']);
        partCount += stats.partCount;
        textPartCount += stats.textPartCount;
        final content = _openAiContent(delta['content']);
        if (content.isNotEmpty) {
          receivedContent = true;
          receivedCharacterCount += content.length;
          accumulated.write(content);
          yield AiStreamEvent.content(content);
        }
      }
      if (!receivedContent && finishReason == null && !receivedDone) {
        throw _beforeContentInterruption(
          model: model,
          httpStatus: responseStatus,
          responseContentType: responseContentType,
          firstByteReceived: firstByteAt != null,
          firstSseEventReceived: streamEventCount > 0,
          streamEventCount: streamEventCount,
          candidateCount: candidateCount,
          partCount: partCount,
          textPartCount: textPartCount,
          causeType: responseStatus == 0
              ? 'abnormal-eof'
              : 'responseBodyInterrupted',
        );
      }
      if (!receivedContent) {
        throw AiProviderInvalidResponseException.empty(
          emptyKind: finishReason == AiFinishReason.contentFiltered
              ? AiEmptyResponseKind.filteredEmpty
              : AiEmptyResponseKind.providerEmpty,
          responseDiagnostics: AiProviderResponseDiagnostics(
            provider: providerType,
            model: model,
            httpStatus: responseStatus == 0 ? null : responseStatus,
            rawFinishReason: rawProviderFinishReason,
            normalizedFinishReason: finishReason?.name,
            candidateCount: candidateCount,
            partCount: partCount,
            textPartCount: textPartCount,
            rawReceivedChars: receivedCharacterCount,
            normalizedChars: receivedCharacterCount,
            finalResultChars: 0,
            streamEventCount: streamEventCount,
            streamClosedNormally: finishReason != null || receivedDone,
            abnormalEof: finishReason == null && !receivedDone,
          ),
        );
      }
      if (finishReason == null && !receivedDone) {
        throw const AiProviderInterruptedException(causeType: 'abnormal-eof');
      }
      finishReason ??= AiFinishReason.stop;
      _record(
        requestId: request.requestId,
        method: 'POST',
        uri: uri,
        model: model,
        stopwatch: stopwatch,
        statusCode: responseStatus,
        stage: 'stream.response.completed',
        streamEventCount: streamEventCount,
        receivedCharacterCount: receivedCharacterCount,
        authoritativeCharacterCount: receivedCharacterCount,
        adapterHash: safeContentFingerprint(accumulated.toString()),
        rawFinishReason: rawProviderFinishReason,
        normalizedFinishReason: finishReason.name,
        generationStartedAt: generationStartedAt,
        httpResponseAt: httpResponseAt,
        firstByteAt: firstByteAt,
        lastChunkAt: lastChunkAt,
        streamEndAt: DateTime.now().toUtc(),
        streamClosedNormally: true,
        timeoutType: 'none',
        lastEventIndex: streamEventCount - 1,
        requestedMaxOutputTokens: request.maxTokens,
      );
      yield AiStreamEvent.finished(finishReason);
    } on AiProviderException catch (error) {
      _recordException(
        request.requestId,
        'POST',
        uri,
        model,
        stopwatch,
        error,
        statusCode: responseStatus == 0 ? null : responseStatus,
        stage: 'stream.response.failed',
        streamEventCount: streamEventCount,
        receivedCharacterCount: receivedCharacterCount,
        authoritativeCharacterCount: receivedCharacterCount,
        adapterHash: receivedCharacterCount == 0
            ? null
            : safeContentFingerprint(accumulated.toString()),
        rawFinishReason: rawProviderFinishReason,
        normalizedFinishReason: finishReason?.name,
        generationStartedAt: generationStartedAt,
        httpResponseAt: httpResponseAt,
        firstByteAt: firstByteAt,
        lastChunkAt: lastChunkAt,
        streamEndAt: DateTime.now().toUtc(),
        streamClosedNormally: false,
        timeoutType: error is AiProviderInterruptedException
            ? error.timeoutType
            : 'none',
        lastEventIndex: streamEventCount - 1,
        requestedMaxOutputTokens: request.maxTokens,
      );
      if (receivedContent && error is AiProviderInvalidResponseException) {
        throw const AiProviderInterruptedException(
          causeType: 'InvalidResponse',
        );
      }
      rethrow;
    } on TimeoutException catch (error) {
      if (cancellation?.isCancelled ?? false) {
        throw const AiProviderCancelledException();
      }
      final timeoutType = receivedContent ? 'idle' : 'firstByte';
      _recordException(
        request.requestId,
        'POST',
        uri,
        model,
        stopwatch,
        error,
        timeoutStage: timeoutType,
        stage: 'stream.response.failed',
        streamEventCount: streamEventCount,
        receivedCharacterCount: receivedCharacterCount,
        authoritativeCharacterCount: receivedCharacterCount,
        rawFinishReason: rawProviderFinishReason,
        normalizedFinishReason: finishReason?.name,
        generationStartedAt: generationStartedAt,
        httpResponseAt: httpResponseAt,
        firstByteAt: firstByteAt,
        lastChunkAt: lastChunkAt,
        streamEndAt: DateTime.now().toUtc(),
        streamClosedNormally: false,
        timeoutType: timeoutType,
        lastEventIndex: streamEventCount - 1,
        requestedMaxOutputTokens: request.maxTokens,
      );
      if (receivedContent) {
        throw const AiProviderInterruptedException(
          causeType: 'TimeoutException',
          timeoutType: 'idle',
        );
      }
      throw _beforeContentInterruption(
        model: model,
        httpStatus: responseStatus,
        responseContentType: responseContentType,
        firstByteReceived: firstByteAt != null,
        firstSseEventReceived: streamEventCount > 0,
        streamEventCount: streamEventCount,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        causeType: 'TimeoutException',
        timeoutType: timeoutType,
      );
    } on HandshakeException catch (error) {
      _recordException(request.requestId, 'POST', uri, model, stopwatch, error);
      throw const AiProviderHandshakeException();
    } on SocketException catch (error) {
      _recordStreamTransportException(
        request: request,
        uri: uri,
        model: model,
        stopwatch: stopwatch,
        error: error,
        responseStatus: responseStatus,
        streamEventCount: streamEventCount,
        receivedCharacterCount: receivedCharacterCount,
        rawFinishReason: rawProviderFinishReason,
        normalizedFinishReason: finishReason?.name,
        generationStartedAt: generationStartedAt,
        httpResponseAt: httpResponseAt,
        firstByteAt: firstByteAt,
        lastChunkAt: lastChunkAt,
      );
      if (receivedContent) {
        throw const AiProviderInterruptedException(
          causeType: 'SocketException',
        );
      }
      throw _beforeContentInterruption(
        model: model,
        httpStatus: responseStatus,
        responseContentType: responseContentType,
        firstByteReceived: firstByteAt != null,
        firstSseEventReceived: streamEventCount > 0,
        streamEventCount: streamEventCount,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        causeType: 'SocketException',
      );
    } on http.ClientException catch (error) {
      if (cancellation?.isCancelled ?? false) {
        throw const AiProviderCancelledException();
      }
      _recordStreamTransportException(
        request: request,
        uri: uri,
        model: model,
        stopwatch: stopwatch,
        error: error,
        responseStatus: responseStatus,
        streamEventCount: streamEventCount,
        receivedCharacterCount: receivedCharacterCount,
        rawFinishReason: rawProviderFinishReason,
        normalizedFinishReason: finishReason?.name,
        generationStartedAt: generationStartedAt,
        httpResponseAt: httpResponseAt,
        firstByteAt: firstByteAt,
        lastChunkAt: lastChunkAt,
      );
      if (receivedContent) {
        throw const AiProviderInterruptedException(
          causeType: 'ClientException',
        );
      }
      final mapped = _mapClientException(error);
      if (mapped is AiProviderHandshakeException) throw mapped;
      throw _beforeContentInterruption(
        model: model,
        httpStatus: responseStatus,
        responseContentType: responseContentType,
        firstByteReceived: firstByteAt != null,
        firstSseEventReceived: streamEventCount > 0,
        streamEventCount: streamEventCount,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        causeType: 'ClientException',
      );
    } on FormatException catch (error) {
      _recordException(request.requestId, 'POST', uri, model, stopwatch, error);
      if (receivedContent) {
        throw const AiProviderInterruptedException(
          causeType: 'InvalidResponse',
        );
      }
      throw const AiProviderInvalidResponseException(
        'openai-compatible stream event json parse failed',
      );
    } finally {
      cancellation?.detach();
    }
  }

  void _recordStreamTransportException({
    required AiGenerationRequest request,
    required Uri uri,
    required String model,
    required Stopwatch stopwatch,
    required Object error,
    required int responseStatus,
    required int streamEventCount,
    required int receivedCharacterCount,
    required String? rawFinishReason,
    required String? normalizedFinishReason,
    required DateTime generationStartedAt,
    required DateTime? httpResponseAt,
    required DateTime? firstByteAt,
    required DateTime? lastChunkAt,
  }) {
    _recordException(
      request.requestId,
      'POST',
      uri,
      model,
      stopwatch,
      error,
      statusCode: responseStatus == 0 ? null : responseStatus,
      stage: 'stream.response.failed',
      streamEventCount: streamEventCount,
      receivedCharacterCount: receivedCharacterCount,
      authoritativeCharacterCount: receivedCharacterCount,
      rawFinishReason: rawFinishReason,
      normalizedFinishReason: normalizedFinishReason,
      generationStartedAt: generationStartedAt,
      httpResponseAt: httpResponseAt,
      firstByteAt: firstByteAt,
      lastChunkAt: lastChunkAt,
      streamEndAt: DateTime.now().toUtc(),
      streamClosedNormally: false,
      timeoutType: 'none',
      lastEventIndex: streamEventCount - 1,
      requestedMaxOutputTokens: request.maxTokens,
    );
  }

  AiProviderInterruptedBeforeContentException _beforeContentInterruption({
    required String model,
    required int httpStatus,
    required String? responseContentType,
    required bool firstByteReceived,
    required bool firstSseEventReceived,
    required int streamEventCount,
    required int candidateCount,
    required int partCount,
    required int textPartCount,
    required String causeType,
    String timeoutType = 'none',
  }) {
    return AiProviderInterruptedBeforeContentException(
      causeType: causeType,
      timeoutType: timeoutType,
      responseDiagnostics: AiProviderResponseDiagnostics(
        provider: providerType,
        model: model,
        httpStatus: httpStatus == 0 ? null : httpStatus,
        responseContentType: responseContentType,
        firstByteReceived: firstByteReceived,
        firstSseEventReceived: firstSseEventReceived,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        rawReceivedChars: 0,
        normalizedChars: 0,
        finalResultChars: 0,
        streamEventCount: streamEventCount,
        streamClosedNormally: false,
        abnormalEof: true,
        exceptionType: causeType,
      ),
    );
  }

  http.Request _generationRequest({
    required Uri uri,
    required AiGenerationRequest request,
    required String model,
    required bool stream,
  }) {
    final messages = <Map<String, Object?>>[
      if (request.systemPrompt.trim().isNotEmpty)
        {'role': 'system', 'content': request.systemPrompt.trim()},
      for (final message in request.messages)
        {'role': message.role.name, 'content': openAiMessageContent(message)},
    ];
    final body = <String, Object?>{
      'model': model,
      'messages': messages,
      'stream': stream,
      if (stream &&
          const {'openai', 'qwen', 'deepseek', 'grok'}.contains(providerType))
        'stream_options': const {'include_usage': true},
      ...request.sampling,
      ...chatCompletionParameters(
        provider: providerType,
        model: model,
        temperature: request.temperature,
        maxTokens: request.maxTokens,
        structuredJson: request.structuredJson,
        reasoning: request.reasoning,
      ),
    };
    request.reportAppliedParameters({
      for (final e in body.entries)
        if (!const {'messages', 'model'}.contains(e.key)) e.key: e.value,
    });
    return http.Request('POST', uri)
      ..headers.addAll({
        'Accept': stream ? 'text/event-stream' : 'application/json',
        'Content-Type': 'application/json',
        if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
      })
      ..body = jsonEncode(body);
  }

  String _validatedModel(
    AiGenerationRequest request,
    AiRequestCancellation? cancellation,
  ) {
    final model = request.model?.trim() ?? '';
    if (model.isEmpty) {
      throw const AiProviderModelUnavailableException();
    }
    if (cancellation?.isCancelled ?? false) {
      throw const AiProviderCancelledException();
    }
    return model;
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _httpClient.close();
  }

  void _ensureOpen() {
    if (_closed) {
      throw const AiProviderNetworkException('连接已经关闭，请重新测试。');
    }
  }

  void _throwForStatus(int statusCode) {
    if (statusCode == 401) {
      throw const AiProviderAuthenticationException();
    }
    if (statusCode == 403) {
      throw const AiProviderRequestRejectedException();
    }
    if (statusCode == 404) {
      throw const AiProviderEndpointException();
    }
    if (statusCode == 408) {
      throw const AiProviderTimeoutException();
    }
    if (statusCode == 429) {
      throw const AiProviderRateLimitedException();
    }
    if (statusCode >= 500) {
      throw const AiProviderServerException();
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw const AiProviderProtocolException('模型列表暂时不可用，请检查服务地址。');
    }
  }

  Never _throwForGenerationStatus(int statusCode, String responseBody) {
    final body = responseBody.toLowerCase();
    if (statusCode == 401) {
      throw const AiProviderAuthenticationException();
    }
    if (statusCode == 403) {
      throw const AiProviderRequestRejectedException();
    }
    if (statusCode == 408) {
      throw const AiProviderTimeoutException();
    }
    if (statusCode == 429) {
      throw const AiProviderRateLimitedException();
    }
    if (statusCode == 404) {
      if (body.contains('model_not_found')) {
        throw const AiProviderModelUnavailableException();
      }
      throw const AiProviderEndpointException();
    }
    if (statusCode == 413 ||
        body.contains('context length') ||
        body.contains('context_length') ||
        body.contains('too many tokens')) {
      throw const AiProviderContextTooLargeException();
    }
    if (statusCode == 400 &&
        (body.contains('model_not_found') ||
            body.contains('unknown model') ||
            body.contains('invalid model') ||
            body.contains('model does not exist'))) {
      throw const AiProviderModelUnavailableException();
    }
    if (statusCode == 400 || statusCode == 422) {
      throw const AiProviderValidationException('模型不接受当前生成参数，请检查模型与接口配置。');
    }
    if (statusCode >= 500) {
      throw const AiProviderServerException();
    }
    throw const AiProviderProtocolException('Provider 拒绝了生成请求。');
  }

  AiProviderException _mapClientException(http.ClientException error) {
    final message = error.message.toLowerCase();
    if (message.contains('handshake') ||
        message.contains('certificate') ||
        message.contains('tls')) {
      return const AiProviderHandshakeException();
    }
    return const AiProviderNetworkException();
  }

  void _record({
    required String requestId,
    required String method,
    required Uri uri,
    required String model,
    required Stopwatch stopwatch,
    int? statusCode,
    String? exceptionType,
    String? timeoutStage,
    String? stage,
    int? streamEventCount,
    int? receivedCharacterCount,
    int? authoritativeCharacterCount,
    String? adapterHash,
    String? rawFinishReason,
    String? normalizedFinishReason,
    DateTime? generationStartedAt,
    DateTime? httpResponseAt,
    DateTime? firstByteAt,
    DateTime? lastChunkAt,
    DateTime? streamEndAt,
    bool? streamClosedNormally,
    String? timeoutType,
    int? lastEventIndex,
    int? requestedMaxOutputTokens,
  }) {
    diagnostics.record(
      AiNetworkDiagnosticEvent(
        requestId: requestId,
        providerType: providerType,
        method: method,
        host: uri.host,
        path: uri.path,
        model: model,
        apiKeyPresent: _apiKey.isNotEmpty,
        statusCode: statusCode,
        exceptionType: exceptionType,
        timeoutStage: timeoutStage,
        stage: stage,
        streamEventCount: streamEventCount,
        receivedCharacterCount: receivedCharacterCount,
        authoritativeCharacterCount: authoritativeCharacterCount,
        adapterHash: adapterHash,
        rawFinishReason: rawFinishReason,
        normalizedFinishReason: normalizedFinishReason,
        generationStartedAt: generationStartedAt,
        httpResponseAt: httpResponseAt,
        firstByteAt: firstByteAt,
        lastChunkAt: lastChunkAt,
        streamEndAt: streamEndAt,
        streamClosedNormally: streamClosedNormally,
        timeoutType: timeoutType,
        lastEventIndex: lastEventIndex,
        requestedMaxOutputTokens: requestedMaxOutputTokens,
        duration: stopwatch.elapsed,
      ),
    );
  }

  void _recordException(
    String requestId,
    String method,
    Uri uri,
    String model,
    Stopwatch stopwatch,
    Object error, {
    int? statusCode,
    String? timeoutStage,
    String? stage,
    int? streamEventCount,
    int? receivedCharacterCount,
    int? authoritativeCharacterCount,
    String? adapterHash,
    String? rawFinishReason,
    String? normalizedFinishReason,
    DateTime? generationStartedAt,
    DateTime? httpResponseAt,
    DateTime? firstByteAt,
    DateTime? lastChunkAt,
    DateTime? streamEndAt,
    bool? streamClosedNormally,
    String? timeoutType,
    int? lastEventIndex,
    int? requestedMaxOutputTokens,
  }) {
    _record(
      requestId: requestId,
      method: method,
      uri: uri,
      model: model,
      stopwatch: stopwatch,
      statusCode: statusCode,
      exceptionType: error.runtimeType.toString(),
      timeoutStage: timeoutStage,
      stage: stage,
      streamEventCount: streamEventCount,
      receivedCharacterCount: receivedCharacterCount,
      authoritativeCharacterCount: authoritativeCharacterCount,
      adapterHash: adapterHash,
      rawFinishReason: rawFinishReason,
      normalizedFinishReason: normalizedFinishReason,
      generationStartedAt: generationStartedAt,
      httpResponseAt: httpResponseAt,
      firstByteAt: firstByteAt,
      lastChunkAt: lastChunkAt,
      streamEndAt: streamEndAt,
      streamClosedNormally: streamClosedNormally,
      timeoutType: timeoutType,
      lastEventIndex: lastEventIndex,
      requestedMaxOutputTokens: requestedMaxOutputTokens,
    );
  }
}

AiFinishReason _openAiFinishReason(String value) {
  return switch (value.toLowerCase()) {
    'stop' => AiFinishReason.stop,
    'length' || 'max_tokens' => AiFinishReason.length,
    'content_filter' || 'content_filtered' => AiFinishReason.contentFiltered,
    'cancelled' || 'canceled' => AiFinishReason.cancelled,
    _ => AiFinishReason.unknown,
  };
}

AiFinishReason? _openAiNonStreamFinishReason(Map decoded) {
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty || choices.first is! Map) {
    return null;
  }
  final value = (choices.first as Map)['finish_reason'];
  return value is String && value.isNotEmpty
      ? _openAiFinishReason(value)
      : null;
}

AiProviderInvalidResponseException _openAiEmptyResponseException({
  required String provider,
  required String model,
  required int httpStatus,
  required Map decoded,
  required String content,
  required AiFinishReason? finishReason,
  required int streamEventCount,
}) {
  final choices = decoded['choices'];
  final candidateCount = choices is List ? choices.length : 0;
  Object? rawContent;
  String? rawFinishReason;
  if (choices is List && choices.isNotEmpty && choices.first is Map) {
    final choice = choices.first as Map;
    rawFinishReason = choice['finish_reason'] as String?;
    final message = choice['message'];
    rawContent = message is Map ? message['content'] : choice['text'];
  }
  final stats = _openAiContentStats(rawContent);
  final whitespaceOnly = content.isNotEmpty && content.trim().isEmpty;
  return AiProviderInvalidResponseException.empty(
    emptyKind: finishReason == AiFinishReason.contentFiltered
        ? AiEmptyResponseKind.filteredEmpty
        : whitespaceOnly
        ? AiEmptyResponseKind.whitespaceOnly
        : AiEmptyResponseKind.providerEmpty,
    responseDiagnostics: AiProviderResponseDiagnostics(
      provider: provider,
      model: model,
      httpStatus: httpStatus,
      rawFinishReason: rawFinishReason,
      normalizedFinishReason: finishReason?.name,
      candidateCount: candidateCount,
      partCount: stats.partCount,
      textPartCount: stats.textPartCount,
      rawReceivedChars: content.length,
      normalizedChars: content.length,
      finalResultChars: 0,
      streamEventCount: streamEventCount,
      streamClosedNormally: finishReason != null,
      abnormalEof: finishReason == null,
    ),
  );
}

class _OpenAiContentStats {
  const _OpenAiContentStats(this.partCount, this.textPartCount);

  final int partCount;
  final int textPartCount;

  _OpenAiContentStats operator +(_OpenAiContentStats other) =>
      _OpenAiContentStats(
        partCount + other.partCount,
        textPartCount + other.textPartCount,
      );
}

_OpenAiContentStats _openAiContentStats(Object? value) {
  if (value is String) {
    return const _OpenAiContentStats(1, 1);
  }
  if (value is List) {
    var result = const _OpenAiContentStats(0, 0);
    for (final part in value) {
      result += _openAiContentStats(part);
    }
    return result;
  }
  if (value is Map) {
    final nested = value['text'] ?? value['content'];
    if (nested == null) return const _OpenAiContentStats(1, 0);
    final nestedStats = _openAiContentStats(nested);
    return _OpenAiContentStats(
      nestedStats.partCount == 0 ? 1 : nestedStats.partCount,
      nestedStats.textPartCount,
    );
  }
  return const _OpenAiContentStats(0, 0);
}

class OpenAiProviderClient extends OpenAiCompatibleProviderClient {
  OpenAiProviderClient({
    required super.baseUri,
    required super.apiKey,
    required super.httpClient,
    super.timeout,
    super.diagnostics,
  }) : super(providerType: 'openai');
}

class DeepSeekProviderClient extends OpenAiCompatibleProviderClient {
  DeepSeekProviderClient({
    required super.baseUri,
    required super.apiKey,
    required super.httpClient,
    super.timeout,
    super.diagnostics,
  }) : super(providerType: 'deepseek');
}

class KimiProviderClient extends OpenAiCompatibleProviderClient {
  KimiProviderClient({
    required super.baseUri,
    required super.apiKey,
    required super.httpClient,
    super.timeout,
    super.diagnostics,
  }) : super(providerType: 'kimi');
}

Uri _appendPath(Uri baseUri, String segment) {
  final parts = baseUri.pathSegments.where((part) => part.isNotEmpty).toList();
  final appended = segment.split('/').where((part) => part.isNotEmpty);
  return baseUri.replace(pathSegments: [...parts, ...appended]);
}

String _openAiContent(Object? value) {
  if (value is String) {
    return value;
  }
  if (value is Map) {
    return _openAiContent(value['text'] ?? value['content']);
  }
  if (value is List) {
    return value.map(_openAiContent).join();
  }
  return '';
}

String _openAiResponseText(Map decoded) {
  final choices = decoded['choices'];
  if (choices is List && choices.isNotEmpty && choices.first is Map) {
    final choice = choices.first as Map;
    final message = choice['message'];
    if (message is Map) {
      final content = _openAiContent(message['content']);
      if (content.isNotEmpty) {
        return content;
      }
      final reasoning = _openAiContent(message['reasoning_content']);
      if (reasoning.isNotEmpty) {
        return reasoning;
      }
    }
    final text = _openAiContent(choice['text']);
    if (text.isNotEmpty) {
      return text;
    }
    final delta = choice['delta'];
    if (delta is Map) {
      final content = _openAiContent(delta['content']);
      if (content.isNotEmpty) {
        return content;
      }
    }
  }
  final outputText = _openAiContent(decoded['output_text']);
  if (outputText.isNotEmpty) {
    return outputText;
  }
  final output = decoded['output'];
  if (output is List) {
    for (final item in output.whereType<Map>()) {
      final content = _openAiContent(item['content']);
      if (content.isNotEmpty) {
        return content;
      }
    }
  }
  return '';
}
