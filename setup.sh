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
    echo "# Settings -> Order Feed -> Bridge Token. pair-with-emr.sh sets both."
    echo "BRIDGE_TOKEN=$BRIDGE_TOKEN"
    echo "# EMR_FEED_URL=http://host.docker.internal:9080/api/pacs/worklist-feed"
  } > .env
  echo ".env created. Orthanc login: user 'admin', password is in .env (ORTHANC_PASSWORD)."
else
  echo ".env already exists — keeping current secrets."
fi

# The image store: ORTHANC_STORAGE_PATH in .env, or ./storage. The image server does not
# start on a folder that has neither the marker nor an image index (docker-compose.yml):
# a first installation makes the folder and the marker here; later, a missing store is said.
STORE="$(sed -n 's/^ORTHANC_STORAGE_PATH=//p' .env | tail -n 1)"
STORE="${STORE:-./storage}"
if [ -n "$BRIDGE_TOKEN" ]; then
  mkdir -p "$STORE"
  [ -f "$STORE/BETHESDA-PACS-STORAGE.id" ] || {
    echo "Bethesda PACS image store"
    echo "created=$(date '+%Y-%m-%d %H:%M')"
    echo "Do not delete this file or anything in this folder."
  } > "$STORE/BETHESDA-PACS-STORAGE.id"
elif [ ! -f "$STORE/BETHESDA-PACS-STORAGE.id" ] && [ ! -f "$STORE/index" ]; then
  echo "The image store is not where it should be: $STORE"
  echo "Is its disk mounted? The image server is NOT started on an empty folder."
  exit 1
fi

if [ -n "$OFFLINE" ]; then
  echo "Offline mode: starting from pre-loaded images (no build, no downloads)."
  docker compose up -d --no-build
else
  docker compose up -d
fi

# First run with the EMR on this machine: pair the two directly, so the token is
# never read off the screen and typed into the EMR (pair-with-emr.sh makes a new
# token, gives it to the EMR on stdin and to .env, and restarts the bridge).
PAIRED=""
if [ -n "$BRIDGE_TOKEN" ] && [ "$(docker inspect -f '{{.State.Running}}' bethesda-emr-db 2>/dev/null)" = "true" ]; then
  echo ""
  echo "The EMR is running on this machine - pairing the worklist bridge with it..."
  sh ./pair-with-emr.sh && PAIRED=1
fi

# The address the other PCs' browsers use for the viewer (not localhost).
LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

echo ""
echo "Bethesda PACS (Orthanc) is starting at http://localhost:9090"
echo "Login with user 'admin' and the ORTHANC_PASSWORD value in .env"
if [ -n "$LAN_IP" ]; then
  echo ""
  echo "Imaging devices send to this machine: $LAN_IP, DICOM port 4242 (give it a fixed IP)."
  echo "Staff see images inside the EMR - nothing to set for the viewer."
fi
if [ -n "$PAIRED" ]; then
  echo ""
  echo "Worklist bridge paired with the EMR on this machine - nothing to copy."
elif [ -n "$BRIDGE_TOKEN" ]; then
  echo ""
  echo "==================================================================="
  echo " IMPORTANT — pair the worklist bridge with the EMR:"
  echo " If the EMR runs on this machine: start it, then run ./pair-with-emr.sh"
  echo " Otherwise, in the EMR open Settings -> Order Feed -> Bridge Token"
  echo " and set it to:"
  echo "   $BRIDGE_TOKEN"
  echo "==================================================================="
fi
echo ""
echo "After restoring an EMR backup, run ./pair-with-emr.sh again - the backup"
echo "brings the old machine's bridge token with it."
