#!/usr/bin/env bash

set -euo pipefail
# script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--name)
      secret_name="$2"
      shift # past argument
      shift # past value
      ;;
    *)
      positional_args+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

main()
{
    echo "Input the secret value for $secret_name"
    read -sr secret_value
    printf "%s\n" "$secret_value" | podman secret create "$secret_name" -
}

main