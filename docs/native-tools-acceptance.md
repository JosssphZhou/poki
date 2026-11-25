# Native iPhone tools: implementation and acceptance

This change adds four groups of native iPhone abilities to the Poki app. It deliberately leaves the
fifth group of the source manual — the Lock Screen, Dynamic Island and task-notification changes —
unapplied, because Poki already has a Live Activity for phone automation and it is kept as it was.
Every ability is one implementation behind two catalog projections: the chat's model sees it as a
`ToolSpec`, and MCP clients see the same spec as a `HostTool` from `NativeTools.hostTools()`. Native
calls do not open an automation session and never read or act on the screen.

## What is implemented

| Batch | Abilities | Main files |
|---|---|---|
| 1 | Steps (HealthKit), calendar read and create, reminders, HomeKit lights, contacts, Bluetooth LE scan, clipboard, read-aloud, AlarmKit alarm, battery | `native/ios-app/Poki/NativeTools/` |
| 2 | Photo search by date, album, kind or place; original export (iCloud, Live Photo, RAW resources); save with optional album; add existing assets to an album; album list | `NativeTools/PhotoTools.swift`, `NativeWorkspace` in `ToolSupport.swift` |
| 3 | One-shot location with timeout/cancel and reverse geocoding; geocode; nearby POI search; routes with ETA and steps; WeatherKit current, daily and hourly forecast with Apple Weather attribution | `NativeTools/PlaceTools.swift` |
| 4 | **Not applied:** Poki's existing Live Activity, Lock Screen, Dynamic Island and completion notifications are unchanged. The original batch-4 change was reverted; native tools do not enter the activity or reroute notification taps. | none |
| 5 | Share Extension for web URLs, text, images, videos and files; App Group staging and atomic ready queue; in-app preview, Later, Remove and Send; path-contained import into the app workspace | `PokiShare/`, `Shared/ShareInbox.swift`, `Poki/App/SharedInboxStore.swift`, `Poki/App/SharedInboxView.swift` |

## Integration points

- `NativeTools.install(app:chat:)` runs at launch, registers the same specs as `HostTool`s with
  PokiCore, and the chat's `Harness.toolSpecs` appends the same specs.
- `ChatModel.performCall` handles native names directly, before the `AppModel.runTool` automation
  gate, so "how many steps did I walk?" works while Poki is otherwise idle.
- `AppModel.refreshHostTools()` composes `ask_poki` and the native tools; one provider no longer
  replaces another's MCP list.
- Native answers are withheld from the saved conversation (`CallRecord`) even though the model sees
  them. They can contain steps, phone numbers, clipboard text or precise places.
- Writes accept an optional `request_id`; a retried calendar event, reminder, alarm, photo save or
  album add returns the first result instead of writing again.
- The Share Extension publishes a batch only after every file and the manifest are in staging, then
  renames the folder into `ready`. The app claims (renames to `claimed`) before importing; a failed
  import restores it.

## Permissions and capabilities

Info.plist usage strings are in `native/ios-app/project-base.yml` and localized in
`Poki/InfoPlist.xcstrings`. App entitlements now include HealthKit, HomeKit and WeatherKit in
`project-base.yml`; the App ID and provisioning profiles must carry the same capabilities. Bluetooth,
AlarmKit, PhotoKit, Contacts, Calendars and Reminders need their usage strings, not entitlements.

## Verification

The final tree was built with Xcode 27.2 (27B52) and the iOS 27.2 SDK, with no iOS 26 compatibility
workaround. The generic simulator Debug build succeeded. A signed QA build (`com.junweizhang.pokiqa`,
with `group.com.junweizhang.pokiqa`) was installed on an iPhone 17 Pro Max running iOS 27.2.

WeatherKit needs **two** settings on the App ID: the WeatherKit capability (which supplies the
entitlement and provisioning profile) and the WeatherKit entry under **App Services**, which
activates the Apple Weather service. With only the capability, `WeatherService` returns
`WeatherKit could not generate an authentication token` even though the entitlement and profile are
present. The QA App ID was enabled and returned Apple Weather data on the device.

