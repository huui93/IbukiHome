import 'dart:async';
import '../../data/repositories/novel_plugin_repository.dart';
import '../../data/repositories/plugin_registry.dart';
import '../../domain/ai/ai_generation.dart';
import '../../domain/plugins/installed_plugin.dart';
import '../../domain/plugins/novel_history_fingerprint.dart';
import '../../domain/plugins/novel_plugin_models.dart';
import '../../domain/segments/segment.dart';
import '../ai/ai_model_resolver.dart';
import '../ai/novel_context_loader.dart';
import 'novel_plugin_bundle.dart';
import 'novel_plugin_scope_store.dart';
import 'novel_plugin_sources.dart';
import 'novel_prompt_compiler.dart';
import 'novel_reply_markup.dart';

typedef NovelPluginBinding = ({
  InstalledPlugin plugin,
  NovelPluginScopeState scope,
  NovelPluginBundle bundle,
});

class NovelPluginRun {
  NovelPluginRun({
    required this.binding,
    required this.compiled,
    required this.history,
    required this.activeWorldInfo,
    required this.mode,
    required this.reasoning,
  });
  final NovelPluginBinding binding;
  final NovelCompiledPrompt compiled;
  final List<NovelHistoryMessage> history;
  final List<String> activeWorldInfo;
  final NovelGenerationMode mode;
  final StringBuffer reasoning;

  Map<String, Object?> inspection() => {
    'plugin': binding.plugin.manifest.name,
    'mode': mode.label,
    'worldInfo': activeWorldInfo,
    ...compiled.toJson(),
    'systemPrompt': compiled.request.systemPrompt,
    'messages': [
      for (final message in compiled.request.messages)
        {'role': message.role.name, 'content': message.content},
      if (compiled.request.assistantPrefill case final prefill?)
        {'role': 'assistant', 'content': prefill},
    ],
  };
}

class NovelPluginHost {
  NovelPluginHost({
    required this.registry,
    required this.repository,
    required this.scopes,
    required this.sources,
    required this.streamingPreference,
    this.scheduleMemory,
    this.cancelMemory,
    this.modelLimits,
    this.loader = const NovelPluginBundleLoader(),
  });
  final PluginRegistry registry;
  final NovelPluginRepository repository;
  final NovelPluginScopeStore scopes;
  final NovelPluginSources sources;
  final Future<bool> Function() streamingPreference;
  final void Function(String)? scheduleMemory;
  final void Function(String)? cancelMemory;
  final Future<({int context, int output})?> Function(ResolvedAiModel)?
  modelLimits;
  final NovelPluginBundleLoader loader;
  final _inspections = <String, NovelPluginRun>{};
  final _events =
      StreamController<
        ({String projectId, String type, String? segmentId})
      >.broadcast();

  Stream<({String projectId, String type, String? segmentId})> get events =>
      _events.stream;
  void publish(String projectId, String type, {String? segmentId}) {
    if (!_events.isClosed) {
      _events.add((projectId: projectId, type: type, segmentId: segmentId));
    }
  }

  NovelPluginRun? lastRun(String projectId) => _inspections[projectId];
  void finalized(Segment segment, String type, {bool automaticMemory = true}) {
    publish(segment.projectId, type, segmentId: segment.id);
    if (automaticMemory) scheduleMemory?.call(segment.projectId);
  }

  Future<bool> complete({
    required NovelPluginRun run,
    required Segment segment,
    required String raw,
    required AiFinishReason? finish,
  }) async {
    final plugin = run.binding.plugin;
    final hash = novelContentHash(segment.content);
    final projectId = segment.projectId;
    var ended = false;
    if (plugin.manifest.permissions.contains('novel.presentation')) {
      final slots = NovelReplyMarkup.parse(raw).slots;
      await repository.saveReplyView(segment.id, hash, {
        'pluginId': plugin.id,
        'slots': slots,
        if (run.reasoning.isNotEmpty)
          'nativeReasoning': run.reasoning.toString(),
      });
    }
    final declaration = run.binding.bundle.options['sessionEnd'];
    if (finish == AiFinishReason.stop &&
        declaration is Map &&
        declaration['attribute'] == 'data-nvwa-end' &&
        run.binding.scope.allowEnd &&
        plugin.manifest.permissions.contains('novel.session.end')) {
      final reason = NovelReplyMarkup.endingReason(raw);
      final current = reason == null
          ? null
          : await registry.getPlugin(plugin.id);
      if (current != null && current.updatedAt == plugin.updatedAt) {
        final scope = await scopes.resolve(current, projectId);
        if (scope.enabled && scope.allowEnd) {
          await repository.endBranch(
            projectId: projectId,
            pluginId: plugin.id,
            segmentId: segment.id,
            revision: segment.revision,
            contentHash: hash,
            reason: reason!,
          );
          cancelMemory?.call(projectId);
          publish(projectId, 'end', segmentId: segment.id);
          ended = true;
        }
      }
    }
    if (!ended) {
      finalized(
        segment,
        run.mode == NovelGenerationMode.regenerate ? 'regenerate' : 'send',
        automaticMemory: run.binding.scope.automaticMemory,
      );
    }
    return ended;
  }

