# Streaming and error policy

The shared SSE decoder handles incremental UTF-8, CRLF/line boundaries, comments, multi-line data and consecutive frames. It does not equate HTTP chunks with JSON events. Unterminated frames, invalid UTF-8/JSON and EOF without the required completion signal are failures. Frames have a 1 MiB data limit.

Chat Completions requires a valid stop finish reason and `[DONE]`; Responses requires `response.completed` with completed status; Gemini requires candidate `STOP`. Usage is parsed using the protocol's own fields. Empty reasoning deltas add no invented reasoning. A completed reply with no reasoning creates a `reasoningUnavailable` Content Part. Native reasoning and summary use separate Content Part kinds and provenance; neither is ordinary RP text or default history input.

| Signal | Result |
|---|---|
| stop / STOP / completed | Eligible successful completion |
| length / MAX_TOKENS / max_output_tokens | Typed outputLimit failure; partial is not presented as a complete reply |
| content_filter / safety / refusal | Typed contentFiltered failure |
| tool call/result request | Typed unsupportedCapability; no execution or fake result |
| unknown finish / server abort | Typed serverAbort failure |
| EOF before terminal signal | Typed incompleteStream failure |
| user Stop | Cancel Runtime, abort request/subscription, discard lore plan |

Provider failures distinguish missing credential, authentication, permission, unknown model, unsupported capability, context exceeded, rate limit, quota, transport, timeout, malformed response, incomplete stream, filtering, cancellation and output limit. Safe reason codes persist on failed Attempts; raw responses and headers do not. HTTP error payloads are read only for in-memory classification and bounded at 16 KiB.

The request has both stream inactivity checks and a total deadline. Stop signals the HTTP AbortableRequest and closes the request-owned client. Runtime remains authoritative for cancel/completion races and ignores output after terminal status. Explicit awaited owner disposal first lets preparation finish/reject, then cancels active Runtime handles and waits for their settlement. Closing a request may not undo server-side token use; no refund guarantee is made.
