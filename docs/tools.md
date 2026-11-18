# Tool behavior and conventions

**Poki MCP** is a local macOS MCP server that lets AI clients inspect and control an iPhone or iOS Simulator. By default it exposes six phone-agent tools (`look`, `do`, `poki_mcp_status`, `list_devices`, `select_device`, and `list_apps`) that match the tool surface of Poki on the iPhone. Passing `--dev-tools` or setting `POKI_MCP_DEV_TOOLS=1` enables the developer tool group for simulator lifecycle, screen recording, app builds and installation, location and appearance simulation, crash diagnostics, and scripted batches.

- **Screen & UI Inspection**: Read numbered Accessibility and Vision OCR elements together with a screenshot via `look` (plus `observe_device`, `list_elements`, `take_screenshot`, and `save_screenshot` in `--dev-tools`).
- **Actions & Approvals**: Run ordered touch, text, gesture, launch, URL, wait, and human-handoff actions in one `do` call with local macOS approval prompts on sensitive steps.
- **Developer Lifecycle (`--dev-tools`)**: Boot simulators, record H.264 video, build and install apps, simulate location or appearance, inspect containers and crash logs, and run `batch_commands` or `run_code`.
- **Local Daemon Architecture**: Runs a local service (`127.0.0.1:47825` by default) with serialized device execution, per-client session isolation, and interactive local approval gates for sensitive actions. Loopback only unless `POKI_BIND_HOST` names another address, and `POKI_HOST_ALLOW` then lists the `Host` names it answers to; `127.0.0.1` is always served, because local clients read that endpoint from `mcp.json`.

Tool definitions live in [`src/cua.mjs`](../src/cua.mjs), [`src/data/tools.json`](../src/data/tools.json), and [`src/tools.mjs`](../src/tools.mjs). MCP serves them through `tools/list`. `poki_mcp_status` returns the selected device, available device count, approval mode, `default_tools` (6), and counts for device, observation, management, and `total_tools` (63).

## MCP tool profiles

### Default profile: six phone-agent tools

By default `tools/list` returns six tools:

| Use | Default tools |
| --- | --- |
| Service and devices | `poki_mcp_status`, `list_devices`, `select_device` |
| Installed apps | `list_apps` |
| Read the screen | `look` |
| Act on the screen | `do` |

`look` reads the screen without acting, numbers visible elements for the next call, marks newly appeared items, lists items that disappeared since the previous read, and attaches a screenshot.

`do` runs an ordered `actions` array, waits briefly after the final step, and reads the screen once:

| Action in `do` | Accepted forms | Replaces legacy tool |
| --- | --- | --- |
| `tap` | `n` or `[x, y]` | `tap`, `handle_alert` |
| `double_tap` | `n` or `[x, y]` | `double_tap` |
| `tap_text` | `"label"` or `{ text, exact }` | `tap_text` |
| `type` | `"text"` with optional `ref`, `clear` | `type_text`, `fill` |
| `key` | `"return"`, `"backspace"`, `"escape"`, `"tab"`, `"space"` | `press_key`, `hide_keyboard` |
| `swipe` | `"up" \| "down" \| "left" \| "right"` or `{ direction, in, distance }` | `swipe`, `scroll` |
| `scroll_to` | `"text"` or `{ text, ref, in, direction, max_swipes }` | `scroll_to` |
| `long_press` | `n`, `[x, y]`, or `{ ref, x, y, ms }` | `long_press` |
| `drag` | `{ from, to, ms, hold_ms }` or `[x1, y1, x2, y2]` | `drag` |
| `pinch` | `n`, `[x, y]`, or `{ ref, x, y, scale }` | `pinch` |
| `button` | `"home"`, `"lock"`, `"volume_up"`, `"volume_down"`, `"action"` | `press_button`, `system_gesture` |
| `back` | `true` (taps a leading back control or swipes from the left edge) | `go_back` |
| `launch` | `"bundle.id"` or `{ bundle, name, fresh }` | `launch_app` |
| `open_url` | `"https://..."` | `open_url` |
| `wait` | `{ ms }` | `wait` |
| `wait_until` | `"text"` or `{ text, gone, settled, ms }` | `wait_for` |
| `handoff` | `{ kind, text }` | `request_human_action` |

