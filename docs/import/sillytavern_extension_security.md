# SillyTavern Extension Security

SillyTavern extensions are untrusted input. Import is a data compatibility
operation, not runtime compatibility.

## Import policy

- JavaScript, STscript, Tavern Helper tasks, regex scripts, RUBY payloads, and
  other executable-looking content are preserved but never evaluated.
- HTTP/HTTPS references are recorded but never requested or downloaded.
- API-key-like, bearer, authorization and explicitly named credential values are
  redacted from native fields and JSON compatibility payloads before persistence.
  They are never copied into provider configuration. An original PNG is retained
  privately as an inert avatar container; its original metadata is never loaded
  as configuration or sent to a provider. Redaction is heuristic, not a guarantee
  that arbitrary prose cannot contain an unrecognized secret.
- Import never invokes a provider, writes SecureStorage, opens a WebView, or
  registers a plugin contribution.
- Unknown extensions remain available for future safe remapping.

Security classification includes data-only, prompt-related, UI-related,
script-like, network-related, and unknown. Classification does not grant an
execution capability.

Any future execution requires explicit conversion to an `.ibuki` package,
installation through `PluginManager`, declared permissions, and the existing
host bridge/sandbox. Imported ST data cannot bypass plugin identity, IbukiAI, or
network policy.

## Bounds and transactions

- 32 MiB source, 8 MiB JSON/metadata, 5,000 lore entries, 1,000 greetings.
- PNG chunk bounds and CRC32 validated; dimensions at most 8,192 per edge and
  16 million pixels. Preview decoding uses a bounded image cache size.
- JSON traversal depth 64, at most 150,000 nodes; parsing and hashing run in an
  isolate. No ZIP container support in this phase.
- SAF-selected bytes are copied to private `imports/sillytavern/assets/<id>`.
  Staging uses `.installing/<id>`; existing assets cannot be overwritten.
  Traversal and symlink destinations are rejected; compensation deletes only
  the newly owned avatar file.
- Native data and payload writes share a SQLite transaction. A failed payload
  write rolls back a newly created collection as well. Preset updates use
  optimistic revisions and update only prompt metadata, never other session
  fields. A stale preview is rejected rather than overwriting newer settings.
- Existing Character soft-delete behavior retains its compatibility payload and
  private avatar for restore/provenance. No automatic destructive purge is added.

The implementation has no JavaScript interpreter, HTTP/Provider client,
SecureStorage writer or PluginManager dependency. Synthetic tests include inert
script text, invalid remote references and fake credentials. This is a structural
security boundary, not a claim that every possible script syntax is classified.
