# Recovery and invariants

On startup, before new work begins, the app-scoped Runtime owner calls `recoverInterrupted()` once. It finds queued/preparing/running/streaming Attempts and marks them failed with stable reason `runtime_restart`. Existing partial Parts remain stored and hidden from the normal transcript. Repeated recovery is a no-op. The shared scope registry rejects recovery while another Runtime is generating against that repository scope; UI pages and Provider adapters never call recovery.

- One Attempt has one terminal outcome. Terminal status never reopens.
- Late or wrong-attempt events never mutate terminal or unrelated content.
- Retry creates an Attempt, not an Alternative. A failed Continue retried on the same Alternative retains Continue provenance and appends to earlier successful content. Regenerate creates an Alternative, not a Story Line. Continue adds an Attempt to the selected Alternative and preserves each Part's Attempt provenance.
- The five target IDs never follow the currently viewed or active Story Line.
- Failed/cancelled partial Parts never leak into selected transcript content. A failed Continue cannot remove earlier completed content.
- Final Parts, completed status and successful selection commit atomically.
- Successful Regenerate/Retry selects only if the previous selection still matches the start-time selection. A user's intervening selection is not overwritten. Continue never selects and cannot follow a new UI selection.
- A Runtime is app-scoped; the shared same-process registry rejects duplicate active generation for a Session even if a second Runtime is constructed. Separate Sessions can generate concurrently. No cross-process lock exists.
- The normalized driver cannot own Tavern Session, Turn, Alternative or selection mutations.

SQLite and in-memory contract tests cover lifecycle, cancellation/completion races, late events, timeout, duplicate start, same/different Session concurrency, restart recovery, large delta batching, and archive semantics. The Phase 5 first-contact UX gate remains **BYPASSED BY PRODUCT DECISION**, not validated by these runtime tests.
