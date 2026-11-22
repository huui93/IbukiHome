import '../prompt/prompt_models.dart';
import 'world_info_models.dart';

class _Candidate {
  _Candidate(
    this.entry,
    this.pass,
    this.primary,
    this.secondary, {
    this.recursionSource,
    this.sticky = false,
  });
  final WorldInfoEntry entry;
  final int pass;
  final List<String> primary, secondary;
  final WorldInfoEntryId? recursionSource;
  final bool sticky;
  double? groupSample;
  int get score =>
      primary.length +
      (entry.selectiveLogic == WorldInfoSelectiveLogic.andAny ||
              entry.selectiveLogic == WorldInfoSelectiveLogic.andAll
          ? secondary.length
          : 0);
}

class WorldInfoRuntime {
  const WorldInfoRuntime();

  WorldInfoActivationPlan evaluate({
    required List<WorldInfoEntry> entries,
    required WorldInfoActivationContext context,
    required WorldInfoRuntimeState state,
    required WorldInfoRandomSource random,
    WorldInfoSettings settings = const WorldInfoSettings(),
  }) {
    if (context.sessionId != state.sessionId ||
        context.storyLineId != state.storyLineId ||
        settings.scanDepth < 0 ||
        settings.maxRecursionPasses < 1) {
      throw ArgumentError('Invalid World Info scope or settings.');
    }
    final ordered = [...entries]..sort(_entryOrder);
    final byId = <WorldInfoEntryId, WorldInfoEntry>{};
    for (final entry in ordered) {
      if (entry.bookId.isEmpty ||
          entry.entryId.isEmpty ||
          byId.containsKey(entry.identity) ||
          entry.probabilityPercent < 0 ||
          entry.probabilityPercent > 100 ||
          entry.groupWeight < 0 ||
          entry.stickyMessages < 0 ||
          entry.cooldownMessages < 0 ||
          entry.delayMessages < 0 ||
          (entry.scanDepth != null && entry.scanDepth! < 0) ||
          entry.placement.depth < 0) {
        throw ArgumentError('Invalid World Info entry ${entry.sourceId}.');
      }
      byId[entry.identity] = entry;
    }

    // A changed transcript or entry definition invalidates its transient timer.
    final historyReplaced =
        context.messageCount < state.observedMessageCount ||
        (context.messageCount == state.observedMessageCount &&
            state.historyMarker.isNotEmpty &&
            state.historyMarker != context.historyMarker);
    final timed = <WorldInfoEntryId, WorldInfoTimedState>{};
    if (!historyReplaced) {
      for (final item in state.timed.entries) {
        final entry = byId[item.key];
        if (entry == null ||
            !entry.enabled ||
            !entry.bookEnabled ||
            entry.definitionSignature != item.value.definitionSignature ||
            (item.value.definitionFingerprint != null &&
                entry.definitionFingerprint !=
                    item.value.definitionFingerprint)) {
          continue;
        }
        final expires =
            item.value.activatedAtMessage +
            entry.stickyMessages +
            entry.cooldownMessages;
        if (context.messageCount <= expires) timed[item.key] = item.value;
      }
    }

    final decisions = <WorldInfoEntryId, WorldInfoActivationDecision>{};
    final active = <WorldInfoEntryId, _Candidate>{};
    final blockedByProbability = <WorldInfoEntryId>{};
    final blockedByGroup = <WorldInfoEntryId>{};
    final recursionGuarded = <WorldInfoEntryId>{};
    var recursiveText = <(WorldInfoEntryId, String)>[];
    for (var pass = 0; pass < settings.maxRecursionPasses; pass++) {
      if (pass > 0 && (!settings.recursive || recursiveText.isEmpty)) break;
      final candidates = <_Candidate>[];
      for (final entry in ordered) {
        final id = entry.identity;
        if (active.containsKey(id) ||
            blockedByProbability.contains(id) ||
            blockedByGroup.contains(id)) {
          if (pass > 0 &&
              active.containsKey(id) &&
              _matchingKeys(
                entry.primaryKeys,
                recursiveText.map((e) => e.$2).join('\n'),
                entry.caseSensitive,
                entry.wholeWords,
              ).isNotEmpty) {
            recursionGuarded.add(id);
          }
          continue;
        }
        WorldInfoActivationReason? skip;
        if (!entry.enabled || !entry.bookEnabled) {
          skip = WorldInfoActivationReason.disabled;
        } else if (!_inScope(entry, context)) {
          skip = WorldInfoActivationReason.scopeMismatch;
        } else if (entry.generationTypes.isNotEmpty &&
            !entry.generationTypes.contains(context.generationType)) {
          skip = WorldInfoActivationReason.generationMismatch;
        } else if (entry.manualOnly) {
          skip = WorldInfoActivationReason.manualOnly;
        } else if (pass == 0 && entry.recursionOnly) {
          skip = WorldInfoActivationReason.recursionOnly;
        } else if (pass > 0 && entry.excludeRecursion) {
          skip = WorldInfoActivationReason.recursionExcluded;
        } else if (context.messageCount < entry.delayMessages) {
          skip = WorldInfoActivationReason.delayPending;
        }
        if (skip != null) {
          decisions[id] = _decision(
            entry,
            false,
            skip,
            delayRemaining: skip == WorldInfoActivationReason.delayPending
                ? entry.delayMessages - context.messageCount
                : 0,
          );
          continue;
        }
        final previous = timed[id];
        final age = previous == null
            ? -1
            : context.messageCount - previous.activatedAtMessage;
        final sticky =
            entry.stickyMessages > 0 &&
            previous != null &&
            age >= 0 &&
            age <= entry.stickyMessages;
        if (!sticky &&
            previous != null &&
            age > entry.stickyMessages &&
            age <= entry.stickyMessages + entry.cooldownMessages) {
          decisions[id] = _decision(
            entry,
            false,
            WorldInfoActivationReason.cooldown,
            cooldownRemaining:
                entry.stickyMessages + entry.cooldownMessages - age + 1,
          );
          continue;
        }
        final depth = entry.scanDepth ?? settings.scanDepth;
        final chat = depth == 0
            ? ''
            : context.messages
                  .skip(
                    (context.messages.length - depth).clamp(
                      0,
                      context.messages.length,
                    ),
                  )
                  .map((message) => message.text)
                  .join('\n');
        final extra = entry.additionalScanSources.toList()
          ..sort((a, b) => a.index.compareTo(b.index));
        final recursion = pass == 0
            ? ''
            : recursiveText.map((e) => e.$2).join('\n');
        final text = [
          chat,
          for (final source in extra) context.additionalScanText[source] ?? '',
          recursion,
        ].where((part) => part.isNotEmpty).join('\n');
        final primary = _matchingKeys(
          entry.primaryKeys,
          text,
          entry.caseSensitive,
          entry.wholeWords,
        );
        if (!sticky && !entry.constant && primary.isEmpty) {
          decisions[id] = _decision(
            entry,
            false,
            WorldInfoActivationReason.primaryNotMatched,
          );
          continue;
        }
        final secondary = _matchingKeys(
          entry.secondaryKeys,
          text,
          entry.caseSensitive,
          entry.wholeWords,
        );
        if (!sticky &&
            !entry.constant &&
            !_secondaryPass(entry, secondary.length)) {
          decisions[id] = _decision(
            entry,
            false,
            WorldInfoActivationReason.secondaryNotMatched,
            primary: primary,
            secondary: secondary,
          );
          continue;
        }
        WorldInfoEntryId? recursiveFrom;
        if (pass > 0) {
          for (final source in recursiveText) {
            if (_matchingKeys(
              entry.primaryKeys,
              source.$2,
              entry.caseSensitive,
              entry.wholeWords,
            ).isNotEmpty) {
              recursiveFrom = source.$1;
              break;
            }
          }
        }
        candidates.add(
          _Candidate(
            entry,
            pass,
            primary,
            secondary,
            sticky: sticky,
            recursionSource: recursiveFrom,
          ),
        );
      }
      if (candidates.isEmpty) break;
      final winners = _groupWinners(
        candidates,
        active.values.toList(),
        context,
        pass,
        random,
        decisions,
        blockedByGroup,
      );
      final newRecursion = <(WorldInfoEntryId, String)>[];
      for (final candidate in winners) {
        final entry = candidate.entry;
        final id = entry.identity;
        double? sample;
        if (!candidate.sticky && entry.probabilityPercent < 100) {
          sample = random.sample(
            'probability:${context.sessionId}:${context.storyLineId}:'
            '${context.historyMarker}:${entry.sourceId}:$pass',
          );
          if (sample < 0 || sample >= 1) {
            throw StateError('World Info random sample must be in [0, 1).');
          }
          if (sample * 100 >= entry.probabilityPercent) {
            blockedByProbability.add(id);
            decisions[id] = _decision(
              entry,
              false,
              WorldInfoActivationReason.probabilityFailed,
              pass: pass,
              primary: candidate.primary,
              secondary: candidate.secondary,
              sample: sample,
              groupScore: candidate.entry.groups.isEmpty
                  ? null
                  : candidate.score,
              groupSample: candidate.groupSample,
            );
            continue;
          }
        }
        active[id] = candidate;
        decisions[id] = _decision(
          entry,
          true,
          candidate.sticky
              ? WorldInfoActivationReason.activatedSticky
              : entry.constant
              ? WorldInfoActivationReason.activatedConstant
              : pass > 0
              ? WorldInfoActivationReason.activatedRecursive
              : WorldInfoActivationReason.activatedPrimary,
          pass: pass,
          primary: candidate.primary,
          secondary: candidate.secondary,
          sample: sample,
          groupScore: candidate.entry.groups.isEmpty ? null : candidate.score,
          groupSample: candidate.groupSample,
          recursionSource: candidate.recursionSource,
          stickyRemaining: candidate.sticky && timed[id] != null
              ? (entry.stickyMessages -
                    (context.messageCount - timed[id]!.activatedAtMessage) +
                    1)
              : 0,
        );
        if (!candidate.sticky &&
            (entry.stickyMessages > 0 || entry.cooldownMessages > 0)) {
          timed[id] = WorldInfoTimedState(
            activatedAtMessage: context.messageCount,
            definitionSignature: entry.definitionSignature,
            definitionFingerprint: entry.definitionFingerprint,
          );
        }
        if (!entry.preventRecursion && entry.content.isNotEmpty) {
          newRecursion.add((id, entry.content));
        }
      }
      recursiveText = newRecursion;
    }
    final activatedEntries = active.values.map((c) => c.entry).toList()
      ..sort(_entryOrder);
    final trace = <WorldInfoActivationDecision>[
      for (final entry in ordered)
        decisions[entry.identity] ??
            _decision(entry, false, WorldInfoActivationReason.recursionGuard),
    ];
    return WorldInfoActivationPlan(
      activated: List.unmodifiable(activatedEntries.map((e) => e.identity)),
      promptSources: List.unmodifiable(activatedEntries.map(_promptSource)),
      trace: WorldInfoActivationTrace(
        List.unmodifiable(trace),
        recursionGuarded: List.unmodifiable(
          recursionGuarded.toList()..sort(_idOrder),
        ),
      ),
      nextState: WorldInfoRuntimeState(
        sessionId: context.sessionId,
        storyLineId: context.storyLineId,
        observedMessageCount: context.messageCount,
        historyMarker: context.historyMarker,
        timed: Map.unmodifiable(timed),
      ),
    );
  }

