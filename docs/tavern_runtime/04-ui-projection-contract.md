# Tavern transcript projection

`loadTranscript(sessionId, storyLineId?)` returns typed domain projections: Session, selected Story Line and ordered Turn projections. Each Turn has stable IDs, all Alternative headers, selected Alternative, and its ordered selected Content Parts. When no line is specified, the Session's canonical active line is used. A read transaction keeps one projection internally consistent. The SQLite implementation scopes all row reads to the Session and performs no per-Turn SQL queries.

For ordinary transcript rendering, consumers must use `TavernTurnProjection.visibleParts`: visible text, attachments and events. `selectedParts` also contains reasoning and tool records for controlled Inspector/developer surfaces; never dump these directly into a character bubble. Tool execution and provider reasoning display policy are separate future decisions.

Phase 5 scroll anchors should use stable `(storyLineId, turnId, alternativeId, contentPartId?)`. Near-bottom follow and per-line reading position belong to view/application state, not `tavern_story_lines`. Last-viewed line can differ from canonical active line. The UI should not reconstruct lineage from SQLite rows or infer branch meaning from a candidate answer index.
