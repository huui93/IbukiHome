# Provider and model capabilities

Capabilities are explicit `TavernModelCapabilities` supplied for the configured Provider/model, optionally persisted with `TavernModelProfileStore` in the existing secure settings store. No model name is inspected to enable a feature. Without a profile, the conservative limits are 4096 context / 512 maximum output, with no reasoning or continuation advertised. These are application limits, not a claim about an unknown model's true capacity.

| Provider | Protocol | Visible text | Reasoning | Continue |
|---|---|---|---|---|
| DeepSeek | Chat Completions | delta.content | delta.reasoning_content only with explicit native capability | Explicit instruction strategy or beta prefix capability |
| OpenAI | Chat Completions | delta.content | No fabricated reasoning; configured native field only if actually returned | Explicit instruction strategy |
| OpenAI | Responses | output_text delta | Actual reasoning text or reasoning summary, distinguished by event | Explicit instruction strategy |
| Gemini | Native streamGenerateContent | candidate text parts | `thought` text is summary, not native internal reasoning | Explicit instruction strategy; no prefix parity claimed |
| Custom | Standard Chat Completions | delta.content | reasoning_content is opt-in | Conservative unsupported, or explicit instruction strategy |

DeepSeek prefix mode requires the user-configured `/beta` endpoint and a final assistant prefix. It never changes endpoint or credentials automatically. The alternative instruction strategy is a visible compiled generation instruction after the existing selected answer; it is not treated as native prefix continuation. [DeepSeek prefix documentation](https://api-docs.deepseek.com/guides/chat_prefix_completion), [Gemini thinking summaries](https://ai.google.dev/gemini-api/docs/thinking).

The model profile also describes system/developer role support, streaming, token-count accuracy, tool calling and multimodal input. V1 invokes streaming text only; tool and multimodal execution are explicitly unsupported even when the external model has those capabilities. Kimi is outside the four-provider scope and fails explicitly rather than guessing a compatible protocol.

Only explicit supported generation parameters are serialized. Protocol-specific allowlists and type/range checks reject reserved fields and unsupported parameters before HTTP. Optional Chat stream usage requests require `streamUsage=true`; unknown Custom defaults do not enable this extension. V1 token counting stays estimated; selecting exact counting is unsupported until an exact tokenizer path exists. Prompt Compiler receives the model context window and output/control reservations; a real context-overflow response remains a typed error without Adapter trimming. Gemini native reasoning is rejected during preflight; only its actual summary is supported.
