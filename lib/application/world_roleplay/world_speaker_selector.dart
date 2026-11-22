import '../../domain/world_roleplay/world_roleplay_engine_models.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';

class WorldSpeakerSelector {
  const WorldSpeakerSelector({this.maxSpeakers = 3});

  final int maxSpeakers;

  WorldSpeakerSelection select({
    required WorldDirectorDecision decision,
    required WorldSpeakerMode mode,
    required List<WorldCharacterInstance> presentCharacters,
    List<WorldFeedEntry> recentFeed = const [],
    Set<String> manualSpeakerIds = const {},
  }) {
    final present = presentCharacters
        .where((character) => character.isActive && character.isPresent)
        .toList(growable: false);
    if (present.isEmpty) {
      return WorldSpeakerSelection(speakerIds: const [], mode: mode);
    }
    final presentById = {for (final item in present) item.id: item};
    if (manualSpeakerIds.isNotEmpty || mode == WorldSpeakerMode.manual) {
      final selected = present
          .where((item) => manualSpeakerIds.contains(item.id))
          .take(maxSpeakers)
          .map((item) => item.id)
          .toList(growable: false);
      return WorldSpeakerSelection(
        speakerIds: List.unmodifiable(selected),
        mode: mode,
      );
    }
    if (mode == WorldSpeakerMode.sequence) {
      final ordered = present.map((item) => item.id).toList(growable: true);
      final lastSpeaker = recentFeed.reversed
          .where((entry) => entry.type == WorldFeedEntryType.characterSpeech)
          .map((entry) => entry.speakerCharacterInstanceId)
          .whereType<String>()
          .firstOrNull;
      final lastIndex = lastSpeaker == null ? -1 : ordered.indexOf(lastSpeaker);
      if (lastIndex >= 0) {
        final head = ordered.sublist(0, lastIndex + 1);
        ordered
          ..removeRange(0, lastIndex + 1)
          ..addAll(head);
      }
      return WorldSpeakerSelection(
        speakerIds: List.unmodifiable(ordered.take(maxSpeakers)),
        mode: mode,
      );
    }

    final candidates = decision.candidateSpeakerIds
        .where(presentById.containsKey)
        .toSet();
    if (candidates.isEmpty && decision.narrationNeeded) {
      return const WorldSpeakerSelection(
        speakerIds: [],
        mode: WorldSpeakerMode.natural,
      );
    }
    final pool = candidates.isEmpty
        ? present
        : present.where((item) => candidates.contains(item.id)).toList();
    final recentSpeakers = recentFeed.reversed
        .where((entry) => entry.type == WorldFeedEntryType.characterSpeech)
        .take(6)
        .map((entry) => entry.speakerCharacterInstanceId)
        .whereType<String>()
        .toList();
    final preferred = decision.preferredSpeakerIds.toSet();
    final scored =
        pool
            .map(
              (item) => (
                item: item,
                score:
                    (preferred.contains(item.id) ? 100.0 : 0.0) +
                    _talkativeness(item) * 10 -
                    recentSpeakers.where((id) => id == item.id).length * 3,
              ),
            )
            .toList()
          ..sort((left, right) {
            final score = right.score.compareTo(left.score);
            return score != 0 ? score : left.item.id.compareTo(right.item.id);
          });
    return WorldSpeakerSelection(
      speakerIds: List.unmodifiable(
        scored.take(maxSpeakers).map((entry) => entry.item.id),
      ),
      mode: mode,
    );
  }

  double _talkativeness(WorldCharacterInstance item) {
    final value = item.metadata['talkativeness'];
    if (value is num && value.isFinite) return value.toDouble().clamp(0, 1);
    return 0.5;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
