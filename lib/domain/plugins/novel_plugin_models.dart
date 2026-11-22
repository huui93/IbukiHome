import '../ai/ai_reasoning_level.dart';

enum NovelGenerationMode {
  normal('normal', '普通生成'),
  regenerate('regenerate', '重新生成'),
  continueReply('continue', '续写'),
  candidateSwitch('swipe', '切换候选'),
  impersonate('impersonate', '代写作者输入'),
  group('group', '指定角色发言'),
  empty('empty', '空发推进'),
  background('background', '后台任务');

  const NovelGenerationMode(this.key, this.label);
  final String key;
  final String label;
  static NovelGenerationMode parse(String key) =>
      values.firstWhere((m) => m.key == key);
}

enum NovelPromptRole { system, user, assistant }

enum NovelPromptPosition { beforeHistory, inHistory, afterHistory }

enum NovelRenderSlot {
  timeBar,
  dialogue,
  secondSpace,
  interaction,
  backstage,
  templateReasoning,
  nativeReasoning,
}

class NovelPromptEntry {
  const NovelPromptEntry({
    required this.id,
    required this.name,
    required this.enabled,
    this.role = NovelPromptRole.system,
    this.position = NovelPromptPosition.beforeHistory,
    this.order = 0,
    this.depth = 0,
    this.modes = const [],
    this.text = '',
    this.resource,
    this.placeholder,
    this.exclusiveGroup,
  });
  final String id;
  final String name;
  final bool enabled;
  final NovelPromptRole role;
  final NovelPromptPosition position;
  final int order;
  final int depth;
  final List<String> modes;
  final String text;
  final String? resource;
  final String? placeholder;
  final String? exclusiveGroup;

  factory NovelPromptEntry.fromJson(Map<String, Object?> j) {
    final id = j['id'];
    if (id is! String || !RegExp(r'^[a-zA-Z0-9._-]{1,150}$').hasMatch(id)) {
      throw const FormatException('提示词条目 ID 无效。');
    }
    final resource = j['resource'] as String?;
    if (resource != null &&
        (!RegExp(r'^[a-zA-Z0-9_./-]+$').hasMatch(resource) ||
            resource.startsWith('/') ||
            resource
                .split('/')
                .any((p) => p.isEmpty || p == '.' || p == '..'))) {
      throw const FormatException('提示词资源路径无效。');
    }
    final depth = j['depth'] as int? ?? 0;
    if (depth < 0 || depth > 100000) throw const FormatException('历史深度无效。');
    return NovelPromptEntry(
      id: id,
      name: j['name'] as String? ?? id,
      enabled: j['enabled'] as bool? ?? true,
      role: NovelPromptRole.values.byName(j['role'] as String? ?? 'system'),
      position: NovelPromptPosition.values.byName(
        j['position'] as String? ?? 'beforeHistory',
      ),
      order: j['order'] as int? ?? 0,
      depth: depth,
      modes: (j['modes'] as List? ?? const []).cast<String>(),
      text: j['text'] as String? ?? '',
      resource: resource,
      placeholder: j['placeholder'] as String?,
      exclusiveGroup: j['exclusiveGroup'] as String?,
    );
  }
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'enabled': enabled,
    'role': role.name,
    'position': position.name,
    'order': order,
    'depth': depth,
    'modes': modes,
    if (text.isNotEmpty) 'text': text,
    if (resource != null) 'resource': resource,
    if (placeholder != null) 'placeholder': placeholder,
    if (exclusiveGroup != null) 'exclusiveGroup': exclusiveGroup,
  };
}

class NovelPluginPreset {
  const NovelPluginPreset({
    required this.id,
    required this.entries,
    this.groups = const {},
    this.request = const {},
    this.schemes = const {},
    this.templates = const {},
    this.renderers = const [],
  });
  final String id;
  final List<NovelPromptEntry> entries;
  final Map<String, List<String>> groups;
  final Map<String, Object?> request;
  final Map<String, Map<String, Object?>> schemes;
  final Map<String, String> templates;
  final List<Map<String, Object?>> renderers;

