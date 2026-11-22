# Tavern Generation Orchestrator v1

`TavernGenerationOrchestrator.start(command, binding)` is the Application entry point. It acquires a session preparation lock and deduplicates command identity. It validates stored Provider configuration and credentials, loads the canonical requested Story Line projection, validates the command target, resolves authorized native assets, evaluates World Info, assembles/compiles Prompt Sources, validates capabilities and fingerprints the Provider request. Only then does the existing Runtime create generation objects and start the registered Driver.

Normal, Retry, Regenerate and Continue creation/selection/persistence remain Runtime responsibilities. The preflight uses PromptHistoryAssembler and WorldInfoScanContextBuilder. Regenerate is recorded by Foundation as an Alternative generation; Ledger now accepts that existing type for regenerate scan mode. Retry of a failed Continue retains continue semantics. Failed preflight creates no generation Turn/Alternative/Attempt and sends no HTTP request.

## Source policy

`NativeTavernSourceResolver` loads the selected CharacterCard, public PlayerPersona fields, optional RoleplayWorld template, safe ST text fields, and books linked through World/Character/Persona references. Other participants contribute public display identity rather than complete personalities. The session's metadata can contain `tavernSessionInstructionsV1` and `worldInfoBookOverridesV1` (inherit/enabled/disabled for already authorized references). These settings are owned by the Tavern Session and naturally included in its existing archive metadata. They do not borrow Legacy WorldSession identity or tables. A disabled but known reference can be explicitly enabled; an arbitrary unreferenced book ID cannot be enabled through the override.

Only application core rules become system/developer messages. Asset content, imported lore, character prompt fields and user-authored instructions are context data serialized as user-role material. Their reference wrapper is budgeted before compilation. Private/director-only Persona fields and explicitly hidden Lore are excluded. Unselected answers, failed/cancelled partials, Reasoning and hidden metadata are not appended as ordinary history. No script/macro/regex content is executed.

V1 reads reusable assets, not Legacy World running state. Tavern has no new Scene/relationship/memory runtime in this phase. PlayerPersona assets are usable through explicit `personaType=playerPersona`; this is not a new Persona management UI. Alternative asset types are rejected instead of guessed.

## Lifecycle and settlement

Root ProviderScope owns one Tavern repository, Driver, Compiler, Ledger and Orchestrator. Production bootstrap injects SQLiteTavernRepository; tests use an explicit in-memory or SQLite repository. The first start calls interrupted-attempt recovery once before generation. Session/screen switching reuses the environment. `dispose()` is awaitable and closes active operations; Riverpod disposal is best-effort asynchronous because its callback cannot await OS process termination. Abrupt process death relies on restart recovery and does not auto-resend a request.

Every run fixes attempt/session/Story Line, Activation Plan, Compiled Prompt and request fingerprint. The Driver rejects a changed serialized request before HTTP. Terminal settlement reloads the canonical Attempt; only an eligible completed Attempt with the held compile result commits lore. Failure/cancel discards it. Duplicate terminal completion does not commit twice; switching the viewed line does not alter the target.

If generation completed but Ledger settlement failed, the result explicitly reports `ledgerFailure`. The affected line is blocked from another request until `retryLedgerSettlement(attemptId)` succeeds. That retry sends no HTTP request and never regenerates content. A stale plan cannot overwrite newer state and is reported separately. This is not a database-atomic transaction across generation and transient lore state; process crash may lose the ledger and in-memory trace.

Observation phases are preparing/compiling/connecting/streaming/finalizing/completed/failed/cancelled. They do not replace Generation Attempt state. Trace links Attempt to activation/compile outcomes and safe Provider metadata; after restart the actual old in-memory trace is unavailable, not reconstructed as if captured at send time.
