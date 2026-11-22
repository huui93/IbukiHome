# IbukiHome Plugin Foundation v1

## Package and storage

An `.ibuki` file is a ZIP container whose root contains `manifest.json`.
Unknown safe files and capability names are retained so newer plugin APIs can
extend the format without changing the installer.

Installed package files live under the application support directory:

```text
plugins/installed/<plugin-id>/
plugins/.installing/<operation-id>/
plugins/.backup/<plugin-id>-<operation-id>/
plugin_data/<plugin-id>/
```

Package files and user-created plugin data are intentionally separate. Updates
replace only the installed package. Uninstall keeps plugin data unless the Core
explicitly requests the delete data policy.

## Runtime boundary

Foundation v1 installs and registers files but does not execute third-party
Dart, JavaScript, Lua, WASM, or native code. `PluginRuntime`,
`PluginLifecycle`, and `PluginContributionRegistry` are extension points for a
future capability-scoped runtime.

Plugin code must never receive provider API keys, Authorization headers, or
direct Secure Storage access. A future plugin that requests AI work must call a
Core-owned API which resolves the configured provider and performs the request.

## Installer limits

- compressed package: 150 MiB
- one extracted file: 75 MiB
- total extracted data: 400 MiB
- archive entries: 4096
- manifest: 1 MiB

Absolute paths, drive paths, `..`, alternate data stream syntax, duplicate
paths, and symbolic links are rejected before extraction. Installation occurs
in a temporary private directory and replaces an existing version only after
the entire new package has been validated and extracted.
