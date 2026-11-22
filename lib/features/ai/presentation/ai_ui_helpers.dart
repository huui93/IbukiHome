import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/errors/data_exceptions.dart';
import '../../../core/network/ai_provider_exceptions.dart';

class AiUiErrorPresentation {
  const AiUiErrorPresentation({
    required this.category,
    required this.title,
    required this.message,
    required this.detail,
  });

  final String category;
  final String title;
  final String message;
  final String detail;

  String get summary => title == message ? title : '$title：$message';
}

String friendlyAiError(Object error, {String stage = 'generation'}) =>
    describeAiError(error, stage: stage).summary;

AiUiErrorPresentation describeAiError(
  Object error, {
  String stage = 'generation',
  String? provider,
  String? model,
  String? requestId,
}) {
  final classified = _classify(error, stage);
  final response = error is AiProviderInvalidResponseException
      ? error.responseDiagnostics
      : error is AiProviderInterruptedBeforeContentException
      ? error.responseDiagnostics
      : null;
  final effectiveProvider = provider ?? response?.provider;
  final effectiveModel = model ?? response?.model;
  final fields = <String>[
    'category=${classified.category}',
    'stage=$stage',
    if (effectiveProvider?.trim().isNotEmpty == true)
      'provider=${effectiveProvider!.trim()}',
    if (effectiveModel?.trim().isNotEmpty == true)
      'model=${effectiveModel!.trim()}',
    if (requestId?.trim().isNotEmpty == true) 'requestId=${requestId!.trim()}',
    'exceptionType=${error.runtimeType}',
    if (error is AiPersistenceException) 'causeType=${error.causeType}',
    if (error is AiProviderInvalidResponseException && error.emptyKind != null)
      'emptyKind=${error.emptyKind!.name}',
    if (error is AiProviderInterruptedBeforeContentException)
      'interruptionKind=transportInterruptedBeforeContent',
    ...?response?.safeFields
        .where(
          (field) =>
              !field.startsWith('provider=') && !field.startsWith('model='),
        )
        .map(_sanitize),
    if (error is AiProviderInvalidResponseException &&
        error.diagnostic.trim().isNotEmpty)
      'diagnostic=${_sanitize(error.diagnostic)}',
    'message=${_sanitize(classified.message)}',
  ];
  return AiUiErrorPresentation(
    category: classified.category,
    title: classified.title,
    message: classified.message,
    detail: _limit(fields.join('\n'), 400),
  );
}

