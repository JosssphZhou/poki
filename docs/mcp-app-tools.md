# Mac MCP and the App protocol

Mac MCP lists `look`, `do`, `status`, and `mac` by default (previously 29 tools). The complete catalog has 65 tools. `POKI_MCP_TOOLS=all` still lists the complete catalog. `POKI_TOOL_PROFILE=cua` is no longer needed; the same compact catalog is the default for every profile.

## Core tools and platform differences

| App tool | Mac behavior |
| --- | --- |
| `look {full?}` | Reads the screen, numbered elements and image. Numbers belong to the latest read, not stable App identities. The image may be scaled; use element frames in screen points for coordinates. |
| `do {actions, full?, finish?}` | Runs supported actions and observes. `finish:false` is accepted; `finish:true` is rejected before any input. It does not return the phone to the task's originating app. |
| `routines` | Not supported and not registered. No stub or false save/replay confirmation. |
| `status {}` | Real Mac version, device inventory, selected device, update information and approval scope. App runner, relay and phone approval state are not represented. |
| `report_plan`, `finish_task` | Agent runtime tools, not MCP tools. The calling agent owns planning and result verification. |
| `ask_poki` | Optional App host tool, disabled by default there. Not registered on Mac; no hidden model login or delegated agent execution. |

The relay forwards the App's catalog; it does not define another tool protocol.

**Mac input has no approval protection for payments, deleting or sending messages.** Existing approval checks on selected legacy management tools still apply. Do not infer phone-side approval, human handoff, routine playback or stable element numbers from the shared tool names.

Supported `do` actions are `tap`, `type` (with `ref` and `clear`), `key`, `swipe`, `scroll_to`, `long_press`, `drag`, `pinch`, `button`, `launch`, and `wait`. Its description gives the accepted forms. App-only `run`, `handoff`, `wait_until`, `back`, `via`, and `drag.hold_ms` are rejected before any action in that call is sent. Use the legacy `wait_for`, `go_back`, or other appropriate Mac capability when needed. Unsupported behavior is not silently treated as successful.

## Mac capabilities

Inspect a capability without operating the device:

```json
{"tool":"start_recording","describe":true}
```

Execute it with its original parameters:

```json
{"tool":"start_recording","arguments":{"device":"DEVICE_ID"}}
```

`mac` accepts a fixed whitelist. It validates arguments against the original tool schema, including stroke timing checks, before using the existing dispatch, locking, cancellation and approval paths. Device selection, leases, simulator controls, Xcode builds, recording, crash logs, drawing and advanced inputs keep all their parameters. There is no arbitrary-function dispatch.

## Every existing tool

For one release, calling any legacy name below still executes that tool and appends a deprecation notice to its MCP result. `bin/call.mjs` prints that notice on stderr to preserve its JSON stdout. `look` and `do` retain their names. The table uses the lossless route for each legacy tool; common screen and input tasks can instead use `look` and `do`.

