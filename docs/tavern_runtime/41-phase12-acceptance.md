# Phase 12 Production Tavern MVP UI v1 acceptance

> Historical acceptance record. Versions and results below describe this checkpoint. [Current Android release](../../README.en.md)

## Baseline and status

- Worktree: `<workspace>`
- Branch: `feature/mobile-tavern-production-ui-mvp-v1`
- Parent/HEAD: `363414853703a01fb4e15e5262742dfa98ebd898`
- Parent tag: `mobile-tavern-durable-reconciliation-v1-approved`
- SQLite: v14. No new table, schema-version, dependency, version or signing change.
- Version remains `1.0.0+1`, package `com.ibuki.ibukihome`, label IbukiHome's existing Chinese app name.
- Uncommitted human acceptance point. No commit/tag/merge/publication.
- Phase 5 First-contact UX Gate: **BYPASSED BY PRODUCT DECISION**.
- Genuine production user experience: **NOT YET VALIDATED**.

## Delivered surfaces and execution

The five independent primary destinations are Novel, Chat, Legacy World, Tavern,
and Settings. Existing Novel/Chat/Legacy World implementations are not replaced.
Tavern has a native-data Home, recent summaries, three-step story creation,
reusable player identity, real native Character/WorldCard/RoleplayWorld/book
selection, story-scoped Provider/model binding, transcript, and management sheets.

The UI uses the SQLite Repository, Foundation transcript projection and formal
Generation Orchestrator/Provider Adapter. No prototype DTO/driver, seeded demo
Session or static AI reply is shipped. Runtime actions are Send/stream/Stop,
Retry (same Alternative/new Attempt), regenerate (new Alternative), and Continue
(same Alternative/new Attempt). Streaming stays typed, and an unselected newly
generating answer has its own temporary preview without changing canonical
selection. Reasoning is never joined into character dialogue.

Alternative selection, safe historical forks, frozen inherited history and
historical World Info state use existing Foundation APIs. Branch switching and
leaving an active story await cancellation and settlement. Invalid selection
errors remain visible without changing saved history. Per-line reading anchors
are local settings, not canonical/archive state.

The authorized World/Character/Persona/local-book union reaches the one formal
World Info runtime. Book contents, enable controls and original activation/compile
traces are accessible. Original traces are bounded in-process records, not
historical recompilation. Missing traces explicitly show unavailable.
See `39-production-ui-audit.md` and `40-production-ui-integration.md` for the
reuse matrix, ownership, integration details and Android SQLite portability fix.

## Gates

| Gate | Result | Evidence and scope |
| --- | --- | --- |
| Code | PASS | Formal repositories, native asset resolution, Orchestrator, World Info and branch APIs; five-mode navigation |
| Offline E2E | PASS | Real SQLite/formal runtime with controlled HTTP transport; complete generation and branch interactions |
| APK | PASS | Both final APKs built, SHA-256 recorded, APK signature verification succeeds |
| Device | PASS | Final Universal install/launch; native creation, sheets, missing-model guard, reopen, modes and SAF merge |
| Live Provider | NOT RUN | No authorization, credential entry or real model call; mock results are not live results |
| UX | NOT YET VALIDATED | Needs genuine human use; implementation/device checks do not validate user understanding |

## Quality and regressions

