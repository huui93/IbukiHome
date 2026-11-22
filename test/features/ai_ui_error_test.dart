import 'package:flutter_test/flutter_test.dart';
import 'package:ibukihome/core/errors/data_exceptions.dart';
import 'package:ibukihome/core/network/ai_provider_exceptions.dart';
import 'package:ibukihome/features/ai/presentation/ai_ui_helpers.dart';

void main() {
  test('empty provider response is not reported as a generic anomaly', () {
    final error = describeAiError(
      const AiProviderInvalidResponseException(),
      stage: 'generate-next-segment',
    );
    expect(error.category, 'providerEmpty');
    expect(error.message, contains('没有返回可用正文'));
    expect(error.summary, isNot(contains('模型返回内容异常')));
  });

  test('empty response categories keep provider structure diagnostics', () {
    for (final expectation in <AiEmptyResponseKind, String>{
      AiEmptyResponseKind.providerEmpty: '没有返回可用正文',
      AiEmptyResponseKind.candidateEmpty: '候选结果',
      AiEmptyResponseKind.promptBlocked: '未接受当前提示内容',
      AiEmptyResponseKind.filteredEmpty: '内容策略终止',
      AiEmptyResponseKind.parserEmpty: '正文解析失败',
      AiEmptyResponseKind.whitespaceOnly: '空白内容',
    }.entries) {
      final error = describeAiError(
        AiProviderInvalidResponseException.empty(
          emptyKind: expectation.key,
          responseDiagnostics: const AiProviderResponseDiagnostics(
            provider: 'gemini',
            model: 'gemini-test',
            httpStatus: 200,
            rawFinishReason: 'STOP',
            candidateCount: 1,
            partCount: 2,
            textPartCount: 1,
            rawReceivedChars: 8,
            normalizedChars: 0,
            finalResultChars: 0,
          ),
        ),
        stage: 'generate-next-segment',
      );
      expect(error.category, expectation.key.name);
      expect(error.message, contains(expectation.value));
      expect(error.detail, contains('provider=gemini'));
      expect(error.detail, contains('candidateCount=1'));
      expect(error.detail, contains('rawReceivedChars=8'));
      expect(error.detail, contains('normalizedChars=0'));
      expect(error.detail, isNot(contains('模型返回内容异常')));
    }
  });

  test('Gemini prompt block keeps the provider reason in user diagnostics', () {
    final error = describeAiError(
      const AiProviderInvalidResponseException.empty(
        emptyKind: AiEmptyResponseKind.promptBlocked,
        responseDiagnostics: AiProviderResponseDiagnostics(
          provider: 'gemini',
          model: 'gemini-3.1-flash-lite',
          httpStatus: 200,
          rawSseEventCount: 1,
          parsedResponseObjectCount: 1,
          candidateEventCount: 0,
          textEventCount: 0,
          promptFeedbackPresent: true,
          promptBlockReason: 'SAFETY',
          streamClosedNormally: true,
          abnormalEof: false,
        ),
      ),
      stage: 'generate-next-segment',
    );

    expect(error.category, 'promptBlocked');
    expect(error.summary, contains('内容策略阻止'));
    expect(error.detail, contains('promptBlockReason=SAFETY'));
    expect(error.detail, contains('rawSseEventCount=1'));
    expect(error.detail, contains('parsedResponseObjectCount=1'));
    expect(error.detail, isNot(contains('模型返回内容异常')));
  });

  test('parser diagnostics are separated from empty response', () {
    final error = describeAiError(
      const AiProviderInvalidResponseException('json parse failed'),
      stage: 'segment-draft',
    );
    expect(error.category, 'parser');
    expect(error.message, contains('格式无法解析'));
  });

  test('zero-content interruption is reported as transport failure', () {
    final error = describeAiError(
      const AiProviderInterruptedBeforeContentException(
        causeType: 'responseBodyInterrupted',
        responseDiagnostics: AiProviderResponseDiagnostics(
          provider: 'gemini',
          model: 'gemini-3.1-flash-lite',
          httpStatus: 200,
          responseContentType: 'text/event-stream',
          firstByteReceived: false,
          firstSseEventReceived: false,
          streamEventCount: 0,
          rawReceivedChars: 0,
          streamClosedNormally: false,
          abnormalEof: true,
        ),
      ),
      stage: 'generate-next-segment',
    );

    expect(error.category, 'transportInterruptedBeforeContent');
    expect(error.summary, contains('AI 连接中断'));
    expect(error.summary, isNot(contains('模型返回内容异常')));
    expect(error.detail, contains('httpStatus=200'));
    expect(error.detail, contains('firstSseEventReceived=false'));
    expect(error.detail, contains('streamEventCount=0'));
  });

  test('generated segment save failure is attributed to persistence', () {
    final error = describeAiError(
      const AiPersistenceException(
        stage: AiPersistenceStage.segmentSave,
        causeType: 'DataConflictException',
        message: '正文已经生成，但本地保存失败。',
      ),
    );
    expect(error.category, 'segmentSave');
    expect(error.title, contains('本地保存失败'));
    expect(error.detail, contains('causeType=DataConflictException'));
  });

  test('diagnostic detail redacts credentials and stays bounded', () {
    final error = describeAiError(
      const AiProviderProtocolException(
        'Authorization: Bearer secret-token api_key=another-secret',
      ),
      provider: 'gemini',
      model: 'gemini-test',
      requestId: 'request-1',
    );
    expect(error.detail, isNot(contains('secret-token')));
    expect(error.detail, isNot(contains('another-secret')));
    expect(error.detail, contains('[REDACTED]'));
    expect(error.detail.runes.length, lessThanOrEqualTo(400));
  });
}
