# Native iPhone tools: implementation and acceptance

This change adds five groups of native iPhone abilities to the Poki app. Every ability is one
implementation behind two catalog projections: the chat's model sees it as a `ToolSpec`, and MCP
clients see the same spec as a `HostTool` from `NativeTools.hostTools()`. Native calls do not open an
automation session and never read or act on the screen.

## What is implemented

| Batch | Abilities | Main files |
|---|---|---|
| 1 | Steps (HealthKit), calendar read and create, reminders, HomeKit lights, contacts, Bluetooth LE scan, clipboard, read-aloud, AlarmKit alarm, battery | `native/ios-app/Poki/NativeTools/` |
| 2 | Photo search by date, album, kind or place; original export (iCloud, Live Photo, RAW resources); save with optional album; add existing assets to an album; album list | `NativeTools/PhotoTools.swift`, `NativeFileStore` in `ToolSupport.swift` |
| 3 | One-shot location with timeout/cancel and reverse geocoding; geocode; nearby POI search; routes with ETA and steps; WeatherKit current, daily and hourly forecast with Apple Weather attribution | `NativeTools/PlaceTools.swift` |
| 4 | Task identity in the Live Activity, failed vs finished state, link back to the task's conversation, a native tool counted as a task step, per-task notification routing | `Shared/PokiActivityAttributes.swift`, `Poki/Activity/`, `Poki/App/AppModel.swift`, `Poki/App/PokiNotificationLink.swift` |
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

Local build (Xcode 26.6, iOS 26.5 SDK) succeeds after omitting one iOS 27 SDK-only
`WKNavigationAction.mainFrameNavigation` block in `PokiBrowser.swift`; that source change is not part
of this change and CI must build with the iOS 27.1 SDK the project documents. The simulator build
embeds `PokiShare.appex` with `com.apple.share-services` and
`PokiShare.ShareViewController`.

Tests were run inside Poki on an iPhone 17 Pro, iOS 26.5 simulator:

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

## Local verification results (2026-11-25)

- Simulator Debug build (`generic/platform=iOS Simulator`, arm64, Xcode 26.6 / iOS 26.5 SDK):
  **BUILD SUCCEEDED**.
- The built app embeds `PokiShare.appex`; its Info.plist declares
  `com.apple.share-services` with principal class `PokiShare.ShareViewController`.
- The app launched to the chat screen on an iPhone 17e simulator.
- Focused in-app tests (NativeTaskActivityTests, NativeToolsTests, ShareInboxTests): 18 passed,
  1 skipped. The skipped PhotoLibraryTests test needs full photo access; the simulator showed the
  limited/full-access prompt even after `simctl privacy grant photos`, so it is marked skipped rather
  than blocking the test host.
- A full-suite run reached 481 passing tests and 11 failures before its 15-minute harness limit. Five
  failures came from this change (native tools in the Split View list and the changed completion
  notification id); those two were fixed after the run. The remaining failures were in Split View
  preparation timings, Interface Size, Idle Return, Frontend setup state, Message Markdown and the
  existing notification delivery tests. They were not re-run after the fixes; treat them as
  incomplete until the suite is run on a fresh simulator whose setup and notification state match CI.

## Commits on `dev/native-ios-capabilities`

| Commit | Contents |
|---|---|
| `e06cfcc9` | Native tool registry, batch 1 tools and permissions |
| `35ac9564` | Photo-library search, export, save and album workflows |
| `58e564c4` | Location, Apple Maps and WeatherKit |
| `2664e914` | Live Activity task identity, failure state and deep links |
| `7f3b1522` | Share Extension, inbox, preview and task submission |
| `1fb1c337`, `9eaefc1b` | Follow-up cleanups and Split View/notification compatibility |

## Pending real-device checks

- HealthKit steps with real data and limited read access.
- A real HomeKit home with a test light, including a duplicate name and a partial batch failure.
- AlarmKit: authorization, a test alarm ringing on the Lock Screen, and a repeating schedule.
- A broadcasting BLE peripheral, Bluetooth off, permission denied and cancellation.
- WeatherKit with a Developer Program App ID and WeatherKit capability; simulator builds without the
  entitlement must report the authorization failure.
- Location permission denial, reduced accuracy, timeout and cancellation on a physical iPhone.
- The photo library with limited access, a Live Photo, a RAW asset, an iCloud-only original and a
  same-named album.
- Lock Screen and Dynamic Island layout, notification permission denied, a cold launch from a
  notification tap, and background completion.
- The Share Extension from Safari, Photos, Files: multi-attachment order, file contents and names,
  kill-and-reopen before Send, and a shared web page → calendar event → read-back.
- Signing: HealthKit, HomeKit and WeatherKit entitlements on the App ID and profile; the Share
  Extension's App Group in the built entitlements.
