#!/usr/bin/env bash

set -euo pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

main()
{
    if [[ $(/usr/bin/id -u) -ne 0 ]]; then
        echo "Not running as root"
        exit 1
    fi

    download_etcd
    setup_etcd_user
    configure_etcd
    start_etcd
}

download_etcd()
{
    cd /tmp
    ETCD_VER="v3.6.6"
    dir_name="etcd-${ETCD_VER}-linux-arm64"
    tar_name="$dir_name.tar.gz"
    url="https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/$tar_name"

    echo "Downloading etcd from $url"

    # curl -o "$tar_name" "$url"
    wget "$url"
    tar xzvf "$tar_name"
    cd "$dir_name"

    echo "Manually installing etcd to /usr/local/bin/"
    mv etcd etcdctl /usr/local/bin/

    echo "Fixing SELinux context for systemd"
    semanage fcontext -a -t bin_t "/usr/local/bin/etcd"
    semanage fcontext -a -t bin_t "/usr/local/bin/etcdctl"
    restorecon -v /usr/local/bin/etcd
    restorecon -v /usr/local/bin/etcdctl
}

setup_etcd_user()
{
    echo "Creating /var/lib/etcd"
    mkdir -p /var/lib/etcd

    echo "Creating /etc/etcd"
    mkdir -p /etc/etcd

    if [[ $(getent group etcd) ]]; then
        echo "Group etcd exists"
    else
        echo "Adding etcd groupgetent"
        groupadd --system etcd
    fi

    if id -u "etcd" >/dev/null 2>&1; then
        echo "User etcd exists"
    else
        useradd --system -s /sbin/nologin -g etcd etcd
    fi

    echo "Taking ownership of /var/lib/etcd"
    chown -R etcd:etcd /var/lib/etcd
}

configure_etcd()
{
    echo "Adding etcd configuration and systemd service"
    cp "$script_dir/services/etcd/etcd.conf" /etc/etcd
    cp "$script_dir/services/etcd/etcd.service" /etc/systemd/system
}

start_etcd()
{
    echo "Starting etcd"
    systemctl daemon-reload
    systemctl enable --now etcd
}

main
