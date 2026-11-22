# SillyTavern Lorebook Mapping

Standalone World Info and embedded CharacterBook entries can become native
`WorldBook` and `LoreEntry` records after explicit confirmation.

| SillyTavern field | IbukiHome field |
| --- | --- |
| `keys` | `keywords` |
| `secondary_keys` | `secondaryKeywords` only when `selective` is true |
| `content` | `content` |
| `enabled` | `enabled` |
| `constant` | `activationMode: always` |
| non-empty keys | `activationMode: keyword` |
| no constant or keys | `activationMode: manual` |
| `order` | `priority` |
| `position` | `insertionPosition` |
| `probability` | Percent converted to 0..1; preserved, current activator does not sample |

Always and keyword modes are consumed by the existing World lore activator.
Recursive activation, groups, sticky state, cooldown, delay, and unsupported
depth/insertion behavior are preserved but not executed. Preview clearly marks
these advanced rules as preserved-only.

Raw entry dictionaries remain in the separate compatibility payload, including
numeric source IDs, position/depth and unknown rule fields. WorldBook management
can switch between the primary and imported books. Onboarding records explicit
`worldBookIds` on the new session; an empty selection means no lore, while older
sessions without this metadata retain the existing all-books behavior.

An embedded CharacterBook defaults to staying with the character compatibility
payload. The user may instead create a WorldBook or choose an existing one.