- `dart format .`: PASS; final source formatted.
- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub --concurrency=2`: **1666/1666 PASS**, +36 over 1630.
- `git diff --check`: PASS; new-file trailing-whitespace check PASS.
- High-confidence secret scan: 0 hits across tracked and new text files.
- `pubspec.yaml` and `pubspec.lock`: unchanged; no dependency upgrade.
- Existing migration, durable recovery/conflict protection, archive fresh restore,
  archive conflict merge, Provider offline adapter, World/Prompt/Lore, Plugin,
  Chat STOP and Novel suites remain in the full passing suite.
- New story-local book IDs are remapped during archive conflict merge; credentials
  and reading View State remain excluded. Portable v14 malformed journal/orphan
  rejection, transaction safety and archive rejection have focused coverage.
- Creation, keyboard-safe composer, rejected-draft preservation, cancellation,
  generation previews, ordered typed content, original/historical Inspector,
  native world detail and narrow-width widgets have explicit tests.

## Performance evidence

The formal in-memory Repository is used for repeatable UI load tests, not fake
projection DTOs: 100/500/1000 Turns with 5 Alternatives each, long selected replies
and multiple speakers. The lazy 360x800 transcript builds fewer than 12 rows,
preserves an upward-reading anchor across reopening and supports jumping latest.
The full-suite host projection timings were 11/27/115 ms respectively. Existing
SQLite Foundation 1000-Turn projection reported 160 ms in that run.
These are host timings, **not Android frame-rate measurements**. The 50-source
World Info integration test exercises actual activation/deduplication/budgeting.
No device long-story FPS or memory profile is claimed.

## Android evidence

Protected `emulator-5554` was never targeted. Every device command explicitly
selected the isolated serial. Existing `IbukiHome_BackupSmoke` / `emulator-5560`
was preserved and stopped, with its viewport overrides reset; no uninstall,
data clear, secret read or credential change was performed there.

For clean native-data checks a separate API 31 Google APIs x86_64 Pixel 5 AVD was
created: `IbukiHome_TavernMvpSmoke`, serial `emulator-5562`, data at
`<avd-dir>`. No Provider was configured.

The final Universal APK was installed successfully and launched without an app
fatal exception. An earlier emulator SystemUI startup exception is not an
IbukiHome exception. Evidence is under ignored `artifacts/testing/phase12-device/`.
Actual smoke covered:

- All five main modes; Chat contacts, Legacy World Home and Settings/backup remain accessible.
- Three-step native creation: reusable Persona `Lia`, Character `Mira`, a real
  Tavern Session titled `Tavern-Device-StoryLia`, scene and main Story Line.
- Cast/player/scene/world detail, Drawer, story-line list, Android Back and Home.
- Missing-model Send safely rejected, `Hello-Mira` draft retained, no AI reply.
- Force-stop/relaunch and continuing the persisted native story/cast/main line.
- Native library book `Native-Device-Lore`, keyword entry `The-Cake`, explicit
  story reference, saved enable state, original native content displayed.
- SAF backup preview/export through real Android DocumentsUI, restore selection
  and validated preview; native conflict merge completed. After force-stop,
  both original and imported story copies open, with usable native book references
  and the `The-Cake` keyword entry. No Provider credentials were restored.

Primary Tavern interaction was checked at overridden 360x800/density 160 and
at normal Pixel 5 1080x2340/density 440 (about 393x851 dp). Pixel 5's physical
cutout yields unusually large insets at the forced low-resolution setting; the
secondary Legacy book-entry editor was exercised at the normal profile instead.
The 360x800 automated widgets cover ordinary mobile insets and long content.
Viewport overrides were reset; the AVD was stopped and retained, not deleted.

Device generated-response/Retry/Continue/Alternative/fork behavior was **NOT RUN**
because it requires an authorized model. These use the identical production
execution path in passing offline tests. Native fresh reinstall/restore was not
repeated in this phase; fresh semantic restoration is an automated gate, while
native SAF export/preview/conflict merge were actually exercised.

The native SAF archive is 11,184 bytes, SHA-256
`EA66EC1137BF7D9F4FE53971FB2BCE7676EED2AE97192EDB77184BF1354F3D4F`.
All JSON/JSONL credential fields (API key/Authorization/SecureStorage) had 0 hits.
The synthetic archive and screenshots are ignored evidence, not product fixtures.

## Final APK provenance

Both APKs use the existing **release build / debug-test signing** configuration;
they are not production-signed releases. `apksigner verify --verbose` passes (v2).
Package/version were independently read from the built APK. Universal ABIs are
`armeabi-v7a`, `arm64-v8a`, `x86_64`. ARM64 was built but not installed on x86_64.

| File under `artifacts/release/` | Bytes | SHA-256 |
| --- | ---: | --- |
| `IbukiHome-TavernMVP-v1-universal.apk` | 73104038 | `7F10FDED7161CD7468AB79CF9B7FE8338FCCBBECF9BB355EAF38C648A824171E` |
| `IbukiHome-TavernMVP-v1-arm64.apk` | 29378940 | `C2B272B9DB1746A718E0525E91B985C2F3AC1A316FAF96B27FEA10EAD81E3951` |

Absolute artifact directory:
`<workspace>\artifacts\release`.

Build commands, run in this worktree:

```powershell
# Configure the local Flutter and Android SDK environment first.
flutter build apk --release --no-pub
# Copy app-release.apk to the Universal artifact before the next build.
flutter build apk --release --no-pub --target-platform android-arm64
# Copy the second app-release.apk to the ARM64 artifact.
```

The environment script's PUB_CACHE was overridden only in the process to use the
existing pinned dependency cache; no machine/user environment changed. Flutter,
JDK, SDK, Gradle cache, AVD, build and controlled temp files remain on D:.

This new worktree lacked ignored `.flutter-plugins-dependencies`; a first no-pub
build omitted native plugin registration. Those early APKs are **not deliverables**.
Using the pinned package configuration, Flutter SDK's own `refreshPluginsList`
and `injectPlugins` regenerated native plugin metadata/registrant without changing
the lockfile. The preparation script is retained under
`<local temporary script>`. The two final APKs above
include native sqflite, SecureStorage, file-picker and the other existing plugins.
Flutter's existing Kotlin plugin migration notices are build warnings, not errors;
no SDK/package upgrade was made in response.

## Limits and next slice

- One selected responder per request; no automatic group scheduler is claimed.
- Original rich Trace is bounded to 100 in-process Attempts; historical missing
  traces stay unavailable. Attempt/journal/content persistence is unaffected.
- Existing asset deletion can safely block source resolution; no automatic resource
  substitution or dangerous Journal-reset repair is added.
- Advanced tools, multimodal generation, RAG, automation, ST scripts and long-term
  memory are out of scope; script/Provider/secret boundaries remain intact.
- Real generation quality, first-contact comprehension, extended device scrolling
  and device frame profiling require subsequent human/authorized testing.
- Next recommended slice: genuine APK UX review plus explicitly authorized Live
  Provider smoke. Do not start a new Runtime phase before this acceptance.

Final Git: 23 tracked modified files, 16 untracked product/test/document files,
39 total; artifacts/cache/device evidence ignored. No existing tests removed,
no unrelated worktree modifications, no commit/tag/merge/version bump.
