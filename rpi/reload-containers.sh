#!/usr/bin/env bash

set -euo pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

main()
{
    link_containers
    # run_services
}

link_containers()
{
    quadlet_dir="$HOME/.config/containers/systemd"
    containers_dir="$(realpath "$script_dir"/containers)"
    # quadlet_dir="/tmp/containers"
    mkdir "$quadlet_dir"

    # https://unix.stackexchange.com/questions/314974/how-to-delete-broken-symlinks-in-one-go
    echo "Cleaning up broken symlinks at $quadlet_dir"
    find "$quadlet_dir" -xtype l -delete
    
    echo "Linking podman quadlet files from $containers_dir to $quadlet_dir."
    mkdir -p "$quadlet_dir"

    find "$containers_dir" -type f -name "*.network" -print0 | xargs -0 ln -s -f -t "$quadlet_dir" # Networks
    find "$containers_dir" -type f -name "*.volume" -print0 | xargs -0 ln -s -f -t "$quadlet_dir" # Volumes
    find "$containers_dir" -type f -name "*.container" -print0 | xargs -0 ln -s -f -t "$quadlet_dir" # Containers

    echo "Reloading systemctl to update quadlet files."
    systemctl --user daemon-reload
}

run_services()
{
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
