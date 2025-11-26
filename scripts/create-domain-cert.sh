#!/usr/bin/env bash

set -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

DOMAIN="$HOSTNAME"
DURATION="1825"
OUTPUT_DIR="$SCRIPT_DIR/.certs"

while [[ $# -gt 0 ]]; do
  case $1 in
    -k|--root-key)
      ROOT_KEY="$2"
      shift # past argument
      shift # past value
      ;;
    -c|--root-cert)
      ROOT_CERT="$2"
      shift # past argument
      shift # past value
      ;;
    -d|--domain)
      DOMAIN="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--output-dir)
      OUTPUT_DIR="$2"
      shift # past argument
      shift # past value
      ;;
    --days)
      DURATION="$2"
      shift # past argument
      shift # past value
      ;;
    -t|--tld)
      TLD="$2"
      shift # past argument
      shift # past value
      ;;
    --country)
      COUNTRY="$2"
      shift # past argument
      shift # past value
      ;;
    --state)
      STATE="$2"
      shift # past argument
      shift # past value
      ;;
    --city)
      CITY="$2"
      shift # past argument
      shift # past value
      ;;
    --org|--organization)
      ORGANIZATION="$2"
      shift # past argument
      shift # past value
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

if [[ -z $ROOT_KEY || -z $ROOT_CERT ]]; then
  echo "Root key and certificate are required"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

CLIENT_SUBJECT="/CN=$DOMAIN"
CLIENT_KEY="$OUTPUT_DIR/$DOMAIN.key"
CLIENT_CERT="$OUTPUT_DIR/$DOMAIN.cert"
CLIENT_CSR="$OUTPUT_DIR/$DOMAIN.csr"
CLIENT_PEM="$OUTPUT_DIR/$DOMAIN.pem"
EXT_FILE="basicConstraints       = CA:FALSE
authorityKeyIdentifier = keyid:always, issuer:always
keyUsage               = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment
subjectAltName         = @alt_names
[ alt_names ]
DNS.1 = $DOMAIN
DNS.2 = *.$DOMAIN"

if [[ -n $TLD ]]; then
  CLIENT_KEY="$OUTPUT_DIR/$DOMAIN.$TLD.key"
  CLIENT_CERT="$OUTPUT_DIR/$DOMAIN.$TLD.cert"
  CLIENT_CSR="$OUTPUT_DIR/$DOMAIN.$TLD.csr"
  CLIENT_PEM="$OUTPUT_DIR/$DOMAIN.$TLD.pem"
  EXT_FILE="$EXT_FILE
DNS.3 = $DOMAIN.$TLD
DNS.4 = *.$DOMAIN.$TLD"
fi

[[ -n $COUNTRY ]] && CLIENT_SUBJECT="$CLIENT_SUBJECT/C=$COUNTRY"
[[ -n $STATE ]] && CLIENT_SUBJECT="$CLIENT_SUBJECT/ST=$STATE"
[[ -n $CITY ]] && CLIENT_SUBJECT="$CLIENT_SUBJECT/L=$CITY"
[[ -n $ORGANIZATION ]] && CLIENT_SUBJECT="$CLIENT_SUBJECT/O=$ORGANIZATION"

echo "Creating directory at $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "Creating client key $CLIENT_KEY"
openssl genrsa -out "$CLIENT_KEY" 2048

echo "Creating client certificate signing request $CLIENT_CSR"
openssl req -new -key "$CLIENT_KEY" -out "$CLIENT_CSR" -subj "$CLIENT_SUBJECT"

echo "Generate client certificate and sign with root key $CLIENT_CERT"
openssl x509 -req -in "$CLIENT_CSR" -CA "$ROOT_CERT" -CAkey "$ROOT_KEY" -CAcreateserial -out "$CLIENT_CERT" -days "$DURATION" -sha256 -extfile <(printf "%s" "$EXT_FILE")

echo "Creating combined key and certificate for .pem"
cat "$CLIENT_KEY" "$CLIENT_CERT" > "$CLIENT_PEM"
