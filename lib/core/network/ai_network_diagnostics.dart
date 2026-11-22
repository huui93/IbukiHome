import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class AiNetworkDiagnosticEvent {
  const AiNetworkDiagnosticEvent({
    required this.requestId,
    required this.providerType,
    required this.method,
    required this.host,
    required this.path,
    required this.model,
    required this.apiKeyPresent,
    required this.duration,
    this.statusCode,
    this.responseContentType,
    this.firstByteReceived,
    this.firstSseEventReceived,
    this.exceptionType,
    this.timeoutStage,
    this.modelCount,
    this.generateContentModelCount,
    this.stage,
    this.providerErrorCode,
    this.providerErrorStatus,
    this.providerErrorMessage,
    this.providerErrorReason,
    this.streamEventCount,
    this.rawSseEventCount,
    this.parsedResponseObjectCount,
    this.candidateEventCount,
    this.textEventCount,
    this.topLevelKeys,
    this.promptFeedbackPresent,
    this.promptBlockReason,
    this.promptSafetyRatingsCount,
    this.promptSafetyRatingsSummary,
    this.responseIdPresent,
    this.modelVersionPresent,
    this.usageMetadataPresent,
    this.modelStatusPresent,
    this.candidateCount,
    this.partCount,
    this.textPartCount,
    this.maxTextPartsPerEvent,
    this.rawReceivedCharacterCount,
    this.receivedCharacterCount,
    this.authoritativeCharacterCount,
    this.adapterHash,
    this.finishReason,
    this.rawFinishReason,
    this.normalizedFinishReason,
    this.streamNormalization,
    this.generationStartedAt,
    this.httpResponseAt,
    this.firstByteAt,
    this.lastChunkAt,
    this.streamEndAt,
    this.streamClosedNormally,
    this.abnormalEof,
    this.timeoutType,
    this.lastEventIndex,
    this.requestedMaxOutputTokens,
    this.modelOutputTokenLimit,
    this.promptTokenCount,
    this.candidatesTokenCount,
    this.totalTokenCount,
  });

  final String requestId;
  final String providerType;
  final String method;
  final String host;
  final String path;
  final String model;
  final bool apiKeyPresent;
  final Duration duration;
  final int? statusCode;
  final String? responseContentType;
  final bool? firstByteReceived;
  final bool? firstSseEventReceived;
  final String? exceptionType;
  final String? timeoutStage;
  final int? modelCount;
  final int? generateContentModelCount;
  final String? stage;
  final int? providerErrorCode;
  final String? providerErrorStatus;
  final String? providerErrorMessage;
  final String? providerErrorReason;
  final int? streamEventCount;
  final int? rawSseEventCount;
  final int? parsedResponseObjectCount;
  final int? candidateEventCount;
  final int? textEventCount;
  final String? topLevelKeys;
  final bool? promptFeedbackPresent;
  final String? promptBlockReason;
  final int? promptSafetyRatingsCount;
  final String? promptSafetyRatingsSummary;
  final bool? responseIdPresent;
  final bool? modelVersionPresent;
  final bool? usageMetadataPresent;
  final bool? modelStatusPresent;
  final int? candidateCount;
  final int? partCount;
  final int? textPartCount;
  final int? maxTextPartsPerEvent;
  final int? rawReceivedCharacterCount;
  final int? receivedCharacterCount;
  final int? authoritativeCharacterCount;
  final String? adapterHash;
  final String? finishReason;
  final String? rawFinishReason;
  final String? normalizedFinishReason;
  final String? streamNormalization;
  final DateTime? generationStartedAt;
  final DateTime? httpResponseAt;
  final DateTime? firstByteAt;
  final DateTime? lastChunkAt;
  final DateTime? streamEndAt;
  final bool? streamClosedNormally;
  final bool? abnormalEof;
  final String? timeoutType;
  final int? lastEventIndex;
  final int? requestedMaxOutputTokens;
  final int? modelOutputTokenLimit;
  final int? promptTokenCount;
  final int? candidatesTokenCount;
  final int? totalTokenCount;

  String get safeMessage {
    final fields = <String>[
      'requestId=$requestId',
      'provider=$providerType',
      'method=$method',
      'host=$host',
      'path=$path',
      'model=$model',
      'apiKeyPresent=$apiKeyPresent',
      if (stage != null) 'stage=$stage',
      if (statusCode != null) 'status=$statusCode',
      if (responseContentType != null)
        'responseContentType=$responseContentType',
      if (firstByteReceived != null) 'firstByteReceived=$firstByteReceived',
      if (firstSseEventReceived != null)
        'firstSseEventReceived=$firstSseEventReceived',
      if (exceptionType != null) 'exception=$exceptionType',
      if (timeoutStage != null) 'timeoutStage=$timeoutStage',
      if (modelCount != null) 'modelCount=$modelCount',
      if (generateContentModelCount != null)
        'generateContentModelCount=$generateContentModelCount',
      if (providerErrorCode != null) 'providerErrorCode=$providerErrorCode',
      if (providerErrorStatus != null)
        'providerErrorStatus=$providerErrorStatus',
      if (providerErrorMessage != null)
        'providerErrorMessage=$providerErrorMessage',
      if (providerErrorReason != null)
        'providerErrorReason=$providerErrorReason',
      if (streamEventCount != null) 'streamEvents=$streamEventCount',
      if (rawSseEventCount != null) 'rawSseEvents=$rawSseEventCount',
      if (parsedResponseObjectCount != null)
        'parsedResponseObjects=$parsedResponseObjectCount',
      if (candidateEventCount != null) 'candidateEvents=$candidateEventCount',
      if (textEventCount != null) 'textEvents=$textEventCount',
      if (topLevelKeys != null) 'topLevelKeys=$topLevelKeys',
      if (promptFeedbackPresent != null)
        'promptFeedbackPresent=$promptFeedbackPresent',
      if (promptBlockReason != null) 'promptBlockReason=$promptBlockReason',
      if (promptSafetyRatingsCount != null)
        'promptSafetyRatingsCount=$promptSafetyRatingsCount',
      if (promptSafetyRatingsSummary != null)
        'promptSafetyRatings=$promptSafetyRatingsSummary',
      if (responseIdPresent != null) 'responseIdPresent=$responseIdPresent',
      if (modelVersionPresent != null)
        'modelVersionPresent=$modelVersionPresent',
      if (usageMetadataPresent != null)
        'usageMetadataPresent=$usageMetadataPresent',
      if (modelStatusPresent != null) 'modelStatusPresent=$modelStatusPresent',
      if (candidateCount != null) 'candidates=$candidateCount',
      if (partCount != null) 'parts=$partCount',
      if (textPartCount != null) 'textParts=$textPartCount',
      if (maxTextPartsPerEvent != null)
        'maxTextPartsPerEvent=$maxTextPartsPerEvent',
      if (rawReceivedCharacterCount != null)
        'rawReceivedChars=$rawReceivedCharacterCount',
      if (receivedCharacterCount != null)
        'receivedChars=$receivedCharacterCount',
      if (authoritativeCharacterCount != null)
        'authoritativeChars=$authoritativeCharacterCount',
      if (adapterHash != null) 'adapterHash=$adapterHash',
      if (finishReason != null) 'finishReason=$finishReason',
      if (rawFinishReason != null) 'rawFinishReason=$rawFinishReason',
      if (normalizedFinishReason != null)
        'normalizedFinishReason=$normalizedFinishReason',
      if (streamNormalization != null)
        'streamNormalization=$streamNormalization',
      if (generationStartedAt != null)
        'generationStart=${generationStartedAt!.toIso8601String()}',
      if (httpResponseAt != null)
        'httpResponseAt=${httpResponseAt!.toIso8601String()}',
      if (firstByteAt != null) 'firstByteAt=${firstByteAt!.toIso8601String()}',
      if (lastChunkAt != null) 'lastChunkAt=${lastChunkAt!.toIso8601String()}',
      if (streamEndAt != null) 'streamEndAt=${streamEndAt!.toIso8601String()}',
      if (streamClosedNormally != null)
        'streamClosedNormally=$streamClosedNormally',
      if (abnormalEof != null) 'abnormalEOF=$abnormalEof',
      if (timeoutType != null) 'timeoutType=$timeoutType',
      if (lastEventIndex != null) 'lastEventIndex=$lastEventIndex',
      if (requestedMaxOutputTokens != null)
        'requestedMaxOutputTokens=$requestedMaxOutputTokens',
      if (modelOutputTokenLimit != null)
        'modelOutputTokenLimit=$modelOutputTokenLimit',
      if (promptTokenCount != null) 'promptTokenCount=$promptTokenCount',
      if (candidatesTokenCount != null)
        'candidatesTokenCount=$candidatesTokenCount',
      if (totalTokenCount != null) 'totalTokenCount=$totalTokenCount',
      'durationMs=${duration.inMilliseconds}',
    ];
    return fields.join(' ');
  }
}

abstract class AiNetworkDiagnostics {
  const AiNetworkDiagnostics();

  void record(AiNetworkDiagnosticEvent event);
}

class DeveloperAiNetworkDiagnostics extends AiNetworkDiagnostics {
  const DeveloperAiNetworkDiagnostics();

  @override
  void record(AiNetworkDiagnosticEvent event) {
    developer.log(event.safeMessage, name: 'ibukihome.ai.network');
    debugPrint('AI_NETWORK ${event.safeMessage}');
  }
}

class NoopAiNetworkDiagnostics extends AiNetworkDiagnostics {
  const NoopAiNetworkDiagnostics();

  @override
  void record(AiNetworkDiagnosticEvent event) {}
}