Future<void> showAiErrorDetails(
  BuildContext context,
  AiUiErrorPresentation error,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(error.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(error.message),
            const SizedBox(height: 12),
            SelectableText(
              error.detail,
              key: const Key('ai-error-detail'),
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          key: const Key('copy-ai-error-detail'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: error.detail));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('复制诊断'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

AiUiErrorPresentation _classify(Object error, String stage) {
  if (error is AiPersistenceException) {
    return switch (error.stage) {
      AiPersistenceStage.segmentSave => _error(
        'segmentSave',
        '正文已经生成，但本地保存失败',
        '请保留当前草稿并稍后重试保存。',
      ),
      AiPersistenceStage.revisionSave => _error(
        'revisionSave',
        '修改结果已经生成，但版本保存失败',
        '原正文没有被覆盖，请稍后重试。',
      ),
      AiPersistenceStage.projectSave => _error(
        'projectSave',
        '项目设置保存失败',
        '本次修改没有写入本地数据库。',
      ),
      AiPersistenceStage.summarySave => _error(
        'summary',
        '正文已生成',
        '后台长期摘要保存失败，可以稍后刷新。',
      ),
      AiPersistenceStage.digestSave => _error(
        'digest',
        '正文已生成',
        '后台故事记忆保存失败，可以稍后刷新。',
      ),
    };
  }
  if (error is AiProviderAuthenticationException ||
      error is AiProviderRequestRejectedException ||
      error is AiProviderEndpointException ||
      error is AiProviderRateLimitedException ||
      error is AiProviderServerException ||
      error is AiProviderProtocolException) {
    return _error('providerHttp', 'Provider 请求失败', _message(error));
  }
  if (error is AiProviderNetworkException ||
      error is AiProviderHandshakeException ||
      error is AiProviderTimeoutException) {
    return _error('network', 'AI 网络连接失败', _message(error));
  }
  if (error is AiProviderInterruptedBeforeContentException) {
    return _error('transportInterruptedBeforeContent', 'AI 连接中断', '请重试。');
  }
  if (error is AiProviderInterruptedException) {
    return _error('streamInterrupted', 'AI 流式回复中断', '已保留收到的内容，可以继续生成。');
  }
  if (error is AiProviderInvalidResponseException) {
    final emptyKind = error.emptyKind;
    if (emptyKind != null) {
      return switch (emptyKind) {
        AiEmptyResponseKind.providerEmpty => _error(
          'providerEmpty',
          'AI 生成失败',
          '模型请求成功，但没有返回可用正文。',
        ),
        AiEmptyResponseKind.candidateEmpty => _error(
          'candidateEmpty',
          'Gemini 未生成正文',
          'Gemini 返回了候选结果，但其中没有可用正文。',
        ),
        AiEmptyResponseKind.promptBlocked => _error(
          'promptBlocked',
          'Gemini 未生成正文',
          _promptBlockedMessage(error.responseDiagnostics?.promptBlockReason),
        ),
        AiEmptyResponseKind.filteredEmpty => _error(
          'filteredEmpty',
          'AI 生成失败',
          '模型没有返回正文，响应被内容策略终止。',
        ),
        AiEmptyResponseKind.parserEmpty => _error(
          'parserEmpty',
          'AI 生成失败',
          '模型返回了内容，但正文解析失败。',
        ),
        AiEmptyResponseKind.whitespaceOnly => _error(
          'whitespaceOnly',
          'AI 生成失败',
          '模型只返回了空白内容。',
        ),
      };
    }
    final parserFailure =
        error.diagnostic.toLowerCase().contains('parse') ||
        error.diagnostic.toLowerCase().contains('json') ||
        error.diagnostic.toLowerCase().contains('sse');
    return parserFailure
        ? _error('parser', 'AI 生成失败', '服务返回格式无法解析。')
        : _error('providerEmpty', 'AI 生成失败', '模型请求成功，但没有返回可用正文。');
  }
  if (error is AiProviderCancelledException) {
    return _error('cancelled', '生成已取消', '没有写入未完成内容。');
  }
  if (error is AiProviderModelUnavailableException ||
      error is AiProviderValidationException) {
    return _error('configuration', 'AI 配置不可用', _message(error));
  }
  if (error is DataException) {
    final category = stage.contains('project')
        ? 'projectSave'
        : stage.contains('revision')
        ? 'revisionSave'
        : stage.contains('summary')
        ? 'summary'
        : stage.contains('digest')
        ? 'digest'
        : 'localData';
    return _error(category, '本地数据操作失败', error.message);
  }
  if (error is ArgumentError) {
    return _error(
      'requestValidation',
      'AI 请求参数无效',
      error.message?.toString() ?? '请检查本次输入。',
    );
  }
  return _error('unknown', 'AI 生成失败', '发生未知错误，请稍后重试。');
}

AiUiErrorPresentation _error(String category, String title, String message) =>
    AiUiErrorPresentation(
      category: category,
      title: title,
      message: message,
      detail: '',
    );

String _message(Object error) => (error as AiProviderException).message;

String _promptBlockedMessage(String? reason) {
  return switch (reason?.trim().toUpperCase()) {
    'SAFETY' => '当前请求未获得正文，Gemini 内容策略阻止了本次生成。',
    'BLOCKLIST' => '当前请求包含 Gemini 不接受的内容，未生成正文。',
    'PROHIBITED_CONTENT' => 'Gemini 拒绝了当前生成请求。',
    _ => 'Gemini 未接受当前提示内容。',
  };
}

String _sanitize(String input) {
  var value = input;
  value = value.replaceAllMapped(
    RegExp(r'(bearer\s+)([^\s,;]+)', caseSensitive: false),
    (match) => '${match.group(1)}[REDACTED]',
  );
  value = value.replaceAllMapped(
    RegExp(r'(authorization\s*[:=]\s*)([^\s,;]+)', caseSensitive: false),
    (match) => '${match.group(1)}[REDACTED]',
  );
  value = value.replaceAllMapped(
    RegExp(
      r'((?:api[_ -]?key|x-goog-api-key)\s*[:=]\s*)([^\s,;]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[REDACTED]',
  );
  return value;
}

String _limit(String value, int maxRunes) {
  final runes = value.runes.toList(growable: false);
  if (runes.length <= maxRunes) return value;
  return '${String.fromCharCodes(runes.take(maxRunes))}…';
}
