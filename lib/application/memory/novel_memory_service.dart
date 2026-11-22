// ignore_for_file: prefer_initializing_formals

import '../../data/repositories/novel_memory_repository.dart';
import '../../data/repositories/segment_repository.dart';
import '../../domain/common/entity_metadata.dart';
import '../../domain/memory/memory_generation_status.dart';
import '../../domain/memory/novel_summary_chunk.dart';
import '../../domain/memory/story_memory_digest.dart';
import '../../domain/segments/segment.dart';
import '../ai/ai_generation_service.dart';
import '../ai/ai_model_resolver.dart';
import '../ai/clean_ai_text.dart';
import '../common/entity_id_generator.dart';
import 'long_context_policy.dart';
import 'novel_memory_context.dart';
import 'novel_summary_prompt_builder.dart';
import 'source_fingerprint.dart';

class NovelMemoryService {
  NovelMemoryService({
    required NovelMemoryRepository repository,
    required SegmentRepository segments,
    required AiGenerationRuntime runtime,
    required EntityIdGenerator ids,
    NovelSummaryPromptBuilder summaryPromptBuilder =
        const NovelSummaryPromptBuilder(),
    StoryDigestPromptBuilder digestPromptBuilder =
        const StoryDigestPromptBuilder(),
    AiModelResolver? modelResolver,
  }) : _repository = repository,
       _segments = segments,
       _runtime = runtime,
       _ids = ids,
       _summaryPromptBuilder = summaryPromptBuilder,
       _digestPromptBuilder = digestPromptBuilder,
       _modelResolver = modelResolver;

  final NovelMemoryRepository _repository;
  final SegmentRepository _segments;
  final AiGenerationRuntime _runtime;
  final EntityIdGenerator _ids;
  final NovelSummaryPromptBuilder _summaryPromptBuilder;
  final StoryDigestPromptBuilder _digestPromptBuilder;
  final AiModelResolver? _modelResolver;
  final Map<String, Future<void>> _jobs = {};

  bool isRunning(String projectId) => _jobs.containsKey(projectId);

  Future<void> refresh(String projectId) {
    final current = _jobs[projectId];
    if (current != null) return current;
    final job = _refresh(projectId).catchError((_) {
      // Background memory maintenance must never break writing or navigation.
    });
    _jobs[projectId] = job;
    return job.whenComplete(() {
      if (identical(_jobs[projectId], job)) _jobs.remove(projectId);
    });
  }

  Future<NovelMemoryContext> loadContext(String projectId) async {
    final digest = await _repository.getDigest(projectId);
    final chunks = await _repository.listChunks(projectId);
    final segments = await _segments.listSegments(projectId);
    final usable = chunks
        .where(
          (item) =>
              item.summary.trim().isNotEmpty &&
              item.status != MemoryGenerationStatus.generating,
        )
        .toList(growable: false);
    final start = usable.length > NovelMemoryPolicy.recentSummaryChunkCount
        ? usable.length - NovelMemoryPolicy.recentSummaryChunkCount
        : 0;
    return NovelMemoryContext(
      digest: digest?.content.trim().isNotEmpty == true ? digest : null,
      recentChunks: List.unmodifiable(usable.sublist(start)),
      rawSegmentStartOrder: calculateNovelRawStartOrder(
        segmentCount: segments.length,
        summarizedChunks: usable,
      ),
    );
  }

  Future<void> saveUserDigest({
    required String projectId,
    required String content,
    required bool pinned,
    required DateTime nowUtc,
  }) async {
    final now = nowUtc.toUtc();
    final current = await _repository.getDigest(projectId);
    await _repository.upsertDigest(
      StoryMemoryDigest(
        metadata:
            current?.metadata.copyWith(
              updatedAt: now,
              revision: current.revision + 1,
            ) ??
            EntityMetadata(
              id: _ids.nextId('story_memory'),
              createdAt: now,
              updatedAt: now,
              revision: 1,
            ),
        projectId: projectId,
        content: content.trim(),
        sourceThroughOrder: current?.sourceThroughOrder ?? -1,
        sourceFingerprint: current?.sourceFingerprint ?? '',
        status: MemoryGenerationStatus.valid,
        isUserEdited: true,
        isPinned: pinned,
        provider: current?.provider,
        model: current?.model,
      ),
    );
  }

  Future<void> restoreAutomaticDigest(String projectId, DateTime nowUtc) async {
    final current = await _repository.getDigest(projectId);
    if (current == null) return;
    await _repository.upsertDigest(
      current.copyWith(
        metadata: current.metadata.copyWith(
          updatedAt: nowUtc.toUtc(),
          revision: current.revision + 1,
        ),
        isUserEdited: false,
        isPinned: false,
        status: MemoryGenerationStatus.stale,
      ),
    );
    await refresh(projectId);
  }

