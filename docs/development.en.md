# Local development and testing

[简体中文](development.md) · **English**

IbukiHome v1.1.0 is the current Android release. The application version is `1.1.0+4` in `pubspec.yaml`, and the database schema is SQLite v22. The plugin host supports extension API versions 1 and 2. The application, database schema, and extension API each have their own version. [v1.1.0 release](https://github.com/huui93/IbukiHome/releases/tag/v1.1.0)

## Set up a workspace

Use the toolchain in the Android README. Flutter generates `android/local.properties`. To configure it manually, start from the example file. Enter model credentials in the app's settings. The default test suite uses mock transports and synthetic data. Check a script and its model configuration before running a live-provider test. [Build requirements](../README.en.md#build-and-run) · [Android configuration template](../android/local.properties.example)

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
```

## Plugin compatibility tests

The host, self-contained tests, and plugin development interface ship with the application. Compatibility tests for separately distributed plugins run when their local fixtures are present.

| Local path | Coverage |
| --- | --- |
| `plugins/nvwa-novel/` | Original preset entries, branch bindings and inheritance, outgoing prompts, memory jobs, rendering, and completion constraints. Supply the full directory with `manifest.json`, `preset.json`, and referenced resources. |
| `artifacts/plugin-packages/RUBY-Ibuki-PoC.ibuki` | Web package installation, lifecycle, reload, and data isolation. |
| `artifacts/plugin-packages/Ibuki-LightNovel-Style.ibuki` | Prompt scope, registration, and removal. |
| `artifacts/plugin-packages/Ibuki-AI-Bridge-Test.ibuki` | Bridge package permissions. |

Obtain these fixtures from their authors and rerun `flutter test test/application` from the repository root. General package tests create synthetic ZIP files in the system temporary directory. [Plugin development interface](plugin/PLUGIN_DEVELOPMENT.en.md)

## Versioning and maintenance

`VERSION` records the Git release version. `pubspec.yaml` records the app version and Android build number. Review the lockfile when updating dependencies. Record the provenance and distribution terms for new artwork. The README describes the current build. Historical acceptance documents retain their original versions, evidence, and results. [Repository README](../README.en.md) · [Historical runtime documents](tavern_runtime/README.md)
