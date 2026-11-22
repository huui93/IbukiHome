# 伊吹之家 · Android

**v1.0.0** · Flutter Android 应用。小说创作与角色聊天分别保存作品、角色和记忆。两个模式共用模型配置，可按任务选择模型。

## 功能

- **小说**提供书架、阅读、TXT 导入和分作品创作。每部作品可配置角色、大纲、长期记忆、系统提示词方案和输出字数范围。生成支持续写、重写和分支。
- **聊天**提供独立人格、示例对话、头像、会话列表及流式回复。每个会话各自保存上下文、摘要和长期记忆，可检索记忆、查看 Token 用量及发送图片。支持独立识图模型。
- **设置**包含本人资料、模型与流式选项、备份和插件管理。内置接口类型覆盖 OpenAI、Gemini、DeepSeek、Kimi、千问、Grok、GLM、Claude 和自定义接口。选择实际可用的模型 ID，并在配置页面验证连接。
- **小说插件宿主**支持项目与分支作用域、结构化提示词、生成参数、历史与记忆、渲染和受控操作。仓库提供宿主及开发接口文档。插件作者单独提供 `.ibuki` 文件。

## 目录

| 目录 | 内容 |
| --- | --- |
| `lib/app`、`lib/features` | 路由、主题和各功能界面 |
| `lib/domain`、`lib/application` | 领域模型、生成、记忆、导入、备份和插件宿主 |
| `lib/data`、`lib/core` | SQLite、平台安全存储、模型客户端和基础设施 |
| `android`、`assets` | Kotlin 平台实现、Gradle 工程和随应用构建的资源 |
| `test`、`tool` | 自动化测试、合成数据和开发工具 |
| `docs` | 开发、接口、备份及历史阶段文档 |

## 安装和运行

- Flutter 稳定版。本候选使用 Flutter **3.44.8**、Dart **3.12.2**，依赖解析要求 Flutter ≥ 3.44.0。保留 `pubspec.lock`。
- Android SDK、Android Platform Tools、JDK **17**。Gradle **9.1.0** 由 Wrapper 下载。Android Gradle 插件 **9.0.1**、Kotlin **2.3.20** 由构建脚本锁定。此 Flutter 版本使用 Android SDK **36** 和 NDK **28.2.13676358**，设备或模拟器最低 Android API **24**。
- 主要 Dart 依赖包括 Riverpod、go_router、sqflite、flutter_secure_storage、http、file_picker、archive 和 webview_flutter。完整版本见 `pubspec.lock`。

在仓库根目录运行以下命令。先按 `flutter doctor -v` 的提示配置 SDK 并接受 Android SDK 许可。

```sh
flutter doctor -v
flutter pub get --enforce-lockfile
flutter devices
flutter run -d <设备ID>
```

Flutter 会生成本地 SDK 配置。手动配置时可参考 [Android 配置模板](android/local.properties.example)。Windows 上可将项目与 `PUB_CACHE` 放到同一磁盘，方便 Gradle 处理原生插件路径。默认 Maven 和 Gradle 下载源在 `android` 下可查，访问受限时先检查代理或镜像连通性。

进入应用后，按需在 **设置 → API 配置** 填写服务地址、模型和 API Key，再为小说、聊天或识图选择模型。Key 写入设备安全存储。在线生成会将本轮请求所需的内容发给当前配置的模型服务。聊天摘要和已有作品保存在设备上，请用应用内备份功能自行迁移。

## 验证和打包

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
flutter build apk --release --no-pub
```

APK 在 `build/app/outputs/flutter-apk/`。现有 release 构建使用 Android 调试签名供测试。正式分发需由项目维护者配置自己的签名，并把密钥及密码放在 Git 之外。项目版本为 `v1.0.0`，Android 版本名为 `1.0.0`，构建号为 `1`。

默认测试使用合成数据和模拟模型调用。有几组兼容测试需要维护者自行取得并存放于被忽略路径的插件资源。路径及覆盖范围见 [测试和本地验证](docs/development.md)。

## 开发资料

- [插件开发接口](docs/plugin/PLUGIN_DEVELOPMENT.md)
- [备份格式和安全边界](docs/backup/IBUKI_BACKUP_FORMAT_V1.md)
- [聊天会话记忆](docs/chat_session_memory_v16.md)
- [生成、历史与分支运行时设计](docs/tavern_runtime/README.md)
- [依赖和资源来源](docs/third-party.md)

此仓库计划以 GitHub Private 创建。项目源码许可由维护者另行决定。提交前检查 `git status` 和 `git diff --cached`。Wiki、Issue、附件和 Git 历史也应避免记录凭据、个人资料或真实聊天及作品内容。
