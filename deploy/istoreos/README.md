# Poki on iStoreOS (aarch64, Docker)

Runs the MCP daemon — and optionally the Telegram channel — on an iStoreOS router so the iPhone can be driven without a Mac staying awake. The phone is reached over Wi-Fi with RemotePairing; the USB path is optional.

Measured on an EasePi A2 (RK3568, 4 GB RAM, no swap), iStoreOS 25.12.6, Docker 29.6.1.

## Why a container

The host is **musl** (`/lib/ld-musl-aarch64.so.1`). Two consequences:

- Node 24 has no musl aarch64 build in the distribution feeds, and Poki requires Node 24+.
- The native bridge is compiled against glibc, because `aws-lc-sys` is painful to build for musl and the toolchain is not installable on the router.

So everything runs in a `node:24-bookworm-slim` based image (`poki:linux`). The router itself only needs Docker.

## Requirements

- iStoreOS with Docker and at least **8 GB free on the data disk**. The image plus build artifacts do not fit on the overlay.
- A phone already paired once with a Mac that has the full Xcode toolchain, or the willingness to build `idevice-tools` for the router (see below).
- `usbmuxd` present on the host if you want the USB path; it is optional.

## 1. Build the native bridge

`poki-native` and `idevice-tools` must be compiled **on the router**, inside a container, because the Mac cannot produce a glibc aarch64 binary without an extra toolchain.

```sh
docker run -d --name poki-build \
  -v /mnt/data/poki/src:/src \
  -v /mnt/data/poki/build:/out \
  -v /mnt/data/poki/cargo-home:/cargo \
  -e CARGO_HOME=/cargo \
  -e PATH=/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  -w /src rust:1-bookworm sh /src/build-poki.sh
```

`build-poki.sh` clones `jkcoxson/idevice` at the revision `bin/setup` pins, builds `idevice-tools`, then builds `poki-native` into `/out`. It overrides the workspace profile (`lto = false`, `codegen-units = 16`); the default `lto = true` makes this take far longer than the ~42 minutes measured with `-j 2`.

Run it with `-j 1` or `-j 2`. Four A55 cores and no swap will OOM at higher parallelism.

Do not mount a volume over `/usr/local/cargo` — it shadows the `cargo` binary that ships in the image. Mount a separate directory and set `CARGO_HOME` instead.

## 2. Install the runtime

```sh
docker build -t poki:linux .
```

The image only adds `python3`, which `native/devices.py` needs to talk to the usbmuxd socket, and which `bin/prepare-remote.mjs` needs at pairing time.

## 3. Start the daemon

```sh
BASE_DIR=/mnt/data/poki sh run-poki.sh
```

The script generates a bearer token into `$BASE_DIR/token` (0600), starts the container with `--network host`, and prints the endpoint plus the token. The token is fixed across restarts through `POKI_MCP_TOKEN`; otherwise the daemon generates a fresh one every launch and every client breaks.

Configuration goes through three environment variables that this branch adds to `src/daemon.mjs`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `POKI_BIND_HOST` | `127.0.0.1` | listen address; `0.0.0.0` exposes the daemon to the LAN |
| `POKI_HOST_ALLOW` | unset | comma-separated `Host` header allowlist; when set it replaces `localhostHostValidation()`, which otherwise rejects any non-loopback `Host` with `403` |
| `POKI_MCP_TOKEN` | random per start | fixed bearer token |

Clients must send `X-Poki-MCP-Session`; the daemon answers `400` without it.

```json
{
  "mcpServers": {
    "poki": {
      "type": "http",
      "url": "http://ROUTER-LAN-IP:47825/mcp",
      "headers": {
        "Authorization": "Bearer TOKEN",
        "X-Poki-MCP-Session": "client-1"
      }
    }
  }
}
```

## 4. Connect the iPhone

Prefer RemotePairing over Wi-Fi. Many RK3568 boards wire only the SuperSpeed pair on the blue USB 3.0 port, so a phone on it charges but never enumerates: `portsc` reports `Powered / Not-connected / Link:RxDetect / PortSpeed:0` while the device tree says `dr_mode = host`. Check `/sys/kernel/debug/usb/xhci/*/ports/port01` before blaming drivers.

On the Mac that has the phone attached over USB:

```sh
idevice-tools --udid UDID lockdown set EnableWifiConnections true
node bin/prepare-remote.mjs UDID PHONE-LAN-IP
```

`EnableWifiConnections` is what actually turns on the phone's Wi-Fi transport; you do not need to tick "Connect via network" in Xcode. After it succeeds, the device appears under `_apple-mobdev2._tcp` with a `supportsRP-26` tag, and its RemotePairing listener accepts connections on port `49152`.

Copy the result to the router and rewrite both paths to the **container's** view of the state directory:

```
state/remote/UDID/pairing.plist
state/remote/UDID/config.json      pairing_file -> /state/remote/UDID/pairing.plist
state/remote-devices.json          config_path  -> /state/remote/UDID/config.json
```

A host path such as `/mnt/data/poki/state/...` makes the helper exit immediately with `No such file or directory (os error 2)`, which the daemon reports as `Remote helper stopped before becoming ready`.

`pairing.plist` is portable between machines: it holds the host key, not the machine identity, so generating it on a Mac and running it on the router works.

### Enabling Wi-Fi automation on the phone

Settings → Privacy & Security → Developer Mode → **Enable UI Automation**. Without it the accessibility tree is empty: `take_screenshot` still works but returns `structure_source: null`, and `list_apps` fails with `service not found`. This is not a transport limit.

## 5. Optional: Telegram channel

```sh
printf '%s' 'BOT-TOKEN' > /mnt/data/poki/telegram-token && chmod 600 /mnt/data/poki/telegram-token
cp telegram.json.example /mnt/data/poki/telegram/telegram.json   # then edit
docker run --rm -v /mnt/data/poki/src:/app -w /app/agent poki:linux npm ci --no-audit --no-fund
sh start-telegram.sh --check
sh start-telegram.sh
```

The worker talks to the daemon through `src/stdio.mjs`, so `--network host` matters. Copy the model configuration from `~/.config/poki-agent` into `$BASE_DIR/agent-config` and mount it at `/root/.config/poki-agent`; set `HOME=/root` or the agent will not find it.

The bot must not have a webhook — the worker polls and refuses to start otherwise. `getUpdates` returns nothing until the owner sends the bot a message, so configure `allowedUsers` after that first message.

## What works over RemotePairing

Available: screenshots, accessibility tree, foreground app, taps and gestures, keyboard input, `launch_app`, `list_apps`, device info, tunnel reconnect.

Rejected by design: `install_app`, `uninstall_app`, `terminate_app`, clipboard tools, settings and appearance changes, location simulation, crash logs, container download, recording, and every simulator tool.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `deadline has elapsed` on every call | A stale `poki-native --remote-server` from an earlier run holds the phone. `pkill -f "poki-native --remote-server"` and remove `/tmp/poki-remote-*/​*.sock`. |
| `Pair verify failed` | The configured host is a different device. Find the right IP with `dns-sd -B _remotepairing._tcp`; do not trust ARP, iPhones rotate their Wi-Fi MAC. |
| `service not found` | UI Automation is off, or the phone is locked. |
| `A message worker already owns this state directory` | The lock records a PID that a new container reused. `start-telegram.sh` removes it before starting. |
| `spawn python3 ENOENT` | The image is missing `python3`; `native/devices.py` needs it. |
