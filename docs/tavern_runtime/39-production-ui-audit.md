# Production Tavern MVP UI audit

Parent: `363414853703a01fb4e15e5262742dfa98ebd898`, tag `mobile-tavern-durable-reconciliation-v1-approved`. SQLite v14, 1630 tests. Independent Phase 12 worktree; no approved/prototype worktree modified or fake runtime copied.

## Read-only references

Reviewed current App/bootstrap/router, primary shell, Novel and Chat entry points, World Lobby/creation/transcript/managers, CharacterCard/WorldCard repositories, WorldBook library/references, PlayerPersona, AI settings/model profiles, BubbleTheme/AppTokens/BubbleBackground/GlassSurface, FollowBottomController and Archive restore. Also reviewed Phase 2 UI reuse/runtime boundaries and Phase 5 final interaction, cancellation and semantic scroll contracts in their existing worktrees. Their product UX gate remains BYPASSED BY PRODUCT DECISION, not validated.

| Classification | Surface | Decision |
| --- | --- | --- |
| Can reuse directly | BubbleTheme, AppTokens, BubbleBackground, IbukiGlassSurface, existing mascot/nav assets | Preserve light/dark and blue/pink language; no new asset pack |
| Can reuse directly | Character/WorldCard, PlayerPersona and WorldBook native storage/editors; import preview; API Settings; Backup | Shared assets, not shared story runtime; no new Persona system |
| Requires adaptation | Five-mode shell | Add Tavern before Settings; keep existing four implementations and root Back semantics |
| Requires adaptation | FollowBottomController | Tavern-only semantic anchors, per-line view state and throttled row updates; don't change Novel/Chat behavior |
| Requires adaptation | Native Source Resolver and Session settings | Real WorldCard as well as RoleplayWorld; explicit validated Session Book references and scene context; archive ID remapping |
| Must rebuild | Tavern Home, story setup, transcript/controller, answer/line actions, Inspector | Formal Tavern projections/commands; no WorldSession/WorldTurn/WorldFeed reuse |
| Out of MVP scope | Full group scheduling, tools, RAG, memory engine, macros, regex, automation, complete historical Prompt Inspector | Do not expand frozen engines or execute ST extensions |

## Findings and minimal integration

Production Bootstrap already overrides Tavern Repository with SQLite and provides one root-scoped Orchestrator. The default in-memory implementation is only a testing/development fallback. The frozen repository lacks Home/list/rename/bundle creation APIs; add thin typed repository operations against existing tables, not raw SQL in widgets. A story must be created atomically with participants and initial line/state.

Native Character assets are project-owned and must be enumerated through Project/Character repositories. WorldCard currently has no Source Resolver path, so a read-only native asset adapter is needed. Reuse PlayerPersona, including its existing visibility boundary. New reusable personas live in the existing hidden native asset-library owner row; that real row is never presented as a story World and no Legacy WorldSession/PlayerInstance is created for Tavern.

Existing World/Character/Persona Book references remain candidate sources. A typed Session settings map can store additional user-selected existing Book references using current metadata, with dedicated validation and archive identity remapping. No schema change is required. Provider/model binding contains IDs and model names only; credentials remain behind SecureStorage and are never part of transcript/diagnostics.

Creation has three stages: identity, cast, place/model/settings. It also accepts character/world/blank starting intent. The transcript uses lazy stable Turn rows and read-only Foundation projection. One selected participant responds per generation; multiple cast is supported without claiming a group controller. Reasoning is secondary typed content, never ordinary speech.

UI/application controllers own user-command coordination and projection refresh, not provider loops, prompt text, activation decisions or mutation rules. Stop/back/line switch wait for the existing cancellation/finalization result. Historical inspection uses retained genuine traces or explicitly unavailable state; never recompiles the past.

## Milestones

A: real five-mode navigation, Home/assets/create/select/save. B: real transcript/Composer/send/stream/stop/error/reopen. C: retry/regenerate/continue/answer switching/line branching/reading anchors. D: authorized Lorebook resolution and truthful Inspector. E: full offline production-path tests, archive/recovery regressions, performance, universal APK and safe device smoke where available.

No commit/tag/merge/version bump during implementation. Live Provider requests require explicit user action/authorization. Protected `emulator-5554` is never operated.
