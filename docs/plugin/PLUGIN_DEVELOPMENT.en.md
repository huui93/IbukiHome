# IbukiHome Mobile plugin development

[简体中文](PLUGIN_DEVELOPMENT.md) · **English**

This reference describes IbukiHome Android v1.1.0 (build 4) and plugin extension APIs v1 and v2. API names, JSON fields, and enum values are case-sensitive.

## Choose an extension point

| Goal | Extension point | Entry in the app |
| --- | --- | --- |
| Add structured styles, prompt presets, or generation templates to fiction | **Declarative novel plugin v2** | Novel → Create → Work → Novel Settings → Novel plugins |
| Add an interactive local page to a conversation | **Chat Web panel v1** | Open a chat and choose the panel from the conversation actions |
| Add writing-style preferences to chat or ordinary fiction generation | **Declarative style v1** | Settings → Plugins → Plugin details → AI scope |

The host executes novel v2 JSON presets. Chat Web panels receive the `window.ibuki` bridge. Novel rendering, branch events, and background tasks are provided by the host through the declarative features described below.

## 1. Package, install, and version a plugin

An `.ibuki` package is a ZIP containing the **contents** of the plugin directory, with `manifest.json` at the root. Use UTF-8 for JSON, text, and HTML. Reference resources by package-relative paths such as `prompts/style.txt`.

| Manifest field | Contract |
| --- | --- |
| `manifestVersion` | Integer. Use `1`. |
| `extensionApiVersion` | Integer. Defaults to `1`. Use `2` for structured novel presets. |
| `id`, `name`, `version` | Required strings. An ID may contain letters, digits, periods, underscores, and hyphens. Keep the ID stable across releases. `version` describes your plugin release. |
| `author`, `description` | Optional. Help installers identify the plugin and understand its purpose. |
| `minIbukiVersion` | Optional minimum app version. The host checks it independently of `extensionApiVersion`. |
| `runtime.type` | `declarative` or `web`. Declare Web entry pages in `contributions.chatPanels[].entry`. |
| `permissions`, `capabilities` | Arrays of permission and capability names. |
| `contributions` | Extension point object, such as `novel` or `chatPanels`. |
| `metadata` | Optional object for provenance or migration notes. |

The ZIP is limited to 150 MiB compressed, 75 MiB per extracted file, 400 MiB total extracted size, 4,096 ZIP entries, and a 1 MiB manifest. The importer rejects absolute paths, `..`, symlinks, and paths that differ only in case. Novel presets and all referenced text resources share a 2 MiB budget. Each chat panel HTML, CSS, or JS file has a 2 MiB limit.

Save each example in its own directory. Run the packaging script from outside the plugin directory, for example `python pack_ibuki.py ./my-novel ./my-novel.ibuki`.

```python pack_ibuki.py
from pathlib import Path
from sys import argv
from zipfile import ZIP_DEFLATED, ZipFile

root = Path(argv[1]).resolve()
target = Path(argv[2]).resolve()
if not (root / "manifest.json").is_file():
    raise SystemExit("manifest.json must be directly inside the source directory")
if target.suffix.lower() != ".ibuki" or root in target.parents:
    raise SystemExit("write an .ibuki file outside the source directory")

with ZipFile(target, "w", ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise SystemExit(f"symbolic links are unsupported: {path}")
        if path.is_file():
            archive.write(path, path.relative_to(root).as_posix())
```

Open **Settings → Plugins → Install plugin** (`安装插件`), select the file, and review the permissions before installing it. An update uses the same `id` and a new `version`. Updating replaces package resources and preserves plugin data. Uninstalling offers a choice to keep that data. The app stores private plugin data separately from package files.

## 2. Declarative novel plugin v2

### Minimal example with two styles

Create `manifest.json`, `preset.json`, and `prompts/natural.txt`. Replace the example plugin ID with your own.

