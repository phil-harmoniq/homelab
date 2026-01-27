#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

VOLUME_NAME="postgres-data-18"
SOURCE_CERT="$SCRIPT_DIR/../../.certs/optiplex.lan/optiplex.lan.cert"
SOURCE_KEY="$SCRIPT_DIR/../../.certs/optiplex.lan/optiplex.lan.key"
SOURCE_ROOT_CA="$SCRIPT_DIR/../../.certs/optiplex.root/optiplex.root.cert"

if podman volume exists "$VOLUME_NAME"; then
    echo "Podman volume $VOLUME_NAME exists. Continuing with import"
else
    echo "Podman volume $VOLUME_NAME does not exist. Please intialize the database first."
    exit 1
fi

DATA_FOLDER="/home/devops/.local/share/containers/storage/volumes/$VOLUME_NAME/_data"
OWNER_UID=$(stat -c '%u' "$DATA_FOLDER")

sudo cp "$SOURCE_CERT" "$DATA_FOLDER"
sudo cp "$SOURCE_KEY" "$DATA_FOLDER"
sudo cp "$SOURCE_ROOT_CA" "$DATA_FOLDER"

sudo chown "$OWNER_UID:$OWNER_UID" "$DATA_FOLDER/optiplex.lan.cert"
sudo chown "$OWNER_UID:$OWNER_UID" "$DATA_FOLDER/optiplex.lan.key"
sudo chown "$OWNER_UID:$OWNER_UID" "$DATA_FOLDER/optiplex.root.cert"

sudo chmod 0600 "$DATA_FOLDER/optiplex.lan.key"
