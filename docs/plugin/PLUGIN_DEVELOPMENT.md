# IbukiHome Mobile 插件开发接口

适用于 NVWA 小说预览版（App `1.0.0+1`，插件扩展 API v1–v2）。这份文档以该版本已接通的入口为准。接口、JSON 字段和枚举值区分大小写。

## 选一个入口

| 想做什么 | 使用什么 | 用户从哪里打开 |
| --- | --- | --- |
| 给小说增加结构化文风、提示词方案、生成模板 | **小说声明式插件 v2** | 小说 → 创作 → 选作品 → 小说设置 → 小说插件 |
| 给聊天增加一个有交互的本地页面 | **聊天 Web 面板 v1** | 打开一条聊天会话，在会话操作区打开插件面板 |
| 给聊天或普通小说生成增加文风偏好 | **文风声明 v1** | 主设置 → 插件 → 插件详情 → 影响 AI 的范围 |

小说 v2 由宿主执行 JSON 预设。聊天 Web 面板才提供 `window.ibuki`。通用小说 Web 桥、独立酒馆运行时的插件入口、第三方分支事件订阅和自定义后台任务接口，在此版本尚未开放。

## 1. 打包、安装和版本

`.ibuki` 是 ZIP 文件。压缩的是插件目录的**内容**，ZIP 根目录必须有 `manifest.json`。JSON、文本和网页使用 UTF-8。统一使用包内相对路径，如 `prompts/style.txt`。

| Manifest 字段 | 约定 |
| --- | --- |
| `manifestVersion` | 整数，当前固定为 `1` |
| `extensionApiVersion` | 整数，省略等于 `1`。小说结构化预设填 `2` |
| `id`、`name`、`version` | 必填字符串。ID 允许字母、数字、点、下划线和连字符。发布后保持 ID 稳定 |
| `author`、`description` | 可选。供安装者判断作者与用途 |
| `minIbukiVersion` | 可选。最低 App 版本。App 版本和扩展 API 版本各自检查 |
| `runtime.type` | `declarative` 或 `web`。Web 页面入口在 `contributions.chatPanels[].entry` |
| `permissions`、`capabilities` | 字符串数组。分别声明权限和能力 |
| `contributions` | 贡献点对象，例如 `novel` 或 `chatPanels` |
| `metadata` | 可选对象。适合放来源、迁移说明等信息 |

安装上限为压缩包 150 MiB、单个解压文件 75 MiB、解压合计 400 MiB、4096 个 ZIP 条目、Manifest 1 MiB。绝对路径、`..`、符号链接和仅大小写不同的重名路径都会被拒绝。小说的预设 JSON 与它引用的全部独立文本文件合计上限为 2 MiB。聊天 Web 面板的 HTML、CSS 和 JS 每个文件上限为 2 MiB。

将下列示例文件放入各自的目录。在目录**外**执行以下脚本，例如 `python pack_ibuki.py ./my-novel ./my-novel.ibuki`。

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

在 **主设置 → 插件 → 安装插件** 选择包，检查权限后确认。同一 `id` 用于更新已有插件，`version` 随发行迭代。更新会更换包资源并保留插件数据。卸载时可选择是否保留插件数据。各插件的私有数据与包文件分别保存。

## 2. 小说声明式插件 v2

### 最小示例 · 两套可切换文风

目录包含 `manifest.json`、`preset.json` 和 `prompts/natural.txt`。使用自己的插件 ID。

