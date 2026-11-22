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
import 'ai_reasoning_parameters.dart';
import 'ai_provider_client.dart';
import 'sse_decoder.dart';

class GeminiProviderClient extends AiProviderClient {
  GeminiProviderClient({
    required Uri baseUri,
    required String apiKey,
    required http.Client httpClient,
    this.preferredModel = '',
    this.timeout = const Duration(seconds: 10),
    this.diagnostics = const DeveloperAiNetworkDiagnostics(),
    Map<String, int>? sharedModelOutputLimits,
  }) : _baseUri = baseUri,
       _apiKey = apiKey,
       _httpClient = httpClient,
       _modelOutputLimits = sharedModelOutputLimits ?? <String, int>{};

  final Uri _baseUri;
  final String _apiKey;
  final http.Client _httpClient;
  final String preferredModel;
  final Duration timeout;
  final AiNetworkDiagnostics diagnostics;
  final Map<String, int> _modelOutputLimits;
  bool _closed = false;

  Duration get firstByteTimeout => timeout;
  Duration get streamIdleTimeout => timeout;

  @override
  Future<List<String>> listModels() async {
    final catalog = await _listModelCatalog();
    return catalog.generateContentModelIds;
  }

  @override
  Future<AiProviderConnectionResult> testConnection({
    String? preferredModel,
  }) async {
    final catalog = await _listModelCatalog();
    final requested = _canonicalModelId(preferredModel ?? this.preferredModel);
    final candidates = _orderedConnectionCandidates(catalog, requested);
    final incompatible = <String>[];
    for (final candidate in candidates) {
      try {
        await _testMinimalGeneration(candidate);
        return AiProviderConnectionResult(
          models: catalog.generateContentModelIds,
          verifiedModel: candidate,
          verifiedModels: [candidate],
          incompatibleModels: List.unmodifiable(incompatible),
        );
      } on AiProviderNativeInterfaceIncompatibleException {
        incompatible.add(candidate);
      } on AiProviderException catch (error) {
        throw AiProviderConnectionTestException(
          error.message,
          availableModels: catalog.generateContentModelIds,
          temporaryModel: candidate,
          incompatibleModels: List.unmodifiable(incompatible),
        );
      }
    }
    throw AiProviderConnectionTestException(
      'Gemini 返回的模型均不支持当前 Native 生成接口。',
      availableModels: catalog.generateContentModelIds,
      temporaryModel: candidates.last,
      incompatibleModels: List.unmodifiable(incompatible),
    );
  }

  List<String> _orderedConnectionCandidates(
    _GeminiModelCatalog catalog,
    String requested,
  ) {
    final candidates = [...catalog.generateContentModelIds]
      ..sort((first, second) {
        final rank = _geminiTextModelRank(
          first,
        ).compareTo(_geminiTextModelRank(second));
        if (rank != 0) return rank;
        final previewRank = _geminiPreviewRank(
          first,
        ).compareTo(_geminiPreviewRank(second));
        if (previewRank != 0) return previewRank;
        final versionRank = _geminiVersion(
          second,
        ).compareTo(_geminiVersion(first));
        return versionRank != 0 ? versionRank : first.compareTo(second);
      });
    if (requested.isNotEmpty && candidates.remove(requested)) {
      candidates.insert(0, requested);
    }
    return candidates;
  }

