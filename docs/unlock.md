# Optional MCP unlock

Unlock is opt-in. Existing calls keep their behavior.

## Unlock

The MCP `unlock_device` tool uses the existing input transport, including RemotePairing. It does not bypass iOS authentication. It requires a trusted and reachable device, UI Automation, a readable system passcode screen, and a six-digit passcode configured by the user on the Mac. A restart or unavailable developer connection can still require manual unlocking.

Only the user should configure these environment variables in their private daemon launcher. In an interactive zsh terminal, before starting the daemon:

```zsh
export POKI_UNLOCK_DEVICE='YOUR_EXACT_DEVICE_ID'
read -rs 'POKI_IPHONE_PASSCODE?iPhone passcode (hidden): '; printf '\n'
export POKI_IPHONE_PASSCODE
npm start
```

Never put the passcode in chat, tool arguments, shell command arguments, source files, or logs. It remains in the host process environment; programs with access to the Mac may be able to read it. Unset it when stopping the daemon. The device binding prevents accidental use on another phone.

Workflow:

1. Wake using `press_button` with `button: "home"`, then take a screenshot. If still on the clock screen, press Home once more and inspect again. If Face ID already unlocked, continue without entering a passcode.
2. Observe the system six-digit numeric keypad with **all six dots empty**, in portrait orientation. If any digits are already entered, or there is a lockout/error, stop for manual handling. Do not guess or clear a partially entered code.
3. Call `unlock_device` with the screenshot's `observation_id`, `empty_keypad_confirmed: true`, and `digits`: ten `{x,y}` centers in logical screen points indexed **0,1,...,9**. Never include the passcode. The screenshot must be from the same session, under 30 seconds old, and not invalidated by intervening input. The server resolves the foreground process executable to SpringBoard, checks an English or Chinese Enter Passcode label, requires an explicitly empty six-digit accessibility value, and matches every supplied coordinate to the freshly observed numeric keys before sending anything. Unknown languages or inaccessible keypads fail closed.
4. Inspect the returned screenshot. `input_sent` alone does not prove unlock. After the keypad disappears, Poki opens Settings and confirms that its process actually becomes the readable foreground. Uncertain results block further attempts across sessions until a human checks the phone and restarts the daemon. No automatic retries.

The keypad uses observed coordinates instead of scaling a hard-coded phone layout. The first implementation intentionally accepts only six digits and standard portrait layout. On an iPhone 15 Pro Max running iOS 27.2 over RemotePairing, locking, waking and observing an empty six-digit keypad have been exercised. One user-local passcode attempt completed successfully, followed by Settings foreground PID verification and screenshot inspection. This is one successful run, not a long-term reliability measurement.