```json novel/manifest.json
{
  "manifestVersion": 1,
  "extensionApiVersion": 2,
  "id": "org.example.novel.styles",
  "name": "小说文风示例",
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
      "name": "自然",
      "enabled": true,
      "role": "system",
      "position": "beforeHistory",
      "order": 10,
      "resource": "prompts/natural.txt"
    },
    {
      "id": "style-mystery",
      "name": "悬疑",
      "enabled": false,
      "role": "system",
      "position": "beforeHistory",
      "order": 20,
      "text": "用已有细节埋下一条线索，延迟揭晓。保留已发生的事实。"
    },
    {
      "id": "story-history",
      "name": "本故事线历史",
      "position": "beforeHistory",
      "order": 100,
      "placeholder": "chatHistory"
    }
  ],
  "groups": {"tone": ["style-natural", "style-mystery"]},
  "schemes": {
    "自然": {"groups": {"tone": "style-natural"}},
    "悬疑": {"groups": {"tone": "style-mystery"}}
  },
  "request": {"temperature": 0.7, "contextTokens": 16000, "outputTokens": 512},
  "templates": {"continue": "从上一段末尾接上，只写新增的正文。"}
}
```

```text novel/prompts/natural.txt
面向{{user}}写自然连贯的正文。保持人物语气一致，用具体行动推进情节。
```

安装后进入一部小说的「小说插件」，打开该插件并选择「悬疑」。回到创作页生成一段，打开 **本轮提示词与实际参数**。检查 `blocks` 和请求正文里是否出现 `style-mystery`。再切回「自然」对照。检查记录随进程保留，并按故事线区分。

同一故事线同时使用一套结构化预设。新故事线可以继承上级配置，也可以保存覆盖。小说 v2 生效时，该轮生成使用结构化流程。作品未绑定 v2 时，仍可走 v1 文风流程。绑定的预设资源不可读或编译失败时，该轮会报告错误。

### 预设字段

| 字段 | 约定 |
| --- | --- |
| `id` | 预设标识。与 Manifest 的插件 ID 是两个字段 |
| `entries` | 条目数组，最多 512 项。条目 ID 必须唯一 |
| `groups` | 互斥组。键为组名，值为成员条目 ID 数组。默认最多启用一个成员 |
| `schemes` | 方案名到配置的映射。使用 `entries`、`groups`、`request` 或 `variables` 覆盖需要调整的部分。组值填成员 ID，`null` 关闭该组 |
| `request` | 默认请求建议。用户可在当前故事线覆盖 |
| `templates` | 模板名到字符串的映射。生成方式和包装模板见下表 |

| 条目字段 | 约定 |
| --- | --- |
| `id` | 1–150 个字符，只使用 ASCII 字母、数字、点、下划线、连字符 |
| `name`、`enabled` | 面板显示名和默认开关。省略时分别取条目 ID 和 `true` |
| `role` | `system`、`user`、`assistant`，默认 `system`。宿主按实际模型接口组织消息 |
| `position` | `beforeHistory`、`inHistory`、`afterHistory`，默认 `beforeHistory` |
| `order` | 整数，默认 `0`。先按数值升序，同值按条目原顺序 |
| `depth` | `inHistory` 向最近一段倒数的插入深度。`0` 在末段之后，`1` 在末段之前 |
| `modes` | 生效方式数组。省略或空数组表示所有经过编译器的生成方式 |
| `text` / `resource` / `placeholder` | 三选一。内联文本、包内 UTF-8 文件、宿主填入的上下文 |

`chatHistory` 是小说故事线正文的占位项，沿用兼容字段名。推荐只声明一次，使用 `beforeHistory` 及合适的 `order`。省略该占位项时宿主自动追加历史。显式声明但关闭时，编译器不自动补回历史。通用互斥以 `groups` 为准。NVWA 专用头尾联动由兼容层处理。

| 可用占位项 | 宿主填入的内容 |
| --- | --- |
| `chatHistory` | 当前故事线中的正文及选中候选 |
| `charDescription`、`charPersonality` | 本轮小说角色卡，以及导入角色卡提供的性格 |
| `personaDescription` | 小说插件设置里的作者人设 |
| `scenario` | 作品说明、导入角色的场景，以及作者指定的当前场景 |
| `worldInfoBefore`、`worldInfoAfter` | 本作世界观和本轮激活的世界书条目，按位置放置 |
| `dialogueExamples`、`opening` | 导入角色卡提供的示例和开场。启用 `chatHistory` 且没有历史时，宿主也可将开场放在历史位置 |

