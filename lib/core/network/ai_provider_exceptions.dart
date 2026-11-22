class AiProviderException implements Exception {
  const AiProviderException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class AiProviderValidationException extends AiProviderException {
  const AiProviderValidationException(super.message);
}

class AiProviderAuthenticationException extends AiProviderException {
  const AiProviderAuthenticationException([
    super.message = 'API Key 无效，请检查后重试。',
  ]);
}

class AiProviderNetworkException extends AiProviderException {
  const AiProviderNetworkException([super.message = '无法连接服务器，请检查网络和地址。']);
}

class AiProviderHandshakeException extends AiProviderException {
  const AiProviderHandshakeException() : super('安全连接失败，请检查设备时间和网络环境。');
}

class AiProviderTimeoutException extends AiProviderException {
  const AiProviderTimeoutException() : super('请求超时，请稍后重试。');
}

class AiProviderProtocolException extends AiProviderException {
  const AiProviderProtocolException([super.message = '服务返回了无法识别的数据。']);
}

class AiProviderConnectionTestException extends AiProviderException {
  const AiProviderConnectionTestException(
    super.message, {
    required this.availableModels,
    required this.temporaryModel,
    this.incompatibleModels = const [],
  });

  final List<String> availableModels;
  final String temporaryModel;
  final List<String> incompatibleModels;
}

class AiProviderServerException extends AiProviderException {
  const AiProviderServerException() : super('服务器暂时不可用，请稍后重试。');
}

class AiProviderRequestRejectedException extends AiProviderException {
  const AiProviderRequestRejectedException([
    super.message = '请求被服务器拒绝，请检查账号权限。',
  ]);
}

class AiProviderEndpointException extends AiProviderException {
  const AiProviderEndpointException([
    super.message = 'API 地址或接口不存在，请检查 Base URL。',
  ]);
}

class AiProviderCancelledException extends AiProviderException {
  const AiProviderCancelledException() : super('生成已取消。');
}

class AiProviderModelUnavailableException extends AiProviderException {
  const AiProviderModelUnavailableException([super.message = '模型不可用，请重新选择。']);
}

class AiProviderNativeInterfaceIncompatibleException
    extends AiProviderModelUnavailableException {
  const AiProviderNativeInterfaceIncompatibleException([
    super.message = '该模型不支持当前 Gemini Native 生成接口。',
  ]);
}

class AiProviderRateLimitedException extends AiProviderException {
  const AiProviderRateLimitedException([super.message = '请求过于频繁或额度不足，请稍后重试。']);
}

class AiProviderContextTooLargeException extends AiProviderException {
  const AiProviderContextTooLargeException() : super('上下文过长，请减少参考内容。');
}

enum AiEmptyResponseKind {
  providerEmpty,
  candidateEmpty,
  promptBlocked,
  filteredEmpty,
  parserEmpty,
  whitespaceOnly,
}

class AiProviderResponseDiagnostics {
  const AiProviderResponseDiagnostics({
    this.provider,
    this.model,
    this.httpStatus,
    this.responseContentType,
    this.firstByteReceived,
    this.firstSseEventReceived,
    this.rawFinishReason,
    this.normalizedFinishReason,
    this.candidateCount,
    this.partCount,
    this.textPartCount,
    this.rawReceivedChars,
    this.normalizedChars,
    this.finalResultChars,
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
    this.streamClosedNormally,
    this.abnormalEof,
    this.providerErrorStatus,
    this.providerErrorMessage,
    this.exceptionType,
  });

  final String? provider;
  final String? model;
  final int? httpStatus;
  final String? responseContentType;
  final bool? firstByteReceived;
  final bool? firstSseEventReceived;
  final String? rawFinishReason;
  final String? normalizedFinishReason;
  final int? candidateCount;
  final int? partCount;
  final int? textPartCount;
  final int? rawReceivedChars;
  final int? normalizedChars;
  final int? finalResultChars;
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
  final bool? streamClosedNormally;
  final bool? abnormalEof;
  final String? providerErrorStatus;
  final String? providerErrorMessage;
  final String? exceptionType;

  AiProviderResponseDiagnostics copyWith({
    String? provider,
    String? model,
    int? httpStatus,
    String? responseContentType,
    bool? firstByteReceived,
    bool? firstSseEventReceived,
    String? rawFinishReason,
    String? normalizedFinishReason,
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
    String? providerErrorMessage,
    String? exceptionType,
  }) {
    return AiProviderResponseDiagnostics(
      provider: provider ?? this.provider,
      model: model ?? this.model,
      httpStatus: httpStatus ?? this.httpStatus,
      responseContentType: responseContentType ?? this.responseContentType,
      firstByteReceived: firstByteReceived ?? this.firstByteReceived,
      firstSseEventReceived:
          firstSseEventReceived ?? this.firstSseEventReceived,
      rawFinishReason: rawFinishReason ?? this.rawFinishReason,
      normalizedFinishReason:
          normalizedFinishReason ?? this.normalizedFinishReason,
      candidateCount: candidateCount ?? this.candidateCount,
      partCount: partCount ?? this.partCount,
      textPartCount: textPartCount ?? this.textPartCount,
      rawReceivedChars: rawReceivedChars ?? this.rawReceivedChars,
      normalizedChars: normalizedChars ?? this.normalizedChars,
      finalResultChars: finalResultChars ?? this.finalResultChars,
      streamEventCount: streamEventCount ?? this.streamEventCount,
      rawSseEventCount: rawSseEventCount ?? this.rawSseEventCount,
      parsedResponseObjectCount:
          parsedResponseObjectCount ?? this.parsedResponseObjectCount,
      candidateEventCount: candidateEventCount ?? this.candidateEventCount,
      textEventCount: textEventCount ?? this.textEventCount,
      topLevelKeys: topLevelKeys ?? this.topLevelKeys,
      promptFeedbackPresent:
          promptFeedbackPresent ?? this.promptFeedbackPresent,
      promptBlockReason: promptBlockReason ?? this.promptBlockReason,
      promptSafetyRatingsCount:
          promptSafetyRatingsCount ?? this.promptSafetyRatingsCount,
      promptSafetyRatingsSummary:
          promptSafetyRatingsSummary ?? this.promptSafetyRatingsSummary,
      responseIdPresent: responseIdPresent ?? this.responseIdPresent,
      modelVersionPresent: modelVersionPresent ?? this.modelVersionPresent,
      usageMetadataPresent: usageMetadataPresent ?? this.usageMetadataPresent,
      modelStatusPresent: modelStatusPresent ?? this.modelStatusPresent,
      streamClosedNormally: streamClosedNormally ?? this.streamClosedNormally,
      abnormalEof: abnormalEof ?? this.abnormalEof,
      providerErrorStatus: providerErrorStatus ?? this.providerErrorStatus,
      providerErrorMessage: providerErrorMessage ?? this.providerErrorMessage,
      exceptionType: exceptionType ?? this.exceptionType,
    );
  }

  Iterable<String> get safeFields sync* {
    if (provider?.trim().isNotEmpty == true) {
      yield 'provider=${provider!.trim()}';
    }
    if (model?.trim().isNotEmpty == true) yield 'model=${model!.trim()}';
    if (httpStatus != null) yield 'httpStatus=$httpStatus';
    if (responseContentType?.trim().isNotEmpty == true) {
      yield 'responseContentType=${responseContentType!.trim()}';
    }
    if (firstByteReceived != null) {
      yield 'firstByteReceived=$firstByteReceived';
    }
    if (firstSseEventReceived != null) {
      yield 'firstSseEventReceived=$firstSseEventReceived';
    }
    if (rawFinishReason != null) yield 'rawFinishReason=$rawFinishReason';
    if (normalizedFinishReason != null) {
      yield 'normalizedFinishReason=$normalizedFinishReason';
    }
    if (candidateCount != null) yield 'candidateCount=$candidateCount';
    if (partCount != null) yield 'partCount=$partCount';
    if (textPartCount != null) yield 'textPartCount=$textPartCount';
    if (rawReceivedChars != null) yield 'rawReceivedChars=$rawReceivedChars';
    if (normalizedChars != null) yield 'normalizedChars=$normalizedChars';
    if (finalResultChars != null) yield 'finalResultChars=$finalResultChars';
    if (streamEventCount != null) yield 'streamEventCount=$streamEventCount';
    if (rawSseEventCount != null) yield 'rawSseEventCount=$rawSseEventCount';
    if (parsedResponseObjectCount != null) {
      yield 'parsedResponseObjectCount=$parsedResponseObjectCount';
    }
    if (candidateEventCount != null) {
      yield 'candidateEventCount=$candidateEventCount';
    }
    if (textEventCount != null) yield 'textEventCount=$textEventCount';
    if (topLevelKeys?.trim().isNotEmpty == true) {
      yield 'topLevelKeys=${topLevelKeys!.trim()}';
    }
    if (promptFeedbackPresent != null) {
      yield 'promptFeedbackPresent=$promptFeedbackPresent';
    }
    if (promptBlockReason?.trim().isNotEmpty == true) {
      yield 'promptBlockReason=${promptBlockReason!.trim()}';
    }
    if (promptSafetyRatingsCount != null) {
      yield 'promptSafetyRatingsCount=$promptSafetyRatingsCount';
    }
    if (promptSafetyRatingsSummary?.trim().isNotEmpty == true) {
      yield 'promptSafetyRatings=${promptSafetyRatingsSummary!.trim()}';
    }
    if (responseIdPresent != null) {
      yield 'responseIdPresent=$responseIdPresent';
    }
    if (modelVersionPresent != null) {
      yield 'modelVersionPresent=$modelVersionPresent';
    }
    if (usageMetadataPresent != null) {
      yield 'usageMetadataPresent=$usageMetadataPresent';
    }
    if (modelStatusPresent != null) {
      yield 'modelStatusPresent=$modelStatusPresent';
    }
    if (streamClosedNormally != null) {
      yield 'streamClosedNormally=$streamClosedNormally';
    }
    if (abnormalEof != null) yield 'abnormalEOF=$abnormalEof';
    if (providerErrorStatus?.trim().isNotEmpty == true) {
      yield 'providerErrorStatus=${providerErrorStatus!.trim()}';
    }
    if (providerErrorMessage?.trim().isNotEmpty == true) {
      yield 'providerErrorMessage=${providerErrorMessage!.trim()}';
    }
    if (exceptionType?.trim().isNotEmpty == true) {
      yield 'transportException=${exceptionType!.trim()}';
    }
  }
}

class AiProviderInvalidResponseException extends AiProviderException {
  const AiProviderInvalidResponseException([this.diagnostic = ''])
    : emptyKind = null,
      responseDiagnostics = null,
      super('模型返回内容异常。');

  const AiProviderInvalidResponseException.withDiagnostics({
    required this.diagnostic,
    required this.responseDiagnostics,
  }) : emptyKind = null,
       super('服务返回格式异常。');

  const AiProviderInvalidResponseException.empty({
    required this.emptyKind,
    this.responseDiagnostics = const AiProviderResponseDiagnostics(),
    this.diagnostic = '',
  }) : super('模型未返回可用正文。');

  final String diagnostic;
  final AiEmptyResponseKind? emptyKind;
  final AiProviderResponseDiagnostics? responseDiagnostics;

  @override
  String toString() {
    final fields = <String>[
      super.toString(),
      if (emptyKind != null) 'emptyKind=${emptyKind!.name}',
      if (diagnostic.isNotEmpty) 'diagnostic=$diagnostic',
      ...?responseDiagnostics?.safeFields,
    ];
    return fields.join(' ');
  }
}

class AiProviderInterruptedException extends AiProviderException {
  const AiProviderInterruptedException({
    this.causeType = 'abnormal-eof',
    this.timeoutType = 'none',
  }) : super('回复意外中断，可以继续生成或重新生成。');

  final String causeType;
  final String timeoutType;
}

class AiProviderInterruptedBeforeContentException
    extends AiProviderInterruptedException {
  const AiProviderInterruptedBeforeContentException({
    super.causeType = 'abnormal-eof',
    super.timeoutType = 'none',
    this.responseDiagnostics = const AiProviderResponseDiagnostics(),
  });

  final AiProviderResponseDiagnostics responseDiagnostics;

  @override
  String toString() => <String>[
    'AiProviderInterruptedBeforeContentException',
    'causeType=$causeType',
    'timeoutType=$timeoutType',
    ...responseDiagnostics.safeFields,
  ].join(' ');
}

class AiProviderUnknownException extends AiProviderException {
  const AiProviderUnknownException() : super('Provider 请求失败，请稍后重试。');
}
