# optiplex: LLDAP-backed login (SSH + Cockpit + sudo)

optiplex authenticates SSH, console, and Cockpit logins against **LLDAP** (the cluster identity
directory) via **SSSD**. LLDAP users with a `uidNumber` can log in; members of the LLDAP `admin`
group get sudo. The local `devops` account remains the break-glass, independent of LLDAP.

> Not GitOps-managed — optiplex is a podman/host box, so this config lives on the host, not in a
> cluster manifest. This file documents it.

## How it fits together

- **SSSD** (`sssd` + `sssd-ldap`, installed) bridges the OS to LLDAP: NSS for user/group lookups,
  PAM for authentication. Config: `/etc/sssd/sssd.conf`.
- **Auth path:** `ldaps://ldap.fivelabs.tech:636` (the LLDAP LDAPS LoadBalancer). optiplex already
  trusts the `*.fivelabs.tech` wildcard cert, so TLS verifies cleanly.
- **Bind user:** a dedicated, read-only LLDAP user `optiplex` (in `lldap_strict_readonly`) does the
  directory lookups — least privilege, not a real person's account.
- **Cockpit** uses PAM, so it authenticates via SSSD automatically; admin actions work because the
  user has sudo.

## POSIX attributes in LLDAP (required)

LLDAP is not a POSIX directory by default, and SSSD **cannot** auto-generate UIDs for LLDAP (ID
mapping only works with Active Directory SIDs). So POSIX attributes are added to LLDAP's schema and
set per user/group:

- User schema: `uidNumber` (Integer), `gidNumber` (Integer).
- Group schema: `gidNumber` (Integer).

Set per entity (via the LLDAP UI):

| Entity | Attribute | Value | Purpose |
|---|---|---|---|
| group `admin` | `gidNumber` | `3000` | the sudo group; resolves `admin` -> gid 3000 |
| user `phil` | `uidNumber` / `gidNumber` | `3001` / `3000` | shell user, primary group = admin |
| user `renate` | `uidNumber` / `gidNumber` | `3002` / `3000` | (example) another shell user |

**Access gate:** only LLDAP users that have a `uidNumber` become Linux users / can log in (enforced
by `ldap_access_filter = (uidNumber=*)`). To grant someone optiplex access, give them a `uidNumber`;
to revoke, remove it. UIDs use the 3000+ range to avoid colliding with local system accounts.

## sudo

`/etc/sudoers.d/lldap-admins`:

```
%admin ALL=(ALL) ALL
```

Members of the LLDAP `admin` group (gid 3000) get full sudo. The rule matches by group name, which
SSSD resolves from LLDAP.

## The SSSD config (`/etc/sssd/sssd.conf`)

Must be `root:root` mode `0600` (SSSD refuses to start otherwise — it holds the bind password).
The bind password is redacted here; the live file has it.

```ini
[sssd]
config_file_version = 2
services = nss, pam
domains = lldap

[domain/lldap]
id_provider = ldap
auth_provider = ldap
chpass_provider = none

ldap_uri = ldaps://ldap.fivelabs.tech:636
ldap_search_base = dc=fivelabs,dc=tech

ldap_default_bind_dn = uid=optiplex,ou=people,dc=fivelabs,dc=tech
ldap_default_authtok = <OPTIPLEX_BIND_PASSWORD>

ldap_schema = rfc2307bis
ldap_id_mapping = false

# user config
ldap_user_search_base = ou=people,dc=fivelabs,dc=tech
ldap_user_object_class = posixAccount
ldap_user_name = uid
ldap_user_uid_number = uidNumber
ldap_user_gid_number = gidNumber
ldap_user_member_of = memberOf

# group config — LLDAP groups are groupOfNames with a `member` attr
ldap_group_search_base = ou=groups,dc=fivelabs,dc=tech
ldap_group_object_class = groupOfNames
ldap_group_name = cn
ldap_group_gid_number = gidNumber
ldap_group_member = member

# access gate: only users with a uidNumber may log in
access_provider = ldap
ldap_access_filter = (uidNumber=*)

fallback_homedir = /home/%u
default_shell = /bin/bash

ldap_tls_reqcert = demand
cache_credentials = true
```

## Enabling it

```bash
sudo dnf install -y oddjob-mkhomedir
sudo authselect select sssd with-mkhomedir --force
sudo systemctl enable --now sssd oddjobd
sudo chown root:root /etc/sssd/sssd.conf && sudo chmod 0600 /etc/sssd/sssd.conf
sudo systemctl restart sssd && sudo sss_cache -E
```

Home dirs auto-create from `/etc/skel` on first login (via `pam_oddjob_mkhomedir`).

## Verify

```bash
id phil                 # uid=3001(phil) gid=3000(admin) groups=3000(admin)
getent group admin      # admin:*:3000:phil,renate
ssh phil@optiplex.lan   # LLDAP password (or key in ~/.ssh/authorized_keys)
sudo whoami             # root  (via %admin)
# Cockpit: https://optiplex.lan:9090 — log in as phil, admin actions work
```

## Resilience & break-glass

- `cache_credentials = true` — a user who has logged in before can still log in if LLDAP is briefly
  unreachable. (A *first-ever* login still needs LLDAP up.)
- **`devops` (local, uid 1000, in `wheel`) is the break-glass** — a real local account independent
  of LLDAP. Since LLDAP runs in the cluster, and the cluster depends on optiplex for DNS, never rely
  solely on LLDAP for optiplex login. `devops` always works.

## Gotchas (hard-won)

- **`/etc/sssd/sssd.conf` must be `root:root 0600`** — any group access (e.g. `root:sssd 0640`) makes
  SSSD refuse to start (`Permission denied` reading the config).
- **LLDAP group resolution needs explicit object class + member attr** — without
  `ldap_group_object_class = groupOfNames` and `ldap_group_member = member`, SSSD searches for the
  wrong group class and `getent group admin` returns empty (so `%admin` sudo silently fails). This was
  the main hurdle.
- **No ID mapping for LLDAP** — `ldap_id_mapping` must be `false`; SSSD can't synthesize UIDs for
  LLDAP, so every shell user needs an explicit `uidNumber` in LLDAP.
- **Avoid the `?subtree?(filter)` extended search-base syntax** — it was unreliable on SSSD 2.12; use
  a plain search base plus `access_provider`/`ldap_access_filter` for the uidNumber gate.
- **Clear the cache after config changes** — `sudo sss_cache -E` (stale cache masks fixes).
- **Dedicated bind user, not a person's account** — `uid=optiplex` in `lldap_strict_readonly` reads
  user/group attributes fine (no broader privilege needed).