条目文本和模板可使用 `{{char}}`、`{{user}}`、`{{group}}`、`{{scenario}}`、`{{personality}}`、`{{date}}`、`{{time}}`。例如 `{{user}}` 来自本小说的作者设置，默认「作者」。时间使用设备当地时间。变量只展开一轮。预设文本引用未提供的变量时会报错，角色或场景数据为空时，相应占位项可以省略。

| 模式键 | 对应入口 |
| --- | --- |
| `normal` | 生成下一段 |
| `regenerate` | 重写、按要求修改、选区改稿 |
| `continue` | 从插件生成模式选择接着上一段续写 |
| `impersonate` | 代写作者草稿。结果回填输入框 |
| `group` | 选择本轮发言的小说角色 |
| `empty` | 空发推进 |

切换已有候选直接选择存量正文。整理记忆由宿主走单独的后台请求。`swipe` 和 `background` 是模型层保留键，在此版本不会触发普通创作预设模板。

`templates` 可按上表的模式键填写本轮指令，也支持 `historyStart`、`groupHistoryStart`、`examplesStart`、`worldInfoFormat`、`scenarioFormat`、`personalityFormat`、`continuePostfix`、`assistantPrefill`、`impersonationPrefill`。其中 `worldInfoFormat` 用 `{0}` 放入条目正文。原生续写预填充取决于模型接口。

### 请求参数与诊断

| `request` 字段 | 类型和含义 |
| --- | --- |
| `temperature` | 数值。宿主接受 0–2 的建议范围，接口可能进一步约束 |
| `contextTokens`、`outputTokens` | 正整数。分别为上下文预算和输出 token 上限 |
| `stream` | 布尔值，流式显示建议。App 的全局关闭优先，底层连接仍可能使用 SSE |
| `reasoning` | `automatic`、`disabled`、`enabled`、`low`、`medium`、`high`、`xhigh`、`max` |
| `top_p`、`top_k`、`frequency_penalty`、`presence_penalty`、`seed` | 可选采样建议。具体字段和数值范围由当前模型适配器决定，`seed: -1` 表示使用随机默认 |
| `continuePrefill` | 布尔值，申请将上一段末尾用作原生续写预填充。预览版只对识别到的兼容 Claude 3 系列条件应用 |

检查面板的 `requested` 是预设和用户设置合并后的建议值。`effective` 是宿主预算与模型校验后的结果。`wireParameters` 是适配器构造实际请求时记录的参数。上下文 token 数是本地估算；达到预算时，宿主先移除较早的历史块。固定内容本身超出额度时，需要缩短预设或增大额度。

### 原生记忆、展示和结束故事线

- **记忆。** `capabilities` 加入 `novel-memory`，并声明 `ai.generate` 和 `novel.generate`，即可使用宿主提供的记忆整理。可在 `contributions.novel.memory` 设置 `batchSize`（1–50，默认 4）和 `automaticDefault`（布尔值，默认关闭）。自动任务使用作品当前模型。生成时只采用来源仍匹配的记忆，世界书扫描有逐块开关。
- **展示。** 当前小说界面识别下表的固定标记，并用原生组件绘制。`novel.presentation` 用于保存回复展示数据，包括模板思考和接口已返回的原生推理。`renderers` 和 `contributions.novel.panels` 可作为描述元数据，当前版本的面板和标记处理由宿主固定提供。
- **结束故事线。** 需要此功能时，在权限中声明 `novel.session.end`，在 `contributions.novel.sessionEnd` 设置 `{"attribute":"data-nvwa-end","requiresStoryAuthorization":true}`。用户须在当前故事线另行授权。宿主仅在本轮真实完成且写入的最新回复上判断。将 `<div data-nvwa-end>故事收束</div>` 放在正文之后的最后一行，写成独立的顶层标记。代码块、Markdown 引用、旧消息、未完成回复以及切换旧候选都不能触发结束。新分支的授权需单独开启。

