# WorldBook References v1

WorldBook is a reusable library asset. LoreEntry remains the independently
enabled and activated unit inside a book.

## References

- A World references zero or more books with `enabled` and `priority`.
- A WorldSession may inherit, enable, or disable a book. The session decision
  is applied last and only affects that story.
- A CharacterCard reference is considered while that character is present.
- A PlayerPersona reference is considered while that persona is active.
- Turn-local manual Lore remains ephemeral and is not saved as a reference.

All sources feed the existing `WorldLoreActivator`. Books and entries are
deduplicated by stable IDs. Reference priority is added to LoreEntry priority,
then the existing activation and token-budget rules select content.

## Ownership

Legacy world-owned books remain readable. New and imported books are stored in
the library and linked by reference. Deleting a World removes its references,
not shared books. A referenced book cannot be deleted until its references are
removed.

SillyTavern Lorebooks become library WorldBooks. Embedded CharacterBooks may
create a CharacterCard reference. Their compatibility payload and unsupported
rules remain separate and are never executed.

## Performance

The context builder resolves active references before loading LoreEntry
content. Unreferenced library books are never read during a turn. UI library
search is repository-backed and compatibility payloads remain lazy-loaded.
