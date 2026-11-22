import 'dart:convert';

import 'prompt_models.dart';

abstract class PromptTokenCounter {
  int countText(String text);
  int get segmentOverhead;
}

class EstimatedPromptTokenCounter implements PromptTokenCounter {
  const EstimatedPromptTokenCounter();
  @override
  int countText(String text) => (text.runes.length + 3) ~/ 4;
  @override
  int get segmentOverhead => 2;
}

class _PreparedSource {
  _PreparedSource(
    this.source,
    this.inputIndex,
    this.atoms,
    this.excludedAtomIds,
    this.tokens,
  );
  final PromptSource source;
  final int inputIndex;
  final List<PromptAtom> atoms;
  final List<String> excludedAtomIds;
  final int tokens;
  bool included = false;
  PromptCompileReason? dropReason;
}

class PromptCompileProfile {
  const PromptCompileProfile({
    required this.prompt,
    required this.total,
    required this.tokenEstimation,
    required this.traceConstruction,
  });
  final CompiledPrompt prompt;
  final Duration total, tokenEstimation, traceConstruction;
}

class PromptCompiler {
  const PromptCompiler(this.counter);
  final PromptTokenCounter counter;

  CompiledPrompt compile(PromptCompileInput input) => _compile(input);

  PromptCompileProfile profile(PromptCompileInput input) {
    final total = Stopwatch()..start();
    final token = Stopwatch();
    final trace = Stopwatch();
    final prompt = _compile(input, tokenWatch: token, traceWatch: trace);
    total.stop();
    return PromptCompileProfile(
      prompt: prompt,
      total: total.elapsed,
      tokenEstimation: token.elapsed,
      traceConstruction: trace.elapsed,
    );
  }

  CompiledPrompt _compile(
    PromptCompileInput input, {
    Stopwatch? tokenWatch,
    Stopwatch? traceWatch,
  }) {
    final constraints = input.constraints;
    if (constraints.maxContextTokens <= 0 ||
        constraints.reservedOutputTokens < 0 ||
        constraints.reservedControlTokens < 0 ||
        constraints.usableInputTokens < 0) {
      throw const PromptCompileFailure(
        PromptCompileFailureKind.invalidConstraints,
      );
    }
    final seen = <String>{};
    final historyOrigins = <(String, String)>{};
    final prepared = <_PreparedSource>[];
    for (final source in input.sources) {
      _validate(source, input.mode, seen);
      if (source.type == PromptSourceType.history &&
          !historyOrigins.add((source.origin.type, source.origin.id))) {
        throw PromptCompileFailure(
          PromptCompileFailureKind.invalidSource,
          sourceId: source.id,
        );
      }
    }
    tokenWatch?.start();
    for (var index = 0; index < input.sources.length; index++) {
      prepared.add(_prepare(input.sources[index], index, constraints));
    }
    tokenWatch?.stop();
    if (input.mode == PromptCompileMode.continueTurn &&
        prepared
                .where(
                  (item) => item.source.type == PromptSourceType.continuation,
                )
                .length !=
            1) {
      throw const PromptCompileFailure(
        PromptCompileFailureKind.invariantViolation,
      );
    }
    var remaining = constraints.usableInputTokens;
    for (final item in prepared.where((item) => item.source.required)) {
      if (item.atoms.isEmpty) {
        throw PromptCompileFailure(
          PromptCompileFailureKind.invalidSource,
          sourceId: item.source.id,
        );
      }
      if (item.tokens > remaining) {
        throw PromptCompileFailure(
          PromptCompileFailureKind.requiredOverflow,
          sourceId: item.source.id,
        );
      }
      item.included = true;
      remaining -= item.tokens;
    }

    final grounding =
        prepared
            .where(
              (item) =>
                  !item.source.required &&
                  item.source.budgetClass == PromptBudgetClass.grounding,
            )
            .toList()
          ..sort(_priorityOrder);
    final history =
        prepared
            .where(
              (item) =>
                  !item.source.required &&
                  item.source.budgetClass == PromptBudgetClass.history,
            )
            .toList()
          ..sort((a, b) => _historyOrder(a.source, b.source));
    final supplemental =
        prepared
            .where(
              (item) =>
                  !item.source.required &&
                  item.source.budgetClass == PromptBudgetClass.supplemental,
            )
            .toList()
          ..sort(_priorityOrder);
    for (final item in grounding) {
      remaining = _includeOptional(
        item,
        remaining,
        constraints.usableInputTokens,
      );
    }
    var trimmedHistory = false;
    for (final item in history.reversed) {
      if (trimmedHistory) {
        item.dropReason = PromptCompileReason.historyTrimmed;
        continue;
      }
      if (item.atoms.isNotEmpty && item.tokens > remaining) {
        trimmedHistory = true;
        item.dropReason = PromptCompileReason.historyTrimmed;
        continue;
      }
      remaining = _includeOptional(
        item,
        remaining,
        constraints.usableInputTokens,
      );
    }
    for (final item in supplemental) {
      remaining = _includeOptional(
        item,
        remaining,
        constraints.usableInputTokens,
      );
    }

    final ordered = _order(prepared.where((item) => item.included).toList());
    final segments = <CompiledPromptSegment>[];
    final positions = <String, int>{};
    for (final item in ordered) {
      positions[item.source.id] = segments.length;
      segments.add(
        CompiledPromptSegment(
          sourceId: item.source.id,
          origin: item.source.origin,
          role: item.source.role,
          atoms: List.unmodifiable(item.atoms),
          tokenEstimate: item.tokens,
          continuation: item.source.type == PromptSourceType.continuation,
        ),
      );
    }
    traceWatch?.start();
    final decisions = prepared.map((item) {
      final included = item.included;
      final reason = included
          ? (item.source.required
                ? PromptCompileReason.required
                : PromptCompileReason.included)
          : (item.dropReason ??
                (item.atoms.isEmpty
                    ? item.source.atoms.every(
                            (atom) =>
                                atom.kind == PromptAtomKind.text &&
                                (atom.text?.trim().isEmpty ?? true),
                          )
                          ? PromptCompileReason.empty
                          : item.excludedAtomIds.isNotEmpty
                          ? PromptCompileReason.policyExcluded
                          : PromptCompileReason.empty
                    : PromptCompileReason.budgetExhausted));
      return PromptCompileDecision(
        inputIndex: item.inputIndex,
        sourceId: item.source.id,
        sourceType: item.source.type,
        origin: item.source.origin,
        role: item.source.role,
        placement: item.source.placement,
        priority: item.source.priority,
        visibility: item.source.visibility,
        outcome: included
            ? PromptCompileOutcome.included
            : reason == PromptCompileReason.historyTrimmed
            ? PromptCompileOutcome.trimmed
            : PromptCompileOutcome.dropped,
        reason: reason,
        estimatedTokens: item.tokens,
        excludedAtomIds: List.unmodifiable(item.excludedAtomIds),
        finalIndex: positions[item.source.id],
      );
    }).toList()..sort((a, b) => a.sourceId.compareTo(b.sourceId));
    final result = CompiledPrompt(
      mode: input.mode,
      segments: List.unmodifiable(segments),
      trace: PromptCompileTrace(
        maxContextTokens: constraints.maxContextTokens,
        reservedOutputTokens: constraints.reservedOutputTokens,
        reservedControlTokens: constraints.reservedControlTokens,
        usableInputTokens: constraints.usableInputTokens,
        usedInputTokens: constraints.usableInputTokens - remaining,
        decisions: List.unmodifiable(decisions),
      ),
    );
    traceWatch?.stop();
    return result;
  }

