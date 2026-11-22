# Repository and state ownership

`TavernRepository` is the production boundary. `SQLiteTavernRepository` persists it; `InMemoryTavernRepository` exercises the same basic semantics in unit tests. Callers can create/load Session, add/list Participant, create/select/archive Story Line, append Turn with initial Alternative and optional Attempt, add/select/delete Alternative, append typed Content Part, record/update/list Attempts, load a transcript projection, and archive/delete Session. A new Alternative and its first Attempt can be added atomically; retries on an existing Alternative use a new Attempt.

The repository owns canonical selection, branch lineage, content and generation status. A future Provider adapter will be passed a target `(sessionId, storyLineId, turnId, alternativeId, attemptId)` and append Parts/update status through this boundary. A future Prompt Compiler will read projections and assets, not issue SQL from UI. No Provider-specific enum or HTTP behavior appears here.

Generation status is provider-independent: queued, preparing, running, streaming, cancelled, failed, completed. Terminal states cannot transition; retries get a new Attempt with a new position. Generation type records normal, regenerate, alternative, continue, impersonate, group or quiet intent, without implementing those behaviors. Provider/model references are identifiers, not credentials.

Content Parts may reference the Attempt that produced them. Transcript projection keeps unowned/manual Parts and Parts from the latest completed or in-progress Attempt, excluding failed/cancelled partial output without deleting its history. Unknown future Part kinds roundtrip with their source kind intact; they are not treated as visible text.

The in-memory repository is intentionally test-only and is not connected to Legacy World, Novel or Chat. Its maps are inspectable fixture state; production code should use the interface, not mutate maps. This phase does not expose a new Tavern user route.
