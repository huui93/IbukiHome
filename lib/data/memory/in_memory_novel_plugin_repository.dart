import 'dart:convert';
import '../../application/common/entity_id_generator.dart';
import '../../core/errors/data_exceptions.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/plugins/novel_history_fingerprint.dart';
import '../../domain/plugins/novel_plugin_models.dart';
import '../../domain/plugins/novel_plugin_storage_keys.dart';
import '../../domain/projects/novel_output_limits.dart';
import '../../domain/projects/novel_story_branch.dart';
import '../../domain/segments/segment.dart';
import '../../domain/segments/segment_revision.dart';
import '../repositories/character_repository.dart';
import '../repositories/outline_repository.dart';
import '../repositories/project_repository.dart';
import '../repositories/segment_repository.dart';
import '../repositories/world_repository.dart';
import '../repositories/plugin_registry.dart';
import '../repositories/plugin_storage_repository.dart';
import '../repositories/novel_output_limits_repository.dart';
import '../repositories/novel_plugin_repository.dart';

class InMemoryNovelPluginRepository implements NovelPluginRepository {
  InMemoryNovelPluginRepository({
    required this.projects,
    required this.segments,
    required this.characters,
    required this.world,
    required this.outlines,
    required this.plugins,
    required this.storage,
    required this.outputLimits,
    EntityIdGenerator? ids,
  }) : ids = ids ?? EntityIdGenerator();
  final ProjectRepository projects;
  final SegmentRepository segments;
  final CharacterRepository characters;
  final WorldRepository world;
  final OutlineRepository outlines;
  final PluginRegistry plugins;
  final PluginStorageRepository storage;
  final NovelOutputLimitsRepository outputLimits;
  final EntityIdGenerator ids;
  final Map<String, NovelStoryBranch> _branches = {};
  final Map<String, String> _active = {};
  final Map<String, String> _origins = {};
  final Map<String, List<Map<String, Object?>>> _candidates = {};
  final Map<String, String> _selected = {};
  final Map<String, ({String hash, Map<String, Object?> data})> _views = {};
  @override
  Future<NovelStoryBranch> branch(String projectId) async {
    if ((await projects.getProject(projectId)).deletedAt != null) {
      throw const DataConflictException('作品已经删除。');
    }
    _active.putIfAbsent(projectId, () => projectId);
    return _branches.putIfAbsent(
      projectId,
      () => NovelStoryBranch(
        projectId: projectId,
        storyId: projectId,
        label: '主线',
      ),
    );
  }

  @override
  Future<List<NovelStoryBranch>> branches(String storyId) async {
    final root = await branch(storyId);
    final active = (await projects.listProjects()).map((p) => p.id).toSet();
    return _branches.values
        .where((b) => b.storyId == root.storyId && active.contains(b.projectId))
        .toList();
  }

  @override
  Future<Set<String>> childProjectIds() async => _branches.values
      .where((b) => b.parentId != null)
      .map((b) => b.projectId)
      .toSet();
  @override
  Future<String> activeProject(String storyId) async {
    final root = await branch(storyId);
    final id = _active[root.storyId] ?? root.storyId;
    return (await projects.getProject(id)).deletedAt == null
        ? id
        : root.storyId;
  }

  @override
  Future<void> selectBranch(String storyId, String projectId) async {
    if ((await branch(projectId)).storyId != storyId) {
      throw const DataConflictException('故事线不属于当前作品。');
    }
    _active[storyId] = projectId;
  }

  String _candidateId(String id, int revision, String content) =>
      'novel_candidate:$id:$revision:${novelContentHash(content).substring(0, 12)}';
  @override
  Future<List<NovelHistoryMessage>> history(String projectId) async {
    await branch(projectId);
    final result = <NovelHistoryMessage>[];
    for (final segment in await segments.listSegments(projectId)) {
      final choices = _candidates.putIfAbsent(segment.id, () => []);
      String add(int revision, String content) {
        final existing = choices
            .where((c) => c['revision'] == revision && c['content'] == content)
            .firstOrNull;
        if (existing != null) return existing['id'] as String;
        final id = _candidateId(segment.id, revision, content);
        choices.add({'id': id, 'content': content, 'revision': revision});
        return id;
      }

      for (final version in await segments.listRevisions(segment.id)) {
        if (version.deletedAt == null) {
          add(version.revisionNumber, version.content);
        }
      }
      final selected = choices
          .where((c) => c['id'] == _selected[segment.id])
          .firstOrNull;
      if (selected == null || selected['content'] != segment.content) {
        _selected[segment.id] = add(segment.revision, segment.content);
      }
      final choice = choices.firstWhere(
        (c) => c['id'] == _selected[segment.id],
      );
      result.add(
        NovelHistoryMessage(
          id: _origins[segment.id] ?? segment.id,
          segmentId: segment.id,
          candidateId: (choice['sourceCandidateId'] ?? choice['id']) as String,
          content: segment.content,
          revision: segment.revision,
          createdAt: segment.createdAt,
          candidates: [
            for (final c in choices)
              {
                'id': c['sourceCandidateId'] ?? c['id'],
                'content': c['content'],
                'revision': c['revision'],
                'selected': c['id'] == _selected[segment.id],
              },
          ],
        ),
      );
    }
    return result;
  }