Passing `finish: true` on the final `do` call returns to the app where the task began.

In default mode, calling any of the 57 unexposed tool names returns `isError: true` with a migration message: the 25 merged tools name their `look` or `do` replacement syntax, and the 32 developer tools explain how to enable the developer tool group.

### Developer tool group (`--dev-tools` / `POKI_MCP_DEV_TOOLS=1`)

Passing `--dev-tools` or setting `POKI_MCP_DEV_TOOLS=1` makes `tools/list` return all 63 tools (the 6 default tools, the 25 standalone action/observation tools, and the 32 developer tools). `POKI_MCP_TOOLS=all` remains supported as a compatibility alias.

For a stdio client, pass `--dev-tools` in `args` or set `POKI_MCP_DEV_TOOLS=1` in `env`:

```json
{
  "mcpServers": {
    "poki-mcp": {
      "command": "node",
      "args": ["/absolute/path/to/poki/src/stdio.mjs", "--dev-tools"]
    }
  }
}
```

The client needs to reconnect after a configuration change. Each stdio client chooses its own profile, or inherits the daemon's `--dev-tools` / `POKI_MCP_DEV_TOOLS=1` setting when neither flag nor environment variable is set on the client. Direct HTTP clients receive the daemon's profile (`npm start -- --dev-tools` or `POKI_MCP_DEV_TOOLS=1 npm start`).

### Device selection and Poki Agent

Consecutive device calls do not require `acquire_device`. With one available device, calls select it automatically. With multiple devices, `list_devices` and `select_device` identify the target (or pass `device` per call). In `--dev-tools` mode, an explicit lease (`acquire_device`) remains available for sessions that need exclusive access across several calls.

Poki Agent starts its own stdio process with `POKI_MCP_TOOLS=all`. Its existing tool allowlist determines which tools reach its model.

### Execution details for `look` and `do`