  Future<void> _testMinimalGeneration(String model) async {
    _ensureOpen();
    final uri = _generationUri(model, stream: false);
    final stopwatch = Stopwatch()..start();
    _record(
      requestId: 'gemini-connection-test',
      method: 'POST',
      uri: uri,
      model: model,
      stopwatch: stopwatch,
      stage: 'minimal_generate.request.start',
    );
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll({
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'x-goog-api-key': _apiKey,
        })
        ..body = jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': 'Reply only OK.'},
              ],
            },
          ],
        });
      final response = await _httpClient.send(request).timeout(timeout);
      final body = await response.stream.bytesToString().timeout(timeout);
      final googleError =
          response.statusCode >= 200 && response.statusCode < 300
          ? null
          : _GoogleApiError.tryParse(body);
      _record(
        requestId: 'gemini-connection-test',
        method: 'POST',
        uri: uri,
        model: model,
        stopwatch: stopwatch,
        statusCode: response.statusCode,
        stage: response.statusCode >= 200 && response.statusCode < 300
            ? 'minimal_generate.request.success'
            : 'minimal_generate.request.failed',
        googleError: googleError,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _throwForStatus(response.statusCode, body, modelRequest: true);
      }
      final packet = _geminiPacket(jsonDecode(body));
      if (packet.text.trim().isEmpty) {
        throw _geminiEmptyResponseException(
          model: model,
          httpStatus: response.statusCode,
          responseContentType: response.headers['content-type'],
          firstByteReceived: body.isNotEmpty,
          firstSseEventReceived: false,
          finishReason: packet.finishReason,
          rawFinishReason: packet.rawFinishReason,
          candidateCount: packet.candidateCount,
          partCount: packet.partCount,
          textPartCount: packet.textPartCount,
          rawReceivedChars: packet.text.length,
          normalizedChars: packet.text.length,
          streamEventCount: 0,
          rawSseEventCount: 0,
          parsedResponseObjectCount: 1,
          candidateEventCount: packet.candidatesPresent ? 1 : 0,
          textEventCount: packet.textPartCount > 0 ? 1 : 0,
          topLevelKeys: packet.topLevelKeys,
          promptFeedbackPresent: packet.promptFeedbackPresent,
          promptSafetyRatingsCount: packet.promptSafetyRatingsCount,
          promptSafetyRatingsSummary: packet.promptSafetyRatingsSummary,
          responseIdPresent: packet.responseIdPresent,
          modelVersionPresent: packet.modelVersionPresent,
          usageMetadataPresent: packet.usageMetadataPresent,
          modelStatusPresent: packet.modelStatusPresent,
          streamClosedNormally: true,
          abnormalEof: false,
          promptBlockReason: packet.promptBlockReason,
          promptBlockMessage: packet.promptBlockMessage,
          whitespaceOnly: packet.text.isNotEmpty && packet.text.trim().isEmpty,
        );
      }
    } on AiProviderException {
      rethrow;
    } on TimeoutException catch (error) {
      _recordException(
        'gemini-connection-test',
        'POST',
        uri,
        model,
        stopwatch,
        error,
        timeoutStage: 'minimal_generate',
        stage: 'minimal_generate.request.failed',
      );
      throw const AiProviderTimeoutException();
    } on HandshakeException catch (error) {
      _recordException(
        'gemini-connection-test',
        'POST',
        uri,
        model,
        stopwatch,
        error,
        stage: 'minimal_generate.request.failed',
      );
      throw const AiProviderHandshakeException();
    } on SocketException catch (error) {
      _recordException(
        'gemini-connection-test',
        'POST',
        uri,
        model,
        stopwatch,
        error,
        stage: 'minimal_generate.request.failed',
      );
      throw const AiProviderNetworkException();
    } on http.ClientException catch (error) {
      _recordException(
        'gemini-connection-test',
        'POST',
        uri,
        model,
        stopwatch,
        error,
        stage: 'minimal_generate.request.failed',
      );
      throw _mapClientException(error);
    } on FormatException catch (error) {
      _recordException(
        'gemini-connection-test',
        'POST',
        uri,
        model,
        stopwatch,
        error,
        stage: 'minimal_generate.response.parse.failed',
      );
      throw const AiProviderInvalidResponseException(
        'gemini connection response json parse failed',
      );
    }
  }

  @override
  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async {
    _ensureOpen();
    final model = _validatedModel(request, cancellation);
    final uri = _generationUri(model, stream: false);
    final stopwatch = Stopwatch()..start();
    final httpRequest = _generationRequest(
      uri: uri,
      request: request,
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
        _throwForStatus(response.statusCode, body, modelRequest: true);
      }
      if (cancellation?.isCancelled ?? false) {
        throw const AiProviderCancelledException();
      }
      final decoded = jsonDecode(body);
      final packet = _geminiPacket(decoded);
      request.reportNativeReasoning(_geminiThought(decoded));
      if (decoded is Map) {
        final usage = geminiUsage(decoded['usageMetadata'], isFinal: true);
        if (usage != null) request.reportUsage(usage);
      }
      if (packet.text.trim().isEmpty) {
        throw _geminiEmptyResponseException(
          model: model,
          httpStatus: response.statusCode,
          responseContentType: response.headers['content-type'],
          firstByteReceived: body.isNotEmpty,
          firstSseEventReceived: false,
          finishReason: packet.finishReason,
          rawFinishReason: packet.rawFinishReason,
          candidateCount: packet.candidateCount,
          partCount: packet.partCount,
          textPartCount: packet.textPartCount,
          rawReceivedChars: packet.text.length,
          normalizedChars: packet.text.length,
          streamEventCount: 0,
          rawSseEventCount: 0,
          parsedResponseObjectCount: 1,
          candidateEventCount: packet.candidatesPresent ? 1 : 0,
          textEventCount: packet.textPartCount > 0 ? 1 : 0,
          topLevelKeys: packet.topLevelKeys,
          promptFeedbackPresent: packet.promptFeedbackPresent,
          promptSafetyRatingsCount: packet.promptSafetyRatingsCount,
          promptSafetyRatingsSummary: packet.promptSafetyRatingsSummary,
          responseIdPresent: packet.responseIdPresent,
          modelVersionPresent: packet.modelVersionPresent,
          usageMetadataPresent: packet.usageMetadataPresent,
          modelStatusPresent: packet.modelStatusPresent,
          streamClosedNormally: true,
          abnormalEof: false,
          promptBlockReason: packet.promptBlockReason,
          promptBlockMessage: packet.promptBlockMessage,
          whitespaceOnly: packet.text.isNotEmpty && packet.text.trim().isEmpty,
        );
      }
      return packet.text;
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
        'gemini response json parse failed',
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
    final uri = _generationUri(model, stream: true);
    final generationStartedAt = DateTime.now().toUtc();
    final stopwatch = Stopwatch()..start();
    final httpRequest = _generationRequest(
      uri: uri,
      request: request,
      stream: true,
    );

    cancellation?.attach(close);
    var receivedContent = false;
    var accumulated = '';
    AiFinishReason? finishReason;
    var responseStatus = 0;
    String? responseContentType;
    var rawSseEventCount = 0;
    var parsedResponseObjectCount = 0;
    var candidateEventCount = 0;
    var textEventCount = 0;
    var candidateCount = 0;
    var partCount = 0;
    var textPartCount = 0;
    var maxTextPartsPerEvent = 0;
    var rawReceivedCharacterCount = 0;
    var receivedCharacterCount = 0;
    var sawDelta = false;
    var sawCumulative = false;
    DateTime? firstByteAt;
    DateTime? httpResponseAt;
    DateTime? lastChunkAt;
    DateTime? streamEndAt;
    String? rawFinishReason;
    String? promptBlockReason;
    String? promptBlockMessage;
    var promptFeedbackPresent = false;
    var promptSafetyRatingsCount = 0;
    String? promptSafetyRatingsSummary;
    final topLevelKeys = <String>{};
    var responseIdPresent = false;
    var modelVersionPresent = false;
    var usageMetadataPresent = false;
    Map? latestUsage;
    var modelStatusPresent = false;
    var promptTokenCount = 0;
    var candidatesTokenCount = 0;
    var totalTokenCount = 0;
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
        _throwForStatus(response.statusCode, errorBody, modelRequest: true);
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
        if (trimmed.isEmpty || trimmed == '[DONE]') continue;
        rawSseEventCount += 1;
        final decoded = jsonDecode(trimmed);
        final packet = _geminiPacket(decoded);
        request.reportNativeReasoning(_geminiThought(decoded));
        if (decoded is Map) {
          if (decoded['usageMetadata'] is Map) {
            latestUsage = decoded['usageMetadata'] as Map;
          }
          final usage = geminiUsage(
            decoded['usageMetadata'],
            isFinal: packet.finishReason != null,
          );
          if (usage != null) request.reportUsage(usage);
        }
        parsedResponseObjectCount += 1;
        if (packet.candidatesPresent) candidateEventCount += 1;
        if (packet.textPartCount > 0) textEventCount += 1;
        topLevelKeys.addAll(
          packet.topLevelKeys.split(',').where((key) => key.isNotEmpty),
        );
        promptFeedbackPresent =
            promptFeedbackPresent || packet.promptFeedbackPresent;
        promptSafetyRatingsCount += packet.promptSafetyRatingsCount;
        promptSafetyRatingsSummary =
            packet.promptSafetyRatingsSummary ?? promptSafetyRatingsSummary;
        responseIdPresent = responseIdPresent || packet.responseIdPresent;
        modelVersionPresent = modelVersionPresent || packet.modelVersionPresent;
        usageMetadataPresent =
            usageMetadataPresent || packet.usageMetadataPresent;
        modelStatusPresent = modelStatusPresent || packet.modelStatusPresent;
        candidateCount += packet.candidateCount;
        partCount += packet.partCount;
        textPartCount += packet.textPartCount;
        if (packet.textPartCount > maxTextPartsPerEvent) {
          maxTextPartsPerEvent = packet.textPartCount;
        }
        rawReceivedCharacterCount += packet.text.length;
        rawFinishReason = packet.rawFinishReason ?? rawFinishReason;
        promptBlockReason = packet.promptBlockReason ?? promptBlockReason;
        promptBlockMessage = packet.promptBlockMessage ?? promptBlockMessage;
        promptTokenCount = packet.promptTokenCount ?? promptTokenCount;
        candidatesTokenCount =
            packet.candidatesTokenCount ?? candidatesTokenCount;
        totalTokenCount = packet.totalTokenCount ?? totalTokenCount;
        if (packet.finishReason != null) finishReason = packet.finishReason;
        if (packet.text.isEmpty) continue;
        receivedContent = true;
        final cumulative = _isClearCumulativePacket(accumulated, packet.text);
        final delta = cumulative
            ? packet.text.substring(accumulated.length)
            : packet.text;
        if (cumulative) {
          sawCumulative = true;
          accumulated = packet.text;
        } else {
          sawDelta = true;
          accumulated = '$accumulated${packet.text}';
        }
        receivedCharacterCount += delta.length;
        if (delta.isNotEmpty) yield AiStreamEvent.content(delta);
      }
      streamEndAt = DateTime.now().toUtc();
      if (!receivedContent && promptBlockReason?.trim().isNotEmpty == true) {
        throw _geminiEmptyResponseException(
          model: model,
          httpStatus: responseStatus,
          responseContentType: responseContentType,
          firstByteReceived: firstByteAt != null,
          firstSseEventReceived: rawSseEventCount > 0,
          finishReason: finishReason,
          rawFinishReason: rawFinishReason,
          candidateCount: candidateCount,
          partCount: partCount,
          textPartCount: textPartCount,
          rawReceivedChars: rawReceivedCharacterCount,
          normalizedChars: receivedCharacterCount,
          streamEventCount: rawSseEventCount,
          rawSseEventCount: rawSseEventCount,
          parsedResponseObjectCount: parsedResponseObjectCount,
          candidateEventCount: candidateEventCount,
          textEventCount: textEventCount,
          topLevelKeys: (topLevelKeys.toList()..sort()).join(','),
          promptFeedbackPresent: promptFeedbackPresent,
          promptSafetyRatingsCount: promptSafetyRatingsCount,
          promptSafetyRatingsSummary: promptSafetyRatingsSummary,
          responseIdPresent: responseIdPresent,
          modelVersionPresent: modelVersionPresent,
          usageMetadataPresent: usageMetadataPresent,
          modelStatusPresent: modelStatusPresent,
          streamClosedNormally: true,
          abnormalEof: false,
          promptBlockReason: promptBlockReason,
          promptBlockMessage: promptBlockMessage,
        );
      }
      if (!receivedContent && parsedResponseObjectCount == 0) {
        throw _beforeContentInterruption(
          model: model,
          httpStatus: responseStatus,
          responseContentType: responseContentType,
          firstByteReceived: firstByteAt != null,
          firstSseEventReceived: rawSseEventCount > 0,
          streamEventCount: rawSseEventCount,
          rawSseEventCount: rawSseEventCount,
          parsedResponseObjectCount: parsedResponseObjectCount,
          candidateEventCount: candidateEventCount,
          textEventCount: textEventCount,
          candidateCount: candidateCount,
          partCount: partCount,
          textPartCount: textPartCount,
          rawReceivedChars: rawReceivedCharacterCount,
          normalizedChars: receivedCharacterCount,
          topLevelKeys: (topLevelKeys.toList()..sort()).join(','),
          promptFeedbackPresent: promptFeedbackPresent,
          promptBlockReason: promptBlockReason,
          promptSafetyRatingsCount: promptSafetyRatingsCount,
          promptSafetyRatingsSummary: promptSafetyRatingsSummary,
          responseIdPresent: responseIdPresent,
          modelVersionPresent: modelVersionPresent,
          usageMetadataPresent: usageMetadataPresent,
          modelStatusPresent: modelStatusPresent,
          causeType: responseStatus == 0
              ? 'abnormal-eof'
              : 'responseBodyInterrupted',
        );
      }
      if (!receivedContent) {
        throw _geminiEmptyResponseException(
          model: model,
          httpStatus: responseStatus,
          responseContentType: responseContentType,
          firstByteReceived: firstByteAt != null,
          firstSseEventReceived: rawSseEventCount > 0,
          finishReason: finishReason,
          rawFinishReason: rawFinishReason,
          candidateCount: candidateCount,
          partCount: partCount,
          textPartCount: textPartCount,
          rawReceivedChars: rawReceivedCharacterCount,
          normalizedChars: receivedCharacterCount,
          streamEventCount: rawSseEventCount,
          rawSseEventCount: rawSseEventCount,
          parsedResponseObjectCount: parsedResponseObjectCount,
          candidateEventCount: candidateEventCount,
          textEventCount: textEventCount,
          topLevelKeys: (topLevelKeys.toList()..sort()).join(','),
          promptFeedbackPresent: promptFeedbackPresent,
          promptSafetyRatingsCount: promptSafetyRatingsCount,
          promptSafetyRatingsSummary: promptSafetyRatingsSummary,
          responseIdPresent: responseIdPresent,
          modelVersionPresent: modelVersionPresent,
          usageMetadataPresent: usageMetadataPresent,
          modelStatusPresent: modelStatusPresent,
          streamClosedNormally: true,
          abnormalEof: false,
          promptBlockReason: promptBlockReason,
          promptBlockMessage: promptBlockMessage,
        );
      }
      if (finishReason == null) {
        throw const AiProviderInterruptedException(causeType: 'abnormal-eof');
      }
      _record(
        requestId: request.requestId,
        method: 'POST',
        uri: uri,
        model: model,
        stopwatch: stopwatch,
        statusCode: responseStatus,
        stage: 'stream.response.completed',
        streamEventCount: rawSseEventCount,
        rawSseEventCount: rawSseEventCount,
        parsedResponseObjectCount: parsedResponseObjectCount,
        candidateEventCount: candidateEventCount,
        textEventCount: textEventCount,
        topLevelKeys: (topLevelKeys.toList()..sort()).join(','),
        promptFeedbackPresent: promptFeedbackPresent,
        promptBlockReason: promptBlockReason,
        promptSafetyRatingsCount: promptSafetyRatingsCount,
        promptSafetyRatingsSummary: promptSafetyRatingsSummary,
        responseIdPresent: responseIdPresent,
        modelVersionPresent: modelVersionPresent,
        usageMetadataPresent: usageMetadataPresent,
        modelStatusPresent: modelStatusPresent,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        maxTextPartsPerEvent: maxTextPartsPerEvent,
        rawReceivedCharacterCount: rawReceivedCharacterCount,
        receivedCharacterCount: receivedCharacterCount,
        authoritativeCharacterCount: accumulated.length,
        adapterHash: safeContentFingerprint(accumulated),
        finishReason: finishReason.name,
        rawFinishReason: rawFinishReason,
        normalizedFinishReason: finishReason.name,
        streamNormalization: sawDelta && sawCumulative
            ? 'mixed'
            : sawCumulative
            ? 'cumulative'
            : 'delta',
        generationStartedAt: generationStartedAt,
        httpResponseAt: httpResponseAt,
        firstByteAt: firstByteAt,
        lastChunkAt: lastChunkAt,
        streamEndAt: streamEndAt,
        streamClosedNormally: true,
        abnormalEof: false,
        timeoutType: 'none',
        lastEventIndex: rawSseEventCount - 1,
        requestedMaxOutputTokens: request.maxTokens,
        modelOutputTokenLimit: _modelOutputLimits[model],
        promptTokenCount: promptTokenCount == 0 ? null : promptTokenCount,
        candidatesTokenCount: candidatesTokenCount == 0
            ? null
            : candidatesTokenCount,
        totalTokenCount: totalTokenCount == 0 ? null : totalTokenCount,
      );
      final completedUsage = geminiUsage(latestUsage, isFinal: true);
      if (completedUsage != null) request.reportUsage(completedUsage);
      yield AiStreamEvent.finished(finishReason);
    } on AiProviderException catch (error) {
      final interruption = error is AiProviderInterruptedBeforeContentException
          ? error.responseDiagnostics
          : null;
      final invalidResponse = error is AiProviderInvalidResponseException
          ? error.responseDiagnostics
          : null;
      final responseDiagnostics = interruption ?? invalidResponse;
      _recordException(
        request.requestId,
        'POST',
        uri,
        model,
        stopwatch,
        error,
        statusCode: responseStatus == 0 ? null : responseStatus,
        responseContentType:
            responseDiagnostics?.responseContentType ?? responseContentType,
        firstByteReceived:
            responseDiagnostics?.firstByteReceived ?? firstByteAt != null,
        firstSseEventReceived:
            responseDiagnostics?.firstSseEventReceived ?? rawSseEventCount > 0,
        stage: 'stream.response.failed',
        streamEventCount: rawSseEventCount,
        rawSseEventCount: rawSseEventCount,
        parsedResponseObjectCount: parsedResponseObjectCount,
        candidateEventCount: candidateEventCount,
        textEventCount: textEventCount,
        topLevelKeys: (topLevelKeys.toList()..sort()).join(','),
        promptFeedbackPresent: promptFeedbackPresent,
        promptBlockReason: promptBlockReason,
        promptSafetyRatingsCount: promptSafetyRatingsCount,
        promptSafetyRatingsSummary: promptSafetyRatingsSummary,
        responseIdPresent: responseIdPresent,
        modelVersionPresent: modelVersionPresent,
        usageMetadataPresent: usageMetadataPresent,
        modelStatusPresent: modelStatusPresent,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        maxTextPartsPerEvent: maxTextPartsPerEvent,
        rawReceivedCharacterCount: rawReceivedCharacterCount,
        receivedCharacterCount: receivedCharacterCount,
        authoritativeCharacterCount: accumulated.length,
        adapterHash: accumulated.isEmpty
            ? null
            : safeContentFingerprint(accumulated),
        rawFinishReason: rawFinishReason,
        normalizedFinishReason: finishReason?.name,
        providerErrorStatus: promptBlockReason,
        providerErrorMessage: promptBlockMessage,
        generationStartedAt: generationStartedAt,
        httpResponseAt: httpResponseAt,
        firstByteAt: firstByteAt,
        lastChunkAt: lastChunkAt,
        streamEndAt: DateTime.now().toUtc(),
        streamClosedNormally:
            responseDiagnostics?.streamClosedNormally ?? false,
        abnormalEof: responseDiagnostics?.abnormalEof ?? true,
        timeoutType: error is AiProviderInterruptedException
            ? error.timeoutType
            : 'none',
        lastEventIndex: rawSseEventCount - 1,
        requestedMaxOutputTokens: request.maxTokens,
        modelOutputTokenLimit: _modelOutputLimits[model],
        promptTokenCount: promptTokenCount == 0 ? null : promptTokenCount,
        candidatesTokenCount: candidatesTokenCount == 0
            ? null
            : candidatesTokenCount,
        totalTokenCount: totalTokenCount == 0 ? null : totalTokenCount,
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
        responseContentType: responseContentType,
        firstByteReceived: firstByteAt != null,
        firstSseEventReceived: rawSseEventCount > 0,
        stage: 'stream.response.failed',
        streamEventCount: rawSseEventCount,
        rawSseEventCount: rawSseEventCount,
        parsedResponseObjectCount: parsedResponseObjectCount,
        candidateEventCount: candidateEventCount,
        textEventCount: textEventCount,
        topLevelKeys: (topLevelKeys.toList()..sort()).join(','),
        promptFeedbackPresent: promptFeedbackPresent,
        promptBlockReason: promptBlockReason,
        promptSafetyRatingsCount: promptSafetyRatingsCount,
        promptSafetyRatingsSummary: promptSafetyRatingsSummary,
        responseIdPresent: responseIdPresent,
        modelVersionPresent: modelVersionPresent,
        usageMetadataPresent: usageMetadataPresent,
        modelStatusPresent: modelStatusPresent,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        maxTextPartsPerEvent: maxTextPartsPerEvent,
        rawReceivedCharacterCount: rawReceivedCharacterCount,
        receivedCharacterCount: receivedCharacterCount,
        authoritativeCharacterCount: accumulated.length,
        adapterHash: accumulated.isEmpty
            ? null
            : safeContentFingerprint(accumulated),
        rawFinishReason: rawFinishReason,
        normalizedFinishReason: finishReason?.name,
        providerErrorStatus: promptBlockReason,
        providerErrorMessage: promptBlockMessage,
        generationStartedAt: generationStartedAt,
        httpResponseAt: httpResponseAt,
        firstByteAt: firstByteAt,
        lastChunkAt: lastChunkAt,
        streamEndAt: DateTime.now().toUtc(),
        streamClosedNormally: false,
        abnormalEof: true,
        timeoutType: timeoutType,
        lastEventIndex: rawSseEventCount - 1,
        requestedMaxOutputTokens: request.maxTokens,
        modelOutputTokenLimit: _modelOutputLimits[model],
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
        firstSseEventReceived: rawSseEventCount > 0,
        streamEventCount: rawSseEventCount,
        rawSseEventCount: rawSseEventCount,
        parsedResponseObjectCount: parsedResponseObjectCount,
        candidateEventCount: candidateEventCount,
        textEventCount: textEventCount,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        rawReceivedChars: rawReceivedCharacterCount,
        normalizedChars: receivedCharacterCount,
        topLevelKeys: (topLevelKeys.toList()..sort()).join(','),
        promptFeedbackPresent: promptFeedbackPresent,
        promptBlockReason: promptBlockReason,
        promptSafetyRatingsCount: promptSafetyRatingsCount,
        promptSafetyRatingsSummary: promptSafetyRatingsSummary,
        responseIdPresent: responseIdPresent,
        modelVersionPresent: modelVersionPresent,
        usageMetadataPresent: usageMetadataPresent,
        modelStatusPresent: modelStatusPresent,
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
        responseContentType: responseContentType,
        streamEventCount: rawSseEventCount,
        rawSseEventCount: rawSseEventCount,
        parsedResponseObjectCount: parsedResponseObjectCount,
        candidateEventCount: candidateEventCount,
        textEventCount: textEventCount,
        topLevelKeys: (topLevelKeys.toList()..sort()).join(','),
        promptFeedbackPresent: promptFeedbackPresent,
        promptBlockReason: promptBlockReason,
        promptSafetyRatingsCount: promptSafetyRatingsCount,
        promptSafetyRatingsSummary: promptSafetyRatingsSummary,
        responseIdPresent: responseIdPresent,
        modelVersionPresent: modelVersionPresent,
        usageMetadataPresent: usageMetadataPresent,
        modelStatusPresent: modelStatusPresent,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        maxTextPartsPerEvent: maxTextPartsPerEvent,
        rawReceivedCharacterCount: rawReceivedCharacterCount,
        receivedCharacterCount: receivedCharacterCount,
        authoritativeCharacterCount: accumulated.length,
        adapterHash: accumulated.isEmpty
            ? null
            : safeContentFingerprint(accumulated),
        rawFinishReason: rawFinishReason,
        normalizedFinishReason: finishReason?.name,
        providerErrorStatus: promptBlockReason,
        providerErrorMessage: promptBlockMessage,
        generationStartedAt: generationStartedAt,
        httpResponseAt: httpResponseAt,
        firstByteAt: firstByteAt,
        lastChunkAt: lastChunkAt,
        promptTokenCount: promptTokenCount,
        candidatesTokenCount: candidatesTokenCount,
        totalTokenCount: totalTokenCount,
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
        firstSseEventReceived: rawSseEventCount > 0,
        streamEventCount: rawSseEventCount,
        rawSseEventCount: rawSseEventCount,
        parsedResponseObjectCount: parsedResponseObjectCount,
        candidateEventCount: candidateEventCount,
        textEventCount: textEventCount,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        rawReceivedChars: rawReceivedCharacterCount,
        normalizedChars: receivedCharacterCount,
        topLevelKeys: (topLevelKeys.toList()..sort()).join(','),
        promptFeedbackPresent: promptFeedbackPresent,
        promptBlockReason: promptBlockReason,
        promptSafetyRatingsCount: promptSafetyRatingsCount,
        promptSafetyRatingsSummary: promptSafetyRatingsSummary,
        responseIdPresent: responseIdPresent,
        modelVersionPresent: modelVersionPresent,
        usageMetadataPresent: usageMetadataPresent,
        modelStatusPresent: modelStatusPresent,
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
        responseContentType: responseContentType,
        streamEventCount: rawSseEventCount,
        rawSseEventCount: rawSseEventCount,
        parsedResponseObjectCount: parsedResponseObjectCount,
        candidateEventCount: candidateEventCount,
        textEventCount: textEventCount,
        topLevelKeys: (topLevelKeys.toList()..sort()).join(','),
        promptFeedbackPresent: promptFeedbackPresent,
        promptBlockReason: promptBlockReason,
        promptSafetyRatingsCount: promptSafetyRatingsCount,
        promptSafetyRatingsSummary: promptSafetyRatingsSummary,
        responseIdPresent: responseIdPresent,
        modelVersionPresent: modelVersionPresent,
        usageMetadataPresent: usageMetadataPresent,
        modelStatusPresent: modelStatusPresent,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        maxTextPartsPerEvent: maxTextPartsPerEvent,
        rawReceivedCharacterCount: rawReceivedCharacterCount,
        receivedCharacterCount: receivedCharacterCount,
        authoritativeCharacterCount: accumulated.length,
        adapterHash: accumulated.isEmpty
            ? null
            : safeContentFingerprint(accumulated),
        rawFinishReason: rawFinishReason,
        normalizedFinishReason: finishReason?.name,
        providerErrorStatus: promptBlockReason,
        providerErrorMessage: promptBlockMessage,
        generationStartedAt: generationStartedAt,
        httpResponseAt: httpResponseAt,
        firstByteAt: firstByteAt,
        lastChunkAt: lastChunkAt,
        promptTokenCount: promptTokenCount,
        candidatesTokenCount: candidatesTokenCount,
        totalTokenCount: totalTokenCount,
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
        firstSseEventReceived: rawSseEventCount > 0,
        streamEventCount: rawSseEventCount,
        rawSseEventCount: rawSseEventCount,
        parsedResponseObjectCount: parsedResponseObjectCount,
        candidateEventCount: candidateEventCount,
        textEventCount: textEventCount,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        rawReceivedChars: rawReceivedCharacterCount,
        normalizedChars: receivedCharacterCount,
        topLevelKeys: (topLevelKeys.toList()..sort()).join(','),
        promptFeedbackPresent: promptFeedbackPresent,
        promptBlockReason: promptBlockReason,
        promptSafetyRatingsCount: promptSafetyRatingsCount,
        promptSafetyRatingsSummary: promptSafetyRatingsSummary,
        responseIdPresent: responseIdPresent,
        modelVersionPresent: modelVersionPresent,
        usageMetadataPresent: usageMetadataPresent,
        modelStatusPresent: modelStatusPresent,
        causeType: 'ClientException',
      );
    } on FormatException catch (error) {
      _recordException(
        request.requestId,
        'POST',
        uri,
        model,
        stopwatch,
        error,
        statusCode: responseStatus == 0 ? null : responseStatus,
        responseContentType: responseContentType,
        firstByteReceived: firstByteAt != null,
        firstSseEventReceived: rawSseEventCount > 0,
        stage: 'stream.response.parse.failed',
        streamEventCount: rawSseEventCount,
        rawSseEventCount: rawSseEventCount,
        parsedResponseObjectCount: parsedResponseObjectCount,
        candidateEventCount: candidateEventCount,
        textEventCount: textEventCount,
        topLevelKeys: (topLevelKeys.toList()..sort()).join(','),
        promptFeedbackPresent: promptFeedbackPresent,
        promptBlockReason: promptBlockReason,
        promptSafetyRatingsCount: promptSafetyRatingsCount,
        promptSafetyRatingsSummary: promptSafetyRatingsSummary,
        responseIdPresent: responseIdPresent,
        modelVersionPresent: modelVersionPresent,
        usageMetadataPresent: usageMetadataPresent,
        modelStatusPresent: modelStatusPresent,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        rawReceivedCharacterCount: rawReceivedCharacterCount,
        receivedCharacterCount: receivedCharacterCount,
        authoritativeCharacterCount: accumulated.length,
        streamClosedNormally: false,
        abnormalEof: false,
        timeoutType: 'none',
      );
      if (receivedContent) {
        throw const AiProviderInterruptedException(
          causeType: 'InvalidResponse',
        );
      }
      throw const AiProviderInvalidResponseException(
        'gemini stream event json parse failed',
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
    required String? responseContentType,
    required int streamEventCount,
    required int rawSseEventCount,
    required int parsedResponseObjectCount,
    required int candidateEventCount,
    required int textEventCount,
    required String topLevelKeys,
    required bool promptFeedbackPresent,
    required String? promptBlockReason,
    required int promptSafetyRatingsCount,
    required String? promptSafetyRatingsSummary,
    required bool responseIdPresent,
    required bool modelVersionPresent,
    required bool usageMetadataPresent,
    required bool modelStatusPresent,
    required int candidateCount,
    required int partCount,
    required int textPartCount,
    required int maxTextPartsPerEvent,
    required int rawReceivedCharacterCount,
    required int receivedCharacterCount,
    required int authoritativeCharacterCount,
    required String? adapterHash,
    required String? rawFinishReason,
    required String? normalizedFinishReason,
    required String? providerErrorStatus,
    required String? providerErrorMessage,
    required DateTime generationStartedAt,
    required DateTime? httpResponseAt,
    required DateTime? firstByteAt,
    required DateTime? lastChunkAt,
    required int promptTokenCount,
    required int candidatesTokenCount,
    required int totalTokenCount,
  }) {
    _recordException(
      request.requestId,
      'POST',
      uri,
      model,
      stopwatch,
      error,
      statusCode: responseStatus == 0 ? null : responseStatus,
      responseContentType: responseContentType,
      stage: 'stream.response.failed',
      streamEventCount: streamEventCount,
      rawSseEventCount: rawSseEventCount,
      parsedResponseObjectCount: parsedResponseObjectCount,
      candidateEventCount: candidateEventCount,
      textEventCount: textEventCount,
      topLevelKeys: topLevelKeys,
      promptFeedbackPresent: promptFeedbackPresent,
      promptBlockReason: promptBlockReason,
      promptSafetyRatingsCount: promptSafetyRatingsCount,
      promptSafetyRatingsSummary: promptSafetyRatingsSummary,
      responseIdPresent: responseIdPresent,
      modelVersionPresent: modelVersionPresent,
      usageMetadataPresent: usageMetadataPresent,
      modelStatusPresent: modelStatusPresent,
      candidateCount: candidateCount,
      partCount: partCount,
      textPartCount: textPartCount,
      maxTextPartsPerEvent: maxTextPartsPerEvent,
      rawReceivedCharacterCount: rawReceivedCharacterCount,
      receivedCharacterCount: receivedCharacterCount,
      authoritativeCharacterCount: authoritativeCharacterCount,
      adapterHash: adapterHash,
      rawFinishReason: rawFinishReason,
      normalizedFinishReason: normalizedFinishReason,
      providerErrorStatus: providerErrorStatus,
      providerErrorMessage: providerErrorMessage,
      generationStartedAt: generationStartedAt,
      httpResponseAt: httpResponseAt,
      firstByteAt: firstByteAt,
      lastChunkAt: lastChunkAt,
      streamEndAt: DateTime.now().toUtc(),
      streamClosedNormally: false,
      abnormalEof: true,
      timeoutType: 'none',
      lastEventIndex: streamEventCount - 1,
      requestedMaxOutputTokens: request.maxTokens,
      modelOutputTokenLimit: _modelOutputLimits[model],
      promptTokenCount: promptTokenCount == 0 ? null : promptTokenCount,
      candidatesTokenCount: candidatesTokenCount == 0
          ? null
          : candidatesTokenCount,
      totalTokenCount: totalTokenCount == 0 ? null : totalTokenCount,
    );
  }

  AiProviderInterruptedBeforeContentException _beforeContentInterruption({
    required String model,
    required int httpStatus,
    required String? responseContentType,
    required bool firstByteReceived,
    required bool firstSseEventReceived,
    required int streamEventCount,
    int rawSseEventCount = 0,
    int parsedResponseObjectCount = 0,
    int candidateEventCount = 0,
    int textEventCount = 0,
    required int candidateCount,
    required int partCount,
    required int textPartCount,
    required int rawReceivedChars,
    required int normalizedChars,
    String topLevelKeys = '',
    bool promptFeedbackPresent = false,
    String? promptBlockReason,
    int promptSafetyRatingsCount = 0,
    String? promptSafetyRatingsSummary,
    bool responseIdPresent = false,
    bool modelVersionPresent = false,
    bool usageMetadataPresent = false,
    bool modelStatusPresent = false,
    required String causeType,
    String timeoutType = 'none',
  }) {
    return AiProviderInterruptedBeforeContentException(
      causeType: causeType,
      timeoutType: timeoutType,
      responseDiagnostics: AiProviderResponseDiagnostics(
        provider: 'gemini',
        model: model,
        httpStatus: httpStatus == 0 ? null : httpStatus,
        responseContentType: responseContentType,
        firstByteReceived: firstByteReceived,
        firstSseEventReceived: firstSseEventReceived,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        rawReceivedChars: rawReceivedChars,
        normalizedChars: normalizedChars,
        finalResultChars: 0,
        streamEventCount: streamEventCount,
        rawSseEventCount: rawSseEventCount,
        parsedResponseObjectCount: parsedResponseObjectCount,
        candidateEventCount: candidateEventCount,
        textEventCount: textEventCount,
        topLevelKeys: topLevelKeys,
        promptFeedbackPresent: promptFeedbackPresent,
        promptBlockReason: promptBlockReason,
        promptSafetyRatingsCount: promptSafetyRatingsCount,
        promptSafetyRatingsSummary: promptSafetyRatingsSummary,
        responseIdPresent: responseIdPresent,
        modelVersionPresent: modelVersionPresent,
        usageMetadataPresent: usageMetadataPresent,
        modelStatusPresent: modelStatusPresent,
        streamClosedNormally: false,
        abnormalEof: true,
        exceptionType: causeType,
      ),
    );
  }

  Future<_GeminiModelCatalog> _listModelCatalog() async {
    _ensureOpen();
    final stopwatch = Stopwatch()..start();
    final models = <_GeminiModelDescriptor>[];
    String? pageToken;
    var lastStatusCode = 0;
    Uri uri = _modelsUri();
    try {
      do {
        uri = _modelsUri(pageToken: pageToken);
        _record(
          requestId: 'gemini-models',
          method: 'GET',
          uri: uri,
          model: '',
          stopwatch: stopwatch,
          stage: 'models.request.start',
        );
        final response = await _httpClient
            .get(
              uri,
              headers: {
                'Accept': 'application/json',
                'x-goog-api-key': _apiKey,
              },
            )
            .timeout(timeout);
        lastStatusCode = response.statusCode;
        if (response.statusCode < 200 || response.statusCode >= 300) {
          _record(
            requestId: 'gemini-models',
            method: 'GET',
            uri: uri,
            model: '',
            stopwatch: stopwatch,
            statusCode: response.statusCode,
            stage: 'models.request.failed',
            googleError: _GoogleApiError.tryParse(response.body),
          );
          _throwForStatus(response.statusCode, response.body);
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded['models'] is! List) {
          throw const AiProviderProtocolException('Gemini 模型列表格式异常。');
        }
        for (final value in decoded['models'] as List) {
          final descriptor = _GeminiModelDescriptor.fromJson(value);
          models.add(descriptor);
          final limit = descriptor.outputTokenLimit;
          if (limit != null) _modelOutputLimits[descriptor.id] = limit;
        }
        final next = decoded['nextPageToken'];
        pageToken = next is String && next.trim().isNotEmpty
            ? next.trim()
            : null;
      } while (pageToken != null);

      final capable =
          models
              .where((model) => model.supportsGenerateContent)
              .map((model) => model.id)
              .toSet()
              .toList()
            ..sort();
      _record(
        requestId: 'gemini-models',
        method: 'GET',
        uri: _modelsUri(),
        model: '',
        stopwatch: stopwatch,
        statusCode: lastStatusCode,
        modelCount: models.length,
        generateContentModelCount: capable.length,
        stage: 'models.request.success',
      );
      if (models.isEmpty) {
        throw const AiProviderProtocolException('Gemini 返回了空模型列表。');
      }
      if (capable.isEmpty) {
        throw const AiProviderModelUnavailableException(
          'Gemini 没有返回支持 generateContent 的模型。',
        );
      }
      return _GeminiModelCatalog(
        descriptors: List.unmodifiable(models),
        generateContentModelIds: List.unmodifiable(capable),
      );
    } on AiProviderException catch (error) {
      _recordException(
        'gemini-models',
        'GET',
        uri,
        '',
        stopwatch,
        error,
        statusCode: lastStatusCode == 0 ? null : lastStatusCode,
      );
      rethrow;
    } on TimeoutException catch (error) {
      _recordException(
        'gemini-models',
        'GET',
        uri,
        '',
        stopwatch,
        error,
        timeoutStage: 'response',
        stage: 'models.request.failed',
      );
      throw const AiProviderTimeoutException();
    } on HandshakeException catch (error) {
      _recordException('gemini-models', 'GET', uri, '', stopwatch, error);
      throw const AiProviderHandshakeException();
    } on SocketException catch (error) {
      _recordException('gemini-models', 'GET', uri, '', stopwatch, error);
      throw const AiProviderNetworkException();
    } on http.ClientException catch (error) {
      _recordException('gemini-models', 'GET', uri, '', stopwatch, error);
      throw _mapClientException(error);
    } on FormatException catch (error) {
      _recordException('gemini-models', 'GET', uri, '', stopwatch, error);
      throw const AiProviderProtocolException('Gemini 模型列表 JSON 解析失败。');
    }
  }

  http.Request _generationRequest({
    required Uri uri,
    required AiGenerationRequest request,
    required bool stream,
  }) {
    final contents = [
      for (final message in request.messages)
        {
          'role': message.role == AiMessageRole.assistant ? 'model' : 'user',
          'parts': geminiMessageParts(message),
        },
    ];
    final reasoning = reasoningParameters(
      provider: 'gemini',
      model: request.model ?? '',
      level: request.reasoning,
      maxTokens: request.maxTokens,
    );
    final body = <String, Object?>{
      if (request.systemPrompt.trim().isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': request.systemPrompt.trim()},
          ],
        },
      'contents': contents,
      if (request.temperature != null ||
          request.maxTokens != null ||
          request.structuredJson ||
          reasoning.isNotEmpty ||
          request.sampling.isNotEmpty)
        'generationConfig': {
          ...request.sampling,
          if (request.temperature != null) 'temperature': request.temperature,
          if (request.maxTokens != null) 'maxOutputTokens': request.maxTokens,
          if (request.structuredJson) 'responseMimeType': 'application/json',
          ...reasoning,
        },
    };
    request.reportAppliedParameters({
      'stream': stream,
      ...Map<String, Object?>.from(
        body['generationConfig'] as Map? ?? const {},
      ),
    });
    return http.Request('POST', uri)
      ..headers.addAll({
        'Accept': stream ? 'text/event-stream' : 'application/json',
        'Content-Type': 'application/json',
        'x-goog-api-key': _apiKey,
      })
      ..body = jsonEncode(body);
  }

  String _validatedModel(
    AiGenerationRequest request,
    AiRequestCancellation? cancellation,
  ) {
    final model = _canonicalModelId(request.model ?? '');
    if (model.isEmpty) {
      throw const AiProviderModelUnavailableException();
    }
    if (cancellation?.isCancelled ?? false) {
      throw const AiProviderCancelledException();
    }
    return model;
  }

  Uri _modelsUri({String? pageToken}) => _baseUri.replace(
    path: '${_basePath()}/models',
    queryParameters: {'pageSize': '1000', 'pageToken': ?pageToken},
  );

  Uri _generationUri(String model, {required bool stream}) {
    final method = stream ? 'streamGenerateContent' : 'generateContent';
    return _baseUri.replace(
      path: '${_basePath()}/models/${Uri.encodeComponent(model)}:$method',
      queryParameters: stream ? const {'alt': 'sse'} : null,
    );
  }

  String _basePath() => _baseUri.path.endsWith('/')
      ? _baseUri.path.substring(0, _baseUri.path.length - 1)
      : _baseUri.path;

  void _ensureOpen() {
    if (_closed) {
      throw const AiProviderNetworkException('连接已经关闭，请重新测试。');
    }
    if (_apiKey.trim().isEmpty) {
      throw const AiProviderValidationException('Gemini API Key 未配置。');
    }
  }

  Never _throwForStatus(
    int statusCode,
    String responseBody, {
    bool modelRequest = false,
  }) {
    final error = _GoogleApiError.tryParse(responseBody);
    final status = error?.status;
    final summary = _safeGoogleErrorSummary(error);
    final reason = error?.reason?.toUpperCase() ?? '';
    final lowerSummary = summary.toLowerCase();
    if (statusCode == 400 &&
        (status == 'API_KEY_INVALID' ||
            reason == 'API_KEY_INVALID' ||
            lowerSummary.contains('api key not valid') ||
            lowerSummary.contains('api key is invalid') ||
            lowerSummary.contains('api key expired') ||
            lowerSummary.contains('api key not found'))) {
      throw AiProviderAuthenticationException(
        _httpMessage('Gemini API Key 无效或已失效。', statusCode, status),
      );
    }
    if (statusCode == 401) {
      throw AiProviderAuthenticationException(
        _httpMessage('Gemini API Key 认证失败。', statusCode, status),
      );
    }
    if (statusCode == 403) {
      throw AiProviderRequestRejectedException(
        _httpMessage('Gemini API Key 无效或没有 Gemini API 权限。', statusCode, status),
      );
    }
    if (statusCode == 404) {
      if (modelRequest) {
        throw AiProviderModelUnavailableException(
          _httpMessage('当前 Gemini 模型不可用。', statusCode, status),
        );
      }
      throw AiProviderEndpointException(
        _httpMessage('Gemini API 接口不存在。', statusCode, status),
      );
    }
    if (statusCode == 408) throw const AiProviderTimeoutException();
    if (statusCode == 429) {
      throw AiProviderRateLimitedException(
        _httpMessage('Gemini 请求过于频繁或额度不足。', statusCode, status),
      );
    }
    if (statusCode >= 500) throw const AiProviderServerException();
    if (statusCode == 413 || summary.toLowerCase().contains('token')) {
      throw const AiProviderContextTooLargeException();
    }
    if (modelRequest && _isNativeInterfaceIncompatible(error)) {
      throw const AiProviderNativeInterfaceIncompatibleException();
    }
    throw AiProviderProtocolException(
      _httpMessage('Gemini 请求格式错误。', statusCode, status),
    );
  }

  String _httpMessage(String message, int statusCode, String? status) {
    final suffix = status == null || status.isEmpty ? '' : ' · $status';
    return '$message（HTTP $statusCode$suffix）';
  }

  String _safeGoogleErrorSummary(_GoogleApiError? error) =>
      error?.message ?? '';

  AiProviderException _mapClientException(http.ClientException error) {
    final lower = error.message.toLowerCase();
    if (lower.contains('handshake') || lower.contains('certificate')) {
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
    String? responseContentType,
    bool? firstByteReceived,
    bool? firstSseEventReceived,
    String? exceptionType,
    String? timeoutStage,
    int? modelCount,
    int? generateContentModelCount,
    String? stage,
    _GoogleApiError? googleError,
    int? streamEventCount,
    int? rawSseEventCount,
    int? parsedResponseObjectCount,
    int? candidateEventCount,
    int? textEventCount,
    String? topLevelKeys,
    bool? promptFeedbackPresent,
    String? promptBlockReason,
    int? promptSafetyRatingsCount,
    String? promptSafetyRatingsSummary,
    bool? responseIdPresent,
    bool? modelVersionPresent,
    bool? usageMetadataPresent,
    bool? modelStatusPresent,
    int? candidateCount,
    int? partCount,
    int? textPartCount,
    int? maxTextPartsPerEvent,
    int? rawReceivedCharacterCount,
    int? receivedCharacterCount,
    int? authoritativeCharacterCount,
    String? adapterHash,
    String? finishReason,
    String? rawFinishReason,
    String? normalizedFinishReason,
    String? streamNormalization,
    DateTime? generationStartedAt,
    DateTime? httpResponseAt,
    DateTime? firstByteAt,
    DateTime? lastChunkAt,
    DateTime? streamEndAt,
    bool? streamClosedNormally,
    bool? abnormalEof,
    String? timeoutType,
    int? lastEventIndex,
    int? requestedMaxOutputTokens,
    int? modelOutputTokenLimit,
    int? promptTokenCount,
    int? candidatesTokenCount,
    int? totalTokenCount,
    String? providerErrorStatus,
    String? providerErrorMessage,
  }) {
    diagnostics.record(
      AiNetworkDiagnosticEvent(
        requestId: requestId,
        providerType: 'gemini',
        method: method,
        host: uri.host,
        path: uri.path,
        model: model,
        apiKeyPresent: _apiKey.isNotEmpty,
        statusCode: statusCode,
        responseContentType: responseContentType,
        firstByteReceived: firstByteReceived,
        firstSseEventReceived: firstSseEventReceived,
        exceptionType: exceptionType,
        timeoutStage: timeoutStage,
        modelCount: modelCount,
        generateContentModelCount: generateContentModelCount,
        stage: stage,
        providerErrorCode: googleError?.code,
        providerErrorStatus: providerErrorStatus ?? googleError?.status,
        providerErrorMessage: providerErrorMessage ?? googleError?.safeMessage,
        providerErrorReason: googleError?.reason,
        streamEventCount: streamEventCount,
        rawSseEventCount: rawSseEventCount,
        parsedResponseObjectCount: parsedResponseObjectCount,
        candidateEventCount: candidateEventCount,
        textEventCount: textEventCount,
        topLevelKeys: topLevelKeys,
        promptFeedbackPresent: promptFeedbackPresent,
        promptBlockReason: promptBlockReason,
        promptSafetyRatingsCount: promptSafetyRatingsCount,
        promptSafetyRatingsSummary: promptSafetyRatingsSummary,
        responseIdPresent: responseIdPresent,
        modelVersionPresent: modelVersionPresent,
        usageMetadataPresent: usageMetadataPresent,
        modelStatusPresent: modelStatusPresent,
        candidateCount: candidateCount,
        partCount: partCount,
        textPartCount: textPartCount,
        maxTextPartsPerEvent: maxTextPartsPerEvent,
        rawReceivedCharacterCount: rawReceivedCharacterCount,
        receivedCharacterCount: receivedCharacterCount,
        authoritativeCharacterCount: authoritativeCharacterCount,
        adapterHash: adapterHash,
        finishReason: finishReason,
        rawFinishReason: rawFinishReason,
        normalizedFinishReason: normalizedFinishReason,
        streamNormalization: streamNormalization,
        generationStartedAt: generationStartedAt,
        httpResponseAt: httpResponseAt,
        firstByteAt: firstByteAt,
        lastChunkAt: lastChunkAt,
        streamEndAt: streamEndAt,
        streamClosedNormally: streamClosedNormally,
        abnormalEof: abnormalEof,
        timeoutType: timeoutType,
        lastEventIndex: lastEventIndex,
        requestedMaxOutputTokens: requestedMaxOutputTokens,
        modelOutputTokenLimit: modelOutputTokenLimit,
        promptTokenCount: promptTokenCount,
        candidatesTokenCount: candidatesTokenCount,
        totalTokenCount: totalTokenCount,
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
    String? responseContentType,
    bool? firstByteReceived,
    bool? firstSseEventReceived,
    String? timeoutStage,
    String? stage,
    int? streamEventCount,
    int? rawSseEventCount,
    int? parsedResponseObjectCount,
    int? candidateEventCount,
    int? textEventCount,
    String? topLevelKeys,
    bool? promptFeedbackPresent,
    String? promptBlockReason,
    int? promptSafetyRatingsCount,
    String? promptSafetyRatingsSummary,
    bool? responseIdPresent,
    bool? modelVersionPresent,
    bool? usageMetadataPresent,
    bool? modelStatusPresent,
    int? candidateCount,
    int? partCount,
    int? textPartCount,
    int? maxTextPartsPerEvent,
    int? rawReceivedCharacterCount,
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
    bool? abnormalEof,
    String? timeoutType,
    int? lastEventIndex,
    int? requestedMaxOutputTokens,
    int? modelOutputTokenLimit,
    int? promptTokenCount,
    int? candidatesTokenCount,
    int? totalTokenCount,
    String? providerErrorStatus,
    String? providerErrorMessage,
  }) {
    _record(
      requestId: requestId,
      method: method,
      uri: uri,
      model: model,
      stopwatch: stopwatch,
      statusCode: statusCode,
      responseContentType: responseContentType,
      firstByteReceived: firstByteReceived,
      firstSseEventReceived: firstSseEventReceived,
      exceptionType: error.runtimeType.toString(),
      timeoutStage: timeoutStage,
      stage: stage,
      streamEventCount: streamEventCount,
      rawSseEventCount: rawSseEventCount,
      parsedResponseObjectCount: parsedResponseObjectCount,
      candidateEventCount: candidateEventCount,
      textEventCount: textEventCount,
      topLevelKeys: topLevelKeys,
      promptFeedbackPresent: promptFeedbackPresent,
      promptBlockReason: promptBlockReason,
      promptSafetyRatingsCount: promptSafetyRatingsCount,
      promptSafetyRatingsSummary: promptSafetyRatingsSummary,
      responseIdPresent: responseIdPresent,
      modelVersionPresent: modelVersionPresent,
      usageMetadataPresent: usageMetadataPresent,
      modelStatusPresent: modelStatusPresent,
      candidateCount: candidateCount,
      partCount: partCount,
      textPartCount: textPartCount,
      maxTextPartsPerEvent: maxTextPartsPerEvent,
      rawReceivedCharacterCount: rawReceivedCharacterCount,
      receivedCharacterCount: receivedCharacterCount,
      authoritativeCharacterCount: authoritativeCharacterCount,
      adapterHash: adapterHash,
      rawFinishReason: rawFinishReason,
      normalizedFinishReason: normalizedFinishReason,
      providerErrorStatus: providerErrorStatus,
      providerErrorMessage: providerErrorMessage,
      generationStartedAt: generationStartedAt,
      httpResponseAt: httpResponseAt,
      firstByteAt: firstByteAt,
      lastChunkAt: lastChunkAt,
      streamEndAt: streamEndAt,
      streamClosedNormally: streamClosedNormally,
      abnormalEof: abnormalEof,
      timeoutType: timeoutType,
      lastEventIndex: lastEventIndex,
      requestedMaxOutputTokens: requestedMaxOutputTokens,
      modelOutputTokenLimit: modelOutputTokenLimit,
      promptTokenCount: promptTokenCount,
      candidatesTokenCount: candidatesTokenCount,
      totalTokenCount: totalTokenCount,
    );
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _httpClient.close();
  }
}