  void clearInspections() => _inspections.clear();
  void dispose() => _events.close();

  Future<NovelPluginBinding?> bindingFor(String projectId) async {
    final branch = await repository.branch(projectId);
    if (branch.ended) {
      throw const NovelPluginRequestException('当前故事线已结束。可另开故事线继续创作。');
    }
    NovelPluginBinding? binding;
    for (final plugin in await registry.listPlugins()) {
      if (!NovelPluginBundleLoader.supports(plugin) ||
          !plugin.manifest.permissions.contains('ai.prompt.modify')) {
        continue;
      }
      final scope = await scopes.resolve(plugin, projectId);
      if (!scope.enabled) continue;
      if (binding != null) {
        throw const NovelPluginRequestException('一条故事线只能启用一套结构化提示词，请在作品设置里选择。');
      }
      try {
        binding = (
          plugin: plugin,
          scope: scope,
          bundle: await loader.load(plugin),
        );
      } on NovelPluginRequestException {
        rethrow;
      } catch (_) {
        throw const NovelPluginRequestException('作品绑定的小说插件资源无法读取，请重新安装插件。');
      }
    }
    return binding;
  }

  Future<List<NovelMemoryBlock>> memories(
    InstalledPlugin plugin,
    String projectId,
    List<NovelHistoryMessage> history,
  ) async {
    final saved = await scopes.privateGet(plugin, projectId, 'memory');
    final raw = saved is Map ? saved['blocks'] : null;
    if (raw is! List) return const [];
    return [
      for (final item in raw.whereType<Map>())
        if (_readMemory(item) case final block?)
          if (novelMemorySourcesCurrent(block, history)) block,
    ];
  }

  NovelMemoryBlock? _readMemory(Map raw) {
    try {
      return NovelMemoryBlock.fromJson(Map<String, Object?>.from(raw));
    } catch (_) {
      return null;
    }
  }

