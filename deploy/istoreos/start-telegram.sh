#!/bin/sh
# Start (or restart) the Poki Telegram channel worker on an iStoreOS router.
# Usage: sh start-telegram.sh [--check]
set -eu
umask 077

BASE_DIR=${BASE_DIR:-/mnt/data/poki}
TOKEN_FILE=${TOKEN_FILE:-$BASE_DIR/telegram-token}
CONF_DIR=${CONF_DIR:-$BASE_DIR/telegram}
ENV_FILE=${ENV_FILE:-$CONF_DIR/telegram.env}
# Model credentials, either an API key or a sign-in file. See the README section.
KEY_FILE=${KEY_FILE:-$BASE_DIR/openai-key}
AUTH_FILE=${AUTH_FILE:-$BASE_DIR/agent-auth.json}

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

# `docker run -e` puts these values on the command line, where shell history and `ps` keep
# them. The env file does not hide them from `docker inspect` (Config.Env still lists them),
# but anyone who can run docker here can read the files they came from anyway.
{
  echo "POKI_MCP_STATE_DIR=/state"
  echo "HOME=/root"
  echo "TELEGRAM_BOT_TOKEN=$(cat "$TOKEN_FILE")"
} > "$ENV_FILE"
# The container has no shell of yours, so the model credential has to be handed over here.
if [ -s "$KEY_FILE" ]; then
  echo "OPENAI_API_KEY=$(cat "$KEY_FILE")" >> "$ENV_FILE"
fi
AUTH_MOUNT=""
if [ -s "$AUTH_FILE" ]; then
  echo "POKI_AGENT_AUTH_FILE=/tg/auth.json" >> "$ENV_FILE"
  AUTH_MOUNT="-v $AUTH_FILE:/tg/auth.json:ro"
fi
chmod 600 "$ENV_FILE"

if [ ! -s "$KEY_FILE" ] && [ ! -s "$AUTH_FILE" ] && ! grep -q '"auth": *"chatgpt"' "$CONF_DIR/telegram.json" 2>/dev/null; then
  echo "No model credential: create $KEY_FILE (chmod 600) with an API key, or $AUTH_FILE for a chatgpt sign-in. --check passes without one; the first message fails." >&2
fi

docker rm -f poki-telegram >/dev/null 2>&1 || true
# Container PIDs are reused across restarts, so a stale lock looks "alive" to the
# worker's kill(pid, 0) probe. Removing it is safe: the only worker that could
# hold it was just stopped above.
rm -f "$CONF_DIR/state/messages.lock"

# shellcheck disable=SC2086
docker run -d --name poki-telegram \
  --network host \
  --restart unless-stopped \
  -v "$BASE_DIR/src":/app -w /app \
  -v "$BASE_DIR/state":/state \
  -v "$BASE_DIR/agent-config":/root/.config/poki-agent \
  -v "$CONF_DIR":/tg \
  $AUTH_MOUNT \
  --env-file "$ENV_FILE" \
  poki:linux node agent/telegram.mjs --config /tg/telegram.json --state /tg/state "$@" >/dev/null

sleep 6
docker ps --filter name=poki-telegram --format "{{.Names}} {{.Status}}"
echo "--- log ---"
docker logs poki-telegram 2>&1 | tail -20