  static int _idOrder(WorldInfoEntryId a, WorldInfoEntryId b) {
    final book = a.$1.compareTo(b.$1);
    return book != 0 ? book : a.$2.compareTo(b.$2);
  }

  static int _entryOrder(WorldInfoEntry a, WorldInfoEntry b) {
    final priority = b.priority.compareTo(a.priority);
    if (priority != 0) return priority;
    final order = a.order.compareTo(b.order);
    return order != 0 ? order : _idOrder(a.identity, b.identity);
  }

  static bool _inScope(
    WorldInfoEntry entry,
    WorldInfoActivationContext context,
  ) =>
      (entry.worldIds.isEmpty || entry.worldIds.contains(context.worldId)) &&
      (entry.personaIds.isEmpty ||
          entry.personaIds.contains(context.personaId)) &&
      (entry.characterIds.isEmpty && entry.characterTags.isEmpty ||
          (entry.excludeCharacterFilter
              ? entry.characterIds.intersection(context.characterIds).isEmpty &&
                    entry.characterTags
                        .intersection(context.characterTags)
                        .isEmpty
              : entry.characterIds
                        .intersection(context.characterIds)
                        .isNotEmpty ||
                    entry.characterTags
                        .intersection(context.characterTags)
                        .isNotEmpty));

