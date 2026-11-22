# Compiler invariants

1. Identical sources, settings and counter produce identical ordering, inclusion and trace.
2. Provider wire formats never enter compiler core; it has no Provider, network, DB, UI or Generation Runtime dependency.
3. World Info activation, RAG retrieval and Memory selection happen upstream and submit typed sources.
4. Stable source and atom identity survives compilation; every successful candidate has exactly one explicit decision, with distinct input and final order indexes. Duplicate source IDs are rejected.
5. Required sources never disappear or truncate silently; estimated input use never exceeds its reservation-adjusted budget.
6. History comes only from Foundation projection, which owns Story Line lineage, selected Alternative and failed-attempt filtering.
7. History trimming removes oldest complete Turns, retains a contiguous recent window and counts each candidate once. Each History source is one Turn; a split Turn origin or wrong budget class is invalid.
8. Placement, history depth and tie-breaks are deterministic and independent of SQLite natural order.
9. Regenerate excludes the old answer; Continue keeps the target answer as a distinct assistant-like continuation, not a new user message.
10. Reasoning, Tool Parts and attachments require explicit inclusion policies; unknown parts never become text by accident. The default excludes all three.
11. Trace explains inclusion, omission, budget and order without exposing source bodies; it is metadata, not a second Prompt copy.
12. Compilation does not mutate Tavern Foundation or Generation Runtime state.
13. Required overflow and estimator failure are typed failures, not partial Compiled Prompts. Every successful estimated input total fits its usable budget.
14. Optional sources are whole or absent; no source appears twice in the final IR. Whitespace-only sources are empty, while a nonempty zero-token estimate remains traceable.

Future World Info may scan keywords, resolve recursion, groups and probability, then emit selected sources. Memory and RAG may retrieve and rank upstream. None of these selectors live in compiler core. Future macro expansion and prompt-side regex transforms have a deliberate application pipeline slot between source collection/normalization and estimation: input is typed sources plus provenance, output is transformed typed sources retaining stable origin and atom identity (or explicit replacement provenance). No transform is implemented in v1. The Provider adapter translates the final IR into wire format and validates capability/token limits; it may not silently re-sort, trim or reactivate content. A deterministic compile fingerprint or Attempt-to-trace association remains a future observability hook and needs no v13 migration now.

The next World Info Runtime can supply activated `PromptSource`s with origin, priority and placement; it does not need a second prompt sorter. The Provider Adapter can consume the compiled IR after capability validation; it does not need a second compiler.