  void _validate(
    PromptSource source,
    PromptCompileMode mode,
    Set<String> seen,
  ) {
    if (source.id.isEmpty ||
        source.origin.type.isEmpty ||
        source.origin.id.isEmpty ||
        !seen.add(source.id) ||
        source.atoms.map((atom) => atom.id).toSet().length !=
            source.atoms.length ||
        source.atoms.any((atom) => atom.id.isEmpty)) {
      throw PromptCompileFailure(
        PromptCompileFailureKind.invalidSource,
        sourceId: source.id,
      );
    }
    for (final atom in source.atoms) {
      final valid = switch (atom.kind) {
        PromptAtomKind.text ||
        PromptAtomKind.reasoning ||
        PromptAtomKind.reasoningSummary ||
        PromptAtomKind.event => atom.text != null,
        PromptAtomKind.toolCall =>
          atom.toolName?.isNotEmpty == true &&
              atom.toolCallId?.isNotEmpty == true &&
              atom.arguments != null,
        PromptAtomKind.toolResult =>
          atom.toolCallId?.isNotEmpty == true &&
              (atom.result != null || atom.error != null),
        PromptAtomKind.attachment =>
          atom.assetReference?.isNotEmpty == true &&
              atom.mimeType?.isNotEmpty == true,
        _ => true,
      };
      if (!valid) {
        throw PromptCompileFailure(
          PromptCompileFailureKind.invalidSource,
          sourceId: source.id,
        );
      }
    }
    if (source.placement.depth < 0 ||
        (source.placement.kind != PromptPlacementKind.atHistoryDepth &&
            source.placement.depth != 0) ||
        (source.type == PromptSourceType.history) !=
            (source.placement.kind == PromptPlacementKind.history) ||
        (source.type == PromptSourceType.history) !=
            (source.budgetClass == PromptBudgetClass.history) ||
        (source.type == PromptSourceType.continuation &&
            (mode != PromptCompileMode.continueTurn ||
                source.placement.kind != PromptPlacementKind.tail))) {
      throw PromptCompileFailure(
        PromptCompileFailureKind.invalidInsertion,
        sourceId: source.id,
      );
    }
  }

