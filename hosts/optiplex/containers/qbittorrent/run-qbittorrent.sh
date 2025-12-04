#!/usr/bin/env bash

# set -euo pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

podman container rm qbittorrent

podman volume rm qbittorrent-config
podman volume rm qbittorrent-downloads

# podman volume create qbittorrent-config
# podman volume create qbittorrent-downloads

# podman run --replace \
#     --label "io.containers.autoupdate=registry" \
#     --name qbittorrent \
#     --hostname qbittorrent \
#     --publish 8080:8080/tcp \
#     --publish 8080:8080/udp \
#     --publish 6881:6881 \
#     --publish 6881:6881/udp \
#     -e PUID=1000 \
#     -e PGID=1000 \
#     -e TZ="America/New_York" \
#     --network devops \
#     -v qbittorrent-config:/qbittorrent/etc \
#     -v qbittorrent-downloads:/qbittorrent/var \
#     ghcr.io/11notes/qbittorrent:5
