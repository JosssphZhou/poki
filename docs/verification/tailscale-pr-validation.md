# Tailscale transport validation

The implementation was built and exercised on 2026-11-06. The initial checks below predate the observation-cancellation fix. Device screenshots are not stored in this repository.

## Automated checks

Seventeen relevant checks passed: the remote-session case and two batch-input cases (6.9 seconds together), three tool-discovery cases (5.2 seconds together), nine native pasteboard cases, and two native app-directory cases. The native release build also passed. This was targeted validation, not a full-suite run.

The added or modified tests in this PR are:

| Test and location | Protected behavior | Regression that fails it | Failed on the pre-change base? |
| --- | --- | --- | --- |
| `Remote screen capture survives client and daemon restarts after the phone stops accepting new connections` in `test/remote.test.mjs` | A later MCP client can still capture the remote phone after the Poki daemon restarts | Dropping the persistent native helper or failing to route registered remote devices | Yes: the base cannot select the configured remote device |
| `stdio reaches the authenticated local MCP service and rejects an absent device` in `test/protocol.test.mjs` | Default discovery stays limited while full HTTP discovery exposes the maintenance tools | Keeping the old full-catalog size after adding the two tools | Yes: full discovery returns 56 instead of 58 |
| `an all-profile HTTP service still lets each stdio client choose its own list` in `test/protocol.test.mjs` | Per-client default/full catalog selection survives the HTTP bridge | Applying the default filter to the full client | Yes: the full catalog lacks the two added tools |
| `Poki Agent opens its own MCP with the complete catalog even when the parent uses the default profile` in `test/protocol.test.mjs` | The independent Agent receives the full catalog | Losing the full profile when launching its own MCP client | Yes: the full catalog lacks the two added tools |

The protocol cases already existed; this PR updates their expected full-catalog size. The pasteboard, app-directory, and batch-input cases were reused without modification.

## Real-device evidence

Tested on iPhone17,1 with iOS 27.3. The operator confirmed USB disconnection and cellular use.

- After initialization over Wi-Fi, the same native session continued on 5G.
- Restarting the Poki daemon preserved the helper. Settings launched, and `poki123 AbC 中文24680` was entered with exact accessibility readback and a matching screen capture inspected during the check. The field was subsequently cleared.
- A failed explicit reconnect preserved the old usable session.
- Disconnecting Tailscale caused capture to fail explicitly rather than return a cached frame.
- Restoring Tailscale on cellular did not restore a lost native tunnel; Wi-Fi was required. Further [native-listener diagnostics](cellular-native-listener.md) record the evidence and its limits.

## Unresolved behavior

An additional, uncommitted diagnostic test reproduced the existing behavior where cancelling a foreground observation terminates the native helper, preventing the next capture when new phone connections are refused. That pending test and its unfinished fix are not included in this PR. The limitation is disclosed in the user documentation; excluding the pending test does not mean the defect is fixed.

Full cellular cold start/reconnection, observation-timeout resilience, simultaneous use with another iOS VPN, and continuous video have not passed acceptance. A clipboard snapshot was unavailable in the final mixed-text run, so restoration was not claimed. One accessibility read took 46.8 seconds; this evidence does not establish latency or long-duration stability targets.