| Existing name | New call (all original arguments retained) |
| --- | --- |
| `list_devices` | `mac {tool:"list_devices", arguments:{...}}` |
| `start_simulator` | `mac {tool:"start_simulator", arguments:{...}}` |
| `shut_down_simulator` | `mac {tool:"shut_down_simulator", arguments:{...}}` |
| `select_device` | `mac {tool:"select_device", arguments:{...}}` |
| `get_device_info` | `mac {tool:"get_device_info", arguments:{...}}` |
| `take_screenshot` | `mac {tool:"take_screenshot", arguments:{...}}` |
| `save_screenshot` | `mac {tool:"save_screenshot", arguments:{...}}` |
| `start_recording` | `mac {tool:"start_recording", arguments:{...}}` |
| `stop_recording` | `mac {tool:"stop_recording", arguments:{...}}` |
| `get_foreground_app` | `mac {tool:"get_foreground_app", arguments:{...}}` |
| `list_elements` | `mac {tool:"list_elements", arguments:{...}}` |
| `tap` | `mac {tool:"tap", arguments:{...}}` |
| `tap_text` | `mac {tool:"tap_text", arguments:{...}}` |
| `double_tap` | `mac {tool:"double_tap", arguments:{...}}` |
| `long_press` | `mac {tool:"long_press", arguments:{...}}` |
| `swipe` | `mac {tool:"swipe", arguments:{...}}` |
| `scroll` | `mac {tool:"scroll", arguments:{...}}` |
| `scroll_to` | `mac {tool:"scroll_to", arguments:{...}}` |
| `drag` | `mac {tool:"drag", arguments:{...}}` |
| `pinch` | `mac {tool:"pinch", arguments:{...}}` |
| `touch_path` | `mac {tool:"touch_path", arguments:{...}}` |
| `draw_strokes` | `mac {tool:"draw_strokes", arguments:{...}}` |
| `type_text` | `mac {tool:"type_text", arguments:{...}}` |
| `fill` | `mac {tool:"fill", arguments:{...}}` |
| `press_key` | `mac {tool:"press_key", arguments:{...}}` |
| `hide_keyboard` | `mac {tool:"hide_keyboard", arguments:{...}}` |
| `press_button` | `mac {tool:"press_button", arguments:{...}}` |
| `system_gesture` | `mac {tool:"system_gesture", arguments:{...}}` |
| `go_back` | `mac {tool:"go_back", arguments:{...}}` |
| `rotate` | `mac {tool:"rotate", arguments:{...}}` |
| `set_appearance` | `mac {tool:"set_appearance", arguments:{...}}` |
| `set_accessibility` | `mac {tool:"set_accessibility", arguments:{...}}` |
| `list_apps` | `mac {tool:"list_apps", arguments:{...}}` |
| `launch_app` | `mac {tool:"launch_app", arguments:{...}}` |
| `terminate_app` | `mac {tool:"terminate_app", arguments:{...}}` |
| `install_app` | `mac {tool:"install_app", arguments:{...}}` |
| `uninstall_app` | `mac {tool:"uninstall_app", arguments:{...}}` |
| `open_settings` | `mac {tool:"open_settings", arguments:{...}}` |
| `open_url` | `mac {tool:"open_url", arguments:{...}}` |
| `build_and_run` | `mac {tool:"build_and_run", arguments:{...}}` |
| `set_location` | `mac {tool:"set_location", arguments:{...}}` |
| `clear_location` | `mac {tool:"clear_location", arguments:{...}}` |
| `get_clipboard` | `mac {tool:"get_clipboard", arguments:{...}}` |
| `set_clipboard` | `mac {tool:"set_clipboard", arguments:{...}}` |
| `list_crashes` | `mac {tool:"list_crashes", arguments:{...}}` |
| `get_crash` | `mac {tool:"get_crash", arguments:{...}}` |
| `download_app_container` | `mac {tool:"download_app_container", arguments:{...}}` |
| `request_human_action` | `mac {tool:"request_human_action", arguments:{...}}` |
| `handle_alert` | `mac {tool:"handle_alert", arguments:{...}}` |
| `wait_for` | `mac {tool:"wait_for", arguments:{...}}` |
| `wait` | `mac {tool:"wait", arguments:{...}}` |
| `batch_commands` | `mac {tool:"batch_commands", arguments:{...}}` |
| `run_code` | `mac {tool:"run_code", arguments:{...}}` |
| `acquire_device` | `mac {tool:"acquire_device", arguments:{...}}` |
| `renew_device` | `mac {tool:"renew_device", arguments:{...}}` |
| `release_device` | `mac {tool:"release_device", arguments:{...}}` |
| `cancel_device` | `mac {tool:"cancel_device", arguments:{...}}` |
| `observe_device` | `mac {tool:"observe_device", arguments:{...}}` |
| `disconnect_device` | `mac {tool:"disconnect_device", arguments:{...}}` |
| `reconnect_device` | `mac {tool:"reconnect_device", arguments:{...}}` |
| `poki_mcp_status` | `mac {tool:"poki_mcp_status", arguments:{...}}` |
| `look` | `look {full?}` |
| `do` | `do {actions, full?, finish?}` |
