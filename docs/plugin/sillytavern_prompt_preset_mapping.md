# SillyTavern Prompt Preset to Ibuki Creative Runtime

This document reserves a compatibility path; it is not a complete adapter.

| SillyTavern concept | Ibuki Creative Runtime v1 |
| --- | --- |
| Main/system prompt style | `PluginPromptContribution.styleInstruction` |
| Prompt injection before user text | `beforeUserInstruction` low-priority layer |
| Post-history instruction | `afterContext` |
| Final style instruction | `finalInstruction` plus Host precedence guard |
| Preset toggles/sliders/text | `settingsSchema` and Core-rendered settings UI |
| Per-character/preset activation | `global`, `project`, or `chatSession` binding |
| Prompt callbacks | owner-scoped `IbukiHookBus` prompt hooks |
| Direct provider call | permission-gated `IbukiPluginAI.generate` |

Ibuki does not import SillyTavern presets as executable JavaScript. A future
adapter should convert declarative fields, preserve unknown metadata, require
explicit scope binding, and keep author instructions above plugin style.
