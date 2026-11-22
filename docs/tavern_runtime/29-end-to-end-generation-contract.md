# End-to-end validation contract

Offline tests create real Foundation Sessions, participants, player Turns and native Character/Persona/WorldBook assets. The chain goes through Foundation projection, native source resolution, World Info, Prompt Compiler, protocol-shaped Mock HTTP, the existing Driver contract, Runtime persistence and Ledger settlement. Mock Transport never opens a network connection or needs a credential.

Coverage includes Normal/Regenerate/Continue/Retry, command deduplication, preflight failure, authentication failure, output limit, Stop, disposal, Story Line switching, frozen parent selection, partial exclusion, typed native/summary/unavailable parts, partial-success ledger reconciliation, SQLite reopen and semantic archive/restore comparisons. Archive comparison checks selected Alternatives, content kinds/order/provenance, Attempts and branch transcript, not just row counts. Transient lore timers and process-local traces are not restored.

## Opt-in real smoke

The developer entry is `tool/tavern_provider_smoke.dart`. It fails immediately unless enabled with:

```powershell
flutter run --no-pub -d <DISPOSABLE_SERIAL> -t tool/tavern_provider_smoke.dart --dart-define=IBUKI_TAVERN_LIVE_SMOKE=true
```

Use only the authorized disposable `IbukiHome_BackupSmoke`; do not operate emulator-5554. The entry consumes existing secure Provider settings and asks for an explicit model reasoning capability. It shows no credential field or raw response. A separate explicit button creates labeled synthetic assets and a formal Tavern Session. Sending is opt-in, limited to one request per launch, capped at 128 output tokens, with Stop available and no automatic retry. Existing production navigation remains the default bootstrap child.

The smoke uses a real configured model ID, actual formal projection and the complete new chain. It reports safe Provider/model, mode/status, visible character count, reasoning kind, persisted Attempt and Ledger outcome. A successful fixture preparation is not a successful network smoke. Actual status for this implementation round: **LIVE SMOKE NOT RUN**. No Android configured credential was accessed or chargeable request issued during automated validation.

The synthetic fixture creates its own project/CharacterCard/World/PlayerPersona/library book/reference and Tavern Session through repositories; it does not overwrite existing assets. Both participants reference formal asset identities. A widget test prepares the fixture without instantiating HTTP, verifies the Persona reference and existing Session preservation, and confirms no Attempt exists. These records are clearly named test data. Model profiles are settings rather than new story schema. The tool is not a production Tavern UI. Leaving its page cancels an active handle.

## Current validation snapshot

103 tests added over the 1483 baseline; full `flutter test --no-pub --concurrency=2` passed **1586/1586**. Acceptance adds atomic preflight failure cases, Regenerate/Continue preflight races, cross-Session concurrency, request identity comparison, root-scope ownership/recovery/disposal, empty Gemini/Responses reasoning semantics, protocol-specific finish reasons and native-role rejection. A loopback-only real HTTP server verifies request-owned IO transport closure; this is not a real Provider/model test. SQLite E2E also preserves failed/cancelled/completed retry provenance and excludes unsuccessful partials from the visible projection. See `31-provider-acceptance-and-freeze.md` for the final acceptance boundary.

Live smoke remains **NOT RUN: authorization not provided**. Read-only device inventory at acceptance showed only the protected `emulator-5554`; no authorized disposable device was connected. **DEVICE SMOKE NOT RUN**. No device App/configuration/credential was accessed, and no live model request was issued. SQLite stays v13; pubspec and lock are unchanged. The approved tag covers Gate A (code/offline), not online model connectivity.
