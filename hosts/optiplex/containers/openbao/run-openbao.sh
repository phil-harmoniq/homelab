#!/usr/bin/env bash

podman run \
    --name openbao \
    --hostname openbao \
    --detach \
    --network devops \
    --volume openbao-config:/openbao/config:z \
    --env BAO_DEV_ROOT_TOKEN_ID="foobar" \
    --publish 8200:8200 \
    ghcr.io/openbao/openbao
