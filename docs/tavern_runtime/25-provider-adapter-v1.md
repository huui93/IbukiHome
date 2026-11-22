# Provider Adapter v1

Baseline: `bc6bedf8ae72f5a085819813783aeb4c1cbe18e3`, `mobile-tavern-world-info-runtime-v1-approved`.

`TavernProviderAdapter` converts Compiled Prompt IR and an explicit model binding into a request, then emits provider-neutral text, reasoning, usage and finish events. It has no repository or story identity. `TavernProviderDriver` attaches these events to the selected Generation Attempt through the existing Runtime contract. No Provider code creates a Turn, selects an Alternative, writes a Content Part or commits lore state.

## Reuse audit

| Existing component | Decision | Reason |
|---|---|---|
| AiProviderConfigRepository | Reuse | Provider identity, configured endpoint and model remain user-owned |
| SecureApiKeyStore / FlutterSecureValueStore | Reuse | Credentials stay outside story SQLite and archives |
| aiHttpClientFactoryProvider | Reuse | Existing HTTP environment and TLS behavior; a separate client per request allows cancellation |
| normalizeAiProviderBaseUri | Reuse | Existing endpoint normalization without host substitution |
| Old OpenAI/Gemini clients | Keep unchanged | Their legacy event path does not provide the complete typed Tavern reasoning contract |
| Legacy AI Generation service / World Engine | Do not use for execution | Tavern uses Foundation identities and the frozen Generation Runtime |
| Existing Provider/model settings | Reuse | No extra global Provider store or hidden model-name inference |
| Model capability profiles | New thin settings adapter | Explicit per Provider/model configuration, outside story schema |

The existing OpenAI path uses Chat Completions. Tavern additionally supports an explicit Responses protocol; neither parser guesses the protocol from payload field names. Gemini uses its native REST endpoint and `systemInstruction` plus user/model contents.

Official protocol references checked during implementation: [OpenAI Chat streaming](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events), [OpenAI Responses streaming](https://developers.openai.com/api/reference/resources/responses/streaming-events), [DeepSeek Chat API](https://api-docs.deepseek.com/api/create-chat-completion/), [Gemini Generate Content](https://ai.google.dev/api/generate-content).

The serialized request preserves compiled segment order. Reference labels are inserted by source assembly before token budgeting. The Adapter does not add hidden prompt instructions, remove sources or perform a second budget trim. Request metadata stores a SHA-256 fingerprint, provider/model/protocol, token usage and character counts, not the request body or credential.

Credentials go only to the configured validated endpoint. HTTPS is default. Explicit local HTTP is limited to loopback/private numeric IPs or localhost; hostname prefixes do not establish a local address. Redirect following and TLS bypass are disabled/not introduced. Responses use `store: false` and `truncation: disabled`. There is no automatic chargeable retry.