  Future<void> _refresh(String projectId) async {
    final segments = await _segments.listSegments(projectId);
    final eligibleCount =
        (segments.length - NovelMemoryPolicy.recentRawSegmentCount).clamp(
          0,
          segments.length,
        );
    final completeChunkCount =
        eligibleCount ~/ NovelMemoryPolicy.chunkSegmentCount;
    if (completeChunkCount == 0) return;

    final existing = await _repository.listChunks(projectId);
    for (var chunkIndex = 0; chunkIndex < completeChunkCount; chunkIndex += 1) {
      final start = chunkIndex * NovelMemoryPolicy.chunkSegmentCount;
      final end = start + NovelMemoryPolicy.chunkSegmentCount;
      final source = segments.sublist(start, end);
      final fingerprint = fingerprintSegments(source);
      final old = existing
          .where(
            (item) =>
                item.sourceStartOrder == start &&
                item.sourceEndOrder == end - 1,
          )
          .firstOrNull;
      if (old?.status == MemoryGenerationStatus.valid &&
          old?.sourceFingerprint == fingerprint) {
        continue;
      }
      await _summarizeChunk(
        projectId: projectId,
        start: start,
        end: end - 1,
        source: source,
        fingerprint: fingerprint,
        previous: old,
      );
    }
    await _updateDigest(projectId);
  }

  Future<void> _summarizeChunk({
    required String projectId,
    required int start,
    required int end,
    required List<Segment> source,
    required String fingerprint,
    required NovelSummaryChunk? previous,
  }) async {
    final now = DateTime.now().toUtc();
    final generating = NovelSummaryChunk(
      metadata:
          previous?.metadata.copyWith(
            updatedAt: now,
            revision: previous.revision + 1,
          ) ??
          EntityMetadata(
            id: _ids.nextId('novel_summary'),
            createdAt: now,
            updatedAt: now,
            revision: 1,
          ),
      projectId: projectId,
      sourceStartOrder: start,
      sourceEndOrder: end,
      sourceStartSegmentId: source.first.id,
      sourceEndSegmentId: source.last.id,
      summary: previous?.summary ?? '',
      sourceFingerprint: fingerprint,
      status: MemoryGenerationStatus.generating,
      provider: previous?.provider,
      model: previous?.model,
    );
    await _repository.upsertChunk(generating);
    try {
      final selected = await _modelResolver?.resolveForProject(projectId);
      final resolved = selected == null
          ? await _runtime.resolveDefault()
          : null;
      final output = cleanAiText(
        await _runtime.generate(
          _summaryPromptBuilder
              .buildChunk(
                requestId: _ids.nextId('summary_request'),
                segments: source,
              )
              .copyWith(
                providerConfigId: selected?.providerConfigId,
                model: selected?.model,
              ),
        ),
      );
      if (output.isEmpty) throw const FormatException('Empty summary');
      await _repository.upsertChunk(
        generating.copyWith(
          metadata: generating.metadata.copyWith(
            updatedAt: DateTime.now().toUtc(),
            revision: generating.revision + 1,
          ),
          summary: output,
          status: MemoryGenerationStatus.valid,
          provider: selected?.providerConfigId ?? resolved!.config.type.name,
          model: selected?.model ?? resolved!.selection.modelId,
        ),
      );
    } catch (_) {
      await _repository.upsertChunk(
        generating.copyWith(
          metadata: generating.metadata.copyWith(
            updatedAt: DateTime.now().toUtc(),
            revision: generating.revision + 1,
          ),
          status: MemoryGenerationStatus.failed,
        ),
      );
    }
  }

  Future<void> _updateDigest(String projectId) async {
    final chunks = (await _repository.listChunks(projectId))
        .where(
          (item) =>
              item.status == MemoryGenerationStatus.valid &&
              item.summary.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (chunks.isEmpty) return;
    final previous = await _repository.getDigest(projectId);
    if (previous?.isProtected == true) return;
    final fingerprint = fingerprintStrings(
      chunks.map(
        (item) => '${item.id}|${item.sourceFingerprint}|${item.summary}',
      ),
    );
    if (previous?.status == MemoryGenerationStatus.valid &&
        previous?.sourceFingerprint == fingerprint) {
      return;
    }
    try {
      final selected = await _modelResolver?.resolveForProject(projectId);
      final resolved = selected == null
          ? await _runtime.resolveDefault()
          : null;
      final output = cleanAiText(
        await _runtime.generate(
          _digestPromptBuilder
              .build(
                requestId: _ids.nextId('digest_request'),
                previous: previous,
                chunks: chunks,
              )
              .copyWith(
                providerConfigId: selected?.providerConfigId,
                model: selected?.model,
              ),
        ),
      );
      if (output.isEmpty) return;
      final now = DateTime.now().toUtc();
      await _repository.upsertDigest(
        StoryMemoryDigest(
          metadata:
              previous?.metadata.copyWith(
                updatedAt: now,
                revision: previous.revision + 1,
              ) ??
              EntityMetadata(
                id: _ids.nextId('story_memory'),
                createdAt: now,
                updatedAt: now,
                revision: 1,
              ),
          projectId: projectId,
          content: output,
          sourceThroughOrder: chunks.last.sourceEndOrder,
          sourceFingerprint: fingerprint,
          status: MemoryGenerationStatus.valid,
          provider: selected?.providerConfigId ?? resolved!.config.type.name,
          model: selected?.model ?? resolved!.selection.modelId,
        ),
      );
    } catch (_) {
      if (previous != null) {
        await _repository.upsertDigest(
          previous.copyWith(status: MemoryGenerationStatus.failed),
        );
      }
    }
  }
}
