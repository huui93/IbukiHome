# Tavern Runtime Foundation: domain model

Phase 6 is production storage and application semantics, not the Phase 3-5 fake controller renamed. The earlier interaction contract informed stable IDs and projections; it is not a runtime dependency.

```text
Session 1 -- N Participant (typed references to assets)
Session 1 -- N Story Line (one active; one root at creation)
Story Line 0..1 -- N Story Line (parent; origin Turn + Alternative)
Story Line 1 -- N owned Turn (ordered by position)
Turn 1 -- N Alternative (one selected on the owning line)
Alternative 1 -- N Content Part (ordered, typed)
Alternative 1 -- N Generation Attempt (ordered retry history)
Story Line 1 -- N inherited selection snapshots (Turn -> Alternative IDs)
```

Session owns all Tavern history. Its optional `worldAssetType/worldAssetId` and `personaType/personaId` refer to *assets*, never a Legacy World runtime session. Participants reference persona, character, system, tool or external identity without copying CharacterCard text. The first two need an entity ID. Identity references are deliberately not foreign keys to Legacy World tables, because asset kinds and their lifetimes differ; an asset resolver must handle missing assets at the presentation boundary.

A Story Line owns only its new Turns. It reads ancestor Turns through parent lineage up to its origin. Creating a child snapshots selected Alternative IDs for inherited Turns, including the fork Turn; it never copies their content. Later selection changes on a parent therefore do not rewrite the child's inherited transcript. Nested branches snapshot their parent's effective choices. Alternative selection on a line's own Turn remains on the Turn; inherited selections remain line-scoped. `activeStoryLineId` is canonical Session state, not last-viewed UI state.

Turn is the stable semantic and scroll-anchor identity. `position` is a unique, nonnegative ordering key within its owning line; time is not ordering. Importers can allocate gaps or rebase positions transactionally later. A Turn always begins with a first Alternative. Alternative means a variant *of that Turn*, not a branch. Generation Attempt is an operation and lifecycle record, not message content. Failure/cancellation creates a terminal Attempt; a retry is another Attempt (or new Alternative), never an overwrite of history.

Content Part has an explicit kind and typed columns for text, reasoning, tool invocation/result, attachment and event. Reasoning, tool internals and visible character text are distinct. No tool execution, Provider call, Prompt compilation, World Info activation or automation exists in this phase.

The former Phase 5 first-contact gate is **BYPASSED BY PRODUCT DECISION**, not VALIDATED. Prototype functionality was too shallow for meaningful blind testing. Story Line user comprehension remains unproven and must be revalidated with a functional Tavern build.
