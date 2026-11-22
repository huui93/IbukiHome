# Migration and archive

`SqliteSchema.version` is 13. `runMigrations` adds only Tavern tables and indexes after v12. `ensureCurrentSchema` follows the project's idempotent on-open pattern. Tests cover fresh v13, v12 -> v13 preserving an old Project, reopen, FK-bound transactions, rollback after a deliberately duplicate Attempt ID, and a failed v12 -> v13 migration that leaves version and old rows unchanged.

The Full Archive snapshot registry includes all eight Tavern tables in FK-safe order. Cyclic Session/Story Line/Turn pointers and Story Line ancestry are deferred and restored after row insertion. Archive merge remaps colliding IDs through actual FKs. Typed World/Persona/Character asset references are remapped when the corresponding assets are present in the same backup. The backup codec still sanitizes secret-looking values; Provider credentials are not Tavern rows and are not backed up.

Tests write and read a real `.ibukibackup`, restore fresh, then merge the same archive into the target. The fixture includes five Alternatives, nested Story Lines, two Participants, failed/cancelled/completed Attempts and typed Parts. The resulting Session IDs differ while each restored transcript retains lineage, active line, frozen selection, Attempt targets and selected content. Legacy Novel, Chat, World and backup collections are unchanged.

The archive's manifest schema version is the actual current database version (13), not the previous default 12. No production keys or external script payloads are introduced by this phase.
