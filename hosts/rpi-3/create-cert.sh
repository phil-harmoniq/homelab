#!/usr/bin/env bash

set -e
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
create_cert_script="$(realpath "$script_dir"/../../scripts/create-domain-cert-v2.sh)"

hostname="rpi-3"
output_dir="$script_dir/.certs/rpi-3.lan"
duration="1825"
tld="lan"
country="US"
state="GA"
city="Atlanta"
organization="FiveLabs.Tech"

while [[ $# -gt 0 ]]; do
  case $1 in
    -k|--root-key)
      root_key="$2"
      shift # past argument
      shift # past value
      ;;
    -c|--root-cert)
      root_cert="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--output-dir)
      output_dir="$2"
      shift # past argument
      shift # past value
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

if [[ -z $root_key || -z $root_cert ]]; then
  echo "Root key and certificate are required"
  exit 1
fi

mkdir -p "$output_dir"

# echo "$create_cert_script"
"$create_cert_script" \
    --root-key "$root_key" \
    --root-cert "$root_cert" \
    --output-dir "$output_dir" \
    --hostname "$hostname" \
    --tld "$tld" \
    --duration "$duration" \
    --country "$country" \
    --state "$state" \
    --city "$city" \
    --organization "$organization"
