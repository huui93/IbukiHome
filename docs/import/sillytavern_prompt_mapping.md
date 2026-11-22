# SillyTavern Prompt Mapping

Prompt import always produces candidates first. It never silently overwrites an
existing World prompt.

| SillyTavern source | IbukiHome destination candidate |
| --- | --- |
| Main/System Prompt | World System Prompt |
| Post-History Instructions | Session or character late instruction |
| Author's Note | Session additional instruction |
| Character System Prompt | Character-specific prompt layer |
| Character note/depth prompt | Character context contribution |
| World Info | WorldBook/LoreEntry |

For preset imports, the default action is preserve-only. The user must choose
append or replace before a prompt is changed. Provider sampler fields are mapped
only when the core model abstraction supports them; all others are retained as
compatibility data.

This v1 importer preserves all sampler candidates without applying provider
configuration. Unknown prompt sections and prompt order remain available for
future remapping. Character depth prompts are preserved-only. Character examples
are not chat history. Greetings are saved and visible in compatibility details;
automatic greeting insertion/selection at story creation is deferred.

World prompt order remains:

1. Core World RP rules
2. World System Prompt
3. Session Additional Instructions
4. Plugin or preset style layer
5. World context
6. User action

Character prompt data is used only in character generation. It is excluded from
memory extraction, timeline extraction, and mutation validation.