- Each action in `do` is reported as `sent`, `not_sent` or `unknown`. Nothing after a failed action is sent, and an `unknown` action is never sent again. Element numbers belong to the device they were read from; switching devices or citing an element number absent from the latest read refuses the action before anything is sent.
- `look` and `do` work on a physical iPhone through the native bridge, on a booted simulator, and on a phone running WebDriverAgent. A physical iPhone needs the bridge built from this version by `./bin/setup`, because typing uses its `type_keys` and `pasteboard` operations.
- On a physical iPhone, typing uses hardware key presses (the bridge's `type_keys`). Only text the keyboard cannot type is pasted, and then the user's clipboard is saved first and put back afterwards; a clipboard that cannot be read back exactly is never pasted over. Key presses that fail part way are reported `unknown` and are never followed by a paste, with or without `clear`.
- On a simulator, `launch` starts the app with `simctl` the way `launch_app` does, and `type` uses the simulator's own `type_text`: key presses, and for text the keyboard cannot type a paste through the simulator's pasteboard, which keeps that text afterwards.
- Accessibility gets `POKI_CUA_TREE_MS` (default 2500 ms) per read; after that the screenshot's OCR answers instead. When accessibility names nothing across a third of the screen's height, the screenshot's text it did not name is listed after its elements, and the read says `accessibility + ocr`. Actions and the wait after them get at most `POKI_CUA_ACTION_CAP_MS` (default 4000 ms), excluding time spent waiting on a human approval dialog or `wait_until`.
- A locked or dark phone, or Poki's own app in front, stops the actions.
- `POKI_CUA_BACKEND=wda` with `POKI_WDA_URL=http://<phone>:8100` reads and acts through a WebDriverAgent runner deliberately launched for network access by the Mac instead of the bridge. That WDA must use a reachable, non-loopback `USE_IP`; Poki's standalone iOS launcher always binds its own runner to `127.0.0.1`. `look` and `do` answer the same way on either backend.

### One daemon, several clients

`POKI_INPUT_LOCK=1` gives each MCP session its own queue instead of one queue for every session. Read-only tools run beside other sessions' work, capped by `POKI_MAX_CONCURRENT_READS` (default 4), and tools that change the screen take a lock on their device. The lock belongs to the device a call resolves to, so a session that names a phone and one that gives its UDID wait for each other. A call whose device is not known yet, such as a phone's name before this session has listed or used that phone, or a batch that reaches more than one device, locks every device. A call that cannot get the lock within `POKI_INPUT_LOCK_WAIT_MS` (default 30000 ms) fails with an error that names the session and tool holding it. The lock lives in one daemon; two daemons driving one phone are not supported.

`POKI_MCP_CALL_LOG=<path>` appends one JSON line per finished tool call: the tool, how long it took, its verdict when it has one, and whether it failed. Arguments, text and images are never written, and the session appears only as a hash.

## Ask in plain language

Ask your agent for the task you want done:

```text
Open Settings on the iPhone simulator and tell me the iOS version.
```

In the default profile, `look` and `do` handle phone tasks:

- `look` captures the current screen and numbers visible elements.
- `do` runs an ordered `actions` list (`launch`, `tap`, `tap_text`, `type`, `swipe`, `scroll_to`, `back`, `wait_until`, `open_url`, `handoff`, and more) and returns the updated screen in one round trip.

When `--dev-tools` or `POKI_MCP_DEV_TOOLS=1` is enabled, standalone tools such as `batch_commands`, `fill`, `tap_text`, and `run_code` are also available directly.

Sensitive actions in `do` (payments, deletions, calling, sending messages, guarded apps, password entry, `open_url`, and `handoff`), as well as developer operations such as installing apps and reading the clipboard, trigger a macOS approval dialog on your Mac. See [Approval & Clipboard Behavior](#approval--clipboard-behavior).

## Optional action verification (`--dev-tools`)

`tap`, `tap_text`, `swipe`, `scroll`, and `go_back` accept `verify: false`. These calls omit the reads that compare the screen before and after an action. Their results include `verified: false` and do not confirm that the app accepted the input. Omitting `verify`, or setting it to `true`, keeps the default verification.

`tap_text` still reads the current screen to locate its target. With verification disabled, it uses the first matching position without waiting for two stable positions. Coordinate actions still obtain the current display dimensions. This option does not promise a call with no device reads.

`batch_commands` also accepts `verify: false`. Supported steps inherit that value, and a step can override it with `arguments.verify: true`. A batch with unverified steps reads the final screen once. That snapshot does not verify each preceding action. An unknown input outcome still stops the batch, including with `stop_on_error: false`.

Inside a batch, a touch step (`tap`, `tap_text`, `double_tap`, `long_press`, `go_back` or `handle_alert`) is compared with the screen before it unless the next step is also aimed by coordinates (`tap`, `double_tap`, `long_press`, `swipe`, `drag`, `scroll` or `pinch`) or the batch sets `stop_on_error: false`. A run of coordinate steps is written for one screen, so the batch does not pause inside it, even after a tap that changed nothing. A step with `arguments.verify: true` is always compared. With the default `stop_on_error`, a compared touch with no observed change pauses the batch before the steps after it.

Accessibility can miss changes that affect only pixels, such as Calculator's display after AC. A default batch can still stop with `no_change` in that case. An unverified tap does not produce `no_change`; inspect the final screenshot before reporting the task result.

## All MCP tools

The 6 default tools are marked **(default)**. The remaining 57 tools require `--dev-tools` or `POKI_MCP_DEV_TOOLS=1` (25 standalone tools merged into `look`/`do`, plus 32 developer tools).

| Group | Tool | What it does |
| --- | --- | --- |
| Default agent | `look` | **(default)** Read the screen and return numbered elements, new/gone diffs, and a screenshot. |
| Default agent | `do` | **(default)** Run an ordered list of actions (`tap`, `double_tap`, `tap_text`, `type`, `key`, `swipe`, `scroll_to`, `long_press`, `drag`, `pinch`, `button`, `back`, `launch`, `open_url`, `wait`, `wait_until`, `handoff`), read the screen once, and optionally return to the starting app (`finish: true`). |
| Devices | `list_devices` | **(default)** Find attached iOS devices and booted or previously used simulators. |
| Devices | `start_simulator` | Boot an existing simulator by id or name, or create one from an available model. |
| Devices | `shut_down_simulator` | Shut down the selected simulator. |
| Devices | `reconnect_device` | Attempt a replacement RemotePairing tunnel while preserving a working tunnel if replacement fails. Does not replay input. |
| Devices | `disconnect_device` | Close the selected RemotePairing helper and tunnel. |
| Devices | `select_device` | **(default)** Select one connected device by id or unambiguous name for this MCP session. |
| Devices | `get_device_info` | Read device identity, capture dimensions in logical points, and optionally platform settings. |
| Devices | `poki_mcp_status` | **(default)** Report tool counts, connected-device count, selected device, and approval mode. |
| Coordination | `acquire_device` | Exclusively occupy one device across tool calls in this MCP session. |
| Coordination | `renew_device` | Extend this session’s active device lease by 1–600 seconds (default 120). |
| Coordination | `release_device` | Release this session’s device lease after cancelling accepted work and awaiting recording/location cleanup. |
| Coordination | `cancel_device` | Stop all previously accepted work and background recording/location in this MCP session, including calls without a lease. |
| Screen | `observe_device` | Capture one image with its structured observation, non-reused element references and prompt check. |
| Screen | `take_screenshot` | Capture the current display and return a JPEG image with screen dimensions and a prompt warning check. |
| Screen | `save_screenshot` | Save a full-resolution screenshot to an absolute PNG or JPEG path or directory. |
| Screen | `start_recording` | Start recording the selected device display to an H.264 movie. |
| Screen | `stop_recording` | Finalize the session recording and inspect the saved movie before returning its path and media details. |
| Screen | `get_foreground_app` | Read the current foreground application from accessibility services. |
| Screen | `list_elements` | Read accessibility elements, or OCR when auto mode cannot use accessibility. Auto mode adds screenshot text that accessibility leaves out across a third of the screen. |
| Screen | `wait_for` | Poll visible text until it appears, or disappears when gone=true. |
| Screen | `wait` | Pause for seconds without interacting with a device. |
| Touch | `tap` | Tap at x/y in screen points or at the center of a current element ref. |
| Touch | `tap_text` | Find one visible element matching text, waiting for it to appear and hold still (five seconds on a screen accessibility can read, longer when only screen text recognition can find it), trying OCR when needed, and tap it. |
| Touch | `double_tap` | Send two taps at x/y in logical screen points or at a current element ref. |
| Touch | `long_press` | Hold one touch at x/y or an element ref. |
| Touch | `swipe` | Move a touch from from_x/from_y to to_x/to_y in logical screen points. |
| Touch | `scroll` | Scroll up, down, left, or right around x/y, or the screen center when omitted. |
| Touch | `scroll_to` | Search for visible text and scroll until it is found, content stops changing, or max_scrolls is reached. |
| Touch | `drag` | Hold a touch, then move between the supplied logical-point endpoints. |
| Touch | `pinch` | Perform a two-finger gesture centered at x/y in screen points. |
| Touch | `touch_path` | Draw one continuous stroke through timed points, such as a circle or a curve. `time_ms` may have a fractional part. |
| Touch | `draw_strokes` | Draw 1 to 12 separately lifted strokes in one call, such as handwriting or a signature. |
| Text and keys | `fill` | Focus a field by ref, coordinates, or matching field label/placeholder/value/identifier, replace its text, and optionally submit after text verification. |
| Text and keys | `type_text` | Enter text into the focused field, optionally clearing it first and sending Return after verification. |
| Text and keys | `press_key` | Send a named keyboard key with optional modifiers and count (default one). |
| Text and keys | `hide_keyboard` | Detect a visible keyboard, send its toggle event, and verify dismissal. |
| Text and keys | `get_clipboard` | Read clipboard contents supported by the platform. |
| Text and keys | `set_clipboard` | Replace the selected device clipboard with text. |
| System | `press_button` | Send a hardware-style button event such as Home, lock, volume, mute, or Siri. |
| System | `system_gesture` | Send the requested system navigation gesture. |
| System | `go_back` | Tap a uniquely identified back control when available, otherwise swipe from the left edge. |
| System | `rotate` | Request a display orientation and invalidate cached coordinates. |
| System | `set_appearance` | Request light or dark appearance through the selected platform adapter. |
| System | `set_accessibility` | Change supported text-size or accessibility display settings. |
| System | `set_location` | Start a simulated latitude/longitude for the selected device. |
| System | `clear_location` | Stop the location simulation owned by this service for the selected device. |
| System | `handle_alert` | Choose a visible alert button by text or accept/dismiss action, looking for five seconds; recognition already running on an unreadable screen may finish after that. |
| System | `request_human_action` | Show a macOS dialog asking the user to complete a step on the device. |
| Apps | `list_apps` | **(default)** List installed applications, excluding system apps unless include_system=true. |
| Apps | `launch_app` | Launch an application by bundle_id or unambiguous name. |
| Apps | `terminate_app` | Stop an application identified by bundle_id on the selected device. |
| Apps | `install_app` | Install an application from a local path. |
| Apps | `uninstall_app` | Remove an installed application identified by bundle_id. |
| Apps | `open_settings` | Open a supported Settings page or an application settings page. |
| Apps | `open_url` | Ask the selected device to open a URL. |
| Apps | `build_and_run` | Build an Xcode project or workspace from project_path, install the result, and launch it. |
| Apps | `download_app_container` | Copy an accessible application container to a local destination, or the service state directory by default. |
| Apps | `list_crashes` | List available reports, optionally filtering by process name or bundle identifier and kind. |
| Apps | `get_crash` | Read a report by path from list_crashes, or find the newest report for process. |
| Batches | `batch_commands` | Do a whole known task in one call: launch the app, tap, fill, scroll, go back and answer alerts, each {tool, arguments}. |
| Batches | `run_code` | Run an async JavaScript function on an isolated worker, calling device tools with `await tools.<name>(args)`, so the code loops, filters and decides each next step from the results in one call instead of a model round trip per step. |

`run_code` is in the developer catalog (`--dev-tools` or `POKI_MCP_DEV_TOOLS=1`, or `POKI_MCP_TOOLS=all`), not the default `tools/list`. The sandbox exposes only `tools`, `input` and `console`: no require, file system, network, process or timers. A tool error throws and the code can catch it; an action receipt with `sent=false` or an unknown outcome stops the script and returns the steps already run, as `batch_commands` does; cancellation and timeout also stop it and cancel the device call in progress. The result lists every tool call with its name, elapsed time and receipt. Default limits are 120 seconds and 60 tool calls, set with `timeout_seconds` and `max_tool_calls`. Use it for predictable multi-step work such as scrolling until something appears and then reading it; use a single tool for a one-step action, and return to the model when the next step needs visual judgement.

## Agent skills

[Unlock an iPhone](../agent/skills/iphone-unlock/SKILL.md) packages an authorized passcode workflow, a calibrated portrait keypad, and a native helper that keeps one connection open for the entire input sequence. Poki Agent loads this skill and exposes the host-side `unlock_device` tool when the user has configured a passcode locally. It requires Poki device ownership; it does not add an MCP tool. The skill documents the physical-device evidence and supported layout.

## Coordinates, Screenshots, and Recordings

- All coordinates and element frames use **logical screen points**.
- `take_screenshot` returns JPEG data. Passing `max_width` scales the returned image without changing logical interaction coordinates.
- `save_screenshot` writes a full-resolution PNG or JPEG based on the file extension.
- The `lossless` parameter does not alter either screenshot rule.
- On a simulator, the screen's rounded corners and Dynamic Island area are black in screenshots. Without this mask, that area differs between frames of a still screen, which would expire element refs.
- Default output directories:
  - Screenshots: `~/Pictures/Poki MCP`
  - Recordings: `~/Movies/Poki MCP`

## Element Inspection & Delivery Flags

- `list_elements` prefers Accessibility in `auto` mode and falls back to Vision OCR when Accessibility cannot be read. Every response reports which source was used. Some apps draw a list with their own renderer and publish only a header to Accessibility. When the named elements leave a third of the screen's height empty, `auto` mode adds the screenshot text that Accessibility did not name, after the Accessibility elements, each with `"source": "ocr"`. `source: "accessibility"` turns this off.
- Element `ref` identifiers are never reassigned within an MCP session. They expire after known input, a device change, a newly captured image showing a change, or **30 seconds**. Input and image changes observed by another session in the same daemon also invalidate the old observation. Re-fetch elements before acting on stale refs. Poki cannot detect an external touch or controller change until it observes that change; it does not continuously watch the display.
- In action responses, `sent=true` means the touch or key report was written to the connection. It does not mean the device acted on it. The device does not acknowledge reports, and a dropped report returns no error.
- A standalone action reads the screen back after it runs. `screen` lists the foreground app and visible text. When `screen_change_verified=true`, `screen_changed` indicates whether the accessibility output changed. This covers elements, text, values, positions, and selected, enabled, or focused states. `false` means no change was observed. It does not prove the action failed. The effect might not be exposed to accessibility, such as a canvas update, or might not have appeared yet. `true` does not prove the action caused the change, because another element may have updated at the same time. `screen_change_verified=false` means the before and after states could not be compared, such as in an app with no accessibility elements. In that case, inspect the screen directly.

## Device ownership and stopping work

Consecutive calls do not require a lease. For exclusive ownership across several calls, call `acquire_device` with an explicit device ID or unambiguous name. Acquisition resolves the device without booting it and returns `lease_id`, `device`, `state` and `expires_at`. Each session can hold one device lease. While holding it, release before switching to another device. Acquisition is serialized with ordinary operations; renewal, release and cancellation bypass that queue.

- `acquire_device({device, ttl_seconds?})`: default TTL 120 seconds, allowed integer range 1–600 seconds. Another session cannot acquire, observe or operate this device during the lease. Selection, aliases, automatic selection, batch steps and existing simulator startup all pass through the same device check. Creating a new simulator reserves its creation operation before running it; an existing lease must be released first.
- `renew_device({lease_id, ttl_seconds?})`: extend the matching session's active lease from the current time. Long operations do not renew automatically. Renew before expiry, including while a long tool is running.
- `release_device({lease_id})`: invalidate accepted work, stop recording and simulated location owned by this session, await cleanup, then make the device available. A lease stays `releasing` until cleanup finishes.
- `cancel_device({lease_id?})`: stop **all previously accepted work in this MCP session**, including queued calls made without a lease, and stop its background recording/location. If supplied, `lease_id` must match this session's active lease. Other sessions are unaffected. New work may be submitted after cleanup finishes; an old queued operation never resumes as an unleased operation.

The stop result identifies its scope, reason and cleanup outcomes. Cancellation stops owned local processes and waits; it cannot undo input already dispatched to the device. Inspect the screen before retrying an unknown outcome. The stdio bridge forwards SDK request cancellation to the corresponding daemon operation, including waits, device helpers and the local approval dialog. A normal HTTP response closing is not a session cancellation. Normal stdio EOF or termination requests session cleanup; a crashed client holding an explicit lease is bounded by its TTL. A client without a lease has no persistent ownership guarantee after an abnormal exit; use an explicit lease for recordings and multi-call tasks.

`list_devices` still reports discovery and occupancy (`occupied`, `owned_by_session`, `state`, `expires_at`) without exposing another session's task. Occupied physical devices are not queried for additional name/model information by other sessions. If an alias has not been discovered, use the displayed device ID. An unleased recording or location must be stopped by its owner before a different session can acquire that device.

This arbitration exists only in **one shared Poki daemon**. Different daemon instances and different `POKI_MCP_STATE_DIR` values are independent. It does not lock out other control software or a person touching the screen. Run one daemon for the clients that need to coordinate; do not start multiple daemons against the same endpoint directory. No persistent task database or recovery across daemon restarts is provided.

## Observations, deadlines and receipts

`observe_device` returns structured elements and a prompt check, plus a PNG by default. `include_image:false` omits the PNG attachment but still captures a frame and checks OCR. For selected single actions, `return_observation:true` reuses the stable **post-input** AX tree with short-lived element refs and an AX-based prompt check; it does **not** add a screenshot or image OCR by default. Fast routes additionally request `post_action_ocr:true`, which captures an image **after** AX stabilization and performs OCR prompt checking. The sources remain non-atomic and their original timestamps are preserved. Each action-bound observation must pass receipt, device/revision, time, foreground, completeness and prompt checks; otherwise Agent and routes fall back to a new `list_elements`/`observe_device` call. AX-only refs are bound to the most recently measured viewport and expire after known input, explicit later capture, session/display changes or 30 seconds. The Agent sends the model **one trimmed element list**, not both the full nested receipt and a duplicate list; full evidence remains in the verification trace. No observed state or `sent:true` alone proves task success or permits retrying uncertain input. Existing tools and callers retain their default behavior.

`wait_for` uses a monotonic deadline covering capture, AX, OCR and polling. It starts no new read after that deadline, aborts in-flight external work and waits for owned processes to close. Consequently response delivery can include bounded process termination time after the deadline; the deadline is not a claim that the HTTP response arrives at the exact requested millisecond.

Input receipts retain `sent`, `text_verified`, `submit_sent` and other confirmed facts when recording recovery fails. The separate `recording` object reports recovery failure. Unconfirmed delivery remains `outcome: "unknown"`; it is never automatically replayed. Automatic recovery is suspended while native input intentionally interrupts the media stream. Normal reconnection after an explicit input is counted as `input_reconnects` and does not consume the automatic retry budget, so healthy multi-step recording is not limited to three inputs. Only background recovery from unexpected stream disconnects consumes `automatic_retries`, at most three per recording lifetime. Each reconnect still has a five-second first-frame deadline. `reconnects` is the total of these two counters. A failed reconnect leaves an explicit error; stop/start a recording to begin a new automatic budget. Stop, release, cancellation and session cleanup disable retries and await owned recording processes, and cleanup reports finalization errors separately.

Batch results retain the executed prefix and each step's `elapsed_ms`, then report `stop_reason`. A step's `device` applies to that step alone; steps without one use the session selection, and the screen read after the last step comes from the device that step used. Human handoff, cancellation, expiry, timeout and unknown input outcomes always stop subsequent steps even with `stop_on_error=false`. A successful action's receipt remains present if stopping occurs later. A detected human-only prompt in `handle_alert`, `take_screenshot`, `observe_device` or the screen read after the last step sets the same `needs_human_action` stop reason; observation tools retain their captured image and structure. With the default `stop_on_error`, every step is checked before any runs, so a mistyped step costs nothing. The last block carries `screen`, and after a stop also `failed_step`, `remaining_steps` and `next`, so the following call can fix one step and send only what is left.

Tool responses include `_meta.timing.stages` with queue, capture, AX, OCR, input, recording recovery and external-process durations where exercised. Each stage has an ID and parent ID. Parent durations include their children, so do not add parents and children. External-process time includes helper startup, connection and work inside the helper; those internal costs are not separately measured. Timing metadata contains no input text, device identifiers or image content, and it does not measure model reasoning or client round-trip time. No end-to-end speed multiplier is claimed.

## Efficient short workflows

- **Put the whole known task in one batch:** When the request already names what to do, send `launch_app` and every step in one `batch_commands` call. `launch_app` on a simulator returns once the interface is readable; `tap_text`, `fill` and `handle_alert` wait five seconds for their target to appear and hold still (a recognition already running on a screen accessibility cannot read may finish a few seconds later), so a batch can cross screens; the reply ends with the visible text, so a closing `take_screenshot` is only needed for pixels. Leave out a step when whether to do it depends on what an earlier step shows, or when it needs the user's decision. A wrong target stops the batch without tapping and reports the closest text on screen. Each step result reports `elapsed_ms`, which reflects server-side execution time only and excludes model reasoning and client round-trip overhead.
- **Use `fill` for known input fields:** Call `fill` directly instead of chaining `tap` and `type_text`; `field` can be left out when one text field is visible. On physical devices, `fill` focuses, replaces, and verifies text within a single native input session to avoid an extra connection wait. On simulators it taps, waits for focus and types, and a verified mismatch is an error. Plain text typed on a simulator first switches its keyboard to `en_US` (`simctl keyboard`), because a simulator created on a Chinese Mac types through Pinyin and rewrites Latin text and punctuation; the setting stays on that simulator. Because `fill` replaces existing field content, review your draft beforehand; reserve `type_text` for appending to an already-focused field.
- **Review and submit with `return`:** To inspect text before sending, `fill` and read the `screen` it returns. After verifying the draft, submit using `press_key` with `return` and inspect the resulting screen. Do not re-enter the full text or call `type_text` with an empty string to submit. Note that `text_verified` only confirms text entry into the field and `sent` only confirms the action was dispatched; neither guarantees application-level delivery.
- **Handle `CoreDeviceError` 4016 via observed UI:** If launching an app fails with `CoreDeviceError` 4016, inspect the current screen and continue through an observed Home Screen or App Switcher entry point. Do not repeatedly retry the same launch path unless device conditions change. This serves as invocation guidance and does not permanently mark the app as unavailable after a single failure.

## Approval & Clipboard Behavior

- **Local approval dialog**: In `do`, sensitive steps (payments, deletions, calling, sending messages, guarded apps such as Wallet or App Store, password entry, `open_url`, and `handoff`) trigger a local macOS approval dialog by default. In `--dev-tools` mode, installing or uninstalling apps, building and running projects, opening URLs, downloading app containers, and reading or writing the clipboard also trigger this dialog.
- Setting `POKI_MCP_APPROVAL_MODE=allow` bypasses this local daemon prompt for preapproved workflows, except for `handoff` and `request_human_action` (which always require the person's confirmation), and it **never** auto-completes iOS/macOS system authorization dialogs.
- **Unicode paste & clipboard restoration**:
  - Unicode text entry may use the device clipboard. On physical devices, Poki MCP attempts to save and restore a complete clipboard snapshot; if full restoration is not possible, the response explicitly reports restoration as unavailable.
  - The snapshot is held only in memory for the duration of that single operation and cannot be restored by a subsequent tool call after a human handoff.
  - If a paste prompt is pending or the target field cannot be verified, automatic submission stops and leaves the intended text on the clipboard.
  - Poki MCP **never** auto-accepts an iOS **Allow Paste** prompt. Note that a true first-time **Allow Paste** human-handoff flow remains unverified on hardware (prior successful paste checks did not trigger the system prompt).