bool _isClearCumulativePacket(String previous, String incoming) {
  return previous.isNotEmpty && incoming.startsWith(previous);
}

bool _isNativeInterfaceIncompatible(_GoogleApiError? error) {
  final value =
      '${error?.status ?? ''} ${error?.message ?? ''} '
              '${error?.reason ?? ''}'
          .toLowerCase();
  return value.contains('only supports interactions api') ||
      value.contains('does not support generatecontent') ||
      value.contains('not supported for generatecontent');
}

int _geminiTextModelRank(String model) {
  final value = model.toLowerCase();
  if (!value.startsWith('gemini-')) return 100;
  if (value.contains('image') ||
      value.contains('tts') ||
      value.contains('live') ||
      value.contains('robotics') ||
      value.contains('computer-use')) {
    return 80;
  }
  if (value.contains('flash-lite')) return 0;
  if (value.contains('flash')) return 10;
  if (value.contains('pro')) return 20;
  return 30;
}

int _geminiPreviewRank(String model) {
  final value = model.toLowerCase();
  return value.contains('preview') || value.contains('exp') ? 1 : 0;
}

int _geminiVersion(String model) {
  final match = RegExp(r'gemini-(\d+)(?:\.(\d+))?').firstMatch(model);
  if (match == null) return 0;
  final major = int.tryParse(match.group(1) ?? '') ?? 0;
  final minor = int.tryParse(match.group(2) ?? '') ?? 0;
  return major * 1000 + minor;
}

