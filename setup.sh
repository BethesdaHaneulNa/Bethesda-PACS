#!/bin/sh
# First-run setup for Bethesda PACS (Orthanc).
# Generates a .env with a random Orthanc admin password (only if missing), then starts.
# Safe to re-run: it never overwrites an existing .env.
#
#   ./setup.sh             normal install (pulls/builds; needs internet)
#   ./setup.sh --offline   use images already loaded from the offline kit; never builds
set -e
cd "$(dirname "$0")"

OFFLINE=""
[ "$1" = "--offline" ] && OFFLINE=1

gen() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$1"
  else
    LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c "$(( $1 * 2 ))"
  fi
}

BRIDGE_TOKEN=""
if [ ! -f .env ]; then
  echo "First run: generating .env with a random Orthanc password and bridge token..."
  BRIDGE_TOKEN="$(gen 24)"
  {
    echo "ORTHANC_PASSWORD=$(gen 16)"
    echo ""
    echo "# Worklist bridge -> EMR. BRIDGE_TOKEN must match the EMR's"
    echo "# Settings -> Order Feed -> Bridge Token (paste the value printed below)."
    echo "BRIDGE_TOKEN=$BRIDGE_TOKEN"
    echo "# EMR_FEED_URL=http://host.docker.internal:9080/api/pacs/worklist-feed"
  } > .env
  echo ".env created. Orthanc login: user 'admin', password is in .env (ORTHANC_PASSWORD)."
else
  echo ".env already exists — keeping current secrets."
fi

if [ -n "$OFFLINE" ]; then
  echo "Offline mode: starting from pre-loaded images (no build, no downloads)."
  docker compose up -d --no-build
else
  docker compose up -d
fi

echo ""
echo "Bethesda PACS (Orthanc) is starting at http://localhost:9090"
echo "Login with user 'admin' and the ORTHANC_PASSWORD value in .env"
if [ -n "$BRIDGE_TOKEN" ]; then
  echo ""
  echo "==================================================================="
  echo " IMPORTANT — pair the worklist bridge with the EMR:"
  echo " In the EMR, open Settings -> Order Feed -> Bridge Token and set it to:"
  echo "   $BRIDGE_TOKEN"
  echo "==================================================================="
fi
