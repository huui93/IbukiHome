# Compile trace

Every successful compile emits one decision per candidate: included, trimmed (whole old History Turn), or dropped, with typed reason, source type and origin, role intent, placement/depth, priority, visibility, estimated tokens, excluded atom IDs and final index when included. The header records maximum context, output/control reservation, usable input and estimated use. An Inspector can render groups, order and “why excluded?” without reverse-engineering a string prompt. Source bodies are deliberately absent from diagnostics.

Decisions are returned in stable source-ID order. Each decision also has an `inputIndex`, which records candidate order independently of `finalIndex`; the Inspector can reconstruct either view. Per-type token totals are sums over included decisions, not a second tokenization pass. A failed compile yields only a typed exception, so no successful-looking trace or Provider request escapes from an invalid input.

Invalid sources, insertion requests, constraints, required overflow and counter failures produce typed `PromptCompileFailure`; a failed compile produces no Provider request. The exception contains a kind and source ID, never the rejected content. `rejected` is reserved in the outcome model for a future preview that renders invalid candidates rather than failing compilation. Token estimates remain estimates until a Provider capability/tokenizer layer supplies exact accounting.

The trace is ephemeral in v1. It is not stored in SQLite or exported by archive. Persisted Inspector provenance and a canonical prompt fingerprint are future application contracts. If added, their digest must be based on the final normalized IR without timestamps or random ordering, and must not log private content.
