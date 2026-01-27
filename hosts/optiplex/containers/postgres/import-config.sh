#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

VOLUME_NAME="postgres-data-18"
DATA_FOLDER="/home/devops/.local/share/containers/storage/volumes/$VOLUME_NAME/_data"
OWNER_UID=$(stat -c '%u' "$DATA_FOLDER")
SOURCE_CONFIG="$SCRIPT_DIR/.config/postgresql.conf"
SOURCE_HBA="$SCRIPT_DIR/.config/pg_hba.conf"
DEST_CONFIG="$DATA_FOLDER/postgresql.conf"
DEST_HBA="$DATA_FOLDER/pg_hba.conf"

if podman volume exists "$VOLUME_NAME"; then
    echo "Podman volume $VOLUME_NAME exists. Continuing with import"
else
    echo "Podman volume $VOLUME_NAME does not exist. Please intialize the database first."
    exit 1
fi

sudo cp "$SOURCE_CONFIG" "$DEST_CONFIG"
sudo cp "$SOURCE_HBA" "$DEST_HBA"

sudo chown "$OWNER_UID:$OWNER_UID" "$DEST_CONFIG"
sudo chown "$OWNER_UID:$OWNER_UID" "$DEST_HBA"

sudo chmod 0600 "$DATA_FOLDER/optiplex.lan.key"
