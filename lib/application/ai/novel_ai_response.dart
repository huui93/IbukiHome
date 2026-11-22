import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../core/network/ai_provider_exceptions.dart';
import '../../domain/ai/ai_generation.dart';
import 'clean_ai_text.dart';

class NovelAiResponse {
  const NovelAiResponse._();

  static String finalize({
    required String requestId,
    required String stage,
    required String adapterText,
    required AiFinishReason? finishReason,
    required int streamEventCount,
    String? provider,
    String? model,
    int attempt = 1,
  }) {
    final trimmed = adapterText.trim();
    if (trimmed.isEmpty) {
      final kind = adapterText.isNotEmpty
          ? AiEmptyResponseKind.whitespaceOnly
          : finishReason == AiFinishReason.contentFiltered
          ? AiEmptyResponseKind.filteredEmpty
          : AiEmptyResponseKind.providerEmpty;
      final error = AiProviderInvalidResponseException.empty(
        emptyKind: kind,
        responseDiagnostics: AiProviderResponseDiagnostics(
          provider: provider,
          model: model,
          normalizedFinishReason: finishReason?.name,
          rawReceivedChars: adapterText.length,
          normalizedChars: adapterText.length,
          finalResultChars: 0,
          streamEventCount: streamEventCount,
          streamClosedNormally: finishReason != null,
          abnormalEof: finishReason == null,
        ),
      );
      throw error;
    }

    final finalText = cleanAiText(adapterText);
    if (finalText.isEmpty) {
      final error = AiProviderInvalidResponseException.empty(
        emptyKind: AiEmptyResponseKind.parserEmpty,
        responseDiagnostics: AiProviderResponseDiagnostics(
          provider: provider,
          model: model,
          normalizedFinishReason: finishReason?.name,
          rawReceivedChars: adapterText.length,
          normalizedChars: adapterText.length,
          finalResultChars: 0,
          streamEventCount: streamEventCount,
          streamClosedNormally: finishReason != null,
          abnormalEof: finishReason == null,
        ),
        diagnostic: 'novel text cleaner produced an empty result',
      );
      throw error;
    }

    _record(
      requestId: requestId,
      stage: stage,
      result: 'success',
      provider: provider,
      model: model,
      finishReason: finishReason?.name,
      rawReceivedChars: adapterText.length,
      normalizedChars: adapterText.length,
      finalResultChars: finalText.length,
      streamEventCount: streamEventCount,
      streamClosedNormally: finishReason != null,
      abnormalEof: finishReason == null,
      attempt: attempt,
    );
    return finalText;
  }

  static AiProviderInvalidResponseException enrich({
    required AiProviderInvalidResponseException error,
    required String adapterText,
    required AiFinishReason? finishReason,
    required int streamEventCount,
    String? provider,
    String? model,
  }) {
    final current = error.responseDiagnostics;
    final diagnostics = (current ?? const AiProviderResponseDiagnostics())
        .copyWith(
          provider: current?.provider ?? provider,
          model: current?.model ?? model,
          normalizedFinishReason:
              current?.normalizedFinishReason ?? finishReason?.name,
          rawReceivedChars: current?.rawReceivedChars ?? adapterText.length,
          normalizedChars: current?.normalizedChars ?? adapterText.length,
          finalResultChars: current?.finalResultChars ?? 0,
          streamEventCount: current?.streamEventCount ?? streamEventCount,
          streamClosedNormally:
              current?.streamClosedNormally ?? finishReason != null,
          abnormalEof: current?.abnormalEof ?? finishReason == null,
        );
    if (error.emptyKind == null) {
      return AiProviderInvalidResponseException.withDiagnostics(
        diagnostic: error.diagnostic,
        responseDiagnostics: diagnostics.copyWith(abnormalEof: false),
      );
    }
    return AiProviderInvalidResponseException.empty(
      emptyKind: error.emptyKind!,
      diagnostic: error.diagnostic,
      responseDiagnostics: diagnostics,
    );
  }

  static void recordFailure({
    required String requestId,
    required String stage,
    required AiProviderInvalidResponseException error,
  }) {
    final diagnostics = error.responseDiagnostics;
    _record(
      requestId: requestId,
      stage: stage,
      result: error.emptyKind?.name ?? 'invalidResponse',
      provider: diagnostics?.provider,
      model: diagnostics?.model,
      httpStatus: diagnostics?.httpStatus,
      finishReason:
          diagnostics?.rawFinishReason ?? diagnostics?.normalizedFinishReason,
      candidateCount: diagnostics?.candidateCount,
      partCount: diagnostics?.partCount,
      textPartCount: diagnostics?.textPartCount,
      rawReceivedChars: diagnostics?.rawReceivedChars,
      normalizedChars: diagnostics?.normalizedChars,
      finalResultChars: diagnostics?.finalResultChars,
      streamEventCount: diagnostics?.streamEventCount,
      rawSseEventCount: diagnostics?.rawSseEventCount,
      parsedResponseObjectCount: diagnostics?.parsedResponseObjectCount,
      candidateEventCount: diagnostics?.candidateEventCount,
      textEventCount: diagnostics?.textEventCount,
      topLevelKeys: diagnostics?.topLevelKeys,
      promptFeedbackPresent: diagnostics?.promptFeedbackPresent,
      promptBlockReason: diagnostics?.promptBlockReason,
      promptSafetyRatingsCount: diagnostics?.promptSafetyRatingsCount,
      promptSafetyRatingsSummary: diagnostics?.promptSafetyRatingsSummary,
      responseIdPresent: diagnostics?.responseIdPresent,
      modelVersionPresent: diagnostics?.modelVersionPresent,
      usageMetadataPresent: diagnostics?.usageMetadataPresent,
      modelStatusPresent: diagnostics?.modelStatusPresent,
      streamClosedNormally: diagnostics?.streamClosedNormally,
      abnormalEof: diagnostics?.abnormalEof,
      providerErrorStatus: diagnostics?.providerErrorStatus,
    );
  }