  @override
  Future<NovelStoryBranch> fork({
    required String projectId,
    required String newProjectId,
    required String label,
    String? atMessageId,
    String? expectedCandidateId,
    required DateTime now,
  }) async {
    final parent = await branch(projectId);
    final original = await projects.getProject(projectId);
    if ((await projects.listProjects(
          includeDeleted: true,
        )).any((p) => p.id == newProjectId) ||
        label.trim().isEmpty) {
      throw const DataConflictException('故事线名称或 ID 无效。');
    }
    final messages = await history(projectId);
    final end = atMessageId == null
        ? messages.length - 1
        : messages.indexWhere((m) => m.id == atMessageId);
    if (atMessageId != null && end < 0) {
      throw const DataConflictException('分叉位置不属于当前故事线。');
    }
    if (expectedCandidateId != null &&
        (end < 0 || messages[end].candidateId != expectedCandidateId)) {
      throw const DataConflictException('选中的候选已变化，请重新选择分叉位置。');
    }
    final sourceSegments = {
      for (final segment in await segments.listSegments(projectId))
        segment.id: segment,
    };
    final chars = await characters.listCharacters(projectId);
    final worlds = await world.listWorldCards(projectId);
    final nodes = await outlines.listOutlineNodes(projectId);
    final limits = await outputLimits.get(projectId);
    final copies = <({String pluginId, String name, Object? value})>[];
    final prefix = novelPluginPrivatePrefix(projectId);
    for (final plugin in await plugins.listPlugins()) {
      for (final entry in (await storage.listValues(plugin.id)).entries) {
        if (entry.key.startsWith(prefix)) {
          copies.add((
            pluginId: plugin.id,
            name: entry.key.substring(prefix.length),
            value: jsonDecode(jsonEncode(entry.value)),
          ));
        }
      }
    }
    EntityMetadata meta(String id) => EntityMetadata(
      id: id,
      createdAt: now.toUtc(),
      updatedAt: now.toUtc(),
      revision: 1,
    );
    await projects.upsertProject(
      original.copyWith(metadata: meta(newProjectId)),
    );
    for (final message in messages.take(end + 1)) {
      final cloneId = ids.nextId('novel_segment');
      final source = sourceSegments[message.segmentId]!;
      await segments.upsertSegment(
        source.copyWith(metadata: meta(cloneId), projectId: newProjectId),
      );
      _origins[cloneId] = message.id;
      final candidateId = ids.nextId('novel_candidate');
      _candidates[cloneId] = [
        {
          'id': candidateId,
          'sourceCandidateId': message.candidateId,
          'content': message.content,
          'revision': 1,
        },
      ];
      _selected[cloneId] = candidateId;
      if (_views.containsKey(source.id)) {
        _views[cloneId] = (
          hash: _views[source.id]!.hash,
          data: Map<String, Object?>.from(
            jsonDecode(jsonEncode(_views[source.id]!.data)) as Map,
          ),
        );
      }
    }
    for (final character in chars) {
      await characters.upsertCharacter(
        character.copyWith(
          metadata: meta(ids.nextId('novel_copy')),
          projectId: newProjectId,
        ),
      );
    }
    for (final card in worlds) {
      await world.upsertWorldCard(
        card.copyWith(
          metadata: meta(ids.nextId('novel_copy')),
          projectId: newProjectId,
        ),
      );
    }
    for (final node in nodes) {
      await outlines.upsertOutlineNode(
        node.copyWith(
          metadata: meta(ids.nextId('novel_copy')),
          projectId: newProjectId,
        ),
      );
    }
    if (!limits.isDefault) {
      await outputLimits.save(
        NovelOutputLimits(
          projectId: newProjectId,
          minimum: limits.minimum,
          maximum: limits.maximum,
          temperature: limits.temperature,
        ),
        expectedRevision: 0,
        now: now,
      );
    }
    for (final copy in copies) {
      await storage.setValue(
        copy.pluginId,
        '${novelPluginPrivatePrefix(newProjectId)}${copy.name}',
        copy.value,
      );
    }
    final child = NovelStoryBranch(
      projectId: newProjectId,
      storyId: parent.storyId,
      parentId: projectId,
      label: label.trim(),
    );
    _branches[newProjectId] = child;
    _active[parent.storyId] = newProjectId;
    return child;
  }

