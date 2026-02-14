#!/usr/bin/env bash

set -e
# SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

while [[ $# -gt 0 ]]; do
  case $1 in
    -k|--in-key)
      in_key="$2"
      shift # past argument
      shift # past value
      ;;
    -c|--in-cert)
      in_cert="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--out-pfx)
      out_pfx="$2"
      shift # past argument
      shift # past value
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

openssl pkcs12 -export \
  -out "$out_pfx" \
  -inkey "$in_key" \
  -in "$in_cert" \
  -nodes
