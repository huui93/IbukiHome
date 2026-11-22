import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../application/common/entity_id_generator.dart';
import '../../core/errors/data_exceptions.dart';
import '../../domain/plugins/novel_plugin_models.dart';
import '../../domain/plugins/novel_plugin_storage_keys.dart';
import '../../domain/plugins/novel_history_fingerprint.dart';
export '../../domain/plugins/novel_history_fingerprint.dart'
    show novelContentHash;
import '../../domain/projects/novel_story_branch.dart';
import '../../domain/segments/segment.dart';
import '../repositories/novel_plugin_repository.dart';
import 'ibuki_database.dart';
import 'sqlite_value_codec.dart';

class SQLiteNovelPluginRepository implements NovelPluginRepository {
  SQLiteNovelPluginRepository(this.database, {EntityIdGenerator? ids})
    : ids = ids ?? EntityIdGenerator();
  final IbukiDatabase database;
  final EntityIdGenerator ids;
  Future<Map<String, Object?>> _project(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'projects',
      where: 'id=? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (rows.isEmpty) throw const DataConflictException('作品不存在或已删除。');
    return rows.single;
  }

  NovelStoryBranch _decode(Map<String, Object?> row) => NovelStoryBranch(
    projectId: row['id'] as String,
    storyId: row['story_id'] as String,
    parentId: row['parent_id'] as String?,
    label: row['label'] as String,
    inheritSettings: row['inherit_settings'] == 1,
    revision: row['revision'] as int,
    endedByPlugin: row['ended_by_plugin'] as String?,
    endedSourceSegmentId: row['ended_source_segment_id'] as String?,
    endedSourceHash: row['ended_source_hash'] as String?,
    endedReason: row['ended_reason'] as String?,
  );
  Future<NovelStoryBranch> _branch(
    DatabaseExecutor db,
    String projectId,
  ) async {
    await _project(db, projectId);
    var rows = await db.query(
      'novel_story_branches',
      where: 'id=?',
      whereArgs: [projectId],
    );
    if (rows.isEmpty) {
      await db.insert('novel_story_branches', {
        'id': projectId,
        'story_id': projectId,
        'label': '主线',
        'inherit_settings': 1,
        'revision': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await db.insert('novel_active_branches', {
        'id': projectId,
        'branch_id': projectId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      rows = await db.query(
        'novel_story_branches',
        where: 'id=?',
        whereArgs: [projectId],
      );
    }
    return _decode(rows.single);
  }

  @override
  Future<NovelStoryBranch> branch(String projectId) async =>
      (await database.database).transaction((db) => _branch(db, projectId));
  @override
  Future<List<NovelStoryBranch>> branches(String storyId) async {
    final db = await database.database;
    final root = await branch(storyId);
    final rows = await db.rawQuery(
      'SELECT b.* FROM novel_story_branches b JOIN projects p ON p.id=b.id WHERE b.story_id=? AND p.deleted_at IS NULL ORDER BY b.updated_at,b.id',
      [root.storyId],
    );
    return rows.map(_decode).toList();
  }

  @override
  Future<Set<String>> childProjectIds() async =>
      (await (await database.database).query(
        'novel_story_branches',
        columns: ['id'],
        where: 'id != story_id',
      )).map((r) => r['id'] as String).toSet();
  @override
  Future<String> activeProject(String storyId) async {
    final db = await database.database;
    final root = await branch(storyId);
    final rows = await db.rawQuery(
      'SELECT a.branch_id FROM novel_active_branches a JOIN projects p ON p.id=a.branch_id WHERE a.id=? AND p.deleted_at IS NULL',
      [root.storyId],
    );
    return rows.isEmpty ? root.storyId : rows.single['branch_id'] as String;
  }

  @override
  Future<void> selectBranch(String storyId, String projectId) async {
    final db = await database.database;
    await db.transaction((txn) async {
      final selected = await _branch(txn, projectId);
      if (selected.storyId != storyId) {
        throw const DataConflictException('故事线不属于当前作品。');
      }
      await txn.insert('novel_active_branches', {
        'id': storyId,
        'branch_id': projectId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Map<String, Object?>>> _segments(
    DatabaseExecutor db,
    String projectId,
  ) => db.query(
    'segments',
    where: 'project_id=? AND deleted_at IS NULL',
    whereArgs: [projectId],
    orderBy: 'order_index,id',
  );
  String _candidateId(String segmentId, int revision, String content) =>
      'novel_candidate:$segmentId:$revision:${novelContentHash(content).substring(0, 12)}';
  Future<void> _sync(DatabaseExecutor db, String projectId) async {
    await _branch(db, projectId);
    for (final segment in await _segments(db, projectId)) {
      final id = segment['id'] as String;
      final content = segment['content'] as String;
      Future<String> ensureCandidate(
        int revision,
        String text,
        Object? stamp,
      ) async {
        final found = await db.query(
          'novel_plugin_candidates',
          columns: ['id'],
          where: 'segment_id=? AND source_revision=? AND content=?',
          whereArgs: [id, revision, text],
          limit: 1,
        );
        if (found.isNotEmpty) return found.single['id'] as String;
        final candidateId = _candidateId(id, revision, text);
        await db.insert('novel_plugin_candidates', {
          'id': candidateId,
          'project_id': projectId,
          'segment_id': id,
          'content': text,
          'source_revision': revision,
          'created_at': stamp,
        });
        return candidateId;
      }

      for (final version in await db.query(
        'segment_revisions',
        where: 'segment_id=? AND deleted_at IS NULL',
        whereArgs: [id],
        orderBy: 'revision_number',
      )) {
        await ensureCandidate(
          version['revision_number'] as int,
          version['content'] as String,
          version['created_at'],
        );
      }
      final selection = await db.rawQuery(
        'SELECT c.content FROM novel_plugin_selections s JOIN novel_plugin_candidates c ON c.id=s.candidate_id WHERE s.id=?',
        [id],
      );
      if (selection.isEmpty || selection.single['content'] != content) {
        final candidateId = await ensureCandidate(
          segment['revision'] as int,
          content,
          segment['updated_at'],
        );
        await db.insert('novel_plugin_selections', {
          'id': id,
          'candidate_id': candidateId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  Future<List<NovelHistoryMessage>> _history(
    DatabaseExecutor db,
    String projectId,
  ) async {
    await _sync(db, projectId);
    final result = <NovelHistoryMessage>[];
    for (final row in await _segments(db, projectId)) {
      final id = row['id'] as String;
      final origins = await db.query(
        'novel_segment_origins',
        where: 'id=?',
        whereArgs: [id],
      );
      final selected = (await db.query(
        'novel_plugin_selections',
        where: 'id=?',
        whereArgs: [id],
      )).single['candidate_id'];
      final choices = await db.query(
        'novel_plugin_candidates',
        where: 'segment_id=?',
        whereArgs: [id],
        orderBy: 'source_revision,id',
      );
      final active = choices.firstWhere((c) => c['id'] == selected);
      result.add(
        NovelHistoryMessage(
          id: origins.isEmpty
              ? id
              : origins.single['origin_segment_id'] as String,
          segmentId: id,
          candidateId:
              (active['source_candidate_id'] ?? active['id']) as String,
          content: row['content'] as String,
          revision: row['revision'] as int,
          createdAt: DateTime.parse(row['created_at'] as String),
          candidates: [
            for (final c in choices)
              {
                'id': c['source_candidate_id'] ?? c['id'],
                'content': c['content'],
                'revision': c['source_revision'],
                'selected': c['id'] == selected,
              },
          ],
        ),
      );
    }
    return result;
  }

  @override
  Future<List<NovelHistoryMessage>> history(String projectId) async =>
      (await database.database).transaction((txn) => _history(txn, projectId));
  @override
  Future<NovelStoryBranch> fork({
    required String projectId,
    required String newProjectId,
    required String label,
    String? atMessageId,
    String? expectedCandidateId,
    required DateTime now,
  }) async {
    final db = await database.database;
    return db.transaction((txn) async {
      final parent = await _branch(txn, projectId);
      final original = await _project(txn, projectId);
      final messages = await _history(txn, projectId);
      final index = atMessageId == null
          ? messages.length - 1
          : messages.indexWhere((m) => m.id == atMessageId);
      if (label.trim().isEmpty || (atMessageId != null && index < 0)) {
        throw const DataConflictException('故事线名称或分叉位置无效。');
      }
      if (expectedCandidateId != null &&
          (index < 0 || messages[index].candidateId != expectedCandidateId)) {
        throw const DataConflictException('选中的候选已变化，请重新选择分叉位置。');
      }
      final stamp = now.toUtc().toIso8601String();
      await txn.insert('projects', {
        ...original,
        'id': newProjectId,
        'created_at': stamp,
        'updated_at': stamp,
        'revision': 1,
        'deleted_at': null,
      });
      await txn.insert('novel_story_branches', {
        'id': newProjectId,
        'story_id': parent.storyId,
        'parent_id': projectId,
        'label': label.trim(),
        'inherit_settings': 1,
        'revision': 1,
        'updated_at': stamp,
      });
      for (final message in messages.take(index + 1)) {
        final source = (await txn.query(
          'segments',
          where: 'id=?',
          whereArgs: [message.segmentId],
        )).single;
        final clonedId = ids.nextId('novel_segment');
        await txn.insert('segments', {
          ...source,
          'id': clonedId,
          'project_id': newProjectId,
          'revision': 1,
          'created_at': stamp,
          'updated_at': stamp,
          'deleted_at': null,
        });
        await txn.insert('novel_segment_origins', {
          'id': clonedId,
          'origin_segment_id': message.id,
        });
        final sourceSelection = (await txn.query(
          'novel_plugin_selections',
          where: 'id=?',
          whereArgs: [message.segmentId],
        )).single['candidate_id'];
        final sourceCandidate = (await txn.query(
          'novel_plugin_candidates',
          where: 'id=?',
          whereArgs: [sourceSelection],
        )).single;
        final candidateId = ids.nextId('novel_candidate');
        await txn.insert('novel_plugin_candidates', {
          'id': candidateId,
          'project_id': newProjectId,
          'segment_id': clonedId,
          'source_candidate_id':
              sourceCandidate['source_candidate_id'] ?? sourceCandidate['id'],
          'content': message.content,
          'source_revision': 1,
          'created_at': stamp,
        });
        await txn.insert('novel_plugin_selections', {
          'id': clonedId,
          'candidate_id': candidateId,
        });
        final views = await txn.query(
          'novel_plugin_reply_views',
          where: 'id=?',
          whereArgs: [message.segmentId],
        );
        if (views.isNotEmpty) {
          await txn.insert('novel_plugin_reply_views', {
            ...views.single,
            'id': clonedId,
          });
        }
      }
      for (final table in [
        'character_cards',
        'world_cards',
        'outline_nodes',
        'novel_output_settings',
      ]) {
        for (final row in await txn.query(
          table,
          where: 'project_id=?',
          whereArgs: [projectId],
        )) {
          await txn.insert(table, {
            ...row,
            'id': ids.nextId('novel_copy'),
            'project_id': newProjectId,
            if (row.containsKey('revision')) 'revision': 1,
            if (row.containsKey('created_at')) 'created_at': stamp,
            if (row.containsKey('updated_at')) 'updated_at': stamp,
          });
        }
      }
      for (final table in ['plugin_storage', 'novel_plugin_state']) {
        final privateRows = await txn.query(
          table,
          where: 'substr(storage_key,1,?)=?',
          whereArgs: [
            novelPluginPrivatePrefix(projectId).length,
            novelPluginPrivatePrefix(projectId),
          ],
        );
        for (final row in privateRows) {
          await txn.insert(table, {
            ...row,
            if (table == 'novel_plugin_state') 'id': ids.nextId('novel_state'),
            if (table == 'novel_plugin_state') 'project_id': newProjectId,
            'storage_key':
                '${novelPluginPrivatePrefix(newProjectId)}${(row['storage_key'] as String).substring(novelPluginPrivatePrefix(projectId).length)}',
            'updated_at': stamp,
          });
        }
      }
      await txn.insert('novel_active_branches', {
        'id': parent.storyId,
        'branch_id': newProjectId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return _decode(
        (await txn.query(
          'novel_story_branches',
          where: 'id=?',
          whereArgs: [newProjectId],
        )).single,
      );
    });
  }

  @override
  Future<void> setInheritance(
    String projectId,
    bool inherit,
    int expectedRevision,
  ) async {
    final db = await database.database;
    await db.transaction((txn) async {
      await _project(txn, projectId);
      final count = await txn.update(
        'novel_story_branches',
        {
          'inherit_settings': inherit ? 1 : 0,
          'revision': expectedRevision + 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id=? AND revision=?',
        whereArgs: [projectId, expectedRevision],
      );
      if (count != 1) throw const DataConflictException('故事线设置已变化，请重新加载。');
    });
  }

  @override
  Future<Segment> selectCandidate({
    required String projectId,
    required String messageId,
    required String candidateId,
    required DateTime now,
  }) async {
    final db = await database.database;
    return db.transaction((txn) async {
      final branch = await _branch(txn, projectId);
      if (branch.ended) throw const DataConflictException('当前故事线已经结束。');
      final message = (await _history(
        txn,
        projectId,
      )).where((m) => m.id == messageId).firstOrNull;
      if (message == null) throw const DataConflictException('消息不属于当前故事线。');
      final choices = await txn.query(
        'novel_plugin_candidates',
        where: 'segment_id=? AND (id=? OR source_candidate_id=?)',
        whereArgs: [message.segmentId, candidateId, candidateId],
      );
      if (choices.isEmpty) throw const DataConflictException('候选不属于当前段落。');
      final currentRow = (await txn.query(
        'segments',
        where: 'id=?',
        whereArgs: [message.segmentId],
      )).single;
      final current = segmentFromSql(currentRow);
      final selected = choices.first;
      final stamp = now.toUtc().toIso8601String();
      if (current.content != selected['content']) {
        await txn.insert('segment_revisions', {
          'id': ids.nextId('revision'),
          'project_id': projectId,
          'segment_id': current.id,
          'revision_number': current.revision,
          'content': current.content,
          'note': '切换候选前归档',
          'user_instruction': '',
          'mode': 'candidate_switch',
          'created_at': stamp,
          'updated_at': stamp,
          'revision': 1,
        });
        await txn.update(
          'segments',
          {
            'content': selected['content'],
            'revision': current.revision + 1,
            'updated_at': stamp,
          },
          where: 'id=? AND revision=?',
          whereArgs: [current.id, current.revision],
        );
      }
      await txn.update(
        'novel_plugin_selections',
        {'candidate_id': selected['id']},
        where: 'id=?',
        whereArgs: [current.id],
      );
      return segmentFromSql(
        (await txn.query(
          'segments',
          where: 'id=?',
          whereArgs: [current.id],
        )).single,
      );
    });
  }

  @override
  Future<void> endBranch({
    required String projectId,
    required String pluginId,
    required String segmentId,
    required int revision,
    required String contentHash,
    required String reason,
  }) async {
    final db = await database.database;
    await db.transaction((txn) async {
      final state = await _branch(txn, projectId);
      if (state.ended) return;
      final messages = await _segments(txn, projectId);
      if (messages.isEmpty ||
          messages.last['id'] != segmentId ||
          messages.last['revision'] != revision ||
          novelContentHash(messages.last['content'] as String) != contentHash) {
        throw const DataConflictException('结束请求不再对应当前最新回复。');
      }
      await txn.update(
        'novel_story_branches',
        {
          'ended_by_plugin': pluginId,
          'ended_source_segment_id': segmentId,
          'ended_source_hash': contentHash,
          'ended_reason': reason,
          'revision': state.revision + 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [projectId],
      );
    });
  }

  @override
  Future<void> saveReplyView(
    String segmentId,
    String contentHash,
    Map<String, Object?> data,
  ) async {
    final db = await database.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'segments',
        where: 'id=? AND deleted_at IS NULL',
        whereArgs: [segmentId],
      );
      if (rows.isEmpty ||
          novelContentHash(rows.single['content'] as String) != contentHash) {
        throw const DataConflictException('展示记录对应的正文已经变化。');
      }
      await txn.insert('novel_plugin_reply_views', {
        'id': segmentId,
        'content_hash': contentHash,
        'data_json': jsonEncode(data),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<Map<String, Object?>?> replyView(
    String segmentId,
    String contentHash,
  ) async {
    final rows = await (await database.database).query(
      'novel_plugin_reply_views',
      where: 'id=? AND content_hash=?',
      whereArgs: [segmentId, contentHash],
    );
    return rows.isEmpty
        ? null
        : Map<String, Object?>.from(
            jsonDecode(rows.single['data_json'] as String) as Map,
          );
  }

  @override
  Future<void> deleteStory(String projectId, DateTime now) async {
    final db = await database.database;
    await db.transaction((txn) async {
      final current = await _branch(txn, projectId);
      final rows = await txn.query(
        'novel_story_branches',
        columns: ['id'],
        where: 'story_id=?',
        whereArgs: [current.storyId],
      );
      for (final row in rows) {
        await txn.rawUpdate(
          'UPDATE projects SET deleted_at=?,updated_at=?,revision=revision+1 WHERE id=? AND deleted_at IS NULL',
          [
            now.toUtc().toIso8601String(),
            now.toUtc().toIso8601String(),
            row['id'],
          ],
        );
      }
    });
  }
}