class _GeminiModelCatalog {
  const _GeminiModelCatalog({
    required this.descriptors,
    required this.generateContentModelIds,
  });

  final List<_GeminiModelDescriptor> descriptors;
  final List<String> generateContentModelIds;
}

class _GeminiModelDescriptor {
  const _GeminiModelDescriptor({
    required this.id,
    required this.displayName,
    required this.supportedGenerationMethods,
    required this.inputTokenLimit,
    required this.outputTokenLimit,
  });

  factory _GeminiModelDescriptor.fromJson(Object? value) {
    if (value is! Map || value['name'] is! String) {
      throw const FormatException('Invalid Gemini model.');
    }
    final methodsValue = value['supportedGenerationMethods'];
    if (methodsValue is! List) {
      throw const FormatException('Invalid Gemini generation methods.');
    }
    return _GeminiModelDescriptor(
      id: _canonicalModelId(value['name'] as String),
      displayName: value['displayName'] is String
          ? value['displayName'] as String
          : '',
      supportedGenerationMethods: methodsValue.whereType<String>().toSet(),
      inputTokenLimit: value['inputTokenLimit'] is num
          ? (value['inputTokenLimit'] as num).toInt()
          : null,
      outputTokenLimit: value['outputTokenLimit'] is num
          ? (value['outputTokenLimit'] as num).toInt()
          : null,
    );
  }

