# Recovery and crash matrix

## Readiness order

1. Open/migrate SQLite.
2. Generation Runtime recovers nonterminal Attempts as interrupted failures; retained partials are not successful visible output.
3. Reconcile Journal with canonical Attempt identity/status and version/base fingerprint.
4. Verify snapshot against committed delta history and last Attempt reference.
5. Load the requested scope into the pure planning mirror and allow generation.

No step sends HTTP, resolves new sources, recompiles an old Prompt or rolls Probability/Group decisions. A read/structural error rejects readiness. `retryRecovery()` is an application-only quiescent retry, not a generation retry. A durable line conflict survives root disposal/recreation and rejects subsequent generation on that line; unrelated valid lines remain usable.

## Outcomes

`prepared` means the canonical Attempt and frozen plan were created atomically before network. A failed/cancelled terminal becomes `discarded`, without changing State. A completed Attempt with valid CAS applies its predetermined delta and becomes `committed`. A target/digest/version/integrity mismatch becomes `conflict`, preserving canonical successful text rather than silently overwriting another State.

Committed/discarded repeats verify their canonical terminal identity before returning unchanged. Completed-but-prepared recovery requires the exact expected base. A newer version is a conflict, not permission to apply again. Repair must restore a provably valid identity/base and use the repository reconciliation API; there is no UI repair console or unsafe automatic reset in this phase.

## Fault matrix evidence

Tests: `test/application/tavern_durable_reconciliation_test.dart`. SQLite triggers inject real transaction failures; isolated database reopen and coherent snapshot images simulate process loss. Tests do not claim literal OS termination at every window.

| Window | Persisted / recovered outcome | State and request behavior |
| --- | --- | --- |
| Before plan persistence | Journal INSERT failure rolls back initial Attempt bundle | No isolated object, no HTTP, version 0 |
| Prepared before HTTP | Interrupted Attempt -> failed, journal discarded | Version 0; no request sent/replayed |
| Streaming | Interrupted Attempt -> failed; partial retained but not treated as successful transcript | Version 0; no automatic retry |
| Provider completion before terminal tx | Attempt update trigger aborts finalization | Whole terminal batch rolls back; interruption recovery discards plan |
| Terminal saved but application absent | Controlled Case C image: completed Attempt + prepared journal + expected base | Recorded delta commits once, ten repeated reconciliations unchanged |
| During ledger transaction | Journal commit trigger aborts terminal batch | Attempt/parts/selection/State all roll back together |
| Ledger committed before notification | Observer throws after atomic repository commit | Completed/committed survive reopen; no duplicate application |
| App shutdown | Existing cancellation/drain lifecycle | Cancelled/discarded; no State advancement |
| Archive during finalization | SQLite snapshot transaction serializes with terminal transaction | Coherent before/after image, no half-state archive |
| Restore conflict merge | Journal INSERT trigger aborts restore | All imported collections rolled back; KEEP-ME unchanged |

Case C is defensive coverage for a split-commit image. Normal v14 SQLite successful terminal writes cannot tear between Attempt and World Info application: they share one transaction. Genuine identity/version corruption remains explicitly blocked, including after reopen.

Missing marked journals are structural errors. Malformed attributable journals and current-state replay mismatches are line conflicts when enough trustworthy ownership remains. A missing state is never silently re-seeded as fresh.
