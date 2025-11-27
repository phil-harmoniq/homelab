#!/usr/bin/env bash

set -e
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

domain="rpi-1"
output_dir="$script_dir/.certs"
duration="1825"
tld="lan"
country="US"
state="GA"
city="Atlanta"
organization="FiveLabs.Tech"

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
      domain="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--output-dir)
      output_dir="$2"
      shift # past argument
      shift # past value
      ;;
    --days)
      duration="$2"
      shift # past argument
      shift # past value
      ;;
    -t|--tld)
      tld="$2"
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

if [[ -z $ROOT_KEY || -z $ROOT_CERT ]]; then
  echo "Root key and certificate are required"
  exit 1
fi

mkdir -p "$output_dir"

client_subject="/CN=$domain"
client_key="$output_dir/$domain.key"
client_cert="$output_dir/$domain.cert"
client_csr="$output_dir/$domain.csr"
client_pem="$output_dir/$domain.pem"
ext_file="basicConstraints       = CA:FALSE
authorityKeyIdentifier = keyid:always, issuer:always
keyUsage               = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment
subjectAltName         = @alt_names
[ alt_names ]
DNS.1 = $domain
DNS.2 = *.$domain"

if [[ -n $tld ]]; then
  client_key="$output_dir/$domain.$tld.key"
  client_cert="$output_dir/$domain.$tld.cert"
  client_csr="$output_dir/$domain.$tld.csr"
  client_pem="$output_dir/$domain.$tld.pem"
  ext_file="$ext_file
DNS.3 = $domain.$tld
DNS.4 = *.$domain.$tld"
fi

[[ -n $country ]] && client_subject="$client_subject/C=$country"
[[ -n $state ]] && client_subject="$client_subject/ST=$state"
[[ -n $city ]] && client_subject="$client_subject/L=$city"
[[ -n $organization ]] && client_subject="$client_subject/O=$organization"

echo "Creating directory at $output_dir"
mkdir -p "$output_dir"

echo "Creating client key $client_key"
openssl genrsa -out "$client_key" 2048

echo "Creating client certificate signing request $client_csr"
openssl req -new -key "$client_key" -out "$client_csr" -subj "$client_subject"

echo "Generate client certificate and sign with root key $client_cert"
openssl x509 -req -in "$client_csr" -CA "$ROOT_CERT" -CAkey "$ROOT_KEY" -CAcreateserial -out "$client_cert" -days "$duration" -sha256 -extfile <(printf "%s" "$ext_file")

echo "Creating combined key and certificate for .pem"
cat "$client_key" "$client_cert" > "$client_pem"
