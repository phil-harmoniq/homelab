#!/usr/bin/env bash

set -euo pipefail
# script_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
base_url="https://raw.githubusercontent.com/phil-harmoniq/hosts/refs/heads/main/rpi"

main()
{
    add_shell_config
    install_packages
    enable_services
    configure_podman
    configure_git
}

add_shell_config()
{
    tmp_dir="/tmp/hosts/rpi"

    echo "Downloading shell config to $tmp_dir"
    mkdir -p "$tmp_dir/shell/.bashrc.d"

    curl "$base_url/shell/.bashrc.d/aliases" > "$tmp_dir/shell/.bashrc.d/aliases"
    curl "$base_url/shell/.bashrc.d/prompt" > "$tmp_dir/shell/.bashrc.d/prompt"
    curl "$base_url/shell/.inputrc" > "$tmp_dir/shell/.inputrc"

    echo "Adding shell config to current user"
    mkdir -p "$HOME/.bashrc.d/"
    cp "$tmp_dir/shell/.bashrc.d/aliases" "$HOME/.bashrc.d"
    cp "$tmp_dir/shell/.bashrc.d/prompt" "$HOME/.bashrc.d"
    cp "$tmp_dir/shell/.inputrc" "$HOME"
}

install_packages()
{
    echo "Installing default environment packages"

    sudo dnf install epel-release -y
    sudo dnf install \
        podman \
        git \
        btop \
        tldr \
        shellcheck \
        fastfetch \
        cockpit \
        cockpit-files \
        cockpit-podman \
        cockpit-storaged \
        samba \
        samba-client \
        cifs-utils \
        nfs-utils \
        pcp \
        python3-pcp \
        wget \
        file \
        -y
}

enable_services()
{
    sudo systemctl enable --now cockpit
    sudo systemctl enable --now pmlogger
}

configure_podman()
{
    sudo loginctl enable-linger devops
}

configure_git()
{
    git config --global user.email "philhawkins.dev@gmail.com"
    git config --global user.name "Phil Hawkins"
}

main