| 模型输出标记 | 呈现方式 |
| --- | --- |
| `————12:30•星期五•九月十三日————` | 单独成行，作为时间栏 |
| `<span data-char="小林">到站了。</span>` | 按说话者显示对白颜色 |
| `<second_space>站外仍在下雨。</second_space>` | 第二时空卡片 |
| `<nvwa_notes>线索还没有揭开。</nvwa_notes>` | 幕后卡片 |
| `<div data-nvwa-ui="站台"><button data-nvwa-draft="我到了。">到达</button></div>` | 互动卡片。点按钮只填入草稿 |
| `<think>模板文本</think>` 或 `<nvwa_think>模板文本</nvwa_think>` | 模板思考区，与接口返回的原生推理分别展示 |

目前第三方小说插件能提供上述声明。分支 CRUD、候选切换、记忆注入位置、事件分发、任务和私有数据由 App 内部管理。请勿依赖 SQLite 表、宿主保留键、内部 Dart 类或尚未出现的 `window.ibuki.novel`。

## 3. 聊天 Web 面板 v1

### 最小示例 · 查看会话与最近消息数

```json chat/manifest.json
{
  "manifestVersion": 1,
  "extensionApiVersion": 1,
  "id": "org.example.chat.status",
  "name": "会话状态",
  "version": "1.0.0",
  "runtime": {"type": "web"},
  "permissions": ["ui.extend", "chat.read"],
  "contributions": {
    "chatPanels": [
      {
        "id": "status",
        "label": "会话状态",
        "entry": "web/index.html",
        "script": "web/status.js"
      }
    ]
  }
}
```

```html chat/web/index.html
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <!-- IBUKI_PLUGIN_STYLE -->
</head>
<body>
  <main>
    <h1>会话状态</h1>
    <p id="status" role="status">正在读取…</p>
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
      ? session.title + ' · 最近 ' + recent.length + ' 条消息'
      : '没有可读取的会话';
  } catch (error) {
    status.textContent = error.message;
  }
}
showStatus();
```

面板字段必填 `id`、`label`、`entry`，可选 `icon`、`style`、`script`。要载入样式，可在面板声明里增加 `"style": "web/status.css"`。保留 HTML 中的两个注入注释，尤其是 `IBUKI_PLUGIN_SCRIPT`。宿主在该位置注入桥接对象及本地脚本。使用 `textContent` 展示会话、模型和用户数据。Web 面板运行在本地 WebView，外部网络和外部页面导航受限。模型调用通过下表的宿主接口进行。

### JavaScript 接口

所有调用返回 Promise。会话与插件身份由宿主绑定。

| 调用 | 权限 | 返回 |
| --- | --- | --- |
| `ibuki.context.get()` | 已打开面板 | `{plugin:{id,name,version},route,sessionId,projectId}`。具备 `character.read` 时可包含 `character` |
| `ibuki.plugin.getMetadata()` | 已打开面板 | 当前插件 Manifest |
| `ibuki.chat.getCurrentSession()` | `chat.read` | `{id,title,projectId,personaId}` 或 `null` |
| `ibuki.chat.getMessages()` | `chat.read` | 当前会话的消息数组 |
| `ibuki.chat.getRecentMessages(limit = 30)` | `chat.read` | 最新的 `limit` 条，保持原顺序。`limit` 是 1–200 的整数 |
| `ibuki.chat.getCurrentCharacter()` | `character.read` | `{id,name,shortDescription}` 或 `null` |
| `ibuki.storage.get(key)` | `storage.private` | JSON 值或 `null` |
| `ibuki.storage.set(key, value)` | `storage.private` | `{saved:true}` |
| `ibuki.storage.remove(key)` | `storage.private` | `{removed:true}` |
| `ibuki.storage.clear()` | `storage.private` | `{cleared:true}`。清除该插件的用户数据 |
| `ibuki.ai.generate(prompt, options = {})` | `ai.generate` | 生成结果对象，示例见下方 |

