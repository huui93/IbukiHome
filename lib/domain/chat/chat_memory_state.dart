import '../common/entity_metadata.dart';

/// All personal memory belongs to one conversation, never to a persona.
class ChatMemoryState {
  const ChatMemoryState({
    required this.metadata,
    required this.sessionId,
    this.savedEnabled = true,
    bool historyEnabled = true,
    this.autoSave = true,
    this.compressionRounds = defaultCompressionRounds,
    this.paused = false,
    this.overview = '',
    this.overviewEdited = false,
    this.cursor,
    this.processedFingerprint = '',
    this.blockedPhrases = const [],
    this.excludedSources = const [],
  }) : historyEnabled = savedEnabled && historyEnabled;

  final EntityMetadata metadata;
  final String sessionId;
  final bool savedEnabled;
  final bool historyEnabled;
  final bool autoSave;
  final int compressionRounds;
  static const defaultCompressionRounds = 50;
  static const maximumCompressionRounds = 1000;
  final bool paused;
  final String overview;
  final bool overviewEdited;
  final String? cursor;
  final String processedFingerprint;
  final List<String> blockedPhrases;
  final List<String> excludedSources;
  bool get canRead => savedEnabled && !paused;
  bool get canOrganize => canRead && (autoSave || historyEnabled);

  ChatMemoryState copyWith({
    EntityMetadata? metadata,
    bool? savedEnabled,
    bool? historyEnabled,
    bool? autoSave,
    int? compressionRounds,
    bool? paused,
    String? overview,
    bool? overviewEdited,
    String? cursor,
    String? processedFingerprint,
    List<String>? blockedPhrases,
    List<String>? excludedSources,
  }) {
    final saved = savedEnabled ?? this.savedEnabled;
    return ChatMemoryState(
      metadata: metadata ?? this.metadata,
      sessionId: sessionId,
      savedEnabled: saved,
      historyEnabled: saved && (historyEnabled ?? this.historyEnabled),
      autoSave: autoSave ?? this.autoSave,
      compressionRounds: compressionRounds ?? this.compressionRounds,
      paused: paused ?? this.paused,
      overview: overview ?? this.overview,
      overviewEdited: overviewEdited ?? this.overviewEdited,
      cursor: cursor ?? this.cursor,
      processedFingerprint: processedFingerprint ?? this.processedFingerprint,
      blockedPhrases: List.unmodifiable(blockedPhrases ?? this.blockedPhrases),
      excludedSources: List.unmodifiable(
        excludedSources ?? this.excludedSources,
      ),
    );
  }

  Map<String, Object?> toData() => {
    'savedEnabled': savedEnabled,
    'historyEnabled': historyEnabled,
    'autoSave': autoSave,
    'compressionRounds': compressionRounds,
    'paused': paused,
    'overview': overview,
    'overviewEdited': overviewEdited,
    'cursor': cursor,
    'processedFingerprint': processedFingerprint,
    'blockedPhrases': blockedPhrases,
    'excludedSources': excludedSources,
  };

  factory ChatMemoryState.fromData({
    required EntityMetadata metadata,
    required String sessionId,
    required Map<String, dynamic> data,
  }) {
    const name = 'ChatMemoryState';
    List<String> strings(String key) {
      final raw = data[key] ?? const <String>[];
      if (raw is! List || raw.any((item) => item is! String)) {
        throw FormatException('Invalid $name.$key');
      }
      return List<String>.unmodifiable(raw);
    }

    final saved = readOptionalBool(
      data,
      'savedEnabled',
      name,
      defaultValue: true,
    );
    final rounds = data['compressionRounds'] ?? defaultCompressionRounds;
    if (rounds is! int || rounds < 1 || rounds > maximumCompressionRounds) {
      throw const FormatException('Invalid ChatMemoryState.compressionRounds');
    }
    return ChatMemoryState(
      metadata: metadata,
      sessionId: sessionId,
      savedEnabled: saved,
      historyEnabled:
          saved &&
          readOptionalBool(data, 'historyEnabled', name, defaultValue: true),
      autoSave: readOptionalBool(data, 'autoSave', name, defaultValue: true),
      compressionRounds: rounds,
      paused: readOptionalBool(data, 'paused', name),
      overview: readOptionalString(data, 'overview', name),
      overviewEdited: readOptionalBool(data, 'overviewEdited', name),
      cursor: readOptionalNullableString(data, 'cursor', name),
      processedFingerprint: readOptionalString(
        data,
        'processedFingerprint',
        name,
      ),
      blockedPhrases: strings('blockedPhrases'),
      excludedSources: strings('excludedSources'),
    );
  }
}

enum ChatMemorySourceKind { saved, summary, message, overview }

class ChatMemorySource {
  const ChatMemorySource({
    required this.kind,
    required this.id,
    required this.sessionId,
    required this.content,
    required this.updatedAt,
    this.score = 0,
    this.version = '',
  });
  final ChatMemorySourceKind kind;
  final String id;
  final String sessionId;
  final String content;
  final DateTime updatedAt;
  final double score;
  final String version;
  String get key => '${kind.name}:$id';
  String get label => switch (kind) {
    ChatMemorySourceKind.saved => '已保存记忆',
    ChatMemorySourceKind.summary => '对话摘要',
    ChatMemorySourceKind.message => '历史消息',
    ChatMemorySourceKind.overview => '记忆概览',
  };
}

class ChatMemoryUsage {
  const ChatMemoryUsage({
    required this.id,
    required this.sessionId,
    required this.messageId,
    required this.sourceKeys,
  });
  final String id;
  final String sessionId;
  final String messageId;
  final List<String> sourceKeys;
}
