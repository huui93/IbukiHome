# Durable reconciliation v1 design

Parent: `510557107559dee6c0e4eae454ca86335b26fc62`. This phase changes consistency only, not Provider, RP selection or UI. Live Smoke stays NOT RUN. Phase 5 UX Gate remains BYPASSED BY PRODUCT DECISION.

## Audit

Phase 10 creates an Attempt, sends HTTP, writes completed content/status, then settles a process-local Ledger. Death after canonical finalization loses the plan/block/timers. Existing SQLite terminal batches and creation bundles already have transactions. The pure World Info evaluator uses process-dependent Object hashes for entry definitions and history markers; these cannot identify durable state across isolates/restarts and must become deterministic digests.

## Minimal coordination

Two v14 tables store a Story Line state and an Attempt-bound journal. After successful preflight/compile, a typed plan is passed through the existing Generation Runtime initialization bundle. Attempt and Journal creation are atomic and precede Driver HTTP. The Journal binds five target IDs, compile/request fingerprints, stable plan identity, expected version/base digest, included entry identities and a predetermined state delta. It contains no prompt/lore body, key or Provider response.

Successful terminal Parts, Attempt status/selection, Journal outcome and State CAS are one repository transaction. Failure/cancellation discards the prepared Journal in that same transaction. Pure evaluation never modifies Attempts. Conflicts preserve completed canonical content but explicitly block that Story Line, including after restart; they do not overwrite newer State.

The persisted history marker is a fixed-length SHA-256 of visible scan text and public role sequence, not the full growing history or an Object hash. It excludes unscanned reasoning/tool payloads and survives canonical ID remapping. Definition fingerprints cover the complete normalized entry definition. Neither digest stores its source text. Application validation rejects malformed fingerprints.

Recovery first marks incomplete Attempts interrupted without HTTP, then reconciles durable journals against canonical terminal status and integrity/version checks. Completed-but-prepared records can be applied once from their recorded delta. Committed repeats are no-ops. Identity/version/integrity conflicts persist; they are never silently reported as success. Recovery readiness gates Tavern generation only; Novel/Chat/Legacy startup is unaffected.

Recovery also replays committed deltas to verify that the current snapshot and last Attempt reference are explained by journal history. An Attempt marked as durable but missing its journal is a structural recovery error. A known line-local conflict blocks its line; an unattributable structural/read failure blocks Tavern readiness until controlled retry succeeds. There is no fallback to an empty ledger and no conflict-bypass switch.

## Historical state

One immutable initial checkpoint per Story Line plus committed journal deltas reconstructs an exact committed historical state. Fork creation and its initial checkpoint are atomic with inherited Alternative selections. Resolve the latest successful journal matching the selected Alternative at the last applicable visible prefix Turn, then replay that line's deltas to its committed version. Never use a later parent snapshot. Nested forks use the same algorithm. Full State is not copied into every journal; deltas retain only changed/removed timers plus scalar transition metadata.

For v13 history, no persisted timers existed: migration seeds version 0 with `legacyUnavailable` provenance, no reroll/replay of old activation. A historical fork with no recorded checkpoint uses explicitly marked `historicalUnavailable` empty initialization. This is a deterministic reset policy, not accurate historical recovery. New histories have recorded checkpoints and deltas. Pending/conflicted origin transitions cannot masquerade as historical checkpoints.

## Risks and scope

SQLite v14 is justified by durable transaction/version/identity semantics, not UI state. Existing tables and Legacy semantics stay unchanged. New data participates in Archive/fresh restore and conflict remapping; opaque historical compile fingerprints stay historical, never regenerated as a fake old Prompt. Timer definitions/history hashes become deterministic. Deleted/edited/unreferenced entries remain subject to existing evaluator pruning. No full Prompt Inspector database, Tool Runtime, Memory/RAG or event-sourcing framework is added.
