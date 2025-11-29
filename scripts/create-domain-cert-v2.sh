#!/usr/bin/env bash

set -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

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
    -h|--hostname)
      hostname="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--output-dir)
      output_dir="$2"
      shift # past argument
      shift # past value
      ;;
    -a|--alt-names)
      alt_names="$2"
      shift # past argument
      shift # past value
      ;;
    --days)
      duration="$2"
      shift # past argument
      shift # past value
      ;;
    --country)
      country="$2"
      shift # past argument
      shift # past value
      ;;
    --state)
      state="$2"
      shift # past argument
      shift # past value
      ;;
    --city)
      city="$2"
      shift # past argument
      shift # past value
      ;;
    --org|--organization)
      organization="$2"
      shift # past argument
      shift # past value
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

if [[ -z $hostname ]]; then
  echo "Hostname required"
  exit 1
fi

if [[ -z $root_key || -z $root_cert ]]; then
  echo "Root key and certificate are required"
  exit 1
fi

mkdir -p "$output_dir"

CLIENT_SUBJECT="/CN=$hostname"
CLIENT_KEY="$output_dir/$hostname.key"
CLIENT_CERT="$output_dir/$hostname.cert"
CLIENT_CSR="$output_dir/$hostname.csr"
CLIENT_PEM="$output_dir/$hostname.pem"
EXT_FILE="basicConstraints       = CA:FALSE
authorityKeyIdentifier = keyid:always, issuer:always
keyUsage               = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment
subjectAltName         = @alt_names
[ alt_names ]
DNS.1 = $hostname
DNS.2 = *.$hostname"

if [[ -n $alt_names ]]; then
  CLIENT_KEY="$output_dir/$hostname.$tld.key"
  CLIENT_CERT="$output_dir/$hostname.$tld.cert"
  CLIENT_CSR="$output_dir/$hostname.$tld.csr"
  CLIENT_PEM="$output_dir/$hostname.$tld.pem"
  EXT_FILE="$EXT_FILE
DNS.3 = $hostname.$tld
DNS.4 = *.$hostname.$tld"
fi

EXT_FILE="DNS.5 = $hostname.woodsdr.fivelabs.tech"

[[ -n $country ]] && CLIENT_SUBJECT="$CLIENT_SUBJECT/C=$country"
[[ -n $state ]] && CLIENT_SUBJECT="$CLIENT_SUBJECT/ST=$state"
[[ -n $city ]] && CLIENT_SUBJECT="$CLIENT_SUBJECT/L=$city"
[[ -n $organization ]] && CLIENT_SUBJECT="$CLIENT_SUBJECT/O=$organization"

echo "Creating directory at $output_dir"
mkdir -p "$output_dir"

echo "Creating client key $CLIENT_KEY"
openssl genrsa -out "$CLIENT_KEY" 2048

echo "Creating client certificate signing request $CLIENT_CSR"
openssl req -new -key "$CLIENT_KEY" -out "$CLIENT_CSR" -subj "$CLIENT_SUBJECT"

echo "Generate client certificate and sign with root key $CLIENT_CERT"
openssl x509 -req -in "$CLIENT_CSR" -CA "$root_cert" -CAkey "$root_key" -CAcreateserial -out "$CLIENT_CERT" -days "$duration" -sha256 -extfile <(printf "%s" "$EXT_FILE")

echo "Creating combined key and certificate for .pem"
cat "$CLIENT_KEY" "$CLIENT_CERT" > "$CLIENT_PEM"
