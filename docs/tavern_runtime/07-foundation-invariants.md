# Tavern Runtime Foundation v1 invariants

This document is the contract for later Tavern runtime phases. The Phase 5 first-contact UX gate is **BYPASSED BY PRODUCT DECISION**, not validated by these technical tests.

## Canonical semantics

- A Session owns Participants, Story Lines, Turns and generation history. Its optional World, Persona and runtime configuration references do not impose one-Character, one-World or one-Provider limits. Participant IDs are stable local speaker identities; Character/Persona assets are referenced, not copied.
- A Story Line owns only new Turns. A child records its parent and origin Turn/Alternative, and freezes the effective selection of every inherited Turn at creation. Parent selection changes cannot alter a child or grandchild's inherited history. The projection orders ancestor prefixes followed by owned Turns.
- Active Story Line is persisted Session state. Last viewed Story Line and scroll/inspector/keyboard/tab state are presentation state. Archive hides a line from active selection and is rejected while it has unarchived descendants; descendants already archived remain readable. There is no public hard-delete Story Line operation; raw parent/origin FKs restrict unsafe deletion. Session deletion removes its complete owned graph.
- Each Turn has at least one Alternative and exactly one selected Alternative belonging to that Turn. Initial Turn/Alternative/optional Attempt is atomic. A selected, branch-origin or snapshotted Alternative cannot be deleted. Manual and imported Alternatives use the same model. New Answer creates an Alternative; retry creates a new Attempt on the same Alternative.
- Turn, Alternative, Content Part and Attempt order uses explicit nonnegative, owner-unique `position`, never timestamps or SQLite natural order. Import and continuation must allocate positions deliberately. Empty initial Alternatives can serve as generation placeholders.
- Content Part has stable identity and a typed kind: visible text, reasoning/native summary/unavailable, tool call/result, attachment, or event. A tool result links to its call by `toolCallId`, never adjacency. Unknown future kinds preserve their raw name and do not silently become visible text. A Part may identify its producing Attempt; failed/cancelled partial output remains stored but is not projected as the selected answer.
- Attempts have stable IDs and ordered immutable history records. Status may progress to completed, failed or cancelled; terminal status cannot transition. New Attempts never overwrite old ones. The target tuple (Session, Story Line, Turn, Alternative) must agree. Partial Parts can survive a failed/cancelled Attempt without becoming canonical visible output.
- Repository methods and transcript projection expose domain models, not table rows or SQL. SQLite write bundles and branch snapshots are transactional. Archive restore preserves semantic identity, lineage, selections, ordered Parts and Attempt targets; merge remaps colliding IDs and references together.

## SQLite v13 audit

All eight tables use text primary keys. `position` constraints and indexes support owner-ordered reads; no index was added for speculative queries. The Session active-line pointer and Story Line/Turn/Alternative cycles are inserted in transaction-safe order. The table definitions in `tavern_schema.dart` are authoritative.

| Table | Purpose | Foreign keys / delete policy | Unique constraints / key indexes |
| --- | --- | --- | --- |
| `tavern_sessions` | Session and active line | active line RESTRICT | PK; active line resolved by PK |
| `tavern_participants` | typed speaker references | session CASCADE | `(session_id, position)` |
| `tavern_story_lines` | lineage and origin | session CASCADE; parent/origin RESTRICT | `(session_id, position)`; `(parent_id, position)` index |
| `tavern_turns` | ordered owned Turns | session CASCADE; line/participant/selected Alternative RESTRICT | `(story_line_id, position)` |
| `tavern_alternatives` | answers within a Turn | Turn CASCADE | `(turn_id, position)` index |
| `tavern_line_selections` | frozen inherited choices | line CASCADE; Turn/Alternative RESTRICT | `(story_line_id, turn_id)` |
| `tavern_content_parts` | ordered typed content | Alternative CASCADE; Attempt RESTRICT | `(alternative_id, position)` index |
| `tavern_generation_attempts` | retry and lifecycle history | session CASCADE; line/Turn/Alternative RESTRICT | `(alternative_id, position)` index |

## Generation Runtime readiness

The repository can atomically start a Turn with its first Alternative and Attempt, append streaming Parts and update status, cancel/fail/complete, retry with another Attempt, create a new Alternative with its first Attempt, and append continuation Turns. It does not call a Provider, compile prompts, activate World Info, or execute tools. A future runtime must coordinate concurrent writers and use bounded streaming batches if per-token writes become costly; neither behavior is claimed by Foundation v1.
