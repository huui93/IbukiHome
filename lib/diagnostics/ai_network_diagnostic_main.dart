import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/network/ai_provider_exceptions.dart';
import '../data/ai/ai_provider_registry.dart';
import '../data/secure/flutter_secure_value_store.dart';
import '../data/secure/secure_ai_provider_config_repository.dart';
import '../data/secure/secure_storage_api_key_store.dart';
import '../domain/ai/ai_generation.dart';
import '../domain/ai/ai_provider_type.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _DiagnosticApp());
  await _runDiagnostic();
}

Future<void> _runDiagnostic() async {
  const storage = FlutterSecureStorage();
  final values = FlutterSecureValueStore(storage);
  final configs = SecureAiProviderConfigRepository(values);
  final keys = SecureStorageApiKeyStore(values);
  final selection = await configs.loadDefault();
  if (selection == null) {
    debugPrint('AI_DIAGNOSTIC result=config_missing');
    return;
  }
  final config = await configs.getConfig(selection.providerId);
  if (config == null) {
    debugPrint('AI_DIAGNOSTIC result=config_id_mismatch');
    return;
  }
  final apiKey = await keys.read(config.apiKeyRef) ?? '';
  debugPrint(
    'AI_DIAGNOSTIC provider=${config.type.name} '
    'configIdMatch=${config.id == selection.providerId} '
    'apiKeyPresent=${apiKey.isNotEmpty} model=${selection.modelId}',
  );
  if (config.type.requiresApiKey && apiKey.isEmpty) {
    debugPrint('AI_DIAGNOSTIC result=key_missing');
    return;
  }

  final registry = AiProviderRegistry(httpClientFactory: http.Client.new);
  try {
    final modelsClient = registry.create(config, apiKey);
    final models = await modelsClient.listModels();
    modelsClient.close();
    debugPrint(
      'AI_DIAGNOSTIC models=success count=${models.length} '
      'selectedAvailable=${models.contains(selection.modelId)}',
    );
    if (!models.contains(selection.modelId)) {
      debugPrint('AI_DIAGNOSTIC result=model_stale');
      return;
    }

    final nonStreamClient = registry.create(config, apiKey);
    final nonStream = await nonStreamClient.generate(
      _request(
        requestId: 'diagnostic-non-stream',
        model: selection.modelId,
        instruction: '回复 OK',
      ),
    );
    nonStreamClient.close();
    debugPrint(
      'AI_DIAGNOSTIC nonStream=success outputPresent=${nonStream.trim().isNotEmpty}',
    );

    final streamClient = registry.create(config, apiKey);
    final streamed = await streamClient
        .streamGenerate(
          _request(
            requestId: 'diagnostic-stream',
            model: selection.modelId,
            instruction: '用一句话说你好',
          ),
        )
        .join();
    streamClient.close();
    debugPrint(
      'AI_DIAGNOSTIC stream=success outputPresent=${streamed.trim().isNotEmpty}',
    );
  } on AiProviderException catch (error) {
    debugPrint('AI_DIAGNOSTIC result=failure exception=${error.runtimeType}');
  } catch (error) {
    debugPrint('AI_DIAGNOSTIC result=failure exception=${error.runtimeType}');
  }
}

AiGenerationRequest _request({
  required String requestId,
  required String model,
  required String instruction,
}) {
  return AiGenerationRequest(
    requestId: requestId,
    model: model,
    systemPrompt: '这是网络链路测试。只需简短回答，不包含用户项目数据。',
    messages: [
      AiGenerationMessage(role: AiMessageRole.user, content: instruction),
    ],
    maxTokens: 32,
  );
}

class _DiagnosticApp extends StatelessWidget {
  const _DiagnosticApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('AI 网络诊断正在运行'))),
    );
  }
}
