# SillyTavern to Ibuki World Mapping

World Roleplay Foundation v1 separates reusable definitions from mutable save
state. This document records compatibility direction only; it does not enable
automatic SillyTavern import or embedded script execution.

| SillyTavern concept | IbukiHome model | Boundary |
| --- | --- | --- |
| Character Card | `CharacterCard` + `WorldCharacterInstance` | The card remains a reusable definition. Location, mood, goals, presence, and session history live only on the instance. |
| Persona | `PlayerPersona` + `WorldPlayerInstance` | The persona is a reusable definition independent from `ChatPersona`. Each `WorldSession` owns an isolated player instance for current location, status, mood, goal, and display override. |
| World Info / Lorebook | `WorldBook` + `LoreEntry` | v1 preserves keywords, priority, activation mode, scope, and open metadata. Advanced recursive/group/vector activation is deferred. |
| Group Chat | `WorldSession` + world cast + scene cast | A session owns many character instances. `WorldScene` selects only the currently present cast. |
| Scenario | `WorldScene` | Scene fields retain location, time, weather, atmosphere, current event, notes, and description instead of one opaque string. |
| Chat History | `WorldFeedEntry` | Typed entries distinguish player action, character speech, narration, and system event on a branch. |
| Branch / Checkpoint | `WorldBranch` | v1 stores branch identity, parent, and branch point metadata. Feed cloning and rollback are explicitly deferred. |
| Extension | `.ibuki` world navigation contribution | Generic `world` and `worldSession` scopes can expose a drawer entry. Core does not contain plugin-specific branches or expose repositories. |

## Prompt Preset Mapping (Reserved)

World Prompt Layer v1 defines a destination model for a future explicit import
flow. It does not parse or import SillyTavern presets in this stage.

| SillyTavern prompt concept | IbukiHome destination | Import rule |
| --- | --- | --- |
| World or scenario system instruction | `WorldPromptMetadata.worldSystemPrompt` | Store only after preview and user confirmation. All sessions under the world inherit it. |
| Chat/session override | `WorldPromptMetadata.sessionAdditionalInstructions` | Bind only to the selected `WorldSession`; never write back into the world template. |
| Author's note / style preset | Existing `.ibuki` prompt contribution at `world` or `worldSession` scope | Convert to a declarative Plugin/Preset layer. Do not execute embedded scripts. |
| Main prompt / context template | Host-owned `WorldPromptLayer` sections | Map known semantic sections; unknown template macros remain unsupported metadata instead of being evaluated. |
| Jailbreak / post-history instruction | No direct privileged mapping | It cannot override Core World RP Rules, structured output, safety boundaries, or mutation validation. |
| Memory and summary prompts | No World style mapping | Memory and Timeline structured post-processing remain isolated from user prose prompts. |

The stable order is Core World RP Rules, World System Prompt, WorldSession
Additional Instructions, Plugin/Preset, World Context, then User Action. Imported
content never receives API keys, provider internals, raw SQLite access, or an
executable runtime merely because it came from a prompt preset.

## Import Safety

- Importing a Character Card never executes embedded scripts.
- Importing a legacy `WorldCard` creates a `LoreEntry` and leaves the source
  card intact.
- Deleting a world or world session deletes owned roleplay state, not global
  `CharacterCard`, `ChatPersona`, project, plugin, or novel data.
- Future plugin access must use a host-owned `IbukiWorldAPI` with DTOs and
  permission checks. Raw SQLite and repository objects are not extension APIs.

## Deferred Engine Work

World Director, speaker selection, AI state/memory/timeline updates, lore
activation, RAG, checkpoint restore, and multi-character generation belong to
World Roleplay Engine v1 or later plugins. Foundation v1 only provides durable
models, repositories, structured management, feed shell, and extension slots.