  final String id;
  final String displayName;
  final Set<String> supportedGenerationMethods;
  final int? inputTokenLimit;
  final int? outputTokenLimit;

  bool get supportsGenerateContent =>
      supportedGenerationMethods.contains('generateContent');
}

class _GeminiPacket {
  const _GeminiPacket(
    this.text,
    this.finishReason, {
    required this.candidatesPresent,
    required this.candidateCount,
    required this.partCount,
    required this.textPartCount,
    required this.topLevelKeys,
    required this.promptFeedbackPresent,
    required this.promptSafetyRatingsCount,
    required this.responseIdPresent,
    required this.modelVersionPresent,
    required this.usageMetadataPresent,
    required this.modelStatusPresent,
    this.rawFinishReason,
    this.promptBlockReason,
    this.promptBlockMessage,
    this.promptSafetyRatingsSummary,
    this.promptTokenCount,
    this.candidatesTokenCount,
    this.totalTokenCount,
  });

  final String text;
  final AiFinishReason? finishReason;
  final bool candidatesPresent;
  final int candidateCount;
  final int partCount;
  final int textPartCount;
  final String topLevelKeys;
  final bool promptFeedbackPresent;
  final int promptSafetyRatingsCount;
  final String? promptSafetyRatingsSummary;
  final bool responseIdPresent;
  final bool modelVersionPresent;
  final bool usageMetadataPresent;
  final bool modelStatusPresent;
  final String? rawFinishReason;
  final String? promptBlockReason;
  final String? promptBlockMessage;
  final int? promptTokenCount;
  final int? candidatesTokenCount;
  final int? totalTokenCount;
}

