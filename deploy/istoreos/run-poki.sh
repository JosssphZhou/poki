#!/bin/sh
# Start (or restart) the Poki MCP daemon in a container on an iStoreOS router.
set -eu

BASE_DIR=${BASE_DIR:-/mnt/data/poki}
STATE_DIR=${STATE_DIR:-$BASE_DIR/state}
SRC_DIR=${SRC_DIR:-$BASE_DIR/src}
TOKEN_FILE=${TOKEN_FILE:-$BASE_DIR/token}
ENV_FILE=${ENV_FILE:-$BASE_DIR/poki.env}

# Bind to the router's own LAN address without hard-coding one. With --network host,
# 0.0.0.0 would answer on the WAN side too, so loopback is the fallback instead.
LAN_IP=$(ip -4 -o addr show br-lan 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
BIND_HOST=${POKI_BIND_HOST:-${LAN_IP:-127.0.0.1}}
HOST_ALLOW=${POKI_HOST_ALLOW:-localhost,127.0.0.1,[::1]${LAN_IP:+,$LAN_IP}}

# A bind address outside the allowlist answers 403 to everything: fail here instead.
case ",$HOST_ALLOW," in
  *",$BIND_HOST,"*) ;;
  *) echo "POKI_BIND_HOST=$BIND_HOST is not covered by POKI_HOST_ALLOW=$HOST_ALLOW." >&2; exit 1 ;;
esac

mkdir -p "$STATE_DIR" "$SRC_DIR/build" "$BASE_DIR/lockdown"
chmod 700 "$STATE_DIR"

if [ ! -s "$TOKEN_FILE" ]; then
  docker run --rm poki:linux node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
fi

# Values passed with `docker run -e` are readable in `docker inspect`, and this token now
# gives anyone on the LAN control of the phone. A 0600 env file keeps it off the process
# table and out of shell history.
umask 077
{
  echo "POKI_MCP_STATE_DIR=/state"
  echo "POKI_MCP_TOKEN=$(cat "$TOKEN_FILE")"
  echo "POKI_BIND_HOST=$BIND_HOST"
  echo "POKI_HOST_ALLOW=$HOST_ALLOW"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

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
  --env-file "$ENV_FILE" \
  poki:linux node src/daemon.mjs >/dev/null

sleep 4
docker logs poki 2>&1 | tail -20
echo "--- endpoint ---"
# The endpoint file repeats the bearer token, so only its path is printed here.
echo "$STATE_DIR/mcp.json (bearer token: $TOKEN_FILE, mode 0600)"
echo "Listening on $BIND_HOST:47825; Host allowlist: $HOST_ALLOW"