```json novel/manifest.json
{
  "manifestVersion": 1,
  "extensionApiVersion": 2,
  "id": "org.example.novel.styles",
  "name": "Novel Style Example",
  "version": "1.0.0",
  "runtime": {"type": "declarative"},
  "capabilities": ["novel-host-v2"],
  "permissions": ["ai.prompt.modify"],
  "contributions": {"novel": {"preset": "preset.json"}}
}
```

```json novel/preset.json
{
  "id": "example-novel-styles",
  "entries": [
    {
      "id": "style-natural",
      "name": "Natural",
      "enabled": true,
      "role": "system",
      "position": "beforeHistory",
      "order": 10,
      "resource": "prompts/natural.txt"
    },
    {
      "id": "style-mystery",
      "name": "Mystery",
      "enabled": false,
      "role": "system",
      "position": "beforeHistory",
      "order": 20,
      "text": "Use an existing detail to plant a clue. Reveal it later and preserve established facts."
    },
    {
      "id": "story-history",
      "name": "Story-line history",
      "position": "beforeHistory",
      "order": 100,
      "placeholder": "chatHistory"
    }
  ],
  "groups": {"tone": ["style-natural", "style-mystery"]},
  "schemes": {
    "Natural": {"groups": {"tone": "style-natural"}},
    "Mystery": {"groups": {"tone": "style-mystery"}}
  },
  "request": {"temperature": 0.7, "contextTokens": 16000, "outputTokens": 512},
  "templates": {"continue": "Continue from the end of the previous passage and write only new prose."}
}
```

```text novel/prompts/natural.txt
Write natural, coherent prose for {{user}}. Keep character voices consistent and advance the plot through concrete actions.
```

In a test novel, enable the plugin and choose **Mystery**. Generate a passage. Open **Prompt and applied parameters for this turn** (`本轮提示词与实际参数`) and check `blocks` and the outgoing request for `style-mystery`. Repeat with **Natural**. Inspection data is kept in the current process and scoped to the story line.

Each story line uses one structured preset at a time. A new story line can inherit the parent configuration or store an override. A bound v2 preset uses the structured generation pipeline. An unbound work can use the v1 style pipeline. Unreadable preset resources or compiler errors are reported for the affected generation.

### Preset fields

| Field | Contract |
| --- | --- |
| `id` | Preset identifier, defined independently of the plugin manifest ID. |
| `entries` | Up to 512 entries. Entry IDs must be unique. |
| `groups` | Maps exclusive group names to arrays of member IDs. At most one member is enabled by default. |
| `schemes` | Maps scheme names to overrides in `entries`, `groups`, `request`, or `variables`. A group override contains a member ID or `null` to disable the group. |
| `request` | Default request suggestions. Users can override them per story line. |
| `templates` | Maps generation modes and wrapper names to template strings. |

| Entry field | Contract |
| --- | --- |
| `id` | 1–150 ASCII letters, digits, periods, underscores, or hyphens. |
| `name`, `enabled` | Display name and default state. Defaults are the entry ID and `true`. |
| `role` | `system`, `user`, or `assistant`. Defaults to `system`. The host formats roles for the selected model API. |
| `position` | `beforeHistory`, `inHistory`, or `afterHistory`. Defaults to `beforeHistory`. |
| `order` | Integer, default `0`. Entries sort in ascending order and retain their original order when tied. |
| `depth` | Insertion depth for `inHistory`, counting backward from the latest passage. `0` inserts after it and `1` inserts before it. |
| `modes` | Array of applicable generation modes. An omitted or empty array applies to all modes handled by the compiler. |
| `text` / `resource` / `placeholder` | Choose exactly one of inline text, a package-relative UTF-8 resource, or a host-provided context placeholder. |

`chatHistory` is the compatibility name for fiction history. A typical preset declares it once at `beforeHistory` with an appropriate `order`. Omitting it lets the host append history. Declaring it and disabling it suppresses that fallback. `groups` defines general exclusivity. The NVWA compatibility layer supplies its own paired start and end behavior.

