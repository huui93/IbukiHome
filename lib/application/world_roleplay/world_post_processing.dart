import '../../domain/world_roleplay/world_roleplay_engine_models.dart';

class WorldMemoryExtractor {
  const WorldMemoryExtractor({this.minimumImportance = 0.65});

  final double minimumImportance;

  List<WorldMemoryCandidate> extract(WorldMutationProposal proposal) {
    return List.unmodifiable(
      proposal.memories.where(
        (item) =>
            item.summary.trim().isNotEmpty &&
            item.importance >= minimumImportance,
      ),
    );
  }
}

class WorldTimelineExtractor {
  const WorldTimelineExtractor({this.minimumImportance = 0.65});

  final double minimumImportance;

  List<WorldTimelineCandidate> extract(WorldMutationProposal proposal) {
    return List.unmodifiable(
      proposal.timelineEvents.where(
        (item) =>
            item.title.trim().isNotEmpty &&
            item.importance >= minimumImportance,
      ),
    );
  }
}