消息字段为 `{id,role,content,createdAt}`。角色可能是 `user`、`assistant` 或 `system`。时间戳为 UTC ISO 8601 字符串。可空的 ID 应当按 `null` 处理。会话 API 只读。

Web 私有存储按**插件 ID**隔离，同一插件的多个聊天会话共享存储。若要按会话保存状态，将 `session.id` 放进键里。键长度 1–128，不使用控制字符或 `__ibuki_host__:` 保留前缀。单个值的 UTF-8 JSON 编码上限为 256 KiB。

`ibuki.ai.generate` 使用当前聊天会话解析出的模型。可在用户点击后调用，例如：

```javascript
const result = await window.ibuki.ai.generate(
  '给这段经过用户确认的文本起一个标题：' + excerpt,
  {systemPrompt: '只返回一个标题。', maxOutputTokens: 128}
);

if (result.finishReason === 'stop') {
  output.textContent = result.text;
}
```

结果字段为 `{requestId,text,finishReason,interrupted,model:{provider,id,displayLabel}}`。默认输出额度 1024 tokens，宿主限制在 1–4096。`prompt` 去除首尾空白后需要 1–64,000 个 UTF-16 代码单元，`systemPrompt` 最多 16,000，整个桥接请求还有 64 KiB 字符长度限制。插件请求可能遇到忙状态或超时（默认 120 秒），用 `try/catch` 展示错误。`finishReason` 也可能为 `length`、`contentFiltered`、`interrupted`、`cancelled` 等。请在发起请求期间禁用重复提交。API 密钥、鉴权头和模型客户端由宿主管理。

## 4. 文风声明 v1

这一入口适合只想在普通生成中添加少量风格辅助的插件。一个 Manifest 即可安装，作用范围由用户在插件详情里绑定。

```json style/manifest.json
{
  "manifestVersion": 1,
  "extensionApiVersion": 1,
  "id": "org.example.style.tone",
  "name": "简洁文风",
  "version": "1.0.0",
  "runtime": {"type": "declarative"},
  "permissions": ["ai.prompt.modify"],
  "promptContributions": [
    {
      "id": "style",
      "operations": ["novel.generate", "novel.rewrite", "chat.reply"],
      "styleInstruction": "优先使用{{setting.tone}}的语气，遵循作者当前要求。",
      "exclusive": true
    }
  ],
  "settingsSchema": {
    "tone": {
      "type": "enum",
      "label": "语气",
      "values": ["自然", "克制"],
      "default": "自然"
    }
  }
}
```

`operations` 当前支持 `novel.generate`、`novel.rewrite`、`novel.modify`、`novel.selectionModify`、`chat.reply` 和 `chat.continue`。可选文本字段还有 `beforeUserInstruction`、`afterContext`、`finalInstruction`，它们会按名字作为文风辅助段落发给模型。作品、会话的具体绑定优先于全局绑定。设置支持 `boolean`、`enum`、`number`、`string`，可用 `label` 和 `description`；枚举可加 `valueLabels`，数值可加 `min`、`max`。通过 `{{setting.键名}}` 引用设置。宿主保留用户指令、角色、世界观和原有正文的优先级。

## 发布前自测

1. 用一个没有旧插件数据的测试环境安装包。检查根目录、权限、资源文件路径和安装后的入口。
2. 小说预设用独立测试作品完成一轮生成，再换一个方案验证实际请求。分叉后检查继承与独立覆盖，确认另一部作品不受影响。
3. Web 面板用两条会话测试读取范围，验证缺少权限、空列表和请求失败时的表现。保存状态时确认所选的键是跨会话共享还是会话独立。
4. 用同一插件 ID 打包一份更新，验证旧设置仍可读。发布时附上适用的扩展 API 版本、权限用途、最短试用路径和已验证的模型。
