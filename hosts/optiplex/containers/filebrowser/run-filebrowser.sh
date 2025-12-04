#!/usr/bin/env bash

podman run --rm \
    --name filebrowser \
    -v qbittorrent-downloads:/srv:Z \
    -v filebrowser_database:/database:z \
    -v filebrowser_config:/config:z \
    -e PUID=$(id -u) \
    -e PGID=$(id -g) \
    -p 8088:80 \
    docker.io/filebrowser/filebrowser:s6
