// ignore_for_file: prefer_initializing_formals

import '../../core/errors/data_exceptions.dart';
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/outline_repository.dart';
import '../../data/repositories/novel_memory_repository.dart';
import '../../data/repositories/segment_repository.dart';
import '../../data/repositories/world_repository.dart';
import '../../domain/characters/character_card.dart';
import '../../domain/projects/project.dart';
import '../../domain/segments/segment.dart';
import '../../domain/world/world_card.dart';
import 'novel_outline_context.dart';
import '../memory/long_context_policy.dart';
import '../memory/novel_memory_context.dart';

class NovelAiContext {
  const NovelAiContext({
    required this.project,
    required this.segments,
    required this.characters,
    required this.worldCards,
    required this.outline,
    required this.memory,
  });

  final Project project;
  final List<Segment> segments;
  final List<CharacterCard> characters;
  final List<WorldCard> worldCards;
  final NovelOutlineContext outline;
  final NovelMemoryContext memory;
}

class NovelContextLoader {
  const NovelContextLoader({
    required ProjectRepository projects,
    required SegmentRepository segments,
    required CharacterRepository characters,
    required WorldRepository worlds,
    required OutlineRepository outlines,
    NovelMemoryRepository? memories,
  }) : _projects = projects,
       _segments = segments,
       _characters = characters,
       _worlds = worlds,
       _outlines = outlines,
       _memories = memories;

  final ProjectRepository _projects;
  final SegmentRepository _segments;
  final CharacterRepository _characters;
  final WorldRepository _worlds;
  final OutlineRepository _outlines;
  final NovelMemoryRepository? _memories;

  Future<NovelAiContext> load({
    required String projectId,
    required Set<String> selectedCharacterIds,
    required Set<String> selectedWorldCardIds,
  }) async {
    final project = await _projects.getProject(projectId);
    if (project.deletedAt != null) {
      throw const DataConflictException('已删除项目不能使用 AI 创作。');
    }
    final segments = await _segments.listSegments(projectId);
    final allCharacters = await _characters.listCharacters(projectId);
    final allWorldCards = await _worlds.listWorldCards(projectId);
    final outlineNodes = await _outlines.listOutlineNodes(projectId);
    final digest = await _memories?.getDigest(projectId);
    final allChunks = await _memories?.listChunks(projectId) ?? const [];
    final usableChunks = allChunks
        .where((item) => item.summary.trim().isNotEmpty)
        .toList(growable: false);
    final rawSegmentStartOrder = calculateNovelRawStartOrder(
      segmentCount: segments.length,
      summarizedChunks: usableChunks,
    );
    final chunkStart =
        usableChunks.length > NovelMemoryPolicy.recentSummaryChunkCount
        ? usableChunks.length - NovelMemoryPolicy.recentSummaryChunkCount
        : 0;
    final characters = _selectCharacters(allCharacters, selectedCharacterIds);
    final worldCards = _selectWorldCards(allWorldCards, selectedWorldCardIds);
    return NovelAiContext(
      project: project,
      segments: List.unmodifiable(segments),
      characters: List.unmodifiable(characters),
      worldCards: List.unmodifiable(worldCards),
      outline: NovelOutlineContext.select(outlineNodes),
      memory: NovelMemoryContext(
        digest: digest?.content.trim().isNotEmpty == true ? digest : null,
        recentChunks: List.unmodifiable(usableChunks.sublist(chunkStart)),
        rawSegmentStartOrder: rawSegmentStartOrder,
      ),
    );
  }

  List<CharacterCard> _selectCharacters(
    List<CharacterCard> all,
    Set<String> selectedIds,
  ) {
    if (selectedIds.isEmpty) {
      return all;
    }
    final selected = all
        .where((item) => selectedIds.contains(item.id))
        .toList(growable: false);
    if (selected.length != selectedIds.length) {
      throw const DataConflictException('所选角色不属于当前项目或已经删除。');
    }
    return selected;
  }

  List<WorldCard> _selectWorldCards(
    List<WorldCard> all,
    Set<String> selectedIds,
  ) {
    if (selectedIds.isEmpty) {
      return all;
    }
    final selected = all
        .where((item) => selectedIds.contains(item.id))
        .toList(growable: false);
    if (selected.length != selectedIds.length) {
      throw const DataConflictException('所选世界观不属于当前项目或已经删除。');
    }
    return selected;
  }
}
