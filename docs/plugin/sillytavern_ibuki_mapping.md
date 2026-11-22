# SillyTavern to Ibuki Extension API Mapping

## Design rule

RUBY is the first consumer, not the owner, of these APIs. Every Host surface in
this document must be useful to other plugins and must be permission-scoped.
No plugin receives a Repository, SQLite connection, Secure Storage handle,
provider key, Authorization header, Flutter private State, or native channel.

## Capability map

| SillyTavern / RUBY dependency | Purpose | Ibuki API | Permission | Class |
| --- | --- | --- | --- | --- |
| PNG `chara` / `ccv3` metadata | Import character and discover embedded extensions | `SillyTavernCardImporter` | Import-time user action | C |
| `window.SillyTavern.getContext()` | Resolve current host state | `IbukiPluginContext.snapshot()` | Per returned capability | C |
| `ctx.chat`, `ctx.chat_metadata` | Read current session and messages | `IbukiChatAPI` | `chat.read` | C |
| `ctx.characters`, character id | Read current Persona/Character | `IbukiCharacterAPI` | `character.read` | C |
| `localStorage` | Plugin settings and UI state | `PluginStorage` | `storage.private` | B/C |
| `/getvar`, `/setvar`, global variants | Task/cursor state | `PluginStorage` with plugin namespace and typed values | `storage.private` | C |
| Character/chat-book get/find/create/write | Structured analysis state | Plugin-owned data or a typed domain contribution API | Separate read/write permissions | C |
| `after_ai` | React after a completed AI response | `IbukiHookBus.afterAiResponse` | `chat.read` as needed | C |
| DOM input/click/change events | Plugin panel interactions | Web document local event system | `ui.extend` | E |
| `MutationObserver` / `window.message` | Detect host stream/UI changes | Semantic Bridge events | Hook permission | C/E |
| `/xbgenraw` and model calls | Generate analysis safely | `IbukiAI.generate()` | `ai.generate` | C |
| Model/base URL/API key controls | Bypass host provider selection | Not exposed; use current resolved model | None | F |
| `fetch` | Remote resource or provider access | Future `PluginNetworkAPI.request()` | `network` | C/F |
| Direct OpenAI/Gemini/DeepSeek key access | Provider authentication | Never exposed | Impossible | F |
| `document`, selectors, HTML, CSS, jQuery | Render the RUBY panel | Sandboxed Web Plugin View | `ui.extend` | E |
| Selecting Core page DOM | Modify host private UI | Not supported | None | F |
| `Blob` export | Export plugin-owned preset data | Web blob inside sandbox or Host file export API | `storage.private` / explicit user action | C/E |
| Images/fonts/audio | Local panel resources | `IbukiAssetResolver` or packaged web assets | `ui.extend` | B/E |
| Google Fonts URL | Remote font load | Package font locally; network denied by default | None | F |
| Toast/confirm | User feedback and confirmation | `IbukiUI.notify()` / `IbukiUI.confirm()` | `ui.extend` | C |
| `window.XBTasks`, generic `STscript` | Xiaobaix task execution | Future compatibility runtime, not a raw command bridge | Runtime-specific | D |

Class meanings: A already supported; B extends an existing Foundation surface;
C new general Extension API; D future executable runtime; E Web Runtime; F
unsafe or intentionally unsupported as-is.

## Implemented v1 context facade

```dart
class IbukiPluginContext {
  InstalledPlugin get plugin;
  String get currentRoute;
  String? get currentSessionId;
  String? get currentProjectId;
  PluginStorage get storage;
  IbukiHookBus get hooks;
  IbukiChatApi get chat;
}
```

Each facade checks the installed plugin identity and current grants for every
call. Data transfer objects expose only stable, minimal fields; they are not
Core domain entities and cannot be cast back to repositories.

## Chat and character APIs

The implemented read-only contract needed by RUBY is:

```dart
abstract interface class IbukiChatAPI {
  Future<PluginChatSessionSummary?> getCurrentSession();
  Future<List<PluginChatMessageSummary>> getMessages();
  Future<List<PluginChatMessageSummary>> getRecentMessages({int limit = 50});
  Future<PluginPersonaSummary?> getCurrentPersona();
  Future<PluginPersonaSummary?> getSafeCharacterContext();
}
```

`chat.read` does not imply `chat.write`. Message mutation, deletion, raw prompt
access, and cross-session enumeration are absent. The Host enforces limits and
returns no secret provider configuration.

## Namespaced PluginStorage

`localStorage` and SillyTavern variables map to a persistent, plugin-scoped
key/value API:

```dart
abstract interface class PluginStorage {
  Future<Object?> get(String key);
  Future<void> set(String key, Object? value);
  Future<void> remove(String key);
  Future<void> clear();
}
```

The namespace is derived from the installed plugin id and is never supplied by
JavaScript. Values have size/depth limits and must be JSON-compatible. The PoC
key replacing `ruby_analyzer_ui_state` stays inside
`compat.sillytavern.ruby.poc`. Force-stop persistence is required. Plugins
cannot enumerate another plugin's namespace or Core tables.

## Semantic event API

RUBY's `after_ai`, DOM mutation checks, and stream polling should become stable
host events:

