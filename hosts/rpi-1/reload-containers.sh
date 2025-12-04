#!/usr/bin/env bash

set -euo pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

main() {
    copy_containers
    # run_services
}

copy_containers() {
    quadlet_dir="/etc/containers/systemd/"
    containers_dir="$(realpath "$script_dir"/containers)"
    mkdir -p "$quadlet_dir"

    # Clean up broken symlinks at the destination
    echo "Cleaning up broken symlinks at $quadlet_dir"
    find "$quadlet_dir" -xtype l -delete

    echo "Copying podman quadlet files from $containers_dir to $quadlet_dir."
    mkdir -p "$quadlet_dir"

    # Copy files instead of linking
    find "$containers_dir" -type f -name "*.network" -exec cp -f {} "$quadlet_dir" \;   # Networks
    find "$containers_dir" -type f -name "*.volume" -exec cp -f {} "$quadlet_dir" \;    # Volumes
    find "$containers_dir" -type f -name "*.container" -exec cp -f {} "$quadlet_dir" \; # Containers

    echo "Reloading systemctl to update quadlet files."
    systemctl daemon-reload
}

run_services() {
    echo "Starting services."

    systemctl --user start postgres
    systemctl --user start pgadmin
    systemctl --user start gitea
    systemctl --user start gitea-runner-01
    systemctl --user start gitea-runner-02
    systemctl --user start gitea-runner-03
    systemctl --user start pihole
    systemctl --user start nginx
    systemctl --user start valkey
}

main
