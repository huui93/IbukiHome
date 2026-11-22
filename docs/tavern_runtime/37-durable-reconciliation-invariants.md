# Durable reconciliation invariants

1. World Info evaluation is pure; it cannot modify canonical Attempts.
2. A formal Orchestrator request persists its Attempt-bound typed plan in the initial creation transaction before chargeable transport starts.
3. A plan binds Session, Story Line, Turn, Alternative and Attempt plus compile/request/plan fingerprints and exact base State version/hash.
4. Successful terminal status, final content/selection, delta application and journal outcome share one SQLite transaction. A transaction exception does not preserve a half-successful durable result.
5. Failed/cancelled/interrupted Attempts discard plans without advancing timers. Preflight/compile failures create no isolated generation objects.
6. Only compiler-included eligible entries receive activation timer changes. Activation trace alone is not commit authority.
7. Commit idempotency uses unique Attempt/line-version constraints and exact CAS, not a process-local flag. Repeated successful reconciliation does not reduce sticky, restart cooldown or increment delay again.
8. Recovery trusts recorded deterministic deltas, never new randomness, recompiled Prompt, automatic retry or HTTP replay.
9. Identity/base/history conflicts are explicit and durable. A conflicting line cannot continue generation; unrelated valid scopes are not unconditionally blocked. Structural uncertainty rejects root Tavern readiness.
10. Current State must be explained by its immutable initial checkpoint and committed delta sequence, including its last Attempt reference. Missing marked journals or missing state never become silent fresh defaults.
11. Timer identity is `(Book ID, Entry ID)`. Definition fingerprints are stable SHA-256 across processes; changed/disabled/deleted/unreferenced definitions are pruned by existing evaluation before future activation. Historical timers cannot invent active source entries.
12. A historical fork uses the selected inherited Alternative's recorded checkpoint, never a parent's latest State. Nested forks preserve Foundation frozen-selection semantics.
13. v13 provenance says historical state was unavailable; empty initialization is a documented reset policy, not a claim to restore nonexistent history.
14. Archive identity remapping preserves lineage, ownership, base-chain consistency, original request provenance and outcomes. Restore failures roll back existing data intact.
15. Canonical durable data excludes view state, credentials and unnecessary body/Prompt copies. Transient planning mirrors and traces are not authoritative across restart.
16. SQLite and deterministic in-memory repositories implement the same contract; SQLite fault/reopen tests are required evidence of real transaction behavior.

Legacy/manual Foundation operations without a World Info plan remain valid. They do not create fictional activation history. Formal generation uses `TavernGenerationOrchestrator.start` and requires the durable repository capability.

Phase 5 First-contact UX Gate remains **BYPASSED BY PRODUCT DECISION**, not VALIDATED. Technical durability tests do not change that product fact. Live Provider Smoke remains **NOT RUN** without explicit authorization.
