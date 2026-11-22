import 'dart:math' as math;

import '../../domain/world_roleplay/world_roleplay_engine_models.dart';
import '../../domain/world_roleplay/world_roleplay_models.dart';

class WorldLoreActivator {
  const WorldLoreActivator();

  WorldLoreActivationResult activate({
    required List<LoreEntry> entries,
    required Iterable<String> searchTexts,
    required int tokenBudget,
    Set<String> manualEntryIds = const {},
  }) {
    final enabled = entries.where((entry) => entry.enabled).toList();
    final haystack = searchTexts
        .map(_normalize)
        .where((value) => value.isNotEmpty)
        .join('\n');
    final activated =
        enabled.where((entry) {
          return switch (entry.activationMode) {
            LoreActivationMode.always => true,
            LoreActivationMode.manual => manualEntryIds.contains(entry.id),
            LoreActivationMode.keyword => _matches(entry, haystack),
          };
        }).toList()..sort((left, right) {
          final pinned = (right.isPinned ? 1 : 0).compareTo(
            left.isPinned ? 1 : 0,
          );
          if (pinned != 0) return pinned;
          final priority = right.priority.compareTo(left.priority);
          if (priority != 0) return priority;
          final activation = _activationRank(
            right.activationMode,
          ).compareTo(_activationRank(left.activationMode));
          if (activation != 0) return activation;
          return left.id.compareTo(right.id);
        });

    final selected = <LoreEntry>[];
    var estimatedTokens = 0;
    final safeBudget = tokenBudget.clamp(0, 12000);
    for (final entry in activated) {
      final estimate = estimateTokens(entry);
      if (estimatedTokens + estimate > safeBudget) continue;
      selected.add(entry);
      estimatedTokens += estimate;
    }
    return WorldLoreActivationResult(
      entries: List.unmodifiable(selected),
      diagnostics: WorldLoreActivationDiagnostics(
        candidateLoreCount: enabled.length,
        activatedLoreCount: activated.length,
        selectedLoreCount: selected.length,
        estimatedTokens: estimatedTokens,
      ),
    );
  }

  int estimateTokens(LoreEntry entry) {
    final hint = entry.tokenBudgetHint;
    if (hint != null && hint > 0) return hint;
    return math.max(1, (entry.content.runes.length / 2.5).ceil());
  }

  bool _matches(LoreEntry entry, String haystack) {
    if (haystack.isEmpty) return false;
    final keys = [
      ...entry.keywords,
      ...entry.secondaryKeywords,
    ].map(_normalize).where((key) => key.isNotEmpty);
    return keys.any(haystack.contains);
  }

  String _normalize(String value) => value.trim().toLowerCase();

  int _activationRank(LoreActivationMode mode) => switch (mode) {
    LoreActivationMode.manual => 3,
    LoreActivationMode.always => 2,
    LoreActivationMode.keyword => 1,
  };
}