Tests were run inside Poki on the iOS 26.5 simulator, and the signed build was exercised on the
physical iPhone:

```sh
xcodegen generate --spec native/ios-app/project.yml
xcodebuild -quiet build-for-testing -project native/ios-app/Poki.xcodeproj \
  -scheme Poki -destination 'id=<UDID>' -derivedDataPath build/app-tests \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
# then launch with libXCTestBundleInject and SIMCTL_CHILD_XCTestBundlePath
```

The repository's `scripts/app-tests.sh` uses `timeout`, which is not installed on this Mac; the
harness above is the same launch without it.

## Local verification results (2026-11-25 to 2026-11-26)

- Simulator Debug build (`generic/platform=iOS Simulator`, arm64, Xcode 27.2 / iOS 27.2 SDK):
  **BUILD SUCCEEDED**.
- Signed device build with `Apple Development: Junwei Zhang (M955Q5TD7S)`; the app embeds
  `PokiShare.appex` and `PokiWidgets.appex` and installs as a separate QA app.
- `NativeToolsTests`: 9 passed. `PhotoLibraryTests`: 1 passed with full photo access.
  `ShareInboxTests`: 5 passed.
- On the physical iPhone, a scripted local OpenAI-compatible model exercised the real native tools:
  battery, clipboard, calendar read/create, HealthKit steps, location, Maps geocode/search/route,
  Photos albums/find/export/save/add, read-aloud start/stop, and an AlarmKit alarm. Reminders and
  Contacts passed after their system permissions were granted. WeatherKit returned current, daily and
  hourly Apple Weather data after the App Services entry was enabled.
- The earlier full-suite simulator run was not green: 767 tests, 13 skipped and 162 failures, mostly
  in existing chat/UI harness paths and the simulator environment. The focused tests above are the
  relevant pass surface for this change; the full suite has not been rerun after the final cleanup.
- The Share Extension was visible in the Safari share sheet and its staging/inbox tests pass; the
  complete Safari → preview → Send flow was not finished before this PR.

## Commits on `dev/native-ios-capabilities`

| Commit | Contents |
|---|---|
| `e06cfcc9` | Native tool registry, batch 1 tools and permissions |
| `35ac9564` | Photo-library search, export, save and album workflows |
| `58e564c4` | Location, Apple Maps and WeatherKit |
| `2664e914` | Live Activity task identity, failure state and deep links — **reverted**; not in the final tree |
| `7f3b1522` | Share Extension, inbox, preview and task submission |
| `1fb1c337` | Follow-up whitespace cleanup |
| Revert commit | Restores the original Live Activity, Lock Screen and notification behavior |
| `5a1b2307` | Drops unused native-tool parameters |

## Pending real-device checks

- HealthKit steps with real data and limited read access.
- A real HomeKit home with a test light, including a duplicate name and a partial batch failure.
- AlarmKit: a test alarm ringing on the Lock Screen and a repeating schedule; the alarm was scheduled
  on the device but its ring was not observed.
- A broadcasting BLE peripheral, Bluetooth off, permission denied and cancellation.
- WeatherKit on a fresh App ID: enable both the capability and **App Services > WeatherKit**; the
  simulator build without the entitlement must report the authorization failure.
- Location permission denial, reduced accuracy, timeout and cancellation on a physical iPhone.
- The photo library with limited access, a Live Photo, a RAW asset, an iCloud-only original and a
  same-named album.
- Out of scope: the existing Live Activity, Lock Screen, Dynamic Island and completion notifications
  are not changed; no new device check is needed for them.
- The Share Extension submit path from Safari, Photos and Files: multi-attachment order, file
  contents and names, kill-and-reopen before Send, and a shared web page → calendar event → read-back.
- Signing: HealthKit, HomeKit and WeatherKit entitlements on the App ID and profile; the Share
  Extension's App Group in the built entitlements.
