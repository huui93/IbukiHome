# Ibuki Backup Format v1

IbukiHome Android v1.1.0 (build 4) uses archive format v1 and SQLite schema v22. The archive version identifies the interchange format. [Current development guide](../development.en.md)

`.ibukibackup` is a ZIP container with a logical, versioned data contract. It is not a copy of `ibukihome.db` and does not use historical SQLite migrations during restore.

## Envelope

- `manifest.json`: `archiveFormat=ibuki-home-backup`, `archiveVersion=1`, source application/schema metadata, logical entity counts, feature flags, asset inventory, and explicit credential-exclusion flags.
- `data/<collection>/<chunk>.jsonl`: bounded JSONL chunks. Collection names are stable archive concepts rather than SQL supplied by the UI.
- `assets/<sha256>/<name>`: private content assets addressed by digest.
- `checksums.json`: SHA-256 for the manifest, every data chunk, and every asset.

Archive version and SQLite schema version are independent. Readers reject a future required archive version and ignore unknown optional manifest fields. Restore adapters map Archive IDs into IDs valid in the current database.

## Logical collections

The v1.1.0 export includes character cards and world-book data, novel projects, system prompt presets, output settings, revision history, native branch state, reply views, and summaries. Chat exports include personas, sessions, messages with image data, usage records, controls, and conversation memory. The archive also carries supported legacy World and Tavern records and external compatibility payloads.

Plugin package files, private Web plugin storage, provider configuration, credentials, diagnostics, caches, logs, and temporary files are excluded. Story-line settings and other host-managed novel plugin state are stored as logical novel records.

Provider/model binding columns are omitted. Restored projects and sessions remain readable and require explicit AI configuration before generation.

## Limits

- Archive bytes: 2 GiB
- Entries: 20,000
- Single entry: 256 MiB
- Expanded total: 4 GiB
- Manifest: 4 MiB
- JSONL chunk: 5,000 rows

The reader rejects absolute paths, drive-letter paths, traversal, duplicate paths, symbolic links, oversized entries, malformed ZIP data, missing checksums, and checksum mismatches before database mutation.
