#!/usr/bin/env bash

set -euo pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

main()
{
    mkdir -p "$script_dir/.certs"

    "$script_dir/../../scripts/certs/create-domain-cert.sh" \
        --root-key "$script_dir/../.certs/optiplex.root.key" \
        --root-cert "$script_dir/../.certs/optiplex.root.cert" \
        --domain "lldap" \
        --output-dir "$script_dir/.certs" \
        --days "1825" \
        --tld "lab" \
        --country "US" \
        --state "GA" \
        --city "Atlanta" \
        --organization "PhilHawkins.Dev"
}

main
