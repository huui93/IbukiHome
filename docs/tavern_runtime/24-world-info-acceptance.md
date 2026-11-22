# World Info acceptance: settlement and restart policy

## Application boundary

The future generation orchestrator owns one `WorldInfoAttemptLedger` per running application. It loads an authorized Foundation Story Line projection and selected books, then calls `prepare` with a nonterminal `TavernGenerationAttempt`. The ledger evaluates against the latest state of that attempt's `(sessionId, storyLineId)` and records its base revision. The caller passes the returned sources to Prompt Compiler. A compile failure or Provider start failure must settle the attempt as failed; a user stop settles it as cancelled. Streaming partials are not scanned by the next attempt.

On the canonical terminal outcome, the caller supplies the Foundation attempt and compiled prompt to `settle`. Only `completed` can commit. The ledger checks attempt identity (attempt, session, Story Line, Turn, Alternative), compiler source origins and outcomes, and the base revision. Duplicate terminal notification is a no-op. A plan that loses a race against a newer completed plan returns `stale` and cannot overwrite state. The orchestration layer must re-evaluate if it intends to generate from the new state. A completed attempt lacking a matching compiled prompt cannot commit. This in-memory boundary does not claim atomic durability across process death; no Generation Runtime or repository contract was changed in Phase 9.

The keyed `SeededWorldInfoRandom` is stateless; repeated evaluation, preview, failure and retry with the same inputs produce the same group/probability outcomes. The orchestrator chooses and retains the seed for a generation attempt. A future non-keyed random source must be snapshotted per attempt rather than shared with dry runs. The ledger is not a Provider adapter and does not perform a network call.

## Activation versus model-visible inclusion

World Next policy: group/probability/recursion determine activation eligibility, but **only activated entries with an `included` or `trimmed` Prompt Compiler outcome advance sticky/cooldown timing**. Compiler-dropped entries remain visible in Activation Trace and show a separate budget-drop reason in Compile Trace. Their timers do not begin; an existing sticky timer dropped this cycle is removed. `WorldInfoRuntime.evaluate` by itself does not know compiler outcomes, so callers must not persist its raw `nextState` directly. This differs intentionally from SillyTavern's integrated World Info budget pipeline and avoids claiming that the model saw lore that was dropped. An activated entry's content may have influenced recursive eligibility before the compiler drops that entry; this remains a known v1 limitation and is visible in the two traces.

## Timed effects and branches

Delay counts projected visible messages, not failed attempts. Activation at message M gives sticky through M+N and cooldown through M+N+C. Sticky bypasses keyword and probability rerolls, but never disabled/scope checks. Cooldown also blocks recursive reactivation. Regenerate uses its pruned Foundation projection; a replaced history marker at the same count invalidates old timers. Retry from a failed/cancelled attempt evaluates from the unchanged committed state. Repeated callback does not increment the ledger revision twice.

Each `(sessionId, storyLineId)` has its own revision and timed map. A new child Story Line **does not automatically inherit the currently viewed parent state**. At creation, the application explicitly seeds it from a parent state snapshot taken at the branch point via `forkAt`, or leaves it empty when no such snapshot is available. Nested branches follow the same rule. A snapshot from after the branch point is not a valid substitute for the origin snapshot. UI selection has no role in state identity.

Editing any entry definition resets that entry's previous effect; a still-eligible entry can immediately activate anew. Disabling the entry or its book, and deleting it, prune its timer and prevent a Prompt Source. Composite `(bookId, entryId)` prevents reuse of a similarly named entry in another book. Re-enabling starts from an ordinary fresh evaluation, not paused timing.

## World Info State Persistence v2 proposal

**Current v1 behavior:** the ledger is in memory. Process restart restores no sticky/cooldown state and does not reconstruct it from transcript; a new evaluation may choose a different result if the seed or source set changes. There is no ghost timer. This is a **medium product-consistency risk** for interrupted long-running stories, but not a v13 data-corruption risk. v1 does not claim SillyTavern restart parity.

Before adding persistence, define a durable per-Story-Line revision, committed attempt ID, entry definition signature, timer activation message count, source-set/seed identity and branch-origin snapshot. A transaction must atomically record successful Generation Attempt settlement and the World Info state revision, with a uniqueness constraint on attempt ID and compare-and-swap on prior revision. Archive/restore and conflict merge must preserve attempt identity and branch lineage without reviving deleted or edited entries. Migration from v13 and crash-recovery tests are prerequisites. **No v14 schema is introduced in this phase.**

## Input trust and next-phase contract

The caller resolves authorized Lorebook references and supplies only the current Story Line projection and knowledge-safe character/persona scan fields. Unselected Alternatives, failed/cancelled partials, Reasoning and hidden metadata are excluded by default; Tool Result text is opt-in. Matching on untrusted chat/import/tool text does not elevate that text to a trusted System instruction. PromptSource role and placement are explicit and still subject to Prompt Compiler validation. The Provider Adapter receives compiled prompt material, not activation rules or an Activation Trace. A future orchestrator must own the plan until the canonical attempt becomes terminal and must never commit on compile failure, Provider startup failure, cancellation, or stale revision.