  _PreparedSource _prepare(
    PromptSource source,
    int inputIndex,
    PromptCompileConstraints constraints,
  ) {
    final atoms = <PromptAtom>[];
    final excluded = <String>[];
    for (final atom in source.atoms) {
      final allowed = switch (atom.kind) {
        PromptAtomKind.text => atom.text?.isNotEmpty == true,
        PromptAtomKind.reasoning =>
          constraints.reasoningPolicy == ReasoningPromptPolicy.include,
        PromptAtomKind.reasoningSummary =>
          constraints.reasoningPolicy != ReasoningPromptPolicy.exclude,
        PromptAtomKind.toolCall || PromptAtomKind.toolResult =>
          constraints.toolPolicy == ToolPromptPolicy.structured,
        PromptAtomKind.attachment =>
          constraints.attachmentPolicy == AttachmentPromptPolicy.reference,
        _ => false,
      };
      if (allowed) {
        atoms.add(atom);
      } else {
        excluded.add(atom.id);
      }
    }
    if (atoms.isNotEmpty &&
        atoms.every(
          (atom) =>
              atom.kind == PromptAtomKind.text &&
              (atom.text?.trim().isEmpty ?? true),
        )) {
      atoms.clear();
    }
    var tokens = 0;
    if (atoms.isNotEmpty) {
      try {
        tokens = counter.segmentOverhead;
        if (tokens < 0) throw StateError('Negative token count.');
        for (final atom in atoms) {
          final count = counter.countText(_countable(atom));
          if (count < 0) throw StateError('Negative token count.');
          tokens += count;
        }
        if (tokens < 0) throw StateError('Negative token count.');
      } catch (_) {
        throw PromptCompileFailure(
          PromptCompileFailureKind.tokenCounterFailure,
          sourceId: source.id,
        );
      }
    }
    return _PreparedSource(source, inputIndex, atoms, excluded, tokens);
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  String _countable(PromptAtom atom) => switch (atom.kind) {
    PromptAtomKind.toolCall =>
      '${atom.toolName ?? ''}:${atom.toolCallId ?? ''}:${jsonEncode(_canonical(atom.arguments))}',
    PromptAtomKind.toolResult =>
      '${atom.toolCallId ?? ''}:${jsonEncode(_canonical(atom.result))}:${atom.error ?? ''}',
    PromptAtomKind.attachment =>
      '${atom.assetReference ?? ''}:${atom.mimeType ?? ''}',
    _ => atom.text ?? '',
  };

  int _includeOptional(_PreparedSource item, int remaining, int usable) {
    if (item.atoms.isEmpty) return remaining;
    if (item.tokens <= remaining) {
      item.included = true;
      return remaining - item.tokens;
    }
    item.dropReason = item.tokens > usable
        ? PromptCompileReason.sourceTooLarge
        : PromptCompileReason.budgetExhausted;
    return remaining;
  }

  static int _priorityOrder(_PreparedSource a, _PreparedSource b) {
    final priority = b.source.priority.compareTo(a.source.priority);
    if (priority != 0) return priority;
    final order = a.source.order.compareTo(b.source.order);
    if (order != 0) return order;
    return a.source.id.compareTo(b.source.id);
  }

  static int _historyOrder(PromptSource a, PromptSource b) {
    final order = a.order.compareTo(b.order);
    return order != 0 ? order : a.id.compareTo(b.id);
  }

  List<_PreparedSource> _order(List<_PreparedSource> included) {
    final history =
        included
            .where(
              (item) =>
                  item.source.placement.kind == PromptPlacementKind.history,
            )
            .toList()
          ..sort((a, b) => _historyOrder(a.source, b.source));
    final depth = included
        .where(
          (item) =>
              item.source.placement.kind == PromptPlacementKind.atHistoryDepth,
        )
        .toList();
    final result = <_PreparedSource>[];
    void addSlot(PromptPlacementKind kind) {
      final slot =
          included.where((item) => item.source.placement.kind == kind).toList()
            ..sort(_priorityOrder);
      result.addAll(slot);
    }

    addSlot(PromptPlacementKind.beforeCharacter);
    addSlot(PromptPlacementKind.afterCharacter);
    addSlot(PromptPlacementKind.beforeHistory);
    for (var boundary = 0; boundary <= history.length; boundary++) {
      final inserted =
          depth
              .where(
                (item) =>
                    (history.length - item.source.placement.depth).clamp(
                      0,
                      history.length,
                    ) ==
                    boundary,
              )
              .toList()
            ..sort(_priorityOrder);
      result.addAll(inserted);
      if (boundary < history.length) result.add(history[boundary]);
    }
    addSlot(PromptPlacementKind.afterHistory);
    addSlot(PromptPlacementKind.tail);
    return result;
  }
}
