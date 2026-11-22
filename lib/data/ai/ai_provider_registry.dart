// ignore_for_file: prefer_initializing_formals

import 'package:http/http.dart' as http;

import '../../core/network/ai_network_diagnostics.dart';
import '../../core/network/ai_provider_exceptions.dart';
import '../../domain/ai/ai_provider_config.dart';
import '../../domain/ai/ai_provider_type.dart';
import 'ai_provider_client.dart';
import 'claude_provider_client.dart';
import 'gemini_provider_client.dart';
import 'openai_compatible_provider_client.dart';

typedef AiProviderClientBuilder =
    AiProviderClient Function(
      AiProviderConfig config,
      String apiKey,
      http.Client client,
      Duration timeout,
      AiNetworkDiagnostics diagnostics,
    );

class AiProviderRegistry {
  AiProviderRegistry({
    required http.Client Function() httpClientFactory,
    Duration timeout = const Duration(seconds: 90),
    AiNetworkDiagnostics diagnostics = const DeveloperAiNetworkDiagnostics(),
  }) : _httpClientFactory = httpClientFactory,
       _timeout = timeout,
       _diagnostics = diagnostics,
       _geminiModelOutputLimits = <String, int>{},
       _builders = {
         AiProviderType.openai: _openAi,
         AiProviderType.gemini: _gemini,
         AiProviderType.deepseek: _deepSeek,
         AiProviderType.kimi: _kimi,
         AiProviderType.qwen: _compatible,
         AiProviderType.grok: _compatible,
         AiProviderType.glm: _compatible,
         AiProviderType.claude: _claude,
         AiProviderType.custom: _custom,
       };

  final http.Client Function() _httpClientFactory;
  final Duration _timeout;
  final AiNetworkDiagnostics _diagnostics;
  final Map<String, int> _geminiModelOutputLimits;
  final Map<AiProviderType, AiProviderClientBuilder> _builders;

  AiProviderClient create(AiProviderConfig config, String apiKey) {
    final uri = Uri.tryParse(config.baseUrl.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const AiProviderValidationException(
        'Base URL 无效，请输入 HTTP 或 HTTPS 地址。',
      );
    }
    final builder = _builders[config.type];
    if (builder == null) {
      throw const AiProviderValidationException('暂不支持这个 Provider。');
    }
    final normalized = config.copyWith(
      baseUrl: normalizeAiProviderBaseUri(config.type, uri).toString(),
    );
    if (config.type == AiProviderType.gemini) {
      return GeminiProviderClient(
        baseUri: Uri.parse(normalized.baseUrl),
        apiKey: apiKey,
        httpClient: _httpClientFactory(),
        timeout: _timeout,
        preferredModel: config.selectedModel,
        diagnostics: _diagnostics,
        sharedModelOutputLimits: _geminiModelOutputLimits,
      );
    }
    return builder(
      normalized,
      apiKey,
      _httpClientFactory(),
      _timeout,
      _diagnostics,
    );
  }

  static AiProviderClient _openAi(
    AiProviderConfig config,
    String key,
    http.Client client,
    Duration timeout,
    AiNetworkDiagnostics diagnostics,
  ) => OpenAiProviderClient(
    baseUri: Uri.parse(config.baseUrl),
    apiKey: key,
    httpClient: client,
    timeout: timeout,
    diagnostics: diagnostics,
  );

  static AiProviderClient _gemini(
    AiProviderConfig config,
    String key,
    http.Client client,
    Duration timeout,
    AiNetworkDiagnostics diagnostics,
  ) => GeminiProviderClient(
    baseUri: Uri.parse(config.baseUrl),
    apiKey: key,
    httpClient: client,
    timeout: timeout,
    preferredModel: config.selectedModel,
    diagnostics: diagnostics,
  );