  static bool _secondaryPass(WorldInfoEntry entry, int matches) {
    final count = entry.secondaryKeys
        .where((key) => key.trim().isNotEmpty)
        .length;
    if (count == 0) return true;
    return switch (entry.selectiveLogic) {
      WorldInfoSelectiveLogic.andAny => matches > 0,
      WorldInfoSelectiveLogic.andAll => matches == count,
      WorldInfoSelectiveLogic.notAny => matches == 0,
      WorldInfoSelectiveLogic.notAll => matches < count,
    };
  }

  static List<String> _matchingKeys(
    List<String> keys,
    String text,
    bool caseSensitive,
    bool wholeWords,
  ) {
    if (text.isEmpty) return const [];
    final normalized = _normalize(text, caseSensitive);
    final matches = <String>[];
    for (final raw in keys) {
      final key = _normalize(raw, caseSensitive);
      if (key.isEmpty) continue;
      var from = 0;
      while (from < normalized.length) {
        final at = normalized.indexOf(key, from);
        if (at < 0) break;
        final boundary =
            wholeWords &&
            !key.contains(' ') &&
            !RegExp(r'[^\x00-\x7f]').hasMatch(key);
        if (!boundary ||
            ((at == 0 || !_wordChar(normalized[at - 1])) &&
                (at + key.length == normalized.length ||
                    !_wordChar(normalized[at + key.length])))) {
          matches.add(raw);
          break;
        }
        from = at + key.length;
      }
    }
    return matches;
  }