  static void recordTransportInterruption({
    required String requestId,
    required String stage,
    required AiProviderInterruptedBeforeContentException error,
    required int attempt,
  }) {
    final diagnostics = error.responseDiagnostics;
    _record(
      requestId: requestId,
      stage: stage,
      result: 'transportInterruptedBeforeContent',
      attempt: attempt,
      provider: diagnostics.provider,
      model: diagnostics.model,
      httpStatus: diagnostics.httpStatus,
      finishReason:
          diagnostics.rawFinishReason ?? diagnostics.normalizedFinishReason,
      candidateCount: diagnostics.candidateCount,
      partCount: diagnostics.partCount,
      textPartCount: diagnostics.textPartCount,
      rawReceivedChars: diagnostics.rawReceivedChars,
      normalizedChars: diagnostics.normalizedChars,
      finalResultChars: diagnostics.finalResultChars,
      streamEventCount: diagnostics.streamEventCount,
      rawSseEventCount: diagnostics.rawSseEventCount,
      parsedResponseObjectCount: diagnostics.parsedResponseObjectCount,
      candidateEventCount: diagnostics.candidateEventCount,
      textEventCount: diagnostics.textEventCount,
      topLevelKeys: diagnostics.topLevelKeys,
      promptFeedbackPresent: diagnostics.promptFeedbackPresent,
      promptBlockReason: diagnostics.promptBlockReason,
      promptSafetyRatingsCount: diagnostics.promptSafetyRatingsCount,
      promptSafetyRatingsSummary: diagnostics.promptSafetyRatingsSummary,
      responseIdPresent: diagnostics.responseIdPresent,
      modelVersionPresent: diagnostics.modelVersionPresent,
      usageMetadataPresent: diagnostics.usageMetadataPresent,
      modelStatusPresent: diagnostics.modelStatusPresent,
      streamClosedNormally: diagnostics.streamClosedNormally,
      abnormalEof: diagnostics.abnormalEof,
      providerErrorStatus: diagnostics.providerErrorStatus,
      responseContentType: diagnostics.responseContentType,
      firstByteReceived: diagnostics.firstByteReceived,
      firstSseEventReceived: diagnostics.firstSseEventReceived,
      exceptionType: diagnostics.exceptionType ?? error.causeType,
    );
  }

  static void _record({
    required String requestId,
    required String stage,
    required String result,
    int? attempt,
    String? provider,
    String? model,
    int? httpStatus,
    String? finishReason,
    int? candidateCount,
    int? partCount,
    int? textPartCount,
    int? rawReceivedChars,
    int? normalizedChars,
    int? finalResultChars,
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
    bool? streamClosedNormally,
    bool? abnormalEof,
    String? providerErrorStatus,
    String? responseContentType,
    bool? firstByteReceived,
    bool? firstSseEventReceived,
    String? exceptionType,
  }) {
    final fields = <String>[
      'requestId=$requestId',
      'stage=$stage',
      'result=$result',
      if (attempt != null) 'attempt=$attempt',
      if (provider?.trim().isNotEmpty == true) 'provider=${provider!.trim()}',
      if (model?.trim().isNotEmpty == true) 'model=${model!.trim()}',
      if (httpStatus != null) 'httpStatus=$httpStatus',
      if (finishReason != null) 'finishReason=$finishReason',
      if (candidateCount != null) 'candidateCount=$candidateCount',
      if (partCount != null) 'partCount=$partCount',
      if (textPartCount != null) 'textPartCount=$textPartCount',
      if (rawReceivedChars != null) 'rawReceivedChars=$rawReceivedChars',
      if (normalizedChars != null) 'normalizedChars=$normalizedChars',
      if (finalResultChars != null) 'finalResultChars=$finalResultChars',
      if (streamEventCount != null) 'streamEventCount=$streamEventCount',
      if (rawSseEventCount != null) 'rawSseEventCount=$rawSseEventCount',
      if (parsedResponseObjectCount != null)
        'parsedResponseObjectCount=$parsedResponseObjectCount',
      if (candidateEventCount != null)
        'candidateEventCount=$candidateEventCount',
      if (textEventCount != null) 'textEventCount=$textEventCount',
      if (topLevelKeys?.isNotEmpty == true) 'topLevelKeys=$topLevelKeys',
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
      if (streamClosedNormally != null)
        'streamClosedNormally=$streamClosedNormally',
      if (abnormalEof != null) 'abnormalEOF=$abnormalEof',
      if (providerErrorStatus != null)
        'providerErrorStatus=$providerErrorStatus',
      if (responseContentType != null)
        'responseContentType=$responseContentType',
      if (firstByteReceived != null) 'firstByteReceived=$firstByteReceived',
      if (firstSseEventReceived != null)
        'firstSseEventReceived=$firstSseEventReceived',
      if (exceptionType != null) 'exceptionType=$exceptionType',
    ];
    final message = fields.join(' ');
    developer.log(message, name: 'ibukihome.ai.novel');
    if (kDebugMode) debugPrint('AI_NOVEL $message');
  }
}
