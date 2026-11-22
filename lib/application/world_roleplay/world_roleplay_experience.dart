import '../../domain/world_roleplay/world_roleplay_engine_models.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';

class WorldTurnGroup {
  const WorldTurnGroup({required this.id, required this.entries, this.turn});

  final String id;
  final List<WorldFeedEntry> entries;
  final WorldTurn? turn;

  WorldFeedEntry? get userAction => entries
      .where((entry) => entry.type == WorldFeedEntryType.userAction)
      .firstOrNull;

  WorldFeedEntry get lastEntry => entries.last;

  bool get isCompleted => turn?.status == WorldTurnStatus.completed;
}

List<WorldTurnGroup> groupWorldFeedByTurn({
  required List<WorldFeedEntry> entries,
  required List<WorldTurn> turns,
}) {
  final turnById = {for (final turn in turns) turn.id: turn};
  final groups = <WorldTurnGroup>[];
  final indexById = <String, int>{};
  for (final entry in entries) {
    final metadataTurnId = entry.metadata['turnId'];
    final groupId = metadataTurnId is String && metadataTurnId.isNotEmpty
        ? metadataTurnId
        : 'legacy:${entry.id}';
    final existingIndex = indexById[groupId];
    if (existingIndex == null) {
      indexById[groupId] = groups.length;
      groups.add(
        WorldTurnGroup(id: groupId, entries: [entry], turn: turnById[groupId]),
      );
      continue;
    }
    final existing = groups[existingIndex];
    groups[existingIndex] = WorldTurnGroup(
      id: existing.id,
      entries: [...existing.entries, entry],
      turn: existing.turn,
    );
  }
  return List.unmodifiable(groups);
}

String? feedEntryBeforeTurn({
  required List<WorldFeedEntry> entries,
  required WorldTurnGroup group,
}) {
  final firstId = group.entries.first.id;
  final index = entries.indexWhere((entry) => entry.id == firstId);
  if (index <= 0) return null;
  return entries[index - 1].id;
}

class WorldTurnExperienceSummary {
  const WorldTurnExperienceSummary({
    this.activatedLoreEntryIds = const [],
    this.manualLoreEntryIds = const [],
    this.changes = const [],
    this.memories = const [],
    this.timelineEvents = const [],
    this.selectedCharacterCount = 0,
    this.selectedMemoryCount = 0,
    this.selectedTimelineCount = 0,
    this.selectedStateCount = 0,
    this.estimatedContextTokens = 0,
  });

  final List<String> activatedLoreEntryIds;
  final List<String> manualLoreEntryIds;
  final List<String> changes;
  final List<String> memories;
  final List<String> timelineEvents;
  final int selectedCharacterCount;
  final int selectedMemoryCount;
  final int selectedTimelineCount;
  final int selectedStateCount;
  final int estimatedContextTokens;

  bool get hasWorldChanges =>
      changes.isNotEmpty || memories.isNotEmpty || timelineEvents.isNotEmpty;

  String? get notice => [
    ...changes,
    ...memories.map((value) => '已记录记忆：$value'),
    ...timelineEvents.map((value) => '已加入时间线：$value'),
  ].firstOrNull;

  factory WorldTurnExperienceSummary.fromTurn(WorldTurn? turn) {
    if (turn == null) return const WorldTurnExperienceSummary();
    final metadata = turn.metadata;
    final diagnostics = metadata['contextDiagnostics'];
    final diagnosticMap = diagnostics is Map
        ? Map<String, Object?>.from(diagnostics)
        : const <String, Object?>{};
    final tokens = diagnosticMap['estimatedTokensBySection'];
    final tokenMap = tokens is Map
        ? Map<Object?, Object?>.from(tokens)
        : const {};
    WorldMutationProposal proposal;
    try {
      proposal = turn.mutationProposal.isEmpty
          ? const WorldMutationProposal()
          : WorldMutationProposal.fromJson(turn.mutationProposal);
    } catch (_) {
      proposal = const WorldMutationProposal();
    }
    return WorldTurnExperienceSummary(
      activatedLoreEntryIds: _strings(metadata['activatedLoreEntryIds']),
      manualLoreEntryIds: _strings(metadata['manualLoreEntryIds']),
      changes: proposal.operations.map(_mutationLabel).toList(growable: false),
      memories: proposal.memories
          .map((memory) => memory.summary)
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      timelineEvents: proposal.timelineEvents
          .map((event) => event.title)
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      selectedCharacterCount: _int(diagnosticMap['selectedCharacterCount']),
      selectedMemoryCount: _int(diagnosticMap['selectedMemoryCount']),
      selectedTimelineCount: _int(diagnosticMap['selectedTimelineCount']),
      selectedStateCount: _int(diagnosticMap['selectedStateCount']),
      estimatedContextTokens: tokenMap.values.fold<int>(
        0,
        (total, value) => total + _int(value),
      ),
    );
  }
}

class WorldErrorPresentation {
  const WorldErrorPresentation({
    required this.summary,
    required this.actionLabel,
    required this.detail,
  });

  final String summary;
  final String actionLabel;
  final String detail;
}

WorldErrorPresentation presentWorldError(WorldEngineException error) {
  final summary = switch (error.category) {
    WorldEngineErrorCategory.directorError => '世界没有成功理解这次行动。',
    WorldEngineErrorCategory.characterGenerationError => '角色的回应没有成功完成。',
    WorldEngineErrorCategory.narrationError => '这次世界叙述没有成功完成。',
    WorldEngineErrorCategory.transportInterrupted => 'AI 连接中断了。',
    WorldEngineErrorCategory.mutationParseError ||
    WorldEngineErrorCategory.mutationValidationError ||
    WorldEngineErrorCategory.mutationSaveError => '世界变化没有成功保存。',
    WorldEngineErrorCategory.providerError => 'AI 暂时无法回应这个世界。',
    WorldEngineErrorCategory.cancelled => '世界回应已停止。',
    WorldEngineErrorCategory.busy => '这个世界正在回应上一条行动。',
    _ => '世界回应没有成功完成。',
  };
  return WorldErrorPresentation(
    summary: summary,
    actionLabel: error.category == WorldEngineErrorCategory.cancelled
        ? '知道了'
        : '重试',
    detail: [
      'Category: ${error.category.name}',
      error.message,
      if (error.detail?.trim().isNotEmpty == true) error.detail!.trim(),
    ].join('\n'),
  );
}

String _mutationLabel(WorldMutationOperation operation) {
  return switch (operation.type) {
    WorldMutationType.sceneUpdate => '当前场景发生变化',
    WorldMutationType.stateSet => '世界状态已更新',
    WorldMutationType.stateRemove => '一项世界状态已结束',
    WorldMutationType.characterUpdate => '角色状态发生变化',
    WorldMutationType.playerUpdate => '你的世界状态发生变化',
    WorldMutationType.sceneCastAdd => '有角色进入当前场景',
    WorldMutationType.sceneCastRemove => '有角色离开当前场景',
    WorldMutationType.relationshipUpsert => '人物关系发生变化',
    WorldMutationType.worldTimeUpdate => _worldTimeLabel(operation.values),
  };
}

String _worldTimeLabel(Map<String, Object?> values) {
  final value = values['worldTime'] ?? values['timeText'] ?? values['value'];
  return value is String && value.trim().isNotEmpty
      ? '时间推进至 ${value.trim()}'
      : '世界时间发生变化';
}

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().where((item) => item.isNotEmpty).toList()
    : const [];

int _int(Object? value) => value is num ? value.toInt() : 0;

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