- `afterAiResponse`
- `afterChatMessageSaved`
- `afterUserMessageSaved`
- `onChatSessionChanged`
- `onCharacterChanged`
- `onPluginEnabled`
- `onPluginDisabled`

Host events contain ids and bounded summaries, not prompt or response bodies by
default. Permission checks apply when a plugin requests message content.
Subscriptions belong to the plugin lifecycle and are removed automatically on
disable/uninstall. One handler failure is returned to that plugin and does not
break Chat.

## AI bridge

RUBY's `/xbgenraw`, custom OpenAI endpoint, model selector, and API-key fields
must be replaced by a Core-owned call:

```dart
abstract interface class IbukiPluginAi {
  Future<PluginAiResult> generate(PluginAiRequest request);
  Future<void> cancel(String requestId);
}
```

The Host resolves the current ChatSession model, validates `ai.generate`, reads
the key internally, classifies timeout/provider/filter errors, and returns only
the generation result and safe diagnostics. The plugin cannot select a hidden
provider, inspect credentials, or receive Authorization headers.

The RUBY panel PoC does not need AI and therefore should not request this
permission. AI compatibility can be a later, separately reviewed increment.

## Two UI routes

### Native contributions

New Ibuki plugins should prefer Flutter-owned extension slots, style tokens,
asset overrides, and declared layouts. This is efficient and integrates with
accessibility and themes.

### Web compatibility runtime

DOM-heavy SillyTavern extensions are better served by a sandbox Web Plugin View
than by rewriting every selector, template, and jQuery interaction into
Flutter. The Web Runtime is a compatibility layer, not access to the Core UI.

```text
.ibuki local web assets
        |
Sandbox Web Plugin View
        |
IbukiWebPluginBridge (one protocol channel)
        |
Permission + capability + argument validation
        |
Typed Extension APIs
        |
Core services
```

## Web Runtime security profile

- Host-read only the manifest-declared files from the installed plugin's
  private directory and stitch them into an in-memory document. The WebView
  receives no browseable filesystem origin.
- Block `http`, `https`, `file`, `content`, `intent`, and custom navigation by
  default. `window.open` is denied.
- Never attach the bridge to a remote document.
- Disable arbitrary Android interfaces, native channels, file browsing, and
  shell/intent access.
- Keep service workers, geolocation, camera, microphone, downloads, and popups
  disabled unless a future permission explicitly enables a mediated feature.
- Do not expose a raw JavaScript reflection bridge.
- Terminate and mark only the plugin panel failed when JavaScript or bridge work
  throws; Core Chat remains available and the user can disable the plugin.

Recommended initial CSP:

```text
default-src 'none';
script-src 'unsafe-inline';
style-src 'unsafe-inline';
img-src data:;
connect-src 'none';
media-src 'none';
frame-src 'none';
object-src 'none';
base-uri 'none';
form-action 'none'
```

The PoC must package any needed CSS, fonts, or libraries locally. It must not
load Google Fonts or remote jQuery.

## Bridge message protocol

All Web plugins use one allowlisted protocol:

```json
{
  "requestId": "plugin-generated-id",
  "method": "chat.getRecentMessages",
  "params": {"limit": 20}
}
```

Success:

```json
{"requestId": "plugin-generated-id", "result": {}}
```

Failure:

```json
{
  "requestId": "plugin-generated-id",
  "error": {"code": "permission_denied", "message": "Permission denied."}
}
```

Implemented allowlist for the RUBY panel PoC:

- `context.get`
- `plugin.getMetadata`
- `chat.getCurrentSession`
- `chat.getMessages`
- `chat.getRecentMessages`
- `storage.get`
- `storage.set`
- `storage.remove`
- `storage.clear`

`context.get` includes the safe character summary only when the installed
plugin has `character.read`. Hook subscription is a Host-side lifecycle API in
v1 and is intentionally not exposed to Web JavaScript yet.

Every method validates plugin id, enabled state, manifest permission, runtime
capability, parameter names/types/ranges, response size, and lifecycle token.
Unknown methods are rejected. Bridge method strings never map to Flutter
reflection.

## Import boundary for embedded scripts

Character data and executable extension data are separate security domains:

```text
Import Character Card
        |
Parse character data
        |
Detect embedded extension scripts
        |
Show explicit warning and metadata
        |
User chooses conversion/install separately
        |
Permission review
        |
Enable plugin
```

Importing a character card must never execute `xiaobaix-tasks`, HTML, CSS, or
JavaScript. The original extension source may be retained as quarantined import
evidence, but only reviewed/reimplemented Ibuki content can be enabled.

## General value of the proposed APIs

These APIs are not RUBY-specific:

- Context and read-only Chat facades support status panels, relationship tools,
  transcript utilities, and accessibility extensions.
- Namespaced storage supports every stateful plugin.
- Semantic hooks support memory, analytics, UI refresh, and workflow plugins.
- Core-owned AI supports analysis and creative tools without secret exposure.
- A sandbox Web Runtime supports other SillyTavern and DOM-heavy compatibility
  projects.
- Native slots remain the preferred route for new Ibuki-first plugins.

The Xiaobaix task engine itself is not generalized in this phase. Emulating it
would be a separate runtime compatibility project with a larger attack surface.
