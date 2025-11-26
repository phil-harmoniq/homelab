#!/usr/bin/env bash
# https://dgu2000.medium.com/working-with-self-signed-certificates-in-chrome-walkthrough-edition-a238486e6858

set -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
DOMAIN="$HOSTNAME"
DAYS="365"
OUTPUT_DIR="$PWD"

while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--domain)
      DOMAIN="$2"
      shift # past argument
      shift # past value
      ;;
    --days)
      DAYS="$2"
      shift # past argument
      shift # past value
      ;;
    -t|--tld)
      TLD="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--output-dir)
      OUTPUT_DIR="$2"
      shift # past argument
      shift # past value
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

ROOT_KEY="$OUTPUT_DIR/$DOMAIN.key"
ROOT_CERT="$OUTPUT_DIR/$DOMAIN.cert"
ROOT_SUBJECT="/CN=$DOMAIN"
ROOT_EXT="subjectAltName=DNS:$DOMAIN,DNS:*.$DOMAIN"

if [[ -n $TLD ]]; then
  ROOT_EXT="$ROOT_EXT,DNS:$DOMAIN.$TLD,DNS:*.$DOMAIN.$TLD"
fi

mkdir -p "$OUTPUT_DIR"

echo "Create a root key"
openssl genrsa -out "$ROOT_KEY" 2048

echo "Create a root certificate"
openssl req -x509 -new -nodes -key "$ROOT_KEY" -sha256 -days "$DAYS" -out "$ROOT_CERT" -subj "$ROOT_SUBJECT" -addext "$ROOT_EXT"

echo "Validate root "
openssl x509 -in "$ROOT_CERT" -text -noout
