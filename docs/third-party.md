# 依赖与资源来源

**简体中文** · [English](third-party.en.md)

## 第三方代码与构建工具

| 组件 | 版本和来源 | 许可记录 |
| --- | --- | --- |
| Flutter 与 Dart | Flutter 3.44.8，Dart 3.12.2。由已安装的 Flutter SDK 提供 | Flutter 和 Dart SDK 各自附带许可与第三方通知 |
| Dart / Flutter 包 | `pubspec.lock` 锁定 118 个条目，含 113 个 hosted 包和 5 个 SDK 条目 | 已检查锁定版本的本地包许可文件。具体条款以各包的 LICENSE / NOTICE 为准 |
| Gradle Wrapper | Gradle 9.1.0。JAR SHA-256 为 `76805e32c009c0cf0dd5d206bddc9fb22ea42e84db904b764f3047de095493f3` | Apache-2.0，JAR 内含 `META-INF/LICENSE` |
| Android Gradle Plugin、Kotlin、Android SDK | AGP 9.0.1、Kotlin 2.3.20。SDK 和 NDK 随 Flutter 构建配置解析 | 依各工具和组件的上游许可，安装至本地 SDK 或构建缓存 |

包管理器按锁文件下载依赖。依赖缓存与 SDK 不进入源代码库。发布 APK 前应保留随 SDK 和依赖生成的第三方许可记录，并复核实际打包的依赖。

- [Gradle 官方校验值](https://gradle.org/release-checksums/#9-1-0)
- [Flutter SDK 许可](https://github.com/flutter/flutter/blob/058e0af2c2/LICENSE)
- [Dart SDK 许可](https://github.com/dart-lang/sdk/blob/main/LICENSE)

## 项目资源

- v1.1.0 公开发行版使用项目维护者以 GPT Image 制作的原始吉祥物、导航图和 Android 启动图。维护者已确认这些素材可随伊吹之家分发。
- NVWA、RUBY、演示插件、分析用角色卡、预设和嵌入脚本由各自维护方单独分发。仓库保存插件宿主、用合成数据进行验证的测试，以及开发接口。
- 项目源码目前由维护者管理分发范围。改成公开仓库、授予开源许可或补回原图前，应先确认维护者和资源权利方的授权。
