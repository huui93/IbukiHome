# 本地开发与验证

项目使用 Flutter 和 Android。开发入口和 SDK 版本见 [项目说明](../README.md)。`android/local.properties` 由 Flutter 生成，也可从 `android/local.properties.example` 复制后填写。API Key 从设备设置页输入，测试由模拟 Transport 提供响应。运行可能调用真实服务的脚本前，请检查脚本和当前配置。

## 插件兼容性测试

插件宿主、自包含的合成测试及开发接口与应用一起维护。以下测试会检查本地是否有对应的包，只在资源齐全时运行。

| 本地路径 | 验证范围 |
| --- | --- |
| `plugins/nvwa-novel/` | 原始预设条目、分支绑定与继承、实际提示词、自动记忆任务及渲染和结束约束。需要完整目录，含 `manifest.json`、`preset.json` 及引用的资源文件。 |
| `artifacts/plugin-packages/RUBY-Ibuki-PoC.ibuki` | Web 插件实际包安装、生命周期、重新载入和数据隔离。 |
| `artifacts/plugin-packages/Ibuki-LightNovel-Style.ibuki` | 实际轻小说包的提示词作用域、注册和卸载。 |
| `artifacts/plugin-packages/Ibuki-AI-Bridge-Test.ibuki` | 实际桥接测试包的权限声明。 |

通过授权渠道取得这些资源后，可从仓库根目录重新运行 `flutter test test/application`。通用插件包测试在系统临时目录用测试数据生成 ZIP，日常开发无需安装插件。

## 版本与维护

`VERSION` 记录 Git 发布版本，`pubspec.yaml` 记录应用版本及 Android 构建编号。更新运行依赖时同时检查锁文件。新素材应记录来源与允许的分发范围。维护说明以当前 README 为准。历史验收文档保留当时设计、断言及运行证据，引用的旧 APK、旧 Git 提交或本地报告仍由原工作区保存。