  Future<NovelPluginRun> prepare({
    required NovelPluginBinding binding,
    required NovelAiContext context,
    required AiGenerationRequest core,
    required ResolvedAiModel? model,
    required String authorInput,
    required String instruction,
    required NovelGenerationMode mode,
    String? targetSegmentId,
    int? targetRevision,
    String? speakerId,
    double? projectTemperature,
    int? projectOutputTokenLimit,
    required DateTime now,
  }) async {
    final projectId = context.project.id;
    final allHistory = await repository.history(projectId);
    final targetIndex = targetSegmentId == null
        ? -1
        : allHistory.indexWhere((m) => m.segmentId == targetSegmentId);
    if (targetSegmentId != null &&
        (targetIndex < 0 ||
            allHistory[targetIndex].revision != targetRevision)) {
      throw const NovelPluginRequestException('目标段落已变化，请重新生成。');
    }
    final history = allHistory
        .where((m) => m.segmentId != targetSegmentId)
        .toList();
    final recentIds = allHistory.reversed.take(4).map((m) => m.id).toSet();
    final memory = await memories(binding.plugin, projectId, allHistory);
    final valid = [
      for (final block in memory)
        if (targetIndex < 0 ||
            !block.coveredMessageIds.contains(allHistory[targetIndex].id))
          block,
    ];
    final usable = _recall(
      valid,
      instruction,
      allHistory.lastOrNull?.content ?? '',
    );
    final excluded = {
      for (final block in usable)
        if (block.kind == 'summary')
          ...block.coveredMessageIds.where((id) => !recentIds.contains(id)),
    };
    final resolved = await sources.resolve(
      context: context,
      settings: binding.scope.settings,
      mode: mode,
      history: history.where((m) => !excluded.contains(m.id)).toList(),
      memories: usable,
      input: instruction,
      requestId: core.requestId,
      now: now,
      speakerId: speakerId,
    );
    final reasoning = StringBuffer();
    final stream = await streamingPreference();
    final positions = {
      for (var i = 0; i < allHistory.length; i++) allHistory[i].id: i,
    };
    final preset = binding.bundle.preset;
    final limits = model == null ? null : await modelLimits?.call(model);
    final endPolicy = binding.scope.allowEnd
        ? '\n\n如本条故事线自然结束，可在新回复最后单独一行写 <div data-nvwa-end>结束原因</div>。其他情况不要输出该标记。'
        : '';
    final result = const NovelPromptCompiler().compile(
      core: core.copyWith(
        streamOutput: stream,
        onNativeReasoning: (text) {
          final remaining = 24000 - reasoning.length;
          if (remaining > 0) {
            reasoning.write(text.substring(0, text.length.clamp(0, remaining)));
          }
        },
      ),
      preset: preset,
      resources: binding.bundle.resources,
      settings: binding.scope.settings,
      variables: resolved.variables,
      placeholders: resolved.placeholders,
      history: history,
      authorInput: '$authorInput$endPolicy',
      mode: mode,
      memories: usable,
      excludedMessageIds: excluded,
      providerType: model?.providerType ?? 'custom',
      model: model?.model ?? core.model ?? '',
      modelContextLimit: limits?.context,
      modelOutputLimit: limits?.output,
      projectTemperature: projectTemperature,
      projectOutputTokenLimit: projectOutputTokenLimit,
      allowStreaming: stream,
      historyText: (message) {
        final index = positions[message.id]!;
        final position = targetIndex < 0
            ? ''
            : index < targetIndex
            ? '目标之前'
            : '目标之后';
        final body = NovelReplyMarkup.parse(message.content).body;
        final suffix =
            mode == NovelGenerationMode.continueReply &&
                message.id == history.last.id
            ? binding.bundle.preset.templates['continuePostfix'] ?? ''
            : '';
        return position.isEmpty ? '$body$suffix' : '【$position】\n$body$suffix';
      },
    );
    final run = NovelPluginRun(
      binding: binding,
      compiled: result,
      history: allHistory,
      activeWorldInfo: resolved.activated,
      mode: mode,
      reasoning: reasoning,
    );
    _inspections.remove(projectId);
    _inspections[projectId] = run;
    if (_inspections.length > 8) _inspections.remove(_inspections.keys.first);
    return run;
  }

  List<NovelMemoryBlock> _recall(
    List<NovelMemoryBlock> blocks,
    String instruction,
    String scene,
  ) {
    if (blocks.length <= 6) return blocks;
    final recent = blocks.reversed.take(3).toSet();
    final query =
        '$instruction ${scene.substring(0, scene.length.clamp(0, 1800))}'
            .toLowerCase();
    final terms = RegExp(
      r'[a-z0-9]{3,}|[\u3400-\u9fff]{2}',
    ).allMatches(query).map((m) => m.group(0)!).take(250).toSet();
    final ranked = [
      for (final block in blocks)
        if (!recent.contains(block))
          (
            block: block,
            score: terms.where(block.content.toLowerCase().contains).length,
          ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    final selected = {
      ...recent,
      ...ranked.where((m) => m.score > 0).take(3).map((m) => m.block),
    };
    return blocks.where(selected.contains).toList();
  }

  Future<void> checkCurrent(String projectId, NovelPluginRun run) async {
    final current = await bindingFor(projectId);
    if (current?.plugin.id != run.binding.plugin.id ||
        current?.plugin.updatedAt != run.binding.plugin.updatedAt) {
      throw const NovelPluginRequestException('本作插件在生成期间发生变化，请重新生成。');
    }
    final latest = await repository.history(projectId);
    if (novelRefsFingerprint(novelSourceRefs(latest)) !=
        novelRefsFingerprint(novelSourceRefs(run.history))) {
      throw const NovelPluginRequestException('正文在生成期间发生变化，请重新生成。');
    }
  }
}
