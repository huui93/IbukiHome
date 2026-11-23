# IbukiHome for Android

[简体中文](README.md) · **English**

IbukiHome is a Flutter app for writing fiction and chatting with AI characters. Fiction projects and chat conversations keep separate characters, histories, and memories. Both modes share model settings and let you choose a model for each task.

[**Download the v1.1.0 universal Android APK**](https://github.com/huui93/IbukiHome/releases/download/v1.1.0/IbukiHome-v1.1.0-universal.apk)

The APK supports Android 7.0 and later on ARM64, ARMv7, and x86_64. It uses the project's test signature. [Release notes and SHA-256 checksum](https://github.com/huui93/IbukiHome/releases/tag/v1.1.0)

## Features

- **Fiction.** Browse your bookshelf, read existing works, or import a TXT file. Each project can have its own characters, outline, long-term memory, system prompt preset, output length range, and temperature. Continue, rewrite, or branch a story.
- **Chat.** Create personas with a prompt, avatar, and optional dialogue examples. Each conversation keeps its own context, summaries, and long-term memory on the device. Search memories, check token usage, and send images. Image recognition can use a separate model. Automatic compression defaults to 50 completed turns and can be changed or run immediately for each conversation.
- **Settings.** Manage your profile, models, streaming, backups, and plugins. The language setting offers Simplified Chinese, English, French, and Japanese. API integrations cover OpenAI, Gemini, DeepSeek, Kimi, Qwen, Grok, GLM, Claude, and custom endpoints. Choose an available model ID and test the connection in the app.
- **Fiction plugin host.** Plugins can bind to projects and branches, contribute structured prompts and generation parameters, access scoped history and memory, and register renderers and controlled actions. Plugin authors distribute their `.ibuki` packages separately. [Plugin development interface](docs/plugin/PLUGIN_DEVELOPMENT.en.md)

## Repository layout

| Path | Contents |
| --- | --- |
| `lib/app`, `lib/features` | Routing, themes, and feature screens |
| `lib/domain`, `lib/application` | Domain models, generation, memory, import, backups, and the plugin host |
| `lib/data`, `lib/core` | SQLite, secure storage, model clients, and shared infrastructure |
| `android`, `assets` | Kotlin platform code, Gradle project, and bundled assets |
| `test`, `tool` | Automated tests, synthetic fixtures, and development tools |
| `docs` | Development guides, interfaces, backup format, and historical design records |

## Build and run

- **Flutter and Dart.** The release was built with Flutter **3.44.8** and Dart **3.12.2**. Dependencies require Flutter **3.44.0** or later. Keep `pubspec.lock` when reproducing a build.
- **Android toolchain.** Install Android SDK **36**, NDK **28.2.13676358**, Android Platform Tools, and JDK **17**. The Gradle wrapper uses **9.1.0**. The build pins Android Gradle Plugin **9.0.1** and Kotlin **2.3.20**. Use a device or emulator running API **24** or later.
- **Dart dependencies.** Key dependencies include Riverpod, `go_router`, `sqflite`, `flutter_secure_storage`, `http`, `file_picker`, `archive`, and `webview_flutter`. See `pubspec.lock` for exact versions.

Run these commands from the repository root. Follow `flutter doctor -v` to configure the SDK and accept the Android SDK licenses.

```sh
flutter doctor -v
flutter pub get --enforce-lockfile
flutter devices
flutter run -d <device-id>
```

Flutter generates the local SDK configuration. On Windows, keeping the project and `PUB_CACHE` on the same drive helps Gradle resolve native plugin paths. [Android SDK configuration template](android/local.properties.example)

In the app, open **Settings → API configuration** to enter a service URL, model, and API key. You can then select models for fiction, chat, and image recognition. API keys are stored in secure storage on the device. Online generation sends the content needed for each request to the configured provider. Saved works and conversation summaries are kept on the device. Use the in-app backup to move them to another device.

## Test and package

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
flutter build apk --release --no-pub
```

APK files go to `build/app/outputs/flutter-apk/`. This release uses Android debug signing for testing. Maintainers preparing a production distribution can configure their own signing keys and keep credentials outside Git. The project version is `v1.1.0`. The Android version name is `1.1.0` and the build number is `4`.

The default tests use synthetic data and simulated model calls. Some compatibility tests require separately distributed plugin fixtures. [Local development and test guide](docs/development.en.md)

## Developer documentation

- [Local development and testing](docs/development.en.md)
- [Plugin development interface](docs/plugin/PLUGIN_DEVELOPMENT.en.md)
- [Backup format and security boundaries](docs/backup/IBUKI_BACKUP_FORMAT_V1.md)
- [Conversation memory](docs/chat_session_memory_v16.en.md)
- [Historical generation, history, and branch runtime design](docs/tavern_runtime/README.md)
- [Dependencies and asset attribution](docs/third-party.en.md)

The project maintainer determines the source licensing terms.
