import 'dart:convert';
import '../../domain/plugins/novel_history_fingerprint.dart';
import '../../domain/plugins/novel_plugin_storage_keys.dart';
import '../../domain/backup/backup_models.dart';
import 'package:sqflite/sqflite.dart';

void rewriteNovelPluginState(
  Map<String, Object?> row,
  Map<String, Map<String, String>> mappings,
) {
  final key = row['storage_key'] as String;
  final owner = novelPluginStorageOwner(key);
  if (owner != row['project_id']) {
    throw const BackupException(
      'invalid_novel_plugin_scope',
      '小说插件数据与作品作用域不一致。',
    );
  }
  final value = jsonDecode(row['value_json'] as String);
  final mappedOwner = owner == null
      ? null
      : mappings['projects']?[owner] ?? owner;
  if (owner != null && key == novelPluginSettingsKey(owner)) {
    row['storage_key'] = novelPluginSettingsKey(mappedOwner!);
    if (value is! Map) {
      throw const BackupException('invalid_novel_plugin_state', '小说插件设置无效。');
    }
    value['allowEnd'] =
        false; // Restoring data does not grant new session-control authority.
  } else if (owner != null && key.startsWith(novelPluginPrivatePrefix(owner))) {
    final name = key.substring(novelPluginPrivatePrefix(owner).length);
    row['storage_key'] = '${novelPluginPrivatePrefix(mappedOwner!)}$name';
    if (name == 'memory' && value is Map && value['blocks'] is List) {
      for (final raw in value['blocks'] as List) {
        if (raw is! Map) continue;
        final refs = (raw['sourceRefs'] as List? ?? const [])
            .map((e) => Map<String, String>.from(e as Map))
            .toList();
        final valid =
            refs.isNotEmpty &&
            novelRefsFingerprint(refs) == raw['sourceFingerprint'];
        final rewritten = [
          for (final ref in refs)
            {
              'id': mappings['segments']?[ref['id']] ?? ref['id']!,
              'candidateId':
                  mappings['novelPluginCandidates']?[ref['candidateId']] ??
                  ref['candidateId']!,
              'contentHash': ref['contentHash']!,
            },
        ];
        raw['sourceRefs'] = rewritten;
        raw['coveredMessageIds'] = [
          for (final id in raw['coveredMessageIds'] as List? ?? const [])
            mappings['segments']?[id] ?? id,
        ];
        if (valid) raw['sourceFingerprint'] = novelRefsFingerprint(rewritten);
      }
    }
  }
  if (value is Map && value['settings'] is Map) {
    final settings = value['settings'] as Map;
    if (settings['worldBookIds'] is List) {
      settings['worldBookIds'] = [
        for (final id in settings['worldBookIds'] as List)
          mappings['worldBooks']?[id] ?? id,
      ];
    }
  }
  row['value_json'] = jsonEncode(value);
}

Future<void> validateNovelPluginGraph(DatabaseExecutor db) async {
  final rows = await db.query('novel_story_branches');
  final branches = {for (final r in rows) r['id'] as String: r};
  for (final row in rows) {
    final id = row['id'] as String;
    final story = row['story_id'];
    final parent = row['parent_id'];
    if (!branches.containsKey(story) ||
        (parent == null
            ? id != story
            : branches[parent]?['story_id'] != story)) {
      throw const BackupException('invalid_novel_branch', '小说故事线归属无效。');
    }
    final seen = <String>{};
    String? cursor = id;
    while (cursor != null) {
      if (!seen.add(cursor) || seen.length > 10000) {
        throw const BackupException('invalid_novel_branch', '小说故事线继承存在环。');
      }
      cursor = branches[cursor]?['parent_id'] as String?;
    }
  }
  final invalid = await db.rawQuery(
    '''SELECT c.id FROM novel_plugin_candidates c JOIN segments s ON s.id=c.segment_id WHERE c.project_id!=s.project_id
    UNION ALL SELECT p.id FROM novel_plugin_selections p JOIN novel_plugin_candidates c ON c.id=p.candidate_id WHERE p.id!=c.segment_id
    UNION ALL SELECT a.id FROM novel_active_branches a JOIN novel_story_branches b ON b.id=a.branch_id WHERE a.id!=b.story_id
    UNION ALL SELECT c.id FROM novel_plugin_candidates c JOIN novel_plugin_candidates o ON o.id=c.source_candidate_id JOIN novel_story_branches b ON b.id=c.project_id JOIN novel_story_branches p ON p.id=o.project_id WHERE b.story_id!=p.story_id OR o.source_candidate_id IS NOT NULL''',
  );
  if (invalid.isNotEmpty) {
    throw const BackupException('invalid_novel_history', '小说历史或候选跨越了所属故事。');
  }
}
