# SillyTavern compatibility decisions

Behavior references: the Phase 1 porting study, [pinned SillyTavern source](https://github.com/SillyTavern/SillyTavern/blob/06bde939fb1e9c4c8d8641d810f0a916b5bce127/public/scripts/world-info.js), and [official SillyTavern World Info documentation](https://docs.sillytavern.app/usage/core-concepts/worldinfo/). This is an independent Dart implementation, not a JS translation. The porting-study worktree contains the fixture ledger; this document does not claim unexecuted differential parity.

| Capability | v1 decision |
|---|---|
| Primary plain keys, four secondary logics, constant, enable filter, generation trigger | ST-inspired matching semantics, deterministic fixtures |
| Case insensitive by default, whole-word option, per-entry scan depth | ST-inspired; CJK substring default is intentional mobile divergence |
| Group weight, priority, key scoring, sticky preference | ST-inspired; overlapping multi-group conflicts use one connected-component winner, not certified ST parity |
| Probability after group; sticky bypasses reroll | Matches observed phase-1 ordering |
| Recursive content activation, exclusion/prevention, bounded passes | ST-inspired; no extension mutation hooks or min-activation depth sweeps |
| Sticky/cooldown/delay measured in messages | ST-inspired; state commits only on successful generation and resets at restart |
| Chat/character/persona/world books, character ID/tag filters, optional character/persona scan fields | Multiple selected books accepted; reference resolution and knowledge-safe field supply belong upstream |
| World Info-specific budget/cap and ignoreBudget | Not in v1; Prompt Compiler handles final budget, an intentional difference |
| Regex keys, macro expansion, named outlets, automation scripts, vector matching | Preserved/imported data only; never executed here |
| ST per-message name prefixes, scan-enabled extension prompts, exact source ordering | Not in v1 |
| Prompt placement | Native supported placements map to Prompt IR; unsupported ST positions stay preserved, not silently claimed |

The native `LoreEntry` adapter maps enabled, constant/keyword/manual, keys, content, probability, priority/order and supported insertion positions. ST unsupported rules and extensions remain in compatibility payload; neither adapter nor runtime executes them. The runtime receives an already-selected entry list, not a raw 100,000-entry library scan.

## Acceptance matrix

`COMPATIBLE` below means the tested subset of the pinned source's behavior, **not** full SillyTavern parity. `UNVERIFIED` means the source audit or differential fixture did not establish exact equivalence.

| Capability | Pinned ST behavior | World Next v1 | Verdict |
|---|---|---|---|
| Primary / secondary | Primary OR; four selective secondary modes | Same plain-key conditions | COMPATIBLE subset |
| Constant / probability | Constant skips key matching; probability after group | Same ordering, seeded keyed sample | COMPATIBLE subset |
| Group | Sticky/override/scoring/weight affect choice | Stable connected-component competition; no extension hooks | INTENTIONAL DIVERGENCE for overlapping groups |
| Recursion | Successful content expands buffer with depth and budget controls | Newly activated content, visited guard, finite passes; compiler budget is later | INTENTIONAL DIVERGENCE at budget edge |
| Sticky / cooldown / delay | Timed effects derive from chat history | Projected message counts, completed-attempt commit, transient state | INTENTIONAL DIVERGENCE across restart |
| Match normalization | Per-entry case/whole-word behavior; regex and macros may apply | Plain keys, case/whole-word, CJK substring; no regex/macro | INTENTIONAL DIVERGENCE |
| Scan depth | Per-entry override of chat scan window | Per-entry override of selected visible projection | COMPATIBLE subset |
| Generation filters | ST trigger filters vary by generation type | Normal/regenerate/continue filters only | UNVERIFIED for other ST triggers |
| Prompt placement | Multiple positions and named outlets | Supported native placement/role only | INTENTIONAL DIVERGENCE |
| Extension mutation | Hooks may alter scan state | No hooks or executable payload | INTENTIONAL DIVERGENCE, security boundary |

The current two-stage budget policy is documented in [acceptance](24-world-info-acceptance.md). It is **not** represented as ST-equivalent. Exact differential parity for advanced recursion, grouping and timed effects remains unverified.
