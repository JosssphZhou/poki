# iPhone over Tailscale

RemotePairing lets Poki use an already paired iPhone through its Tailscale address. It uses an encrypted userspace tunnel and does not change the Mac's default route, DNS, proxy, or other VPN settings. This is an opt-in transport; the existing USB path remains available for devices without a remote configuration.

## Prepare

1. Run `./bin/setup` in this checkout. Both devices must already be connected to the same tailnet.
2. Connect the trusted, unlocked iPhone over USB and Wi-Fi. Developer Mode and UI Automation must already be enabled.
3. Set `POKI_MCP_STATE_DIR` to this installation's private state directory, then run:

   ```sh
   node bin/prepare-remote.mjs DEVICE_ID TAILSCALE_IP
   ```

   This verifies a RemotePairing record over the existing trusted USB connection. The pairing key remains in the private state directory. Ordinary operations never trigger a new pairing flow.
4. Start Poki with the same state directory. Call `take_screenshot` with the selected device ID while Wi-Fi is connected. Confirm the actual screen before disconnecting USB.
5. Disconnect Wi-Fi from Control Center, leaving the Wi-Fi setting enabled, Tailscale connected, and the phone unlocked. Verify the phone is using cellular data.

The configured device uses RemotePairing even when a USB connection is present, so testing does not silently fall back to USB.

## Operations and recovery

Supported paths are screenshots, accessibility observations, app listing and launch, touches and gestures, keyboard events, and verified text input through Poki's existing clipboard/field verification flow. Clipboard restoration is reported separately; an unavailable snapshot means the prior clipboard cannot be restored.

The native connection helper is independent of MCP clients and the Poki daemon. Closing a client or restarting the daemon preserves an idle phone connection. The private local socket is under `/tmp/poki-remote-<uid>`; it exposes no network listener. Pairing keys remain in the state directory; ephemeral tunnel keys are not saved.

`reconnect_device` attempts a replacement tunnel before dropping a working one. It never repeats a previous input. If an operation loses its response, inspect the screen before retrying. `disconnect_device` explicitly closes the helper and phone connection. Cancellation of an active operation also terminates its helper before releasing ownership, because delivery may be ambiguous.

**A complete loss of the phone tunnel is not recoverable on every cellular configuration.** On the tested iOS 27.3 phone, new RemotePairing connections are refused on cellular even though an established connection continues working. Returning the phone to Wi-Fi is required after the helper exits, the Mac restarts, or the underlying tunnel is lost. Keeping the helper alive handles client/daemon restarts; it does not prove recovery from those other failures.

Device-management paths such as app installation, process termination, Settings deep links, recording, location simulation, and standalone clipboard access are not supported by this transport. They report a transport limitation instead of silently using a local connection.

## Verification status

The experimental branch has demonstrated real 5G screenshots, launching Settings, and exact readback of `poki123 AbC 中文24680`, followed by a verified clear without submitting. Complete cellular reconnection remains an acceptance blocker. Do not describe this transport as fully accepted until that requirement is resolved.