| Placeholder | Host data |
| --- | --- |
| `chatHistory` | Current story-line text and selected candidates. |
| `charDescription`, `charPersonality` | Character cards selected for this request, including personality from imported cards. |
| `personaDescription` | Author persona from the novel plugin settings. |
| `scenario` | Project description, imported character scenario, and the current scene specified by the author. |
| `worldInfoBefore`, `worldInfoAfter` | This project's world setting and active world-book entries, placed at the requested positions. |
| `dialogueExamples`, `opening` | Examples and an opening from imported character cards. With an enabled `chatHistory` and an empty history, the host can place the opening in the history slot. |

Entries and templates support `{{char}}`, `{{user}}`, `{{group}}`, `{{scenario}}`, `{{personality}}`, `{{date}}`, and `{{time}}`. `{{user}}` comes from the novel's author configuration and defaults to the app's author label. Date and time use the device's local time. Variables expand once. An undefined variable in preset text raises an error. Empty character and scenario data can leave their placeholders empty.

| Mode key | Entry in the app |
| --- | --- |
| `normal` | Generate the next passage. |
| `regenerate` | Rewrite, revise with instructions, or revise a selection. |
| `continue` | Continue from the end of the last passage through the plugin generation modes. |
| `impersonate` | Generate an author draft and put it in the input field. |
| `group` | Choose the novel character who speaks this turn. |
| `empty` | Advance the story with an empty input. |

Selecting another saved candidate switches to existing text. Memory organization runs in a separate host request. `swipe` and `background` are reserved keys in the model layer.

`templates` accepts the mode keys above and the wrappers `historyStart`, `groupHistoryStart`, `examplesStart`, `worldInfoFormat`, `scenarioFormat`, `personalityFormat`, `continuePostfix`, `assistantPrefill`, and `impersonationPrefill`. Use `{0}` in `worldInfoFormat` for the entry body. Native continuation prefill depends on the selected model interface.

### Request parameters and diagnostics

| `request` field | Contract |
| --- | --- |
| `temperature` | Number from 0 to 2. The selected model interface may apply a narrower range. |
| `contextTokens`, `outputTokens` | Positive integers for context budget and output limit. |
| `stream` | Boolean display preference. The app's global streaming-off setting takes precedence. The underlying transport may still use SSE. |
| `reasoning` | `automatic`, `disabled`, `enabled`, `low`, `medium`, `high`, `xhigh`, or `max`. |
| `top_p`, `top_k`, `frequency_penalty`, `presence_penalty`, `seed` | Optional sampling suggestions. Supported fields and ranges depend on the adapter. `seed: -1` uses the random default. |
| `continuePrefill` | Boolean request to prefill a continuation with the previous passage ending. The current adapter applies it for recognized compatible Claude 3 models. |

`requested` shows preset and story-line suggestions, including explicitly configured `projectTemperature` and `projectOutputTokenLimit`. Project temperature takes precedence over the plugin suggestion. The host uses the smaller of the project's estimated output token limit and the plugin output limit, subject to model and host limits. `effective` shows the validated result. `wireParameters` shows the parameters the adapter recorded when constructing the request. Context token counts are local estimates. When the budget is reached, the compiler removes older history blocks first. If fixed content exceeds the budget, shorten the preset or increase the budget.

### Memory, presentation, and story-line completion

- **Memory.** Add capability `novel-memory` and permissions `ai.generate` and `novel.generate` to use host-managed organization. `contributions.novel.memory` supports `batchSize` (1–50, default 4) and `automaticDefault` (boolean, off by default). Automatic jobs use the work's selected model. Prompts use memories whose sources still match. World-book scanning can be enabled per memory block.
- **Presentation.** The novel UI renders the markers below using native widgets. `novel.presentation` allows reply presentation data to be saved, including template reasoning and reasoning reported by the model interface. `renderers` and `contributions.novel.panels` can describe capabilities. The host supplies the current panels and marker handling.
- **Complete a story line.** Declare `novel.session.end` and set `contributions.novel.sessionEnd` to `{"attribute":"data-nvwa-end","requiresStoryAuthorization":true}`. The writer authorizes each story line separately. Put the completion marker on its own top-level line after the body. The host evaluates the newest completed and persisted generation. It ignores markers inside code blocks, quotes, older messages, incomplete replies, and previously stored candidates.