  static String _normalize(String value, bool caseSensitive) {
    final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return caseSensitive ? compact : compact.toLowerCase();
  }

  static bool _wordChar(String char) =>
      RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(char);

  static WorldInfoActivationDecision _decision(
    WorldInfoEntry entry,
    bool active,
    WorldInfoActivationReason reason, {
    int? pass,
    List<String> primary = const [],
    List<String> secondary = const [],
    WorldInfoEntryId? groupWinner,
    int? groupScore,
    double? groupSample,
    double? sample,
    WorldInfoEntryId? recursionSource,
    int stickyRemaining = 0,
    int cooldownRemaining = 0,
    int delayRemaining = 0,
  }) => WorldInfoActivationDecision(
    identity: entry.identity,
    title: entry.title,
    active: active,
    reason: reason,
    pass: pass,
    matchedPrimary: List.unmodifiable(primary),
    matchedSecondary: List.unmodifiable(secondary),
    groupWinner: groupWinner,
    groupScore: groupScore,
    groupSample: groupSample,
    groupWeight: entry.groups.isEmpty ? null : entry.groupWeight,
    probabilitySample: sample,
    recursionSource: recursionSource,
    stickyRemaining: stickyRemaining,
    cooldownRemaining: cooldownRemaining,
    delayRemaining: delayRemaining,
  );

