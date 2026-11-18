---
name: poki-mcp
description: How to send text and answer prompts with Poki MCP on a physical iPhone. Read before the first Poki call on a task that types into a field, meets a system prompt, or navigates with hardware buttons.
license: AGPL-3.0-only
---

# Poki MCP

For installation or updates of the standalone iPhone app, read [install-poki](../install-poki/SKILL.md) in the repository. If this skill was copied alone, use `skills/install-poki/SKILL.md` in the Poki checkout. The iPhone update branch checks the existing data, signing identity and release channel before installation. Updating the Mac's MCP service does not update the iPhone app.

## Tool discovery

The default `tools/list` exposes six phone-agent tools that match Poki on the iPhone: `look`, `do`, `poki_mcp_status`, `list_devices`, `select_device`, and `list_apps`. `look` reads the screen and returns numbered elements plus a screenshot. `do` runs an ordered `actions` list (`tap`, `double_tap`, `tap_text`, `type`, `key`, `swipe`, `scroll_to`, `long_press`, `drag`, `pinch`, `button`, `back`, `launch`, `open_url`, `wait`, `wait_until`, `handoff`) and reads the screen once at the end; pass `finish: true` on the final action step to return to the app where the task started. Calling an unexposed legacy tool in default mode returns an error naming the `look` or `do` replacement, or explaining how to enable the developer tool group.

Pass `--dev-tools` to `src/stdio.mjs` or set `POKI_MCP_DEV_TOOLS=1` in the MCP client's process environment (`POKI_MCP_TOOLS=all` also works) and reconnect to unlock the full 63-tool developer catalog, including simulator management, screen recording, Xcode builds, location and appearance simulation, crash reports, `batch_commands`, `fill`, and `run_code`. Read `docs/tools.md` in the Poki checkout for the full catalog. Consecutive calls do not require `acquire_device`. Poki Agent selects the complete catalog for its own MCP process and retains its own tool allowlist.

## Typing, navigation, and prompts in default mode

- **Typing**: In `do`, pass `{ type: "text", ref: 3, clear: true }` to tap element `3` and enter text, or follow `{ type: ... }` with `{ key: "return" }` to submit. On a physical iPhone, typing sends hardware key presses and falls back to clipboard paste only when needed while saving and restoring the user's clipboard.
- **Home and back**: Use `{ button: "home" }` inside `do` to go to the iPhone Home screen (`{ key: "home" }` sends a keyboard Home key). Use `{ back: true }` to tap a visible back control or swipe from the leading edge.
- **Prompts and approvals**: Sensitive actions in `do` (payments, deletions, calling, sending messages, guarded apps such as Wallet or App Store, password fields, `open_url`, and `{ handoff: { kind, text } }`) trigger a local macOS approval dialog unless preapproved (`handoff` always asks). Read the returned screen after any prompt or handoff to confirm the dialog closed.

## Developer catalog notes (`--dev-tools` / `POKI_MCP_DEV_TOOLS=1`)

`run_code` is in the developer catalog. It runs an async JavaScript function that calls device tools with `await tools.<name>(args)`, so the code reads a result and decides the next step in one call instead of a model round trip per step. Prefer it when a task is predictable but depends on what each step returns, such as scrolling until a row appears and then reading its value. A tool error throws and the code can catch it; an action that reports `sent=false` or an unknown outcome stops the script, as a batch stops. The sandbox has no require, file system, network, process or timers.

The examples below record earlier physical-iPhone checks. They are not a guarantee for every iOS version or app. Verify the current screen after each task.

## Send known text in one batch

When the text is already decided, send the steps that open the field and the `fill` in one `batch_commands` call, with `submit: true` on the `fill` when Return sends. `fill` reads the text back from that field before it sends Return, and a failed `fill` stops a batch with the default `stop_on_error: true`, so no look at the draft is needed in between. Keep them apart when the user asked to review the draft.

Basis: tapping `Add Row` then `fill` with `submit: true` in one batch, in a list of text fields: only the new row changed and Return followed the read-back, 3 of 3. A search typed into Chrome's address bar the same way reached the results, 1 of 1.

## When `fill` refuses

`fill` types nothing unless it can confirm the field being edited is the one you aimed at. A field-confirmation error says nothing was typed or sent. The default batch stops there. Read `screen` in the reply, aim again, and retry only the unfinished steps. A `batch_commands` failure returns `remaining_steps` for that batch.

Basis: a tap that gave the edit to the next row, 3 of 3; a list that kept moving, 3 of 3; coordinates with no field under them while another row was being edited, 1 of 1. Every row kept its text and Return was not sent.

## Paste permission

`fill` answers the system paste prompt itself: it taps Allow Paste, reads the text back, then sends Return. The receipt says `paste_permission_answered: true`, and no `handle_alert` call is needed.

Basis: Chrome's address bar, 1 of 1.

## Other prompts

Use `handle_alert` with `action: "accept"`, then read `screen` to confirm the prompt closed. A `button` label that is not there returns `Nothing was tapped` and leaves the prompt up.

Basis: a test alert, both paths, 1 of 1.

## Go to the Home screen

On a physical iPhone, use `press_button` with `button: "home"`. `press_key` with `key: "home"` sends a keyboard Home key and does not navigate to the iPhone Home screen. Read the screen after the button event to confirm navigation.

## Optional iPhone unlock

Poki Agent's host-integrated `unlock_device` is separate from the MCP tool catalog. Only the user may choose and configure `POKI_IPHONE_PASSCODE` in a private local launcher environment. Ask "Do you want Poki Agent to unlock this iPhone when it is locked?" and stop for that decision. Default to no configuration. Anyone or any program with access to this Mac may be able to read the passcode. If the user agrees, give them the hidden-input zsh commands in `agent/README.md` to run themselves. Never ask for the passcode in chat. Never read or write their passcode for them. The host passes it to the helper over stdin, outside model inputs and logs.

The verified hardware case is only iPhone17,1 in portrait orientation with a six-digit passcode and a 402-by-874-point keypad. Read `agent/skills/iphone-unlock/SKILL.md` in the Poki checkout before use. Setup builds `build/native-target/release/examples/unlock_iphone`. Confirm the current keypad layout and inspect the resulting screen. Without configuration, ask the user to unlock manually.

## Handle prompts

Read the visible prompt and its reported kind. Use `handle_alert` with a button label or `action: "accept"` / `"dismiss"` to choose a visible button. For a purchase prompt, generic `action: "accept"` leaves the prompt open and returns its kind and available buttons. After the action, read the screen to confirm the dialog closed and the task reached its intended state.

For login or verification, use the credentials available for the authorized task. Read a requested SMS verification code from Messages or notifications, enter it, and verify the resulting screen. Confirm a purchase only when the user's task explicitly requests that purchase. In that case, set `button` to the visible purchase button text. Otherwise dismiss the prompt or continue the task without purchasing.