  @override
  Future<void> setInheritance(
    String projectId,
    bool inherit,
    int expectedRevision,
  ) async {
    final current = await branch(projectId);
    if (current.revision != expectedRevision) {
      throw const DataConflictException('故事线设置已经变化。');
    }
    _branches[projectId] = NovelStoryBranch(
      projectId: current.projectId,
      storyId: current.storyId,
      parentId: current.parentId,
      label: current.label,
      inheritSettings: inherit,
      revision: current.revision + 1,
      endedByPlugin: current.endedByPlugin,
      endedSourceSegmentId: current.endedSourceSegmentId,
      endedSourceHash: current.endedSourceHash,
      endedReason: current.endedReason,
    );
  }

  @override
  Future<Segment> selectCandidate({
    required String projectId,
    required String messageId,
    required String candidateId,
    required DateTime now,
  }) async {
    if ((await branch(projectId)).ended) {
      throw const DataConflictException('当前故事线已经结束。');
    }
    final message = (await history(
      projectId,
    )).where((m) => m.id == messageId).firstOrNull;
    if (message == null) throw const DataConflictException('消息不属于当前故事线。');
    final selected = _candidates[message.segmentId]!
        .where(
          (c) =>
              c['id'] == candidateId || c['sourceCandidateId'] == candidateId,
        )
        .firstOrNull;
    if (selected == null) throw const DataConflictException('候选不属于当前消息。');
    var current = await segments.getSegment(message.segmentId);
    if (current.content != selected['content']) {
      final updated = current.copyWith(
        content: selected['content'] as String,
        metadata: current.metadata.copyWith(
          updatedAt: now.toUtc(),
          revision: current.revision + 1,
        ),
      );
      await segments.saveSegmentWithRevision(
        updatedSegment: updated,
        revision: SegmentRevision(
          metadata: EntityMetadata(
            id: ids.nextId('revision'),
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
            revision: 1,
          ),
          projectId: projectId,
          segmentId: current.id,
          revisionNumber: current.revision,
          content: current.content,
          note: '切换候选前归档',
          userInstruction: '',
          mode: 'candidate_switch',
        ),
      );
      current = updated;
    }
    _selected[current.id] = selected['id'] as String;
    return current;
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
    final current = await branch(projectId);
    if (current.ended) return;
    final messages = await history(projectId);
    if (messages.isEmpty ||
        messages.last.segmentId != segmentId ||
        messages.last.revision != revision ||
        novelContentHash(messages.last.content) != contentHash) {
      throw const DataConflictException('结束请求不再对应当前最新回复。');
    }
    _branches[projectId] = NovelStoryBranch(
      projectId: projectId,
      storyId: current.storyId,
      parentId: current.parentId,
      label: current.label,
      inheritSettings: current.inheritSettings,
      revision: current.revision + 1,
      endedByPlugin: pluginId,
      endedSourceSegmentId: segmentId,
      endedSourceHash: contentHash,
      endedReason: reason,
    );
  }

  @override
  Future<void> saveReplyView(
    String segmentId,
    String contentHash,
    Map<String, Object?> data,
  ) async {
    if (novelContentHash((await segments.getSegment(segmentId)).content) !=
        contentHash) {
      throw const DataConflictException('正文已变化。');
    }
    _views[segmentId] = (hash: contentHash, data: Map.unmodifiable(data));
  }

  @override
  Future<Map<String, Object?>?> replyView(
    String segmentId,
    String contentHash,
  ) async =>
      _views[segmentId]?.hash == contentHash ? _views[segmentId]!.data : null;
  @override
  Future<void> deleteStory(String projectId, DateTime now) async {
    for (final current in await branches((await branch(projectId)).storyId)) {
      await projects.softDeleteProject(current.projectId, now);
    }
  }
}
