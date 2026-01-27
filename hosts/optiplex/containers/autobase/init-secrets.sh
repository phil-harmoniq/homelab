#!/usr/bin/env bash

set -euo pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

main()
{
    secret_name="autobase-token"

    if podman secret exists "$secret_name" >/dev/null 2>&1; then
        echo "Removing existing secret $secret_name"
        podman secret rm "$secret_name"
    fi

    echo -n "Enter secret value for '$secret_name': "
    read -rs secret_value
    echo

    # Create the podman secret from the provided input
    echo "$secret_value" > "$script_dir/$secret_name.secret"
    printf "%s" "$secret_value" | podman secret create $secret_name -
    echo "Secret '$secret_name' created."
}

main
