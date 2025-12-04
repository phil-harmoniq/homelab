#!/usr/bin/env bash

set -euo pipefail

podman run -d \
  --name pgedge-2 \
  --hostname pgedge-2 \
  --network host \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=your_password \
  -e PG_REPLICATION_MODE=master \
  -e PG_REPLICATION_USER=replica_user \
  -e PG_REPLICATION_PASSWORD=replica_password \
  -e PG_CLUSTERS=pgedge-1,pgedge-2 \
  ghcr.io/pgedge/pgedge-postgres:17-spock5-standard
