# World Info persistence schema v14

SQLite v13 -> v14 adds only two Tavern tables.

- `tavern_world_info_states`: one row per Story Line, Session FK, current version/data, immutable initial data/provenance, last committed Attempt reference and initial checkpoint reference. Line identity is unique; deletion follows Session/line ownership. Snapshot JSON is typed timer/scalar data, not an arbitrary serialized Ledger.
- `tavern_world_info_journal`: one row per Attempt, five target FKs, immutable compile/request/plan fingerprints, base version/digest, included entry identities, typed delta, outcome/reason and unique committed version per line. Attempt identity is unique; owner/outcome indexes serve pending/conflict recovery and scope readiness.

Creation, prepare and successful terminal application are transactional. State uses compare-and-swap on version and digest; Journal committed version uniqueness and Attempt uniqueness enforce idempotency. No asset FK prevents deletion of Lore: historical identities remain historical and cannot independently create sources. Current authorized definitions always govern future activation.

Existing v13 lines seed `legacyUnavailable` version 0. Fresh lines seed `fresh`; branches get an exact historical checkpoint or an explicitly unavailable legacy checkpoint. Migration is additive and transactional; re-opening does not re-seed missing state. Archive ordering restores Attempts before Journal and defers checkpoint/last references as needed. Conflict merge remaps canonical IDs and typed timer/entry references together, recalculating structural integrity fingerprints while preserving original compile/request provenance. The semantic history digest contains no canonical ID and remains unchanged.

## Constraints and indexes

| Table | Key / uniqueness | Foreign keys / delete policy | Checks |
| --- | --- | --- | --- |
| `tavern_world_info_states` | PK `id = story_line_id`; unique line | Session and line CASCADE; last/initial Attempt RESTRICT | version >= 0; valid JSON; provenance enum |
| `tavern_world_info_journal` | PK `id = attempt_id`; unique Attempt; unique `(story_line_id, committed_version)` | Session CASCADE; Attempt, line, Turn, Alternative RESTRICT | expected version >= 0; committed version > 0 when present; valid JSON; outcome enum; typed plan target IDs equal columns |

`idx_tavern_wi_pending(outcome, session_id, story_line_id, expected_version)` supports readiness/recovery. `idx_tavern_wi_history(alternative_id, outcome, committed_version)` supports historical checkpoint resolution. Existing Foundation indexes continue to cover canonical traversal. SHA format, delta identities and committed-version consistency are validated in the typed repository codecs/rules, not inferred from JSON validity alone.

Deleting a Session explicitly removes its state/journals in the ownership transaction before deleting canonical history. Deleting an Alternative with committed/prepared/conflicted durable history is restricted; discarded journals can be removed with their failed/cancelled targets. Global Character/Persona/Lore assets are not deleted by Session cleanup. There is deliberately no Lore asset FK: historical deleted-entry identity remains useful for replay but can never manufacture an activation source.

Implementation definitions and validation tests are authoritative for final constraints and rollback behavior. No pubspec/lock/version change is needed.
