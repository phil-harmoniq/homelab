#!/usr/bin/env bash

set -euo pipefail

# For Linux and without a web server or reverse proxy (like Apache, Nginx and else) already in place:
# podman run \
#     --sig-proxy=false \
#     --name nextcloud-aio-mastercontainer \
#     --restart always \
#     --publish 18080:8080 \
#     --publish 18443:8443 \
#     --volume nextcloud_aio_mastercontainer:/mnt/docker-aio-config \
#     --volume /var/run/docker.sock:/var/run/docker.sock:ro \
#     ghcr.io/nextcloud-releases/all-in-one:latest

# podman run -d --name nextcloud-db --pod nextcloud-pod -e MYSQL_ROOT_PASSWORD=your_root_password -e MYSQL_PASSWORD=nextcloud_password -e MYSQL_DATABASE=nextcloud -e MYSQL_USER=nextcloud -v $HOME/homelab/hosts/optiplex/containers/nextcloud/volumes/db:/var/lib/mysql:Z docker.io/mariadb:latest

podman run -d --rm --name nextcloud --network devops -p 18080:80 -p 18443:443 -v nextcloud:/var/www/html:Z docker.io/nextcloud:latest