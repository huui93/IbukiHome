enum PromptSourceType {
  system,
  character,
  persona,
  scenario,
  worldInfo,
  memory,
  rag,
  exampleDialogue,
  history,
  authorNote,
  userInput,
  postHistory,
  generationInstruction,
  continuation,
}

enum PromptRoleIntent { systemLike, userLike, assistantLike, context }

enum PromptPlacementKind {
  beforeCharacter,
  afterCharacter,
  beforeHistory,
  history,
  atHistoryDepth,
  afterHistory,
  tail,
}

class PromptPlacement {
  const PromptPlacement(this.kind, {this.depth = 0});
  final PromptPlacementKind kind;
  final int depth;
}

enum PromptAtomKind {
  text,
  reasoning,
  reasoningSummary,
  reasoningUnavailable,
  toolCall,
  toolResult,
  attachment,
  event,
  unknown,
}

class PromptAtom {
  const PromptAtom({
    required this.id,
    required this.kind,
    this.text,
    this.toolName,
    this.toolCallId,
    this.arguments,
    this.result,
    this.error,
    this.assetReference,
    this.mimeType,
  });
  final String id;
  final PromptAtomKind kind;
  final String? text, toolName, toolCallId, error, assetReference, mimeType;
  final Map<String, Object?>? arguments, result;
}

class PromptOrigin {
  const PromptOrigin(this.type, this.id, {this.parentId, this.label});
  final String type, id;
  final String? parentId;
  final String? label;
}

enum PromptInspectionVisibility { normal, sensitive, hidden }

enum PromptBudgetClass { grounding, history, supplemental }

class PromptSource {
  const PromptSource({
    required this.id,
    required this.type,
    required this.origin,
    required this.role,
    required this.placement,
    required this.atoms,
    this.priority = 0,
    this.order = 0,
    this.required = false,
    this.budgetClass = PromptBudgetClass.supplemental,
    this.visibility = PromptInspectionVisibility.normal,
  });
  final String id;
  final PromptSourceType type;
  final PromptOrigin origin;
  final PromptRoleIntent role;
  final PromptPlacement placement;
  final List<PromptAtom> atoms;
  final int priority, order;
  final bool required;
  final PromptBudgetClass budgetClass;
  final PromptInspectionVisibility visibility;
}

enum PromptCompileMode { normal, regenerate, continueTurn }

enum ReasoningPromptPolicy { exclude, summaryOnly, include }

enum ToolPromptPolicy { exclude, structured }

enum AttachmentPromptPolicy { exclude, reference }

class PromptCompileConstraints {
  const PromptCompileConstraints({
    required this.maxContextTokens,
    required this.reservedOutputTokens,
    this.reservedControlTokens = 0,
    this.reasoningPolicy = ReasoningPromptPolicy.exclude,
    this.toolPolicy = ToolPromptPolicy.exclude,
    this.attachmentPolicy = AttachmentPromptPolicy.exclude,
  });
  final int maxContextTokens, reservedOutputTokens, reservedControlTokens;
  final ReasoningPromptPolicy reasoningPolicy;
  final ToolPromptPolicy toolPolicy;
  final AttachmentPromptPolicy attachmentPolicy;
  int get usableInputTokens =>
      maxContextTokens - reservedOutputTokens - reservedControlTokens;
}

class PromptCompileInput {
  const PromptCompileInput({
    required this.sources,
    required this.constraints,
    this.mode = PromptCompileMode.normal,
  });
  final List<PromptSource> sources;
  final PromptCompileConstraints constraints;
  final PromptCompileMode mode;
}

class CompiledPromptSegment {
  const CompiledPromptSegment({
    required this.sourceId,
    required this.origin,
    required this.role,
    required this.atoms,
    required this.tokenEstimate,
    this.continuation = false,
  });
  final String sourceId;
  final PromptOrigin origin;
  final PromptRoleIntent role;
  final List<PromptAtom> atoms;
  final int tokenEstimate;
  final bool continuation;
}

enum PromptCompileOutcome { included, trimmed, dropped, rejected }

enum PromptCompileReason {
  included,
  required,
  empty,
  policyExcluded,
  sourceTooLarge,
  budgetExhausted,
  historyTrimmed,
  invalid,
}

class PromptCompileDecision {
  const PromptCompileDecision({
    required this.inputIndex,
    required this.sourceId,
    required this.sourceType,
    required this.origin,
    required this.role,
    required this.placement,
    required this.priority,
    required this.visibility,
    required this.outcome,
    required this.reason,
    required this.estimatedTokens,
    required this.excludedAtomIds,
    this.finalIndex,
  });
  final int inputIndex;
  final String sourceId;
  final PromptSourceType sourceType;
  final PromptOrigin origin;
  final PromptRoleIntent role;
  final PromptPlacement placement;
  final int priority;
  final PromptInspectionVisibility visibility;
  final PromptCompileOutcome outcome;
  final PromptCompileReason reason;
  final int estimatedTokens;
  final List<String> excludedAtomIds;
  final int? finalIndex;
}

class PromptCompileTrace {
  const PromptCompileTrace({
    required this.maxContextTokens,
    required this.reservedOutputTokens,
    required this.reservedControlTokens,
    required this.usableInputTokens,
    required this.usedInputTokens,
    required this.decisions,
  });
  final int maxContextTokens,
      reservedOutputTokens,
      reservedControlTokens,
      usableInputTokens,
      usedInputTokens;
  final List<PromptCompileDecision> decisions;
}

class CompiledPrompt {
  const CompiledPrompt({
    required this.mode,
    required this.segments,
    required this.trace,
  });
  final PromptCompileMode mode;
  final List<CompiledPromptSegment> segments;
  final PromptCompileTrace trace;
}

enum PromptCompileFailureKind {
  invalidConstraints,
  invalidSource,
  invalidInsertion,
  requiredOverflow,
  tokenCounterFailure,
  invariantViolation,
}

class PromptCompileFailure implements Exception {
  const PromptCompileFailure(this.kind, {this.sourceId});
  final PromptCompileFailureKind kind;
  final String? sourceId;
  @override
  String toString() => 'PromptCompileFailure(${kind.name}, source: $sourceId)';
}
