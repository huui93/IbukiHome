# Durable World Info archive and merge semantics

The two new collections are `tavernWorldInfoStates` and `tavernWorldInfoJournal`. They are captured in the existing coherent SQLite snapshot and included in `.ibukibackup`; existing asset and secret-exclusion policies stay unchanged.

## Fresh restore

Restore canonical Sessions, lines, Turns, Alternatives and Attempts, then state/journal records. Deferred last/initial Attempt references are restored inside the same transaction. Validate line coverage, ownership, typed identity/digest checks, journal terminal status and state replay. Invalid durable data aborts the whole restore rather than producing a partially imported Session.

Older archives without durable collection keys seed explicitly `legacyUnavailable` line baselines. A current archive containing an empty/missing record for a marked durable Attempt is not treated as old data; it is rejected. Pending and known conflict outcomes are preserved, not silently converted to successful commits. Root recovery subsequently interrupts nonterminal Attempts without HTTP or applies valid completed pending deltas once.

## Collision merge

State identity aliases the remapped Story Line ID. Journal identity aliases the remapped Attempt ID. Remap every canonical target/reference, including initial/last Attempt pointers, and composite Book/Entry timer identities and included/removal identities. Keep Session/line histories independent; do not concatenate unrelated timer histories or duplicate applications.

Recompute structural plan/base fingerprints after identity remapping using initial checkpoints and recorded deltas. Update the remapped Attempt's plan identity consistently. Preserve original compile/request digests and `originalPlanIdentity` provenance: they describe the historical request, not a newly compiled request. Fixed-length semantic history digests do not contain IDs and remain unchanged.

An unavailable base checkpoint can remain explicitly conflicted. Invalid or ambiguous history is rejected; it is never silently dropped. World binding and per-Session Book override IDs are also remapped using the existing native entity mapping, not external file paths.

## Evidence

Tests compare semantic State fingerprints/versions, Attempt references, nested lineage, Alternative selection, projected transcript and included identities after a real archive-file roundtrip and collision merge. They repeatedly reconcile the imported scopes without advancing again. FK checks remain clean. Prepared/conflict images preserve blocking policy. A restore transaction fault leaves every existing collection and KEEP-ME unchanged.

## Data minimization

Journal contains IDs, hashes, eligible deltas and outcomes, not credentials, Authorization, full Provider responses, Prompt or Lore bodies. It is not a historical Prompt Inspector. No old missing trace is regenerated and presented as what the model actually saw.
