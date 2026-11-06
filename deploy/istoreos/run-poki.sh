#!/bin/sh
# Start (or restart) the Poki MCP daemon in a container on an iStoreOS router.
set -eu

BASE_DIR=${BASE_DIR:-/mnt/data/poki}
STATE_DIR=${STATE_DIR:-$BASE_DIR/state}
SRC_DIR=${SRC_DIR:-$BASE_DIR/src}
TOKEN_FILE=${TOKEN_FILE:-$BASE_DIR/token}
BIND_HOST=${POKI_BIND_HOST:-0.0.0.0}

# Allow the router's own LAN address without hard-coding one.
LAN_IP=$(ip -4 -o addr show br-lan 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
HOST_ALLOW=${POKI_HOST_ALLOW:-localhost,127.0.0.1,[::1]${LAN_IP:+,$LAN_IP}}

mkdir -p "$STATE_DIR" "$SRC_DIR/build" "$BASE_DIR/lockdown"
chmod 700 "$STATE_DIR"

if [ ! -s "$TOKEN_FILE" ]; then
  docker run --rm poki:linux node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
fi
TOKEN=$(cat "$TOKEN_FILE")

docker rm -f poki >/dev/null 2>&1 || true

USB_ARGS=""
if [ -S /var/run/usbmuxd ]; then
  USB_ARGS="-v /var/run/usbmuxd:/var/run/usbmuxd"
fi

# shellcheck disable=SC2086
docker run -d --name poki \
  --network host \
  --restart unless-stopped \
  -v "$SRC_DIR":/app -w /app \
  -v "$STATE_DIR":/state \
  -v "$BASE_DIR/lockdown:/var/lib/lockdown" \
  $USB_ARGS \
  -e POKI_MCP_STATE_DIR=/state \
  -e POKI_MCP_TOKEN="$TOKEN" \
  -e POKI_BIND_HOST="$BIND_HOST" \
  -e POKI_HOST_ALLOW="$HOST_ALLOW" \
  poki:linux node src/daemon.mjs >/dev/null

sleep 4
docker logs poki 2>&1 | tail -20
echo "--- endpoint ---"
cat "$STATE_DIR/mcp.json"
echo
echo "--- token ---"
echo "Bearer $(cat "$TOKEN_FILE")"
