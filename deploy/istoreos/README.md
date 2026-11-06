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

## 0. Put the repository on the router

Every command below runs **on the router**, over SSH, from the checkout directory unless stated otherwise. Clone into the data disk, not the overlay:

```sh
mkdir -p /mnt/data/poki
git clone https://github.com/REPO/OWNER/poki.git /mnt/data/poki/src
cd /mnt/data/poki/src
```

`/mnt/data/poki/src` is then mounted at `/app` in the runtime container, so the daemon runs the source you cloned rather than a copy baked into the image.

## 1. Build the native bridge

`poki-native` and `idevice-tools` must be compiled **on the router**, inside a container, because the Mac cannot produce a glibc aarch64 binary without an extra toolchain.

Run this from the checkout root (`/mnt/data/poki/src`):

```sh
docker run -d --name poki-build \
  -v /mnt/data/poki/src:/src \
  -v /mnt/data/poki/build:/out \
  -v /mnt/data/poki/cargo-home:/cargo \
  -e CARGO_HOME=/cargo \
  -e PATH=/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  -w /src rust:1-bookworm sh /src/deploy/istoreos/build-poki.sh
```

`deploy/istoreos/build-poki.sh` clones `jkcoxson/idevice` at the revision `bin/setup` pins, builds `idevice-tools`, then builds `poki-native` into `/out`. It overrides the workspace profile (`lto = false`, `codegen-units = 16`); the default `lto = true` makes this take far longer than the ~42 minutes measured with `-j 2`.

Run it with `-j 1` or `-j 2`. Four A55 cores and no swap will OOM at higher parallelism.

Do not mount a volume over `/usr/local/cargo` — it shadows the `cargo` binary that ships in the image. Mount a separate directory and set `CARGO_HOME` instead.

## 2. Install the runtime

From `deploy/istoreos`:

```sh
cd deploy/istoreos
docker build -t poki:linux .
```

The image adds `python3` (which `native/devices.py` needs for the usbmuxd socket and `bin/prepare-remote.mjs` needs at pairing time) and tesseract with the `chi_sim` and `eng` packs, which replaces the macOS-only recognizer — see [screen text recognition](#screen-text-recognition).

The MCP server dependencies are not part of the image, so install them into the checkout itself. From the checkout root:

```sh
docker run --rm -v /mnt/data/poki/src:/app -w /app poki:linux npm ci --no-audit --no-fund
```

Do not copy `node_modules` from a Mac: `sharp` ships per-platform binaries and the arm64 macOS build will not load on Linux.

## 3. Start the daemon

From `deploy/istoreos`:

```sh
BASE_DIR=/mnt/data/poki sh run-poki.sh
```

The script generates a bearer token into `$BASE_DIR/token` (0600), writes the container's environment to `$BASE_DIR/poki.env` (0600, so the token never appears in `docker inspect`), starts the container with `--network host`, and prints the endpoint path, the token path, the bind address and the Host allowlist. It does not print the token itself. The token is fixed across restarts through `POKI_MCP_TOKEN`; otherwise the daemon generates a fresh one every launch and every client breaks.

The daemon is bound to the router's `br-lan` address, so it is reachable from the LAN and not from the WAN.

Configuration goes through three environment variables that this branch adds to `src/daemon.mjs`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `POKI_BIND_HOST` | `br-lan` address, else `127.0.0.1` | listen address; the script refuses to start if it is not covered by the allowlist |
| `POKI_HOST_ALLOW` | `localhost,127.0.0.1,[::1]` plus the `br-lan` address | comma-separated `Host` header allowlist; when set it replaces `localhostHostValidation()`, which otherwise rejects any non-loopback `Host` with `403` |
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

From `deploy/istoreos`:

```sh
printf '%s' 'BOT-TOKEN' > /mnt/data/poki/telegram-token && chmod 600 /mnt/data/poki/telegram-token
mkdir -p /mnt/data/poki/telegram
cp telegram.json.example /mnt/data/poki/telegram/telegram.json   # then edit device and model
docker run --rm -v /mnt/data/poki/src:/app -w /app/agent poki:linux npm ci --no-audit --no-fund
sh start-telegram.sh --check
sh start-telegram.sh
```

`telegram.json.example` contains only the keys the worker accepts. This branch does not add model providers: the worker and `agent/model-config.mjs` support the OpenAI configurations that ship with the agent today. Running something else on the router takes a separate patch, which belongs in its own change rather than here.

`start-telegram.sh` writes the bot token into `$BASE_DIR/telegram/telegram.env` (0600) and passes it with `--env-file`, so it is not visible in `docker inspect`.

The worker talks to the daemon through `src/stdio.mjs`, so `--network host` matters. Copy the model configuration from `~/.config/poki-agent` into `$BASE_DIR/agent-config` and mount it at `/root/.config/poki-agent`; set `HOME=/root` or the agent will not find it.

The bot must not have a webhook — the worker polls and refuses to start otherwise. `getUpdates` returns nothing until the owner sends the bot a message, so configure `allowedUsers` after that first message.

## Screen text recognition

`src/device.mjs` runs `build/ocr` when the accessibility tree cannot describe a screen, which is how system dialogs — the paste permission prompt, for one — are found. On macOS that binary is `native/ocr.swift`, built by `bin/setup`, and it links Vision. There is no Vision here.

Install the tesseract equivalent once, from the checkout root:

```sh
install -m 755 native/ocr-linux.py /mnt/data/poki/src/build/ocr
```

It prints the same JSON as the Swift helper (`text`, `confidence`, `x`, `y`, `width`, `height`, in pixels of the image it is handed), so nothing above it changes. Recognition takes about 8 seconds on a 390×844 capture on this SoC, against roughly 2 seconds for one accessibility read, so it stays a fallback: `src/interaction.mjs` only waits for it when accessibility returned nothing at all.

The language packs are `chi_sim` and `eng`; set `POKI_OCR_LANGS` to change them, `POKI_OCR_PSM` for the tesseract page mode (default `11`, sparse text), and `POKI_OCR_UPSCALE=1` to recognize the frame at native size when speed matters more than small labels.

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
