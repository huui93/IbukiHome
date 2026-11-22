# SillyTavern Character Card Mapping

## Supported sources

- Character Card V2 JSON
- Character Card V3 JSON
- PNG `tEXt` metadata using `chara` or `ccv3`
- Future card versions on a best-effort basis, with a compatibility warning

The importer computes a SHA-256 provenance value before building an import
plan. File paths are not used as portable identity.

## Native mapping

| SillyTavern field | IbukiHome use |
| --- | --- |
| `name` | Character name |
| `description` | Character description section |
| `personality` | Personality section |
| `scenario` | Initial scenario section |
| Card PNG | Private copied avatar asset |
| `system_prompt` | Character-only prompt layer |
| `post_history_instructions` | Character late instruction |
| `mes_example` | Character speech examples |

`first_mes`, `alternate_greetings`, creator metadata, tags, and fields without a
native destination remain in the compatibility payload. They are not converted
to chat history.

Imported cards use the normal `CharacterCard` repository and can be selected by
Chat or added to a World as a `WorldCharacterInstance`. There is no alternate
SillyTavern execution path and the import is not labelled as fanfic or original.

## Preservation

Recognized native data stays small and frequently readable. Unknown fields and
extensions stay in `ExternalCompatibilityPayload` and are loaded only from the
compatibility detail flow. This permits future remapping without the original
source file.
