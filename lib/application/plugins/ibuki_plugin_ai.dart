import 'dart:async';

import '../../core/network/ai_provider_exceptions.dart';
import '../../data/ai/ai_provider_client.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/plugins/installed_plugin.dart';
import '../ai/ai_generation_service.dart';
import '../ai/ai_model_resolver.dart';
import 'ibuki_hook_bus.dart';
import 'plugin_creative_state.dart';
import 'plugin_permissions.dart';
import '../../core/errors/plugin_exceptions.dart';

class PluginAiResult {
  const PluginAiResult({
    required this.requestId,
    required this.text,
    required this.finishReason,
    required this.interrupted,
    required this.provider,
    required this.model,
    required this.modelDisplayLabel,
  });

  final String requestId;
  final String text;
  final String finishReason;
  final bool interrupted;
  final String provider;
  final String model;
  final String modelDisplayLabel;

  Map<String, Object?> toSafeJson() => {
    'requestId': requestId,
    'text': text,
    'finishReason': finishReason,
    'interrupted': interrupted,
    'model': {
      'provider': provider,
      'id': model,
      'displayLabel': modelDisplayLabel,
    },
  };
}

abstract class IbukiPluginAi {
  Future<PluginAiResult> generate({
    required InstalledPlugin plugin,
    required PluginScopeRef scope,
    required String prompt,
    String systemPrompt = '你正在响应一个经过用户授权的伊吹之家插件请求。只返回请求所需的结果。',
    int maxOutputTokens = 1024,
  });

  bool cancelPlugin(String pluginId);
}

class CoreIbukiPluginAi implements IbukiPluginAi {
  CoreIbukiPluginAi({
    required this.runtime,
    required this.modelResolver,
    required this.hooks,
    this.requestTimeout = const Duration(seconds: 120),
    this.maximumOutputTokens = 4096,
  }) {
    _disableSubscription = hooks.subscribe(
      pluginId: _hostOwnerId,
      hook: IbukiHook.onPluginDisabled,
      handler: (event) {
        final pluginId = event['pluginId'];
        if (pluginId is String) cancelPlugin(pluginId);
      },
    );
  }

  static const _hostOwnerId = '__ibuki_host_plugin_ai__';

  final AiGenerationRuntime runtime;
  final AiModelResolver modelResolver;
  final IbukiHookBus hooks;
  final Duration requestTimeout;
  final int maximumOutputTokens;
  final Map<String, AiRequestCancellation> _active = {};
  late final PluginHookSubscription _disableSubscription;

  int get activeRequestCount => _active.length;

  @override
  Future<PluginAiResult> generate({
    required InstalledPlugin plugin,
    required PluginScopeRef scope,
    required String prompt,
    String systemPrompt = '你正在响应一个经过用户授权的伊吹之家插件请求。只返回请求所需的结果。',
    int maxOutputTokens = 1024,
  }) async {
    PluginPermissionGuard(
      plugin.manifest,
    ).require(PluginPermissions.aiGenerate);
    if (!plugin.enabled || plugin.isBroken) {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件当前不可用。',
      );
    }
    final normalizedPrompt = prompt.trim();
    if (normalizedPrompt.isEmpty || normalizedPrompt.length > 64000) {
      throw const PluginException(
        PluginErrorCategory.invalidBridgeRequest,
        '插件 AI 请求内容无效。',
      );
    }
    if (systemPrompt.length > 16000) {
      throw const PluginException(
        PluginErrorCategory.invalidBridgeRequest,
        '插件 AI 系统指令过长。',
      );
    }
    if (_active.containsKey(plugin.id)) {
      throw const PluginException(
        PluginErrorCategory.aiRequestBusy,
        '此插件已有一个 AI 请求正在进行。',
      );
    }

