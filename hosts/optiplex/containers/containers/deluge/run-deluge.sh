#!/usr/bin/env bash

set -euo pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

podman run --replace \
    --name=deluge \
    --user 1000 \
    -e PUID=1000 \
    -e PGID=1000 \
    -e TZ=Etc/UTC \
    -p 8112:8112 \
    -p 6881:6881 \
    -p 6881:6881/udp \
    -p 58846:58846 \
    -v ./.config:/config:Z \
    -v ./.downloads:/downloads \
    -v ./.completed:/completed \
    --restart unless-stopped \
    ghcr.io/linuxserver/deluge:latest
