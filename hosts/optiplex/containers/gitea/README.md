### Configuration

- Gitea is configured entirely through `GITEA__<section>__<KEY>` environment variables in `gitea.container`.
- `/etc/gitea` is not mounted, so `app.ini` is regenerated from the image template plus these variables on every container start. Removing a variable removes the setting, and edits made inside the container are lost on restart.
- In section names, '.' is encoded as `_0X2E_` and '-' as `_0X2D_`.
- Only non-default values are listed; paths and ports come from the rootless image's app.ini template.

### Secrets

- Secrets are passed as Podman secrets and never stored in the repo or a persistent volume. Use `*_URI = file:/run/secrets/<name>` where Gitea supports it. The DB password has no `_URI` option, so it is passed as an env secret and lands only in the temporary `app.ini`.
- `SECRET_KEY` must use `SECRET_KEY_URI` when it is set, or a generated key would be lost on restart.
- JWT secrets must be 32 random bytes, base64url without padding:
- `openssl rand 32 | base64 | tr '+/' '-_' | tr -d '=' | podman secret create <name> -`
