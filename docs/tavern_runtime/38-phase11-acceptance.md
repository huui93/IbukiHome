# Phase 11 acceptance evidence

> Historical acceptance record. Versions and results below describe this checkpoint. [Current Android release](../../README.en.md)

Phase 11 Code / Offline Gate: **APPROVED** after final acceptance and critical invariant audit. Freeze reference: annotated tag `mobile-tavern-durable-reconciliation-v1-approved`. This is a technical freeze, not real-model or Android experience approval. No Production Tavern UI or real Provider request in this phase; not merged.

## Baseline

- Parent: `510557107559dee6c0e4eae454ca86335b26fc62`.
- Tag: `mobile-tavern-provider-adapter-v1-approved`.
- Worktree: `<workspace>`.
- Branch: `feature/mobile-tavern-durable-reconciliation-v1`.
- Parent tests: 1586. No existing test deleted or skipped to obtain passing quality gates.
- SQLite v13 -> v14; two new tables only. No dependency/app-version change.

## Focused evidence

`tavern_durable_reconciliation_test.dart` and `sqlite_tavern_world_info_migration_test.dart`: 42 implementation tests plus 2 final-acceptance tests, all passed in the final complete suite. Coverage includes ten crash windows, deterministic replay/ten-time idempotency, stale/identity conflicts across reopen, root gating/retry, compiler-drop filtering, entry lifecycle and stable definition digests, Session isolation, exact historical/nested forks, archive-file fresh restore/collision merge/rollback, missing journal, missing-plan repository parity, replay-integrity blocking and stale last-commit restore rejection.

The v13 fixture is actually opened as schema 13 and records every pre-existing table before upgrade. Upgrade comparison finds no changed rows. Fresh v14 has ten total Tavern tables (eight existing + two new). Injected upgrade failure retains v13 and its old data. Repeat reopen retains provenance; legacy historical forks explicitly mark unavailable state.

## Final critical audit

- Atomic terminal: `SQLiteTavernRepository.persistGenerationBatch` owns the transaction for final content parts, completed Attempt, conditional Alternative selection and `_SQLiteTavernWorldInfo(txn).settle`. State CAS and journal outcome use that same `txn`. Trigger-aborted terminal/ledger writes roll back the whole batch; reopen does not preserve half-successful replies.
- Pre-request preparation: Normal, Regenerate, Retry and Continue pass the typed plan through the existing `appendTurn` / `addAlternative` / `recordAttempt` transaction. `TavernGenerationRuntime.start` awaits `_prepare` before `_run` can call the Driver. Plan INSERT failure prevents HTTP and rolls back creation.
- Mixed recovery: the added five-Session SQLite test stores A committed, B completed/pending, C failed, D cancelled and E conflicted. Dispose/close/reopen and repeated root recovery preserve A, reconcile B once, never advance C/D, keep E blocked and leave other Sessions ready. It compares the whole logical snapshot before/after repeated recovery and verifies 0 fixture HTTP requests and clean FK checks.
- Continuous migration: the added real v12 -> v13 -> v14 test preserves every old table's rows, including actual Novel text, Chat reply, Character/WorldCard, Legacy World prompt/session state and plugin/storage values. It creates an existing Tavern Session on the actual v13 intermediate database, preserves it through v14, marks its state `legacyUnavailable`, round-trips the logical archive and verifies repeated reopen does not seed duplicates. Existing direct v12-to-latest and failure rollback tests remain intact.
- Root: existing tests prove one non-autoDispose execution owner and one cached initialization Future; recovery failure never uses an empty fallback, and controlled retry sends no HTTP. Reconciliation only reads canonical Attempts and typed deltas, not the model transcript or new random rolls.
- Historical state, lifecycle, FK/uniqueness, invalid compile identity, stale version and archive remapping were audited against production implementations and existing semantic assertions. No additional product fix or schema expansion was needed during acceptance.

## Performance sample

Host measurements, not device/UI performance claims:

- 1000 committed journal deltas: batch reconciliation 64 ms; reopen root recovery 79 ms.
- 1000 independent scope snapshots (1001 including the seeded scope): 20 ms recovery.
- Journal JSON: 1,354,527 bytes for 1000 generations.
- Compressed full archive: 425,250 bytes; canonical-only size-comparison archive: 173,777 bytes; incremental durable data: 251,473 bytes.

The canonical-only archive is a synthetic size comparison, not a valid replacement for a full v14 backup. Journal history markers remain 64 characters as history grows. Plans store changed/removed timers, not full copies of State or all prior text. Bulk recovery uses bounded set-based reads and local replay, not a database query per completed journal. No aggressive pruning of history needed for historical forks is implemented.

Preparation adds the journal to the existing initial creation transaction. Successful settlement adds State/journal writes to the existing terminal batch transaction: no new standalone write transaction is needed per successful generation. The Orchestrator's completion observer performs an idempotent repository verification transaction and reloads the mirror; the committed path makes no further State/Journal writes. Streaming partial batches keep their existing transaction semantics.

The large test intentionally performs 1000 real creation/terminal transactions plus two archive builds. One intermediate implementation run exceeded the default 30-second test budget during fixture/archive construction. Its timeout is explicitly two minutes; no assertion was removed, no test was skipped and no product timeout changed. Final freeze verification passed all 1630 tests in 1 minute 53 seconds. Measured recovery intervals above are separate from fixture construction and are not Android performance guarantees.

## Final quality

- `dart format .`: 442 Dart files formatted; final verification changed 0 files.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub --concurrency=2`: 1630/1630 PASS (1586 parent + 42 implementation + 2 acceptance).
- `git diff --check`: PASS.
- Untracked whitespace: 16 files, 0 issues.
- High-confidence secret scan: 529 tracked/new text files, 0 hits; findings never print secret values.
- `pubspec.yaml` / `pubspec.lock`: unchanged; app version remains `1.0.0+1`.
- Before freezing, the validated snapshot contained 20 modified + 16 untracked Phase 11 product/test/documentation files. No temporary logs, cache or build artifacts are part of the commit.

Generation Runtime, Prompt Compiler, World Info, Provider offline fixtures/E2E, Archive, Plugin, Novel, Chat and Legacy World regressions all pass in that full suite.

## Scope and limitations

- Live Provider Smoke: **NOT RUN**. All transports in tests are offline fixtures.
- Device Smoke: **NOT RUN**. SQLite fault injection/reopen is not Android process-kill or UI acceptance.
- No protected emulator/device operations; no AVD smoke was required for these repository-only tests.
- v13 historical timers cannot be recovered and are explicitly initialized with unavailable provenance.
- No user-facing reconciliation repair UI, automatic corruption reset or full Prompt Inspector history.
- Committed journal retention is deliberate; safe compaction is a future concern, not an unproved deletion policy.
- Phase 5 First-contact UX Gate: **BYPASSED BY PRODUCT DECISION**, not VALIDATED.

## Freeze protocol

Commit subject: `feat(tavern): add durable world info reconciliation v1`.

Annotated tag: `mobile-tavern-durable-reconciliation-v1-approved`.

Verify `git rev-list -n 1 mobile-tavern-durable-reconciliation-v1-approved` equals final HEAD and tag object type is `tag`. Final report records the resulting SHA and confirms tracked/untracked counts are both 0; the commit does not embed its own recursive identity. Retain all earlier approved worktrees and do not merge.

There are no remaining observed code/offline blockers. Phase 12 can start only on a separate formally requested task/worktree from this frozen reference. This acceptance round does not start Production Tavern MVP UI and does not change the three unvalidated/bypassed product facts above.
