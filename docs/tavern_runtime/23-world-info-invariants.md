# World Info Runtime invariants

1. Activation and prompt compilation are separate; activation never performs final token budgeting.
2. The scan builder consumes Foundation projection, not raw Story Line rows. It cannot see unselected Alternatives or failed/cancelled partials.
3. With identical context, entry set, state and keyed random source, activation, trace and prompt sources are deterministic.
4. Every provided entry receives one typed decision. Every active composite ID emits at most one Prompt Source per cycle.
5. Recursion has a visited guard and a finite pass limit. Group and probability outcomes stay stable during later passes.
6. Disabled, deleted, edited and book-disabled entries cannot leave active timer state. State never crosses session/story-line boundaries implicitly.
7. Sticky, cooldown and delay use explicit message-count intervals. Evaluation is pure; an attempt-bound plan can be settled once only after a completed generation and matching compiler trace. Duplicate completion is a no-op; a stale base version is rejected. Preview/failure/cancel do not advance state.
8. World Info emits typed provider-neutral sources with stable origin. It does not touch Provider, Generation Runtime, DB, network, tool execution, Macro, Regex, Memory or RAG.
9. Activation Trace records reasons, not lore bodies; Compile Trace independently explains final prompt inclusion.
10. SQLite remains v13; transient timed effects intentionally reset on restart in v1.
11. Story Line state is isolated. A child receives an explicit parent snapshot at its branch point or starts empty; it never reads a mutable parent state implicitly.
12. Activation is eligibility. Only entries actually included or trimmed into the compiled prompt can start or retain timed effects. The activation and compile traces stay separate.
13. Disabled, deleted, edited or book-disabled entries prune old effects before scanning. A changed enabled constant may immediately activate anew, starting a fresh timer.
14. World Info does not perform Provider calls or final budgeting; the Prompt Compiler does not import World Info matching rules.