| Model output | Presentation |
| --- | --- |
| `————12:30•星期五•九月十三日————` | Timeline label when placed on its own line. |
| `<span data-char="Lin">We have arrived.</span>` | Speaker-specific dialogue color. |
| `<second_space>It is still raining outside.</second_space>` | Secondary-scene card. |
| `<nvwa_notes>The clue is still unresolved.</nvwa_notes>` | Behind-the-scenes card. |
| `<div data-nvwa-ui="Platform"><button data-nvwa-draft="I'm here.">Arrive</button></div>` | Interactive card. The button fills the draft field. |
| `<think>Template text</think>` or `<nvwa_think>Template text</nvwa_think>` | Template reasoning, displayed separately from model-reported reasoning. |
| `<div data-nvwa-end>End of the story line.</div>` | Completion marker for an authorized story line. |

The app owns branch mutations, candidate selection, memory injection, event distribution, background tasks, and private data. Depend on the documented manifest and markup contracts for novel plugins. Host tables, reserved keys, internal Dart classes, and `window.ibuki.novel` are outside the public API.

## 3. Chat Web panel v1

### Minimal conversation panel

```json chat/manifest.json
{
  "manifestVersion": 1,
  "extensionApiVersion": 1,
  "id": "org.example.chat.status",
  "name": "Conversation status",
  "version": "1.0.0",
  "runtime": {"type": "web"},
  "permissions": ["ui.extend", "chat.read"],
  "contributions": {
    "chatPanels": [
      {
        "id": "status",
        "label": "Conversation status",
        "entry": "web/index.html",
        "script": "web/status.js"
      }
    ]
  }
}
```

```html chat/web/index.html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <!-- IBUKI_PLUGIN_STYLE -->
</head>
<body>
  <main>
    <h1>Conversation status</h1>
    <p id="status" role="status">Loading…</p>
  </main>
  <!-- IBUKI_PLUGIN_SCRIPT -->
</body>
</html>
```

```javascript chat/web/status.js
async function showStatus() {
  const status = document.getElementById('status');
  try {
    const [session, recent] = await Promise.all([
      window.ibuki.chat.getCurrentSession(),
      window.ibuki.chat.getRecentMessages(20),
    ]);
    status.textContent = session
      ? session.title + ' · ' + recent.length + ' recent messages'
      : 'No conversation is available';
  } catch (error) {
    status.textContent = error.message;
  }
}
showStatus();
```

Panel fields `id`, `label`, and `entry` are required. `icon`, `style`, and `script` are optional. Set `"style": "web/status.css"` to attach a stylesheet. Keep both HTML injection comments. The host uses `IBUKI_PLUGIN_SCRIPT` to insert the bridge and local script. Render user, conversation, and model data with `textContent`. The panel runs in a local WebView with external network access and page navigation restricted. Use the host bridge for model calls.

### JavaScript API

Calls return promises. The host binds the open panel to its plugin identity and current conversation.

| Call | Required permission | Result |
| --- | --- | --- |
| `ibuki.context.get()` | Open panel | `{plugin:{id,name,version},route,sessionId,projectId}`. Can include `character` with `character.read`. |
| `ibuki.plugin.getMetadata()` | Open panel | Manifest for the current plugin. |
| `ibuki.chat.getCurrentSession()` | `chat.read` | `{id,title,projectId,personaId}` or `null`. |
| `ibuki.chat.getMessages()` | `chat.read` | Messages in the current conversation. |
| `ibuki.chat.getRecentMessages(limit = 30)` | `chat.read` | Latest `limit` messages in their original order. `limit` is an integer from 1 to 200. |
| `ibuki.chat.getCurrentCharacter()` | `character.read` | `{id,name,shortDescription}` or `null`. |
| `ibuki.storage.get(key)` | `storage.private` | JSON value or `null`. |
| `ibuki.storage.set(key, value)` | `storage.private` | `{saved:true}`. |
| `ibuki.storage.remove(key)` | `storage.private` | `{removed:true}`. |
| `ibuki.storage.clear()` | `storage.private` | `{cleared:true}` when the plugin's user data is cleared. |
| `ibuki.ai.generate(prompt, options = {})` | `ai.generate` | Generation result object. See the example below. |

