# Postgres

This is running as a rootless contianer. The original docker container doesn't support this so there are some extra steps needed.

### INIT

- Let the container run with the default settings to create the volume and let the postgres user take permission of the files.
- After the container is intialized and running, stop it.
- The user and group ID should be `524357`. Double check to make sure using `sudo ls -lhaF /home/devops/.local/share/containers/storage/volumes/postgres-data/_data`
- Copy the certificate files to `/home/devops/.local/share/containers/storage/volumes/postgres-data/_data`.
- Use `chown 524357:524357` on all certificate files copied.
- Use `chmod 0600` on the private key file in the volume.
- Use root powers to modify the existing `postgresql.conf` and `pg_hba.conf`
