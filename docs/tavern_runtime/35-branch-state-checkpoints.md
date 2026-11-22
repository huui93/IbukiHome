# Historical branch state checkpoints

## Exact recorded histories

A Story Line keeps one immutable initial checkpoint and a current snapshot. Each successful eligible Attempt records a delta and a unique increasing local committed version. Replay starts at version 0 and verifies every expected version/base hash; it never reruns activation.

Foundation still freezes the selected Alternative at each inherited Turn. Fork creation traverses that visible inherited prefix backwards, finds the latest committed Attempt for the selected Alternative and reconstructs the originating line's state at that committed version. The child stores the result as its initial/current version-0 checkpoint, provenance `forkCheckpoint`, and `initialAttemptId` referencing the historical source.

Creating from Turn 20 after Main has reached Turn 50 uses S20, not S50. Parent later changes Alternative selection do not change child history or timers. Nested A -> A2 repeats the same lookup and can resolve an ancestral Main checkpoint or a later A checkpoint. Pending/conflicted transitions cannot be used as successful fork checkpoints.

Tests cover both SQLite and in-memory stores, the historical Turn20/Turn50 case, changed parent selection, nested forks, reopen, fresh restore and collision merge.

## Legacy / unavailable histories

v13 never persisted these timers. Upgrade establishes an explicitly empty version-0 baseline with `legacyUnavailable`. Continuing creates new trustworthy journal history from that baseline; this does not reconstruct old timers or reroll old random outcomes.

A fork before any available recorded transition initializes empty state with `historicalUnavailable` when its parent was not a wholly fresh history. `initialAttemptId` is null. Fresh manual-only history can use `fresh` empty initialization. Both policies are deterministic and visible through typed provenance; neither copies a later parent State and pretends it existed at an earlier Turn.

## Retention

Keep committed deltas while history can participate in fork/reconciliation/archive. Ordinary successful generations do not duplicate full state snapshots in journals. Each child needs one real checkpoint. No compaction/garbage-collection engine is introduced; unsafe deletion of retained durable history is restricted. Session deletion removes the owned ledger, never global assets.
