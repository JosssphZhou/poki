---
name: poki-mcp
description: How to send text and answer prompts with Poki MCP on a physical iPhone. Read before the first Poki call on a task that types into a field, meets a system prompt, or navigates with hardware buttons.
license: AGPL-3.0-only
---

# Poki MCP

## Tool discovery

The default `tools/list` contains four tools: `look`, `do`, `status`, and `mac`. Use `look {}` to read the screen, `do {actions:[...]}` for supported input, and `status {}` for Mac service and device state. Use numbers from the latest `look` or `do` answer; they are not stable App identities.

For capabilities such as device selection, prompts and batches, call `mac {tool:"name", describe:true}` to inspect the original argument schema, then `mac {tool:"name", arguments:{...}}` to execute it. For example, `mac {tool:"list_devices", arguments:{}}` finds devices and `mac {tool:"select_device", arguments:{device:"DEVICE_ID"}}` selects one in this MCP session. Every legacy capability remains available through this wrapper. The action names inside `batch_commands` and `run_code` remain unwrapped; lease management calls stay outside a batch. Consecutive calls do not require a lease.

Old tool names remain directly callable for one release and return migration notices, but clients using default discovery do not list them. Set `POKI_MCP_TOOLS=all` in the MCP client's process environment and reconnect if that client needs the complete catalog. Poki Agent selects the complete catalog for its own MCP process and retains its own tool allowlist. `POKI_TOOL_PROFILE=cua` no longer selects a separate list.

Read the [migration table](../../docs/mcp-app-tools.md) and [tool reference](../../docs/tools.md) for platform differences and capability parameters. If this skill was copied into a client skill directory, resolve those documents as `docs/mcp-app-tools.md` and `docs/tools.md` in the checkout used by the registered MCP server, not relative to the copied skill.

Mac input has no approval protection for payments, deleting or sending messages. App routines and phone-side handoff are not implemented; `routines` is not registered, and `do` rejects unsupported App actions or `finish:true` before input. Do not assume App safety guarantees.

Use `mac {tool:"run_code", arguments:{code:"..."}}` for scripted work. It runs an async JavaScript function that calls device tools with `await tools.<name>(args)`, so the code reads a result and decides the next step in one call instead of a model round trip per step. Prefer it when a task is predictable but depends on what each step returns, such as scrolling until a row appears and then reading its value. A tool error throws and the code can catch it; an action that reports `sent=false` or an unknown outcome stops the script, as a batch stops. The sandbox has no require, file system, network, process or timers.

The examples below record earlier physical-iPhone checks. They are not a guarantee for every iOS version or app. Verify the current screen after each task.

## Send known text in one batch

When the text is already decided, call `mac {tool:"batch_commands", arguments:{commands:[...]}}` with the steps that open the field and fill it. Inside `commands`, retain the original step shape, such as `{tool:"fill", arguments:{text:"...", submit:true}}`; do not wrap each step in another `mac` call. Use `submit:true` only when sending is authorized and Return sends. `fill` reads the text back from that field before it sends Return, and a failed `fill` stops a batch with the default `stop_on_error: true`, so no look at the draft is needed in between. Keep them apart when the user asked to review the draft.

Basis: tapping `Add Row` then `fill` with `submit: true` in one batch, in a list of text fields: only the new row changed and Return followed the read-back, 3 of 3. A search typed into Chrome's address bar the same way reached the results, 1 of 1.

## When `fill` refuses

`fill` types nothing unless it can confirm the field being edited is the one you aimed at. A field-confirmation error says nothing was typed or sent. The default batch stops there. Read `screen` in the reply, aim again, and retry only the unfinished steps. A `batch_commands` failure returns `remaining_steps` for that batch.

Basis: a tap that gave the edit to the next row, 3 of 3; a list that kept moving, 3 of 3; coordinates with no field under them while another row was being edited, 1 of 1. Every row kept its text and Return was not sent.

## Paste permission

`fill` answers the system paste prompt itself: it taps Allow Paste, reads the text back, then sends Return. The receipt says `paste_permission_answered: true`, and no `handle_alert` call is needed.

Basis: Chrome's address bar, 1 of 1.

## Other prompts

Use `mac {tool:"handle_alert", arguments:{action:"accept"}}`, then read `screen` to confirm the prompt closed. A `button` label that is not there returns `Nothing was tapped` and leaves the prompt up.

Basis: a test alert, both paths, 1 of 1.

## Go to the Home screen

On a physical iPhone, use `do {actions:[{button:"home"}]}` or `mac {tool:"press_button", arguments:{button:"home"}}`. The legacy `press_key` capability with `key:"home"` sends a keyboard Home key and does not navigate to the iPhone Home screen. Read the screen after the button event to confirm navigation.

## Optional iPhone unlock

Poki Agent's host-integrated `unlock_device` is separate from the MCP tool catalog. Only the user may choose and configure `POKI_IPHONE_PASSCODE` in a private local launcher environment. Ask "Do you want Poki Agent to unlock this iPhone when it is locked?" and stop for that decision. Default to no configuration. Anyone or any program with access to this Mac may be able to read the passcode. If the user agrees, give them the hidden-input zsh commands in `agent/README.md` to run themselves. Never ask for the passcode in chat. Never read or write their passcode for them. The host passes it to the helper over stdin, outside model inputs and logs.

The verified hardware case is only iPhone17,1 in portrait orientation with a six-digit passcode and a 402-by-874-point keypad. Read `agent/skills/iphone-unlock/SKILL.md` in the Poki checkout before use. Setup builds `build/native-target/release/examples/unlock_iphone`. Confirm the current keypad layout and inspect the resulting screen. Without configuration, ask the user to unlock manually.

## Handle prompts

Read the visible prompt and its reported kind. Call `mac {tool:"handle_alert", arguments:{button:"VISIBLE LABEL"}}`, or supply `action:"accept"` / `"dismiss"` in `arguments`, to choose a visible button. For a purchase prompt, generic `action: "accept"` leaves the prompt open and returns its kind and available buttons. After the action, read the screen to confirm the dialog closed and the task reached its intended state.

For login or verification, use the credentials available for the authorized task. Read a requested SMS verification code from Messages or notifications, enter it, and verify the resulting screen. Confirm a purchase only when the user's task explicitly requests that purchase. In that case, set `button` to the visible purchase button text. Otherwise dismiss the prompt or continue the task without purchasing.
