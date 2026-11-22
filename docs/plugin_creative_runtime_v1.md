# IbukiHome Plugin Creative Runtime v1

## Request Path

Creative operations use one Host-owned path:

`Core prompt builder -> IbukiPromptPipeline -> AiModelResolver -> provider`

The pipeline is connected only to novel generate/rewrite/modify/selection
modify and chat reply/continue. Summary, digest, and memory extraction remain
Core-only in v1.

## Priority

Prompt contributions are rendered as a labelled, low-priority style layer.
The original Core system prompt and user messages remain intact, followed by a
Host precedence guard. The effective priority is:

1. Host safety and invariants
2. Current explicit user instruction
3. Project system prompt or Chat persona
4. Existing story facts, Character Cards, and World Cards
5. Plugin style contribution

A plugin cannot persistently edit Project prompts, Chat personas, Segments, or
messages through the Creative Runtime.

## Scope and Settings

Installation and application are separate. Prompt plugins can be bound to a
global, project, or chat-session scope. Bindings and schema-generated settings
are stored in the Core-reserved `plugin_storage` namespace. Plugin code cannot
read or clear this reserved state. The database stays at schema v8.

An exclusive style conflict at the same scope and operation requires an
explicit user switch. A more specific project/chat binding takes precedence
over a global style.

## IbukiPluginAI

`IbukiPluginAI.generate` requires `ai.generate`. Project requests resolve with
`resolveForProject`; chat requests use `resolveForChatSession`; global tools use
the configured global default. There is no silent provider fallback.

The Host enforces one active request per plugin, a 4096-token request ceiling,
a timeout, cancellation, and cancellation on plugin disable. Results contain
text, finish reason, interruption state, and display-only model metadata.
Provider clients, request objects, headers, API keys, Secure Storage, and raw
debug responses never cross the plugin boundary.

## Failure Isolation

Malformed contributions, invalid scoped settings, or throwing prompt hooks
fall back to the unchanged Core prompt for that request. Plugin-owned AI
failures do not share the Novel or Chat generation coordinator and cannot
cancel a Core generation.

External network access remains unavailable. Creative Runtime v1 does not add
a Plugin Network API or expose `fetch` from the sandboxed Web runtime.