  factory NovelPluginPreset.fromJson(Map<String, Object?> j) {
    final entries = (j['entries'] as List)
        .map(
          (e) => NovelPromptEntry.fromJson(Map<String, Object?>.from(e as Map)),
        )
        .toList();
    if (entries.length > 512 ||
        entries.map((e) => e.id).toSet().length != entries.length) {
      throw const FormatException('提示词条目过多或 ID 重复。');
    }
    final groups = <String, List<String>>{
      for (final e in (j['groups'] as Map? ?? const {}).entries)
        e.key as String: (e.value as List).cast<String>(),
    };
    for (final ids in groups.values) {
      if (ids.any((id) => !entries.any((e) => e.id == id))) {
        throw const FormatException('互斥组引用了不存在的条目。');
      }
    }
    return NovelPluginPreset(
      id: j['id'] as String,
      entries: List.unmodifiable(entries),
      groups: groups,
      request: Map<String, Object?>.from(j['request'] as Map? ?? const {}),
      schemes: {
        for (final e in (j['schemes'] as Map? ?? const {}).entries)
          e.key as String: Map<String, Object?>.from(e.value as Map),
      },
      templates: Map<String, String>.from(j['templates'] as Map? ?? const {}),
      renderers: (j['renderers'] as List? ?? const [])
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList(),
    );
  }
}

class NovelHistoryMessage {
  const NovelHistoryMessage({
    required this.id,
    required this.segmentId,
    required this.candidateId,
    required this.content,
    required this.revision,
    required this.createdAt,
    this.role = NovelPromptRole.assistant,
    this.candidates = const [],
  });
  final String id;
  final String segmentId;
  final String candidateId;
  final String content;
  final int revision;
  final DateTime createdAt;
  final NovelPromptRole role;
  final List<Map<String, Object?>> candidates;
  Map<String, Object?> toJson() => {
    'id': id,
    'segmentId': segmentId,
    'selectedCandidateId': candidateId,
    'content': content,
    'revision': revision,
    'role': role.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'candidates': candidates,
  };
}

class NovelMemoryBlock {
  const NovelMemoryBlock({
    required this.id,
    required this.content,
    this.kind = 'summary',
    this.position = NovelPromptPosition.afterHistory,
    this.depth = 0,
    this.order = 0,
    this.scanForWorldInfo = false,
    this.coveredMessageIds = const [],
    this.sourceFingerprint = '',
    this.sourceRefs = const [],
  });
  final String id;
  final String kind;
  final String content;
  final NovelPromptPosition position;
  final int depth;
  final int order;
  final bool scanForWorldInfo;
  final List<String> coveredMessageIds;
  final String sourceFingerprint;
  final List<Map<String, String>> sourceRefs;
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'content': content,
    'position': position.name,
    'depth': depth,
    'order': order,
    'scanForWorldInfo': scanForWorldInfo,
    'coveredMessageIds': coveredMessageIds,
    'sourceFingerprint': sourceFingerprint,
    'sourceRefs': sourceRefs,
  };
  factory NovelMemoryBlock.fromJson(Map<String, Object?> j) => NovelMemoryBlock(
    id: j['id'] as String,
    content: j['content'] as String,
    kind: j['kind'] as String? ?? 'summary',
    position: NovelPromptPosition.values.byName(
      j['position'] as String? ?? 'afterHistory',
    ),
    depth: j['depth'] as int? ?? 0,
    order: j['order'] as int? ?? 0,
    scanForWorldInfo: j['scanForWorldInfo'] as bool? ?? false,
    coveredMessageIds: (j['coveredMessageIds'] as List? ?? const [])
        .cast<String>(),
    sourceFingerprint: j['sourceFingerprint'] as String? ?? '',
    sourceRefs: (j['sourceRefs'] as List? ?? const [])
        .map((e) => Map<String, String>.from(e as Map))
        .toList(),
  );
}

class NovelRequestAdvice {
  const NovelRequestAdvice({
    this.temperature,
    this.contextTokens,
    this.outputTokens,
    this.stream,
    this.reasoning,
  });
  final double? temperature;
  final int? contextTokens;
  final int? outputTokens;
  final bool? stream;
  final AiReasoningLevel? reasoning;
  factory NovelRequestAdvice.fromJson(Map<String, Object?> j) =>
      NovelRequestAdvice(
        temperature: (j['temperature'] as num?)?.toDouble(),
        contextTokens: j['contextTokens'] as int?,
        outputTokens: j['outputTokens'] as int?,
        stream: j['stream'] as bool?,
        reasoning: j['reasoning'] == null
            ? null
            : AiReasoningLevel.values.byName(j['reasoning'] as String),
      );
  Map<String, Object?> toJson() => {
    if (temperature != null) 'temperature': temperature,
    if (contextTokens != null) 'contextTokens': contextTokens,
    if (outputTokens != null) 'outputTokens': outputTokens,
    if (stream != null) 'stream': stream,
    if (reasoning != null) 'reasoning': reasoning!.name,
  };
}