_GeminiPacket _geminiPacket(Object? value) {
  if (value is! Map) {
    throw const AiProviderInvalidResponseException(
      'gemini response parse: top-level object missing',
    );
  }
  final topLevelKeys = value.keys.whereType<String>().toList()..sort();
  final candidatesPresent = value.containsKey('candidates');
  final rawCandidates = value['candidates'];
  if (rawCandidates != null && rawCandidates is! List) {
    throw const AiProviderInvalidResponseException(
      'gemini response parse: candidates has invalid type',
    );
  }
  final candidates = rawCandidates is List ? rawCandidates : const <Object?>[];
  final promptFeedback = value['promptFeedback'];
  final promptFeedbackPresent = promptFeedback is Map;
  final rawPromptBlockReason = promptFeedback is Map
      ? promptFeedback['blockReason']
      : null;
  final promptBlockReason = rawPromptBlockReason is String
      ? rawPromptBlockReason
      : null;
  final rawPromptBlockMessage = promptFeedback is Map
      ? promptFeedback['blockReasonMessage']
      : null;
  final promptBlockMessage = rawPromptBlockMessage is String
      ? rawPromptBlockMessage
      : null;
  final promptSafetyRatings = promptFeedback is Map
      ? promptFeedback['safetyRatings']
      : null;
  final promptSafetyRatingList = promptSafetyRatings is List
      ? promptSafetyRatings
      : const <Object?>[];
  final promptSafetyRatingsSummary = _safeSafetyRatingsSummary(
    promptSafetyRatingList,
  );
  final usage = value['usageMetadata'];
  final promptTokenCount = usage is Map && usage['promptTokenCount'] is num
      ? (usage['promptTokenCount'] as num).toInt()
      : null;
  final candidatesTokenCount =
      usage is Map && usage['candidatesTokenCount'] is num
      ? (usage['candidatesTokenCount'] as num).toInt()
      : null;
  final totalTokenCount = usage is Map && usage['totalTokenCount'] is num
      ? (usage['totalTokenCount'] as num).toInt()
      : null;
  if (candidates.isEmpty || candidates.first is! Map) {
    return _GeminiPacket(
      '',
      promptBlockReason == null ? null : AiFinishReason.contentFiltered,
      candidatesPresent: candidatesPresent,
      candidateCount: candidates.length,
      partCount: 0,
      textPartCount: 0,
      topLevelKeys: topLevelKeys.join(','),
      promptFeedbackPresent: promptFeedbackPresent,
      promptSafetyRatingsCount: promptSafetyRatingList.length,
      promptSafetyRatingsSummary: promptSafetyRatingsSummary,
      responseIdPresent: _hasNonEmptyValue(value['responseId']),
      modelVersionPresent: _hasNonEmptyValue(value['modelVersion']),
      usageMetadataPresent: usage is Map,
      modelStatusPresent: value['modelStatus'] != null,
      rawFinishReason: promptBlockReason,
      promptBlockReason: promptBlockReason,
      promptBlockMessage: promptBlockMessage,
      promptTokenCount: promptTokenCount,
      candidatesTokenCount: candidatesTokenCount,
      totalTokenCount: totalTokenCount,
    );
  }
  final candidate = candidates.first as Map;
  final content = candidate['content'];
  if (content is! Map || content['parts'] is! List) {
    return _GeminiPacket(
      '',
      _geminiFinishReason(candidate['finishReason']),
      candidatesPresent: candidatesPresent,
      candidateCount: candidates.length,
      partCount: 0,
      textPartCount: 0,
      topLevelKeys: topLevelKeys.join(','),
      promptFeedbackPresent: promptFeedbackPresent,
      promptSafetyRatingsCount: promptSafetyRatingList.length,
      promptSafetyRatingsSummary: promptSafetyRatingsSummary,
      responseIdPresent: _hasNonEmptyValue(value['responseId']),
      modelVersionPresent: _hasNonEmptyValue(value['modelVersion']),
      usageMetadataPresent: usage is Map,
      modelStatusPresent: value['modelStatus'] != null,
      rawFinishReason: candidate['finishReason'] is String
          ? candidate['finishReason'] as String
          : null,
      promptBlockReason: promptBlockReason,
      promptBlockMessage: promptBlockMessage,
      promptTokenCount: promptTokenCount,
      candidatesTokenCount: candidatesTokenCount,
      totalTokenCount: totalTokenCount,
    );
  }
  final parts = content['parts'] as List;
  final textParts = parts
      .whereType<Map>()
      .where((part) => part['thought'] != true)
      .map((part) => part['text'])
      .whereType<String>()
      .toList(growable: false);
  return _GeminiPacket(
    textParts.join(),
    _geminiFinishReason(candidate['finishReason']),
    candidatesPresent: candidatesPresent,
    candidateCount: candidates.length,
    partCount: parts.length,
    textPartCount: textParts.length,
    topLevelKeys: topLevelKeys.join(','),
    promptFeedbackPresent: promptFeedbackPresent,
    promptSafetyRatingsCount: promptSafetyRatingList.length,
    promptSafetyRatingsSummary: promptSafetyRatingsSummary,
    responseIdPresent: _hasNonEmptyValue(value['responseId']),
    modelVersionPresent: _hasNonEmptyValue(value['modelVersion']),
    usageMetadataPresent: usage is Map,
    modelStatusPresent: value['modelStatus'] != null,
    rawFinishReason: candidate['finishReason'] is String
        ? candidate['finishReason'] as String
        : null,
    promptBlockReason: promptBlockReason,
    promptBlockMessage: promptBlockMessage,
    promptTokenCount: promptTokenCount,
    candidatesTokenCount: candidatesTokenCount,
    totalTokenCount: totalTokenCount,
  );
}

