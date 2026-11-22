import '../../domain/ai/ai_generation.dart';
import '../../core/network/ai_provider_exceptions.dart';

class AiProviderConnectionResult {
  const AiProviderConnectionResult({
    required this.models,
    this.verifiedModel,
    this.verifiedModels = const [],
    this.incompatibleModels = const [],
  });

  final List<String> models;
  final String? verifiedModel;
  final List<String> verifiedModels;
  final List<String> incompatibleModels;
}

abstract class AiProviderClient {
  Future<List<String>> listModels();

  Future<AiProviderConnectionResult> testConnection({
    String? preferredModel,
  }) async {
    final preferred = preferredModel?.trim() ?? '';
    var models = <String>[];
    try {
      models = await listModels();
    } on AiProviderEndpointException {
      if (preferred.isEmpty) {
        throw const AiProviderValidationException(
          '此服务未提供模型列表，请先手动填写模型 ID，再测试连接。',
        );
      }
    } on AiProviderProtocolException {
      if (preferred.isEmpty) rethrow;
    }
    if (preferred.isEmpty) {
      return AiProviderConnectionResult(models: models);
    }
    try {
      await generate(
        AiGenerationRequest(
          requestId: 'connection-test',
          model: preferred,
          systemPrompt: 'Reply only OK.',
          messages: const [
            AiGenerationMessage(role: AiMessageRole.user, content: 'Hi'),
          ],
          maxTokens: 2048,
        ),
      );
    } on AiProviderException catch (error) {
      throw AiProviderConnectionTestException(
        error.message,
        availableModels: models,
        temporaryModel: preferred,
      );
    }
    return AiProviderConnectionResult(
      models: List.unmodifiable({...models, preferred}.toList()..sort()),
      verifiedModel: preferred,
      verifiedModels: [preferred],
    );
  }

  Stream<String> streamGenerate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  });

  Stream<AiStreamEvent> streamEvents(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async* {
    await for (final chunk in streamGenerate(
      request,
      cancellation: cancellation,
    )) {
      yield AiStreamEvent.content(chunk);
    }
    yield const AiStreamEvent.finished(AiFinishReason.stop);
  }

  Future<String> generate(
    AiGenerationRequest request, {
    AiRequestCancellation? cancellation,
  }) async {
    final output = StringBuffer();
    await for (final chunk in streamGenerate(
      request,
      cancellation: cancellation,
    )) {
      output.write(chunk);
    }
    return output.toString();
  }

  void close();
}

class AiRequestCancellation {
  bool _cancelled = false;
  void Function()? _cancelRequest;

  bool get isCancelled => _cancelled;

  void attach(void Function() cancelRequest) {
    _cancelRequest = cancelRequest;
    if (_cancelled) {
      cancelRequest();
    }
  }

  void detach() {
    _cancelRequest = null;
  }

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _cancelRequest?.call();
  }
}
