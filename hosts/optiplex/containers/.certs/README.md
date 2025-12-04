# Permissions needed for certificates

Place certificates in this folder and reference them in podman volumes

## Requirements

Four files are to support all containers running on this system. The optiplex public cert, the optiplex private key, the optiplex private/public chain, and the root CA cert with the following filenames:
- Public cert: `optiplex.lan.cert`
- Private key: `optiplex.lan.key`
- Private/public key chain: `optiplex.lan.pem`
- Root CA public cert: `optiplex.root.cert`

### Postgres
- `chown 100069:100069` on public and private key files
- `chmod 0600` on private key
