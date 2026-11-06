#!/bin/sh
# Start (or restart) the Poki Telegram channel worker on an iStoreOS router.
# The bot token lives in its own file so it never shows up in the process list.
# Usage: sh start-telegram.sh [--check]
set -eu

BASE_DIR=${BASE_DIR:-/mnt/data/poki}
TOKEN_FILE=${TOKEN_FILE:-$BASE_DIR/telegram-token}
CONF_DIR=${CONF_DIR:-$BASE_DIR/telegram}

if [ ! -s "$TOKEN_FILE" ]; then
  echo "Missing $TOKEN_FILE (one bot token per file, chmod 600)." >&2
  exit 1
fi
if [ ! -s "$CONF_DIR/telegram.json" ]; then
  echo "Missing $CONF_DIR/telegram.json" >&2
  exit 1
fi

mkdir -p "$CONF_DIR/state"
chmod 700 "$CONF_DIR" "$CONF_DIR/state"

docker rm -f poki-telegram >/dev/null 2>&1 || true
# Container PIDs are reused across restarts, so a stale lock looks "alive" to the
# worker's kill(pid, 0) probe. Removing it is safe: the only worker that could
# hold it was just stopped above.
rm -f "$CONF_DIR/state/messages.lock"

docker run -d --name poki-telegram \
  --network host \
  --restart unless-stopped \
  -v "$BASE_DIR/src":/app -w /app \
  -v "$BASE_DIR/state":/state \
  -v "$BASE_DIR/agent-config":/root/.config/poki-agent \
  -v "$CONF_DIR":/tg \
  -e POKI_MCP_STATE_DIR=/state \
  -e HOME=/root \
  -e TELEGRAM_BOT_TOKEN="$(cat "$TOKEN_FILE")" \
  poki:linux node agent/telegram.mjs --config /tg/telegram.json --state /tg/state "$@" >/dev/null

sleep 6
docker ps --filter name=poki-telegram --format "{{.Names}} {{.Status}}"
echo "--- log ---"
docker logs poki-telegram 2>&1 | tail -20
