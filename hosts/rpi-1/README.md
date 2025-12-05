# rpi-1

This machine is intended to run as a AlmaLinux alongside `rpi-2` for hosting replicated postgres.

## Postgres Cluster

### Install Postgres

AlmaLinux 10 only includes postgres 16 by default so we first need to enable the PostgreSQL yum repository

1. Add PostgreSQL repo
   - `sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-10-x86_64/pgdg-redhat-repo-latest.noarch.rpm`
2. Disable AlmaLinux's built-in PostgreSQL module (required)
   - `sudo dnf -qy module disable postgresql`
3. Install Postgres 18 packages
   - `sudo dnf install -y postgresql18-server postgresql18`
4. Initialize the data directory
   - `sudo /usr/pgsql-18/bin/postgresql-18-setup initdb`
5. Disable systemd’s PostgreSQL service (Patroni controls it)
   - `sudo systemctl disable --now postgresql-18`

### Install ETCD

ETCD is used as a distributed configuration store to keep track of which machine is designated as the master node

1. Install ETCD
   - `sudo dnf install -y etcd`
2. Add [etcd.conf](./services/etcd/etcd.conf) to `/etc/etcd/etcd.conf`
3. Start the ETCD service
   - `sudo systemctl enable --now etcd`

### Install Patroni

Patroni is used to 

1. Install Pagroni
   - `sudo dnf install -y python3-pip`
   - `sudo pip3 install patroni[etcd] psycopg[binary]`
2. Copy [patroni.yml](./services/patroni/patroni.yml) to `/etc/patroni.yml`
3. Copy [patroni.service](./services/patroni/patroni.service) to `/etc/systemd/system/patroni.service`
4. Copy [patroni_ha_check.sh](./services/patroni/patroni_ha_check.sh) to `/usr/local/bin/patroni_ha_check.sh`
5. Enable the Patroni service
   - `sudo systemctl daemon-reload`
   - `sudo systemctl enable --now patroni`

### Install Keepalived

Keepalived manages the VIP (virtual IP) that ensures a designated always points to the current active master node

1. Install Keepalived
   - `sudo dnf install -y keepalived`
2. Copy [keepalived.conf](./services/keepalived/keepalived.conf) to `/etc/keepalived/keepalived.conf`
3. Start the Keepalived service
   - `sudo systemctl enable --now keepalived`

### Setup all machines

Before proceding to [verification](#verification) setup these services on all the additional machines

- [rpi-1](../rpi-1/README.md)
- [rpi-2](../rpi-2/README.md)

### Verification

On rpi-1 (initial leader):
- `ip a | grep 10.0.0.175`

Simulate failover:
- `sudo systemctl stop patroni`

On rpi-2:
- `ip a | grep 10.0.0.175`

VIP should immediately move.