    final resolved = await _resolve(scope);
    final requestId =
        'plugin_ai_${DateTime.now().microsecondsSinceEpoch}_${plugin.id.hashCode.abs()}';
    final cancellation = AiRequestCancellation();
    _active[plugin.id] = cancellation;
    final output = StringBuffer();
    var finishReason = AiFinishReason.unknown;
    try {
      await hooks.publish(IbukiHook.beforePluginAiRequest, {
        'pluginId': plugin.id,
        'requestId': requestId,
        'scope': scope.storageKey,
        'provider': resolved.providerType,
        'model': resolved.model,
        'promptChars': normalizedPrompt.length,
      });
      final request = AiGenerationRequest(
        requestId: requestId,
        systemPrompt: systemPrompt,
        messages: [
          AiGenerationMessage(
            role: AiMessageRole.user,
            content: normalizedPrompt,
          ),
        ],
        providerConfigId: resolved.providerConfigId,
        model: resolved.model,
        temperature: 0.7,
        maxTokens: maxOutputTokens.clamp(1, maximumOutputTokens),
      );
      await _collect(request, cancellation, output, (reason) {
        finishReason = reason;
      }).timeout(
        requestTimeout,
        onTimeout: () {
          cancellation.cancel();
          throw const PluginException(
            PluginErrorCategory.aiRequestTimeout,
            '插件 AI 请求超时。',
          );
        },
      );
      final text = output.toString();
      if (text.trim().isEmpty &&
          finishReason != AiFinishReason.contentFiltered) {
        throw const PluginException(
          PluginErrorCategory.pluginRuntimeFailure,
          '插件 AI 没有返回可用内容。',
        );
      }
      final result = PluginAiResult(
        requestId: requestId,
        text: text,
        finishReason: finishReason.name,
        interrupted: finishReason == AiFinishReason.interrupted,
        provider: resolved.providerType,
        model: resolved.model,
        modelDisplayLabel: resolved.displayLabel,
      );
      await hooks.publish(IbukiHook.afterPluginAiResponse, {
        'pluginId': plugin.id,
        'requestId': requestId,
        'finishReason': finishReason.name,
        'responseChars': text.length,
      });
      return result;
    } on PluginException {
      rethrow;
    } on AiProviderCancelledException {
      throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件 AI 请求已取消。',
      );
    } on AiProviderException catch (error) {
      throw PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '插件 AI 请求失败。',
        detail: error.runtimeType.toString(),
      );
    } finally {
      _active.remove(plugin.id);
    }
  }

  Future<void> _collect(
    AiGenerationRequest request,
    AiRequestCancellation cancellation,
    StringBuffer output,
    void Function(AiFinishReason reason) onFinish,
  ) async {
    await for (final event in runtimeStreamEvents(
      runtime,
      request,
      cancellation: cancellation,
    )) {
      if (event.isTerminal) {
        onFinish(event.finishReason ?? AiFinishReason.unknown);
      } else {
        output.write(event.content);
      }
    }
  }

  Future<ResolvedAiModel> _resolve(PluginScopeRef scope) async {
    return switch (scope.type) {
      PluginScopeType.project => modelResolver.resolveForProject(scope.id!),
      PluginScopeType.chatSession => modelResolver.resolveForChatSession(
        scope.id!,
      ),
      PluginScopeType.global => _resolveGlobal(),
      PluginScopeType.world ||
      PluginScopeType.worldSession => throw const PluginException(
        PluginErrorCategory.pluginRuntimeFailure,
        '当前版本尚未开放世界模式插件 AI。',
      ),
    };
  }

  Future<ResolvedAiModel> _resolveGlobal() async {
    final resolved = await runtime.resolveDefault();
    return ResolvedAiModel(
      providerConfigId: resolved.config.id,
      providerType: resolved.config.type.name,
      model: resolved.selection.modelId,
      displayLabel: resolved.displayLabel,
      source: AiModelSelectionSource.globalDefault,
    );
  }

  @override
  bool cancelPlugin(String pluginId) {
    final cancellation = _active[pluginId];
    if (cancellation == null) return false;
    cancellation.cancel();
    return true;
  }

  void dispose() {
    _disableSubscription.cancel();
    for (final cancellation in _active.values) {
      cancellation.cancel();
    }
    _active.clear();
  }
}
