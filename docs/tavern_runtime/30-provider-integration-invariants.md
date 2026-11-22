# Provider integration invariants

1. Provider Adapter never writes Tavern or Legacy domain state.
2. Existing Generation Runtime alone creates and finalizes generated Turns, Alternatives, Content Parts and Attempts.
3. Prompt Compiler alone performs final source ordering and budgeting. Reference wrappers are counted before it runs.
4. World Info Runtime alone matches/activates lore; Native source resolution only restricts authorized candidates.
5. Serialization preserves compiled order. Unsupported role placement or continuation fails explicitly.
6. Provider/model capabilities are explicit; names are not a feature detector. Unknown models use conservative settings.
7. Visible text, returned native reasoning, returned summary and unavailable semantics remain separate.
8. Tools and multimodal execution are unsupported in v1; no Tool Result is invented.
9. Cancel/dispose abort request-owned transport; late output cannot mutate terminal Attempts.
10. Duplicate command does not create another chargeable request. Network failure does not auto-retry.
11. Preflight finishes before Runtime creation and HTTP. Failure leaves old selection unchanged.
12. Ledger submission is bound to canonical Attempt and held compiled/request identity, independent of displayed Story Line.
13. Completed generation plus failed Ledger settlement is explicit and requires safe reconciliation before more work on that line.
14. Source trust is not promoted by imported text claiming SYSTEM. Hidden Persona and metadata stay excluded.
15. Credentials remain in the existing secure store and temporary request memory, never in story rows, archives, traces or test snapshots.
16. Core tests are offline; live smoke is explicitly opt-in and must be reported separately.
17. SQLite stays v13 and Archive format is unchanged. Timers/traces remain transient; no cross-crash atomicity is claimed.
18. Empty returned reasoning text and Gemini signature-only parts do not establish reasoning availability; no content is fabricated.
19. Chat's natural `stop` and Gemini's native `STOP` are validated separately. DeepSeek/Gemini cannot claim the OpenAI developer message role.
20. Cancel after canonical finalization has begun may lose to completion; exactly one persisted terminal outcome is authoritative. Late cancellation does not replace it.

## Explicit restart limitation

Ledger plans, timed state, settlement deduplication, unresolved plans, blocking flags and traces are process-local. A completed canonical Attempt survives restart, but its failed Ledger settlement cannot be identified or retried by a newly created owner. The previous Story Line block is lost and further generation is possible. Sticky/cooldown consistency and replay protection across a crash are not guaranteed. The acceptance test deliberately demonstrates this limitation rather than asserting a false recovery guarantee.

This is a recorded product risk that must be resolved before a playable production release, not a claim of durable orchestration. SQLite v13 has no durable settlement journal in this phase. Archive comparisons cover canonical records only. A separately scoped durable reconciliation design is needed; no v14 or hidden persistence is added here.

The additive Runtime changes are limited to summary/unavailable Driver events, existing Attempt provider/model fields and safe failure reason codes. Normal/Retry/Regenerate/Continue, selection, batching and transaction rules are unchanged. The additive Ledger type check accepts Foundation's existing `alternative` type for regenerate. Phase 5 First-contact UX Gate remains **BYPASSED BY PRODUCT DECISION**, not VALIDATED.