  static List<_Candidate> _groupWinners(
    List<_Candidate> candidates,
    List<_Candidate> alreadyActive,
    WorldInfoActivationContext context,
    int pass,
    WorldInfoRandomSource random,
    Map<WorldInfoEntryId, WorldInfoActivationDecision> decisions,
    Set<WorldInfoEntryId> blockedByGroup,
  ) {
    final pending = [...candidates]
      ..sort((a, b) {
        if (a.sticky != b.sticky) return a.sticky ? -1 : 1;
        if (a.entry.constant != b.entry.constant) {
          return a.entry.constant ? -1 : 1;
        }
        return _entryOrder(a.entry, b.entry);
      });
    final winners = <_Candidate>[];
    final reserved = <String>{
      for (final item in alreadyActive) ...item.entry.groups,
    };
    while (pending.isNotEmpty) {
      final first = pending.removeAt(0);
      final conflicts = <_Candidate>[first];
      final shared = {...first.entry.groups};
      var expanded = true;
      while (expanded) {
        expanded = false;
        for (final other in [...pending]) {
          if (other.entry.groups.any(shared.contains)) {
            conflicts.add(other);
            shared.addAll(other.entry.groups);
            pending.remove(other);
            expanded = true;
          }
        }
      }
      if (shared.any(reserved.contains)) {
        final winner = alreadyActive.firstWhere(
          (item) => item.entry.groups.any(shared.contains),
        );
        for (final loser in conflicts) {
          blockedByGroup.add(loser.entry.identity);
          decisions[loser.entry.identity] = _decision(
            loser.entry,
            false,
            WorldInfoActivationReason.groupLost,
            pass: pass,
            primary: loser.primary,
            secondary: loser.secondary,
            groupWinner: winner.entry.identity,
            groupScore: loser.score,
          );
        }
        continue;
      }
      final selection = _chooseGroup(conflicts, context, pass, random);
      final winner = selection.$1;
      winner.groupSample = selection.$2;
      winners.add(winner);
      reserved.addAll(winner.entry.groups);
      for (final loser in conflicts) {
        if (identical(loser, winner)) continue;
        blockedByGroup.add(loser.entry.identity);
        decisions[loser.entry.identity] = _decision(
          loser.entry,
          false,
          WorldInfoActivationReason.groupLost,
          pass: pass,
          primary: loser.primary,
          secondary: loser.secondary,
          groupWinner: winner.entry.identity,
          groupScore: loser.score,
          groupSample: selection.$2,
        );
      }
    }
    return winners;
  }

  static (_Candidate, double?) _chooseGroup(
    List<_Candidate> items,
    WorldInfoActivationContext context,
    int pass,
    WorldInfoRandomSource random,
  ) {
    if (items.length == 1) return (items.single, null);
    final sticky = items.where((item) => item.sticky).toList();
    var eligible = sticky.isNotEmpty ? sticky : items;
    if (eligible.any((item) => item.entry.scoreGroup)) {
      final best = eligible
          .map((item) => item.score)
          .reduce((a, b) => a > b ? a : b);
      eligible = eligible.where((item) => item.score == best).toList();
    }
    if (eligible.any((item) => item.entry.prioritizeGroup)) {
      eligible.sort((a, b) {
        final order = b.entry.order.compareTo(a.entry.order);
        return order != 0
            ? order
            : _idOrder(a.entry.identity, b.entry.identity);
      });
      return (eligible.first, null);
    }
    eligible.sort((a, b) => _idOrder(a.entry.identity, b.entry.identity));
    final total = eligible.fold<int>(
      0,
      (sum, item) => sum + item.entry.groupWeight,
    );
    if (total == 0) return (eligible.first, null);
    final key =
        'group:${context.sessionId}:${context.storyLineId}:'
        '${context.historyMarker}:$pass:'
        '${eligible.map((item) => item.entry.sourceId).join(",")}';
    final sample = random.sample(key);
    if (sample < 0 || sample >= 1) {
      throw StateError('World Info random sample must be in [0, 1).');
    }
    final point = sample * total;
    var cumulative = 0;
    for (final item in eligible) {
      cumulative += item.entry.groupWeight;
      if (point < cumulative) return (item, sample);
    }
    return (eligible.last, sample);
  }

  static PromptSource _promptSource(WorldInfoEntry entry) => PromptSource(
    id: entry.sourceId,
    type: PromptSourceType.worldInfo,
    origin: PromptOrigin(
      'worldInfoEntry',
      entry.entryId,
      parentId: entry.bookId,
      label: entry.title,
    ),
    role: entry.role,
    placement: entry.placement,
    atoms: [
      PromptAtom(
        id: '${entry.sourceId}:text',
        kind: PromptAtomKind.text,
        text: entry.content,
      ),
    ],
    priority: entry.priority,
    order: entry.order,
    required: false,
    budgetClass: PromptBudgetClass.grounding,
  );
}