AiProviderInvalidResponseException _geminiEmptyResponseException({
  required String model,
  required int httpStatus,
  required String? responseContentType,
  required bool firstByteReceived,
  required bool firstSseEventReceived,
  required AiFinishReason? finishReason,
  required String? rawFinishReason,
  required int candidateCount,
  required int partCount,
  required int textPartCount,
  required int rawReceivedChars,
  required int normalizedChars,
  required int streamEventCount,
  required int rawSseEventCount,
  required int parsedResponseObjectCount,
  required int candidateEventCount,
  required int textEventCount,
  required String topLevelKeys,
  required bool promptFeedbackPresent,
  required int promptSafetyRatingsCount,
  required String? promptSafetyRatingsSummary,
  required bool responseIdPresent,
  required bool modelVersionPresent,
  required bool usageMetadataPresent,
  required bool modelStatusPresent,
  required bool streamClosedNormally,
  required bool abnormalEof,
  required String? promptBlockReason,
  required String? promptBlockMessage,
  bool whitespaceOnly = false,
}) {
  final promptBlocked = promptBlockReason?.trim().isNotEmpty == true;
  final filtered = finishReason == AiFinishReason.contentFiltered;
  return AiProviderInvalidResponseException.empty(
    emptyKind: promptBlocked
        ? AiEmptyResponseKind.promptBlocked
        : filtered
        ? AiEmptyResponseKind.filteredEmpty
        : whitespaceOnly
        ? AiEmptyResponseKind.whitespaceOnly
        : candidateEventCount > 0
        ? AiEmptyResponseKind.candidateEmpty
        : AiEmptyResponseKind.providerEmpty,
    responseDiagnostics: AiProviderResponseDiagnostics(
      provider: 'gemini',
      model: model,
      httpStatus: httpStatus == 0 ? null : httpStatus,
      responseContentType: responseContentType,
      firstByteReceived: firstByteReceived,
      firstSseEventReceived: firstSseEventReceived,
      rawFinishReason: rawFinishReason,
      normalizedFinishReason: finishReason?.name,
      candidateCount: candidateCount,
      partCount: partCount,
      textPartCount: textPartCount,
      rawReceivedChars: rawReceivedChars,
      normalizedChars: normalizedChars,
      finalResultChars: 0,
      streamEventCount: streamEventCount,
      rawSseEventCount: rawSseEventCount,
      parsedResponseObjectCount: parsedResponseObjectCount,
      candidateEventCount: candidateEventCount,
      textEventCount: textEventCount,
      topLevelKeys: topLevelKeys,
      promptFeedbackPresent: promptFeedbackPresent,
      promptBlockReason: promptBlockReason,
      promptSafetyRatingsCount: promptSafetyRatingsCount,
      promptSafetyRatingsSummary: promptSafetyRatingsSummary,
      responseIdPresent: responseIdPresent,
      modelVersionPresent: modelVersionPresent,
      usageMetadataPresent: usageMetadataPresent,
      modelStatusPresent: modelStatusPresent,
      streamClosedNormally: streamClosedNormally,
      abnormalEof: abnormalEof,
      providerErrorStatus: promptBlockReason,
      providerErrorMessage: promptBlockMessage,
    ),
  );
}