  static AiProviderClient _deepSeek(
    AiProviderConfig config,
    String key,
    http.Client client,
    Duration timeout,
    AiNetworkDiagnostics diagnostics,
  ) => DeepSeekProviderClient(
    baseUri: Uri.parse(config.baseUrl),
    apiKey: key,
    httpClient: client,
    timeout: timeout,
    diagnostics: diagnostics,
  );

  static AiProviderClient _kimi(
    AiProviderConfig config,
    String key,
    http.Client client,
    Duration timeout,
    AiNetworkDiagnostics diagnostics,
  ) => KimiProviderClient(
    baseUri: Uri.parse(config.baseUrl),
    apiKey: key,
    httpClient: client,
    timeout: timeout,
    diagnostics: diagnostics,
  );

  static AiProviderClient _compatible(
    AiProviderConfig config,
    String key,
    http.Client client,
    Duration timeout,
    AiNetworkDiagnostics diagnostics,
  ) => OpenAiCompatibleProviderClient(
    baseUri: Uri.parse(config.baseUrl),
    apiKey: key,
    httpClient: client,
    timeout: timeout,
    diagnostics: diagnostics,
    providerType: config.type.name,
  );

  static AiProviderClient _claude(
    AiProviderConfig config,
    String key,
    http.Client client,
    Duration timeout,
    AiNetworkDiagnostics diagnostics,
  ) => ClaudeProviderClient(
    baseUri: Uri.parse(config.baseUrl),
    apiKey: key,
    httpClient: client,
    timeout: timeout,
    diagnostics: diagnostics,
  );

  static AiProviderClient _custom(
    AiProviderConfig config,
    String key,
    http.Client client,
    Duration timeout,
    AiNetworkDiagnostics diagnostics,
  ) => OpenAiCompatibleProviderClient(
    baseUri: Uri.parse(config.baseUrl),
    apiKey: key,
    httpClient: client,
    timeout: timeout,
    diagnostics: diagnostics,
  );
}

Uri normalizeAiProviderBaseUri(AiProviderType type, Uri uri) {
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (type == AiProviderType.gemini &&
      uri.host.toLowerCase() == 'generativelanguage.googleapis.com') {
    return uri.replace(
      pathSegments: const ['v1beta'],
      query: null,
      fragment: null,
    );
  }
  if (segments.length >= 2 &&
      segments[segments.length - 2].toLowerCase() == 'chat' &&
      segments.last.toLowerCase() == 'completions') {
    segments.removeLast();
    segments.removeLast();
  } else if (segments.isNotEmpty && segments.last.toLowerCase() == 'models') {
    segments.removeLast();
  }
  if (type == AiProviderType.claude) {
    if (segments.lastOrNull?.toLowerCase() == 'messages') segments.removeLast();
    if (segments.lastOrNull != 'v1') segments.add('v1');
  }
  if (segments.isEmpty) {
    final host = uri.host.toLowerCase();
    if ((type == AiProviderType.openai && host == 'api.openai.com') ||
        (type == AiProviderType.kimi &&
            {'api.moonshot.cn', 'api.moonshot.ai'}.contains(host)) ||
        (type == AiProviderType.grok && host == 'api.x.ai')) {
      segments.add('v1');
    }
    if (type == AiProviderType.qwen &&
        (host == 'dashscope.aliyuncs.com' ||
            host == 'dashscope-intl.aliyuncs.com' ||
            host.endsWith('.maas.aliyuncs.com'))) {
      segments.addAll(['compatible-mode', 'v1']);
    }
    if (type == AiProviderType.glm && host == 'open.bigmodel.cn') {
      segments.addAll(['api', 'paas', 'v4']);
    }
  }
  if (type == AiProviderType.deepseek &&
      uri.host.toLowerCase() == 'api.deepseek.com' &&
      segments.isNotEmpty &&
      segments.last.toLowerCase() == 'v1') {
    segments.removeLast();
  }
  return uri.replace(pathSegments: segments, query: null, fragment: null);
}
