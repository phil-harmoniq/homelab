#!/usr/bin/env bash

podman run --rm \
    --name nebula-sync \
    --network host \
    -e PRIMARY='http://rpi-1.lan:10088|StinkyBeans2025!' \
    -e REPLICAS='http://rpi-2.lan:10088|StinkyBeans2025!' \
    -e FULL_SYNC=true \
    -e RUN_GRAVITY=true \
    -e CLIENT_SKIP_TLS_VERIFICATION=true \
    ghcr.io/lovelaze/nebula-sync:latest