Message objects have `{id,role,content,createdAt}`. Roles are `user`, `assistant`, and `system`. Timestamps are UTC ISO 8601 strings. Handle nullable IDs as `null`. Conversation APIs are read-only.

Private storage is scoped to the plugin ID. A plugin shares its storage across conversations. Include `session.id` in the key for per-conversation state. Keys are 1–128 characters and exclude control characters and the reserved `__ibuki_host__:` prefix. Each value has a 256 KiB UTF-8 JSON limit.

`ibuki.ai.generate` uses the current conversation's resolved model. Call it in response to a user action.

```javascript
const result = await window.ibuki.ai.generate(
  'Give this user-approved excerpt a title: ' + excerpt,
  {systemPrompt: 'Return only a title.', maxOutputTokens: 128}
);

if (result.finishReason === 'stop') {
  output.textContent = result.text;
}
```

The response contains `{requestId,text,finishReason,interrupted,model:{provider,id,displayLabel}}`. The default output budget is 1,024 tokens, bounded by the host to 1–4,096. Trimmed `prompt` must be 1–64,000 UTF-16 code units. `systemPrompt` is limited to 16,000 code units. The bridge also limits the full request to 65,536 UTF-16 code units. Handle busy errors and timeouts with `try/catch`. The default timeout is 120 seconds. Finish reasons include `stop`, `length`, `contentFiltered`, `interrupted`, and `cancelled`. Disable repeat submissions while the request is in progress. The host manages API keys, authentication headers, and model clients.

## 4. Declarative style v1

Use a single manifest to add style guidance to ordinary generation. Users set the scope on the plugin details screen.

```json style/manifest.json
{
  "manifestVersion": 1,
  "extensionApiVersion": 1,
  "id": "org.example.style.tone",
  "name": "Concise style",
  "version": "1.0.0",
  "runtime": {"type": "declarative"},
  "permissions": ["ai.prompt.modify"],
  "promptContributions": [
    {
      "id": "style",
      "operations": ["novel.generate", "novel.rewrite", "chat.reply"],
      "styleInstruction": "Use a {{setting.tone}} tone and follow the writer’s current instructions.",
      "exclusive": true
    }
  ],
  "settingsSchema": {
    "tone": {
      "type": "enum",
      "label": "Tone",
      "values": ["Natural", "Restrained"],
      "default": "Natural"
    }
  }
}
```

`operations` supports `novel.generate`, `novel.rewrite`, `novel.modify`, `novel.selectionModify`, `chat.reply`, and `chat.continue`. The optional `beforeUserInstruction`, `afterContext`, and `finalInstruction` fields place style guidance at the named positions. Work and conversation bindings take precedence over global bindings. Settings types are `boolean`, `enum`, `number`, and `string`, with optional `label` and `description`. Enum settings accept `valueLabels` and numbers accept `min` and `max`. Reference settings with `{{setting.key}}`. The host preserves the priority of user instructions, characters, world settings, and existing text.

## Before publishing

1. Install a fresh package in a test environment. Verify the manifest location, permissions, resource paths, and entry point in the app.
2. Run a novel preset in a test work, switch schemes, and compare the actual requests. Create a branch and verify both inheritance and overrides. Check a separate work for isolation.
3. Open the Web panel from two conversations. Verify the scope of reads and storage, behavior with missing permissions or an empty history, and failed requests.
4. Install an update using the same plugin ID and confirm that existing settings are readable. Document the supported extension API version, required permissions, quickest way to try the plugin, and models you tested.
