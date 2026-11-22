# Phase 10 acceptance and technical freeze

Date: 2026-10-15. Parent: `bc6bedf8ae72f5a085819813783aeb4c1cbe18e3`, `mobile-tavern-world-info-runtime-v1-approved`.

Worktree: `<workspace>`. Branch: `feature/mobile-tavern-provider-adapter-v1`.

## Gates

- Gate A (code / offline integration): APPROVED after the complete quality gate.
- Offline E2E: PASS, using frozen Foundation, Generation Runtime, Prompt Compiler and World Info Runtime; no second generation chain.
- Live Provider Smoke: **NOT RUN**. Reason: explicit authorization for a paid request was not provided. No real credential was inspected.
- Device Smoke: **NOT RUN**. Only protected `emulator-5554` was listed; no disposable device was available. No installation, configuration, reset or credential access was performed.
- Phase 5 First-contact UX Gate: **BYPASSED BY PRODUCT DECISION**, not VALIDATED.

The approved tag is a technical Gate A freeze. It does not certify real model connectivity or all Providers online.

## Protocol audit

| Protocol | Offline result | Contract verified |
| --- | --- | --- |
| DeepSeek Chat | PASS | Configured host, `/chat/completions`, `reasoning_content` separate from visible text, natural `stop` plus `[DONE]` |
| DeepSeek Beta Prefix | PASS | Explicit capability and configured `/beta` path, final assistant prefix, ordinary configuration rejected; no automatic Beta selection |
| OpenAI Chat | PASS | System/developer capability, typed Chat chunks, usage, `finish_reason` plus `[DONE]`; no Responses field reuse |
| OpenAI Responses | PASS | `input`, `store:false`, `truncation:disabled`, named text/reasoning/summary events, `response.completed`, explicit incomplete/failure |
| Gemini native | PASS | Leading systemInstruction, user/model roles, `alt=sse`, native `STOP`, thought text treated as summary, empty/signature-only reasoning unavailable |
| Custom Chat | PASS | User-configured host and key reference only, no builtin credential fallback, redirects disabled, conservative capabilities, unknown finish/parameters rejected |

Official references: [DeepSeek Chat](https://api-docs.deepseek.com/api/create-chat-completion/), [Beta Prefix](https://api-docs.deepseek.com/guides/chat_prefix_completion/), [OpenAI Responses events](https://developers.openai.com/api/reference/resources/responses/streaming-events), [OpenAI Chat events](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events), [Gemini native](https://ai.google.dev/api/generate-content). Fixtures are synthetic, not real model outputs.

## Orchestration and atomicity

Accepted path: Command -> Preflight -> Foundation Projection -> World Info -> Source Assembly -> Compiler -> serialized request -> normalized events -> Runtime -> canonical terminal Attempt -> Ledger.

A capturing compiler test compares the ordered compiled texts/roles with the actual mock HTTP request. Reference wrappers are budgeted before compilation. Adapter validation never silently trims, reorders or supplies untracked roleplay text. Changed request fingerprint fails before creating an HTTP client and discards the plan.

Missing credential, invalid Session/Story Line/Alternative, unsupported capability, required overflow, configuration mismatch, evaluation failure and compiler failure leave canonical selection/content/Attempt history unchanged, send zero requests and advance no lore state. Recovery of genuinely interrupted existing Attempts is a separate startup responsibility, tested before any new HTTP request.

The owner locks a Session synchronously before async preflight. Double Send/Regenerate/Continue share the same handle for the same command; competing commands are rejected. Independent Sessions can prepare and stream concurrently. Retry is explicit; no network auto-retry. Identity includes target, timeout, key reference and every declared capability.

## Stop and reasoning

Connecting/streaming/after-final-delta Stop, streaming timeout, preflight/active-owner dispose, late events and finalization competition are tested. Request-owned transport closes and the subscription is cancelled. Real HTTP loopback verifies IOClient closure with one synthetic local request, no external endpoint. Its direct-loopback proxy override is test-local, not an application/network setting.

Completion can win once canonical finalization begins; subsequent Stop cannot replace it. Failed/cancelled partials remain inspectable by provenance, never normal transcript or Retry context. Native reasoning, summary and unavailable parts have independent kinds/source metadata and Attempt IDs. Empty Gemini/Responses text and Gemini signatures do not fabricate reasoning.

## Ledger and restart

Normal/Retry/Regenerate/Continue completion, failure/cancel/timeout discard, stale/duplicate settlement, wrong compile source/request identity and displayed Story Line switching are covered by integration and frozen Ledger tests. Settlement uses the held compile result and original canonical target, not the current UI line.

In-process commit failure is surfaced separately from generation success, blocks that line and permits no-HTTP reconciliation. **The block, pending plan, deduplication, timers and traces do not survive restart.** A new owner cannot distinguish completed-but-unsettled from ordinary completed Attempts and can start another generation. Cross-crash sticky/cooldown/replay correctness is not guaranteed. This risk must be solved before a production playable release; the requested technical Adapter freeze permits it with an explicit record. No SQLite v14 or hidden persistence is introduced.

## Lifecycle, security and persistence

The non-autoDispose root ProviderScope owns one environment. Page listener detach/re-entry reuses it; recovery runs once before generation. Root dispose closes active HTTP and leaves no active Attempt on the awaited path. OS termination remains best-effort, followed by canonical interruption recovery.

Credentials stay in secure storage and temporary request memory. Errors retain enum reasons and safe status. Traces retain IDs/hashes/counts, not keys, private prompts or bodies. Custom reads its own explicit reference. Imported assets/lore stay context data, never application system role. Legacy provider/generation semantics are not replaced.

SQLite stays v13; no migration or Archive format change. Rich SQLite E2E covers Normal, Regenerate, selection, frozen child, Continue, failed/cancelled/completed retry, then archive -> fresh restore -> close/reopen. Semantic comparison includes Alternatives, content order/kind/source/provenance, failure/cancel reasons and Attempt provider/model history. Transient Ledger/Trace/settings are not claimed to restore. Existing v12->v13 and Legacy/archive regressions remain in the full suite.

## Quality and limitations

`dart format .`: 433 files, 0 changes on final run. `flutter analyze --no-pub`: No issues found. `flutter test --no-pub --concurrency=2`: **1586/1586 PASS**, 103 added over 1483 (38 acceptance additions over 1548). Tracked diff and untracked whitespace: PASS. High-confidence secret scan: 512 tracked/untracked text files, **0 hits** (credential prefixes, static key/header assignment and private-key material; no match bodies logged). No old tests removed or skipped.

Unsupported: Tool/multimodal execution, exact tokenizer capability, automatic model capability discovery, Memory/RAG, formal Tavern UI and durable Ledger. Online model validation is unverified without explicit authorization. Long-lived transient command/settlement cache sizing is not optimized in this phase. Pubspec/lock/version are unchanged.

Recommended next work: separately approved durable Ledger reconciliation design and one authorized bounded Provider smoke. Do not infer permission to start either from this freeze.
