import 'dart:convert';

import '../../application/ai/ai_generation_service.dart';
import '../../application/ai/ai_model_resolver.dart';
import '../../core/network/ai_provider_exceptions.dart';
import '../../data/ai/ai_provider_client.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/world_roleplay/world_roleplay_engine_models.dart';
import '../plugins/ibuki_prompt_pipeline.dart';
import 'world_context_builder.dart';

abstract class WorldDirector {
  Future<WorldDirectorDecision> decide({
    required String requestId,
    required WorldRoleplaySnapshot snapshot,
    required AiRequestCancellation cancellation,
  });
}

class AiWorldDirector implements WorldDirector {
  const AiWorldDirector({
    required this.runtime,
    required this.modelResolver,
    this.promptPipeline = const CoreOnlyPromptPipeline(),
  });

  final AiGenerationRuntime runtime;
  final AiModelResolver modelResolver;
  final IbukiPromptPipeline promptPipeline;

  @override
  Future<WorldDirectorDecision> decide({
    required String requestId,
    required WorldRoleplaySnapshot snapshot,
    required AiRequestCancellation cancellation,
  }) async {
    final resolved = await modelResolver.resolveForWorldSession(
      snapshot.session.id,
    );
    Object? firstError;
    String? invalidResponse;
    for (var attempt = 1; attempt <= 2; attempt += 1) {
      try {
        final repair = attempt == 1
            ? ''
            : '\n上一次输出无法解析。请只返回符合指定 schema 的 JSON 对象，不要 Markdown。';
        final coreRequest = AiGenerationRequest(
          requestId: '$requestId-director-$attempt',
          providerConfigId: resolved.providerConfigId,
          model: resolved.model,
          systemPrompt: repair + snapshot.context.directorSystemPrompt,
          messages: [
            AiGenerationMessage(
              role: AiMessageRole.user,
              content: snapshot.context.directorUserPrompt,
            ),
          ],
          temperature: 0.2,
          maxTokens: 1400,
          structuredJson: true,
        );
        final piped = await promptPipeline.apply(
          coreRequest,
          PluginPromptContext(
            operation: PluginPromptOperation.worldDirector,
            worldId: snapshot.world.id,
            worldSessionId: snapshot.session.id,
            safeMetadata: const {'requestKind': 'worldDirector'},
          ),
        );
        final raw = await runtime.generate(
          piped.request,
          cancellation: cancellation,
        );
        invalidResponse = raw;
        return WorldDirectorDecision.fromJson(_decodeObject(raw));
      } on WorldEngineException catch (error) {
        firstError ??= error;
      } on AiProviderException {
        rethrow;
      } on FormatException catch (error) {
        firstError ??= error;
      }
    }
    throw WorldEngineException(
      WorldEngineErrorCategory.directorError,
      '世界导演未能理解本次行动。',
      detail:
          'parse=${firstError.runtimeType}; receivedChars=${invalidResponse?.length ?? 0}',
    );
  }

  Map<String, Object?> _decodeObject(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) throw const FormatException('empty');
    final start = normalized.indexOf('{');
    final end = normalized.lastIndexOf('}');
    if (start < 0 || end < start) throw const FormatException('object missing');
    final decoded = jsonDecode(normalized.substring(start, end + 1));
    if (decoded is! Map) throw const FormatException('not object');
    return Map<String, Object?>.from(decoded);
  }
}
