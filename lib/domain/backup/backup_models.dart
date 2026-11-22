import 'dart:convert';

const ibukiBackupFormat = 'ibuki-home-backup';
const ibukiBackupVersion = 1;

enum BackupRestoreMode { fresh, merge }

class BackupException implements Exception {
  const BackupException(this.code, this.message, {this.detail});

  final String code;
  final String message;
  final String? detail;

  @override
  String toString() => 'BackupException($code, $message)';
}

class BackupCollectionManifest {
  const BackupCollectionManifest({
    required this.name,
    required this.rowCount,
    required this.files,
  });

  final String name;
  final int rowCount;
  final List<String> files;

  Map<String, Object?> toJson() => {
    'name': name,
    'rowCount': rowCount,
    'files': files,
  };

  factory BackupCollectionManifest.fromJson(Map<String, Object?> json) {
    return BackupCollectionManifest(
      name: json['name'] as String? ?? '',
      rowCount: json['rowCount'] as int? ?? 0,
      files: (json['files'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

class BackupAssetManifest {
  const BackupAssetManifest({
    required this.id,
    required this.archivePath,
    required this.fileName,
    required this.bytes,
    required this.sha256,
  });

  final String id;
  final String archivePath;
  final String fileName;
  final int bytes;
  final String sha256;

  Map<String, Object?> toJson() => {
    'id': id,
    'archivePath': archivePath,
    'fileName': fileName,
    'bytes': bytes,
    'sha256': sha256,
  };

  factory BackupAssetManifest.fromJson(Map<String, Object?> json) {
    return BackupAssetManifest(
      id: json['id'] as String? ?? '',
      archivePath: json['archivePath'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      bytes: json['bytes'] as int? ?? 0,
      sha256: json['sha256'] as String? ?? '',
    );
  }
}

class IbukiBackupManifest {
  const IbukiBackupManifest({
    required this.createdAt,
    required this.appVersion,
    required this.schemaVersion,
    required this.collections,
    required this.assets,
    required this.security,
  });

  final DateTime createdAt;
  final String appVersion;
  final int schemaVersion;
  final List<BackupCollectionManifest> collections;
  final List<BackupAssetManifest> assets;
  final Map<String, Object?> security;

  Map<String, Object?> toJson() => {
    'archiveFormat': ibukiBackupFormat,
    'archiveVersion': ibukiBackupVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'sourceAppVersion': appVersion,
    'sourceSchemaVersion': schemaVersion,
    'sourcePlatform': 'android',
    'entityCounts': {for (final item in collections) item.name: item.rowCount},
    'modeCounts': {
      'novel': _count(const [
        'projects',
        'novelPromptPresets',
        'novelOutputSettings',
        'novelStoryBranches',
        'novelActiveBranches',
        'novelSegmentOrigins',
        'novelPluginCandidates',
        'novelPluginSelections',
        'novelPluginReplyViews',
        'novelPluginState',
        'outlineNodes',
        'segments',
        'segmentRevisions',
        'novelSummaryChunks',
        'storyMemoryDigests',
        'readerPreferences',
        'readerProgress',
      ]),
      'chat': _count(const [
        'chatPersonas',
        'chatSessions',
        'chatSessionControls',
        'chatMessages',
        'chatUsageRecords',
        'chatMemoryEntries',
        'conversationSummaries',
        'chatMemoryStates',
        'chatMemoryUsage',
      ]),
      'world': _count(const [
        'worlds',
        'worldSessions',
        'worldBooks',
        'loreEntries',
        'worldFeed',
        'worldTurns',
      ]),
    },
    'assetCounts': {
      'files': assets.length,
      'bytes': assets.fold<int>(0, (sum, item) => sum + item.bytes),
    },
    'checksumAlgorithm': 'SHA-256',
    'featureFlags': const [
      'logical-jsonl',
      'shared-assets',
      'id-mapping',
      'credential-exclusion',
    ],
    'containsCredentials': false,
    'containsSecureStorage': false,
    'collections': collections.map((item) => item.toJson()).toList(),
    'assets': assets.map((item) => item.toJson()).toList(),
    'security': security,
  };

  int _count(List<String> names) => collections
      .where((item) => names.contains(item.name))
      .fold<int>(0, (sum, item) => sum + item.rowCount);

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory IbukiBackupManifest.parse(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, Object?>) {
      throw const BackupException('invalid_manifest', '备份清单格式无效。');
    }
    if (value['archiveFormat'] != ibukiBackupFormat) {
      throw const BackupException('invalid_format', '这不是伊吹之家的完整备份。');
    }
    final version = value['archiveVersion'];
    if (version is! int || version < 1) {
      throw const BackupException('invalid_version', '备份版本无效。');
    }
    if (version > ibukiBackupVersion) {
      throw const BackupException('future_version', '这个备份由更新版本创建，当前版本暂时无法恢复。');
    }
    return IbukiBackupManifest(
      createdAt:
          DateTime.tryParse(value['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      appVersion:
          value['sourceAppVersion'] as String? ??
          value['appVersion'] as String? ??
          'unknown',
      schemaVersion:
          value['sourceSchemaVersion'] as int? ??
          value['schemaVersion'] as int? ??
          0,
      collections: (value['collections'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(BackupCollectionManifest.fromJson)
          .toList(growable: false),
      assets: (value['assets'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(BackupAssetManifest.fromJson)
          .toList(growable: false),
      security: value['security'] is Map<String, Object?>
          ? value['security'] as Map<String, Object?>
          : const {},
    );
  }
}

class BackupSnapshot {
  const BackupSnapshot({required this.collections});
  final Map<String, List<Map<String, Object?>>> collections;
}

class PreparedBackup {
  const PreparedBackup({required this.snapshot, required this.preview});
  final BackupSnapshot snapshot;
  final BackupPreview preview;
}

class BackupCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) {
      throw const BackupException('cancelled', '操作已取消。');
    }
  }
}

class BackupPreview {
  const BackupPreview({required this.manifest, required this.checksum});
  final IbukiBackupManifest manifest;
  final String checksum;

  int get totalRows =>
      manifest.collections.fold(0, (sum, item) => sum + item.rowCount);
  int get totalAssets => manifest.assets.length;
}

class RestorePlan {
  const RestorePlan({required this.preview, required this.mode});
  final BackupPreview preview;
  final BackupRestoreMode mode;
}

class BackupProgress {
  const BackupProgress(this.stage, this.completed, this.total);
  final String stage;
  final int completed;
  final int total;
}
