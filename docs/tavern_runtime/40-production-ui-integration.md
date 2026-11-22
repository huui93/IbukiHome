# Production Tavern UI integration

Parent: `363414853703a01fb4e15e5262742dfa98ebd898`,
`mobile-tavern-durable-reconciliation-v1-approved`. SQLite remains v14.

## Ownership

- Five independent primary branches: Novel, Chat, Legacy World, Tavern, Settings.
- Bootstrap still overrides `tavernRepositoryProvider` with SQLite. Memory
  Repository remains the formal contract's test implementation, not a demo driver.
- Home reads batched native story summaries. No seeded production story, fake
  entity IDs, prototype state, or cross-mode runtime calls.
- `TavernStoryService` validates native assets and creates Session/root/Participants
  in one Repository transaction. Player input/first Alternative/text also share
  one transaction. User-created reusable Persona is an independent native asset.
- Native reusable PlayerPersona uses the existing library owner, not a new
  WorldSession/WorldPlayerInstance. Public information alone enters Character
  context. The underlying asset schema, visibility rules and archive remain intact.
- Character/WorldCard imports use the same native asset selection. Their retained
  compatibility payload is not executed or placed in list summaries.

## Settings and source resolution

No schema-version/dependency/signing change. Existing Session metadata owns:

| Key | Meaning |
| --- | --- |
| `tavernBindingV1` | Provider/model reference and explicitly selected capabilities; no key |
| `tavernSceneV1` | User-authored scene name, description and time text |
| `tavernBookReferencesV1` | Explicit native book references, enable and priority |
| `worldInfoBookOverridesV1` | Existing story-scoped inherited book override |
| `tavernSessionInstructionsV1` | Existing safe text instruction contribution |

WorldCard context requires the native WorldRepository adapter; RoleplayWorld
retains its existing source path. Explicit story books join the same authorized
World/Character/Persona book union, deterministic dedupe and World Info runtime.
Disabled/private/director-only rules remain in force. Displaying a book does not
claim activation: only an original orchestration trace can report the turn's
actual activation decisions. Asset deletion subsequently makes source resolution
fail safely; it never silently substitutes an empty Character/world.

Archive collision merge remaps the local book-reference map keys in addition to
the already supported world/persona/participant identities. Binding is a reference
only; credentials still stay outside the archive. Reading anchors use a distinct
local settings namespace and are not canonical/archive state.

## Generation and lifecycle

- One app-scoped formal Orchestrator owns execution. One route controller guards
  repeated taps before asynchronous preflight. Binding reads configuration/profile,
  not secrets; only the formal Provider driver resolves credentials at generation.
- Send saves actual user text, then calls `start`. Composer clears only after
  acceptance and only if the draft is still unchanged. A rejected preflight retains
  the draft. Failed/cancelled attempts remain inspectable; no fake AI message.
- Retry targets the same Alternative/new Attempt. Regenerate creates a new
  Alternative. Continue targets the same Alternative and does not add player text.
  Compatible continuation is an explicit story-local option, never a global
  capability or Provider mutation.
- Streaming exposes an additive typed pending-part read model from the existing
  runtime's pending chunks. Stable IDs match persisted parts. It does not change
  flush, cancellation, terminal transaction or World Info CAS semantics.
- Only the active answer body repaints on streaming notifications (80 ms batching).
  Native reasoning, reasoning summary and unavailable remain secondary typed
  content, never joined into dialogue.
- Back/Home while active confirms, cancels the actual handle, and waits for route
  controller settlement before `go('/tavern')`. Keyboard and Drawer close first.
  Story-line switch also waits for settlement. No background next-speaker loop.
- Formal fork freezes Alternative and uses existing historical World Info
  checkpoint; inherited rows cannot be edited by the descendant UI.

## Reading and diagnostics

The Phase 5 semantic-anchor contract is adapted, not its fake DTO implementation.
Reverse lazy lists start at the latest turn without eagerly building all historical
rows. Per-line local anchors store stable Turn ID, viewport coordinate, following
flag and an offset hint. Scroll-up stops following; streaming does not take over
old reading. Disposal never overwrites a valid anchor with a detached zero offset.
Same-line data/Alternative changes correct the visible anchor after layout.
Keys are stable; images use bounded decode and Flutter's image cache.

Original traces are cached in-process for at most 100 Attempts. Inspector separates
Prompt (budget/source decisions/activation) from Runtime (actual attempts, model,
typed content, reconciliation). Historical unavailable traces are explicitly
unavailable, never recomputed. No full prompt, secret, Provider header or arbitrary
failure payload is logged or shown as a diagnostic.

## Scope and gates

No automatic group scheduler, tools, multimodal generation, macros, RAG, memory
engine, full inspector history or ST runtime. Multi-character stories select one
actual responder per request. Scene metadata is user-authored; no new scene
simulation or Legacy World mutation is claimed.

Phase 5 First-contact UX Gate remains **BYPASSED BY PRODUCT DECISION**.
Production UX remains **NOT YET VALIDATED** by genuine first-contact users.
Offline tests use the formal Repository/Orchestrator and controlled HTTP transport.
They do not count as Live Provider success. No real API smoke is authorized here.

## Android portability found during APK smoke

API 31's actual Android SQLite 3.32.2 has no `json_valid`/`json_extract`.
The original v14 SQL CHECK expressions prevented both a fresh database and an
upgrade from opening, before Tavern itself could start. This is a verified native
deployment defect, not a justification to clear existing user data.

v14 table creation now probes the two optional JSON functions using a literal
empty object. On engines without them, the same columns/FKs/uniqueness/status/CAS
constraints are created without the optional SQL JSON checks. Engines with JSON
retain those additional checks. Every native preparation still calls the existing
strict `TavernWorldInfoPlan.fromJson` and target/fingerprint validation before
insertion; every state/journal read and logical archive validates typed payloads
and column identities. This validation is mandatory on all platforms. Direct
unvalidated SQL is never an application/UI API; malformed raw tampering is rejected
at read/recovery/restore, not accepted as canonical state. Portable orphan checks
batch-read only unjournaled Attempt metadata and decode it structurally in Dart.
They retain missing-journal protection without SQL JSON functions or N+1 reads.

There is no version bump, new data field, destructive migration, weakened CAS,
new reconciliation algorithm or dependency upgrade. Native device smoke and the
portable-schema generation/fork/archive/rejection tests cover this path.