bool _hasNonEmptyValue(Object? value) =>
    value != null && (value is! String || value.trim().isNotEmpty);

String? _safeSafetyRatingsSummary(List ratings) {
  final summaries = ratings
      .whereType<Map>()
      .map((rating) {
        final fields = <String>[
          if (rating['category'] is String) rating['category'] as String,
          if (rating['probability'] is String) rating['probability'] as String,
          if (rating['blocked'] is bool) 'blocked=${rating['blocked']}',
        ];
        return fields.join(':');
      })
      .where((summary) => summary.isNotEmpty)
      .toList(growable: false);
  return summaries.isEmpty ? null : summaries.join(',');
}

AiFinishReason? _geminiFinishReason(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return switch (value.toUpperCase()) {
    'STOP' => AiFinishReason.stop,
    'MAX_TOKENS' => AiFinishReason.length,
    'SAFETY' ||
    'BLOCKLIST' ||
    'PROHIBITED_CONTENT' ||
    'SPII' => AiFinishReason.contentFiltered,
    'MALFORMED_FUNCTION_CALL' || 'RECITATION' => AiFinishReason.providerError,
    _ => AiFinishReason.unknown,
  };
}

String _canonicalModelId(String value) {
  var result = value.trim();
  while (result.startsWith('models/')) {
    result = result.substring('models/'.length);
  }
  return result;
}

class _GoogleApiError {
  const _GoogleApiError({this.code, this.status, this.message, this.reason});

  final int? code;
  final String? status;
  final String? message;
  final String? reason;

  String? get safeMessage => _sanitizeGoogleErrorMessage(message);

  static _GoogleApiError? tryParse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['error'] is! Map) return null;
      final error = decoded['error'] as Map;
      return _GoogleApiError(
        code: error['code'] is num ? (error['code'] as num).toInt() : null,
        status: error['status'] is String ? error['status'] as String : null,
        message: error['message'] is String ? error['message'] as String : null,
        reason: _readGoogleErrorReason(error['details']),
      );
    } catch (_) {
      return null;
    }
  }
}

String? _readGoogleErrorReason(Object? details) {
  if (details is! List) return null;
  for (final detail in details.whereType<Map>()) {
    final reason = detail['reason'];
    if (reason is String && reason.trim().isNotEmpty) return reason.trim();
    final metadata = detail['metadata'];
    if (metadata is Map) {
      final nested = metadata['reason'];
      if (nested is String && nested.trim().isNotEmpty) return nested.trim();
    }
  }
  return null;
}

String? _sanitizeGoogleErrorMessage(String? value) {
  if (value == null) return null;
  var safe = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  safe = safe.replaceAll(
    RegExp(r'AIza[0-9A-Za-z_-]{10,}'),
    '[REDACTED_API_KEY]',
  );
  if (safe.length > 240) safe = '${safe.substring(0, 240)}...';
  return safe.isEmpty ? null : safe;
}

String _geminiThought(Object? decoded) {
  if (decoded is! Map || decoded['candidates'] is! List) return '';
  final candidate = (decoded['candidates'] as List).firstOrNull;
  if (candidate is! Map || candidate['content'] is! Map) return '';
  final parts = (candidate['content'] as Map)['parts'];
  if (parts is! List) return '';
  return parts
      .whereType<Map>()
      .where((p) => p['thought'] == true)
      .map((p) => p['text'])
      .whereType<String>()
      .join();
}
