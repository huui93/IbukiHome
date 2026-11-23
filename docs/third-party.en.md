# Dependencies and asset attribution

[简体中文](third-party.md) · **English**

## Third-party code and build tools

| Component | Version and source | License record |
| --- | --- | --- |
| Flutter and Dart | Flutter 3.44.8 and Dart 3.12.2 from the installed Flutter SDK | The SDKs include their licenses and third-party notices. |
| Dart and Flutter packages | `pubspec.lock` pins 118 packages, including 113 hosted and 5 SDK entries. | See the `LICENSE` and `NOTICE` files for each resolved package. |
| Gradle wrapper | Gradle 9.1.0. The JAR SHA-256 is `76805e32c009c0cf0dd5d206bddc9fb22ea42e84db904b764f3047de095493f3`. | Apache-2.0. The JAR includes `META-INF/LICENSE`. |
| Android Gradle Plugin, Kotlin, and Android SDK | AGP 9.0.1 and Kotlin 2.3.20. The Flutter build configuration resolves the SDK and NDK. | See the corresponding upstream licenses and the local SDK or build cache. |

The build resolves dependencies from the lockfile. SDKs and dependency caches are stored outside the source repository. When publishing an APK, retain the third-party notices for the SDK and bundled dependencies. [Gradle release checksums](https://gradle.org/release-checksums/#9-1-0) · [Flutter SDK license](https://github.com/flutter/flutter/blob/058e0af2c2/LICENSE) · [Dart SDK license](https://github.com/dart-lang/sdk/blob/main/LICENSE)

## Project assets

- IbukiHome v1.1.0 includes the original mascot, navigation, and Android launcher artwork created by the project maintainer using GPT Image. The maintainer confirmed the artwork may be distributed with IbukiHome.
- NVWA, RUBY, demonstration plugins, analysis character cards, presets, and embedded scripts are distributed separately by their maintainers. This repository provides the plugin host, synthetic tests, and development interface. [Plugin development interface](plugin/PLUGIN_DEVELOPMENT.en.md)
- The project maintainer determines the source licensing terms.
