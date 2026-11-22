# Ibuki Backup Format v1

`.ibukibackup` is a ZIP container with a logical, versioned data contract. It is not a copy of `ibukihome.db` and does not use historical SQLite migrations during restore.

## Envelope

- `manifest.json`: `archiveFormat=ibuki-home-backup`, `archiveVersion=1`, source application/schema metadata, logical entity counts, feature flags, asset inventory, and explicit credential-exclusion flags.
- `data/<collection>/<chunk>.jsonl`: bounded JSONL chunks. Collection names are stable archive concepts rather than SQL supplied by the UI.
- `assets/<sha256>/<name>`: private content assets addressed by digest.
- `checksums.json`: SHA-256 for the manifest, every data chunk, and every asset.

Archive version and SQLite schema version are independent. Readers reject a future required archive version and ignore unknown optional manifest fields. Restore adapters map Archive IDs into IDs valid in the current database.

## Logical collections

The v1 whitelist covers shared character/persona/world-book data, novel projects and revision history, chat sessions/messages/memory/summaries, all World v12 roleplay state, and external compatibility payloads. Plugin binaries, plugin private storage, Provider configuration, diagnostics, caches, logs, and temporary files are outside the format.

Provider/model binding columns are omitted. Restored projects and sessions remain readable and require explicit AI configuration before generation.

## Limits

- Archive bytes: 2 GiB
- Entries: 20,000
- Single entry: 256 MiB
- Expanded total: 4 GiB
- Manifest: 4 MiB
- JSONL chunk: 5,000 rows

The reader rejects absolute paths, drive-letter paths, traversal, duplicate paths, symbolic links, oversized entries, malformed ZIP data, missing checksums, and checksum mismatches before database mutation.
