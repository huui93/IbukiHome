import '../../../domain/tavern/tavern_models.dart';
import 'prompt_models.dart';

class PromptHistoryAssembly {
  const PromptHistoryAssembly(this.mode, this.sources);
  final PromptCompileMode mode;
  final List<PromptSource> sources;
}

class PromptHistoryAssembler {
  const PromptHistoryAssembler();

  PromptHistoryAssembly assemble(
    TavernTranscriptProjection transcript, {
    required PromptCompileMode mode,
    String? targetTurnId,
  }) {
    final turns = transcript.turns;
    if (turns.isEmpty) {
      throw const PromptCompileFailure(
        PromptCompileFailureKind.invariantViolation,
      );
    }
    final sources = <PromptSource>[];
    switch (mode) {
      case PromptCompileMode.normal:
        final current = turns.last;
        if (current.turn.role != TavernTurnRole.player ||
            (targetTurnId != null && targetTurnId != current.turn.id)) {
          throw const PromptCompileFailure(
            PromptCompileFailureKind.invariantViolation,
          );
        }
        for (var i = 0; i < turns.length - 1; i++) {
          sources.add(_source(turns[i], PromptSourceType.history, i));
        }
        sources.add(_source(current, PromptSourceType.userInput, turns.length));
      case PromptCompileMode.regenerate:
        final target = turns.indexWhere((item) => item.turn.id == targetTurnId);
        if (target <= 0 ||
            turns[target].turn.role != TavernTurnRole.character) {
          throw const PromptCompileFailure(
            PromptCompileFailureKind.invariantViolation,
          );
        }
        var userIndex = -1;
        for (var i = target - 1; i >= 0; i--) {
          if (turns[i].turn.role == TavernTurnRole.player) {
            userIndex = i;
            break;
          }
        }
        if (userIndex < 0) {
          throw const PromptCompileFailure(
            PromptCompileFailureKind.invariantViolation,
          );
        }
        for (var i = 0; i < target; i++) {
          if (i == userIndex) continue;
          sources.add(_source(turns[i], PromptSourceType.history, i));
        }
        sources.add(
          _source(
            turns[userIndex],
            PromptSourceType.userInput,
            userIndex,
            placement: PromptPlacementKind.atHistoryDepth,
            depth: target - userIndex - 1,
          ),
        );
      case PromptCompileMode.continueTurn:
        final target = turns.indexWhere((item) => item.turn.id == targetTurnId);
        if (target < 0 || turns[target].turn.role != TavernTurnRole.character) {
          throw const PromptCompileFailure(
            PromptCompileFailureKind.invariantViolation,
          );
        }
        for (var i = 0; i < target; i++) {
          sources.add(_source(turns[i], PromptSourceType.history, i));
        }
        sources.add(
          _source(turns[target], PromptSourceType.continuation, target),
        );
    }
    return PromptHistoryAssembly(mode, List.unmodifiable(sources));
  }

  PromptSource _source(
    TavernTurnProjection projection,
    PromptSourceType type,
    int order, {
    PromptPlacementKind? placement,
    int depth = 0,
  }) {
    final turn = projection.turn;
    final alternative = projection.selectedAlternative;
    return PromptSource(
      id: '${type.name}:${turn.id}:${alternative.id}',
      type: type,
      origin: PromptOrigin('turn', turn.id, parentId: alternative.id),
      role: switch (type) {
        PromptSourceType.userInput => PromptRoleIntent.userLike,
        PromptSourceType.continuation => PromptRoleIntent.assistantLike,
        _ => switch (turn.role) {
          TavernTurnRole.player => PromptRoleIntent.userLike,
          TavernTurnRole.character ||
          TavernTurnRole.narrator => PromptRoleIntent.assistantLike,
          _ => PromptRoleIntent.context,
        },
      },
      placement: PromptPlacement(
        placement ??
            (type == PromptSourceType.history
                ? PromptPlacementKind.history
                : PromptPlacementKind.tail),
        depth: depth,
      ),
      atoms: List.unmodifiable(projection.selectedParts.map(_atom)),
      order: order,
      required: type != PromptSourceType.history,
      budgetClass: type == PromptSourceType.history
          ? PromptBudgetClass.history
          : PromptBudgetClass.grounding,
    );
  }

  PromptAtom _atom(TavernContentPart part) => PromptAtom(
    id: part.id,
    kind: switch (part.kind) {
      TavernContentKind.text => PromptAtomKind.text,
      TavernContentKind.reasoning => PromptAtomKind.reasoning,
      TavernContentKind.reasoningSummary => PromptAtomKind.reasoningSummary,
      TavernContentKind.reasoningUnavailable =>
        PromptAtomKind.reasoningUnavailable,
      TavernContentKind.toolCall => PromptAtomKind.toolCall,
      TavernContentKind.toolResult => PromptAtomKind.toolResult,
      TavernContentKind.attachment => PromptAtomKind.attachment,
      TavernContentKind.event => PromptAtomKind.event,
      TavernContentKind.unknown => PromptAtomKind.unknown,
    },
    text: part.text,
    toolName: part.toolName,
    toolCallId: part.toolCallId,
    arguments: part.arguments,
    result: part.result,
    error: part.error,
    assetReference: part.assetReference,
    mimeType: part.mimeType,
  );
}
