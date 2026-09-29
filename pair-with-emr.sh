#!/bin/sh
# Pair this PACS with the EMR running on the same machine (Linux / NAS).
#
# Makes a new bridge token and puts the same value in this folder's .env and in
# the EMR's settings (pacs_config.bridge_token), then restarts the bridge. The
# value never appears on screen, on a command line or in a log: the EMR gets it
# on stdin, and the two copies are compared by hash.
#
# Run it after installing (setup.sh does this when the EMR is already up), and
# again AFTER RESTORING AN EMR BACKUP - the backup brings the old token with it.
#
#   ./pair-with-emr.sh
#   NO_RESTART=1 ./pair-with-emr.sh      # leave the bridge alone (tests)
set -e
cd "$(dirname "$0")"
ENV_FILE="${ENV_FILE:-.env}"
DB="${EMR_DB_CONTAINER:-bethesda-emr-db}"

[ -f "$ENV_FILE" ] || { echo "No $ENV_FILE - run setup first."; exit 1; }
[ "$(docker inspect -f '{{.State.Running}}' "$DB" 2>/dev/null)" = "true" ] || {
  echo "The EMR database ($DB) is not running on this machine - start the EMR first."; exit 1; }
[ "$(grep -c '^BRIDGE_TOKEN=' "$ENV_FILE")" = "1" ] || {
  echo "BRIDGE_TOKEN= must appear exactly once in $ENV_FILE - stopped, nothing changed."; exit 1; }

if command -v openssl >/dev/null 2>&1; then TOK="$(openssl rand -hex 24)"
else TOK="$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 48)"; fi

# The EMR first (its tables may still be being created right after install).
ok=""; i=0
while [ $i -lt 20 ]; do
  if printf "UPDATE pacs_config SET bridge_token = '%s', updated_at = NOW() WHERE id = 1;" "$TOK" |
       docker exec -i "$DB" psql -U medconnect -d medconnect -q -v ON_ERROR_STOP=1 >/dev/null 2>&1; then ok=1; break; fi
  i=$((i+1)); sleep 3
done
[ -n "$ok" ] || { echo "Could not write to the EMR settings (is the EMR finished starting?) - $ENV_FILE not changed."; exit 1; }

BACKUP="$(mktemp "${TMPDIR:-/tmp}/pacs-env-before-pair.XXXXXX")"
cp "$ENV_FILE" "$BACKUP"
tmp="$ENV_FILE.new.$$"
awk -v t="$TOK" '/^BRIDGE_TOKEN=/{print "BRIDGE_TOKEN=" t; next} {print}' "$ENV_FILE" > "$tmp" && mv "$tmp" "$ENV_FILE"

want="$(printf '%s' "$TOK" | md5sum | cut -d' ' -f1)"
TOK=""
db="$(docker exec "$DB" psql -U medconnect -d medconnect -tAc "SELECT md5(bridge_token) FROM pacs_config WHERE id = 1" | tr -d '[:space:]')"
file="$(sed -n 's/^BRIDGE_TOKEN=//p' "$ENV_FILE" | tr -d '\r\n' | md5sum | cut -d' ' -f1)"
if [ "$db" != "$want" ] || [ "$file" != "$want" ]; then
  echo "FAILED - the EMR and $ENV_FILE do not hold the same token. The previous file is at $BACKUP"; exit 1
fi
rm -f "$BACKUP"

if [ -z "$NO_RESTART" ]; then
  docker compose up -d --force-recreate worklist-bridge ||
    { echo "Paired, but the bridge did not restart - run: docker compose up -d --force-recreate worklist-bridge"; exit 1; }
fi
echo "Paired with the EMR: both hold the same new bridge token (not shown)."
