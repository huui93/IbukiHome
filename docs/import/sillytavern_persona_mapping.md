# SillyTavern Persona Mapping

An asset is treated as a Persona only when its structure identifies it as one.
Generic JSON containing only `name` and `description` is not guessed to be a
Persona.

Recognized forms are explicit `spec`/`type: persona` envelopes and the official
single-persona backup pair `personas` + `persona_descriptions`. A multi-persona
backup is detected but rejected with a clear selection limitation in v1; the
importer never guesses which identity to activate. The backup structure was
checked against [SillyTavern's backup implementation](https://github.com/SillyTavern/SillyTavern/blob/release/public/scripts/personas.js).
Remote or local-looking avatar references are preserved as provenance only;
the importer does not open them or treat them as an App-private path.

## Product mapping

| SillyTavern concept | IbukiHome concept |
| --- | --- |
| Persona | My character (`PlayerPersona`) |
| Persona used in a story | Current story's me (`WorldPlayerInstance`) |

The reusable template and session-owned state remain separate. Location, mood,
goals, relationships, memories, and story events must never be written back to
the `PlayerPersona` template.

The imported description defaults to public character knowledge. Import preview
also allows director-only visibility. Private and director-only information is
not automatically exposed to generated characters.

Importing a Persona does not create a `WorldPlayerInstance`. The instance is
created only when the user chooses that character for a WorldSession.

During onboarding, Persona/Lore previews are held in memory until step 3 selects
or creates a World. Canceling leaves no hidden World or Persona rows. Starting
the story executes the normal import plan, then creates the player instance.
Existing cross-world templates are copied with their visibility metadata,
while session-owned player state is always new.
