# LLDAP Secrets

- `lldap-admin-password.secret`
- `lldap-database-url.secret`
- `lldap-jwt-key.secret`

Example:

```
Secret=lldap-admin-password,type=env,target=LLDAP_LDAP_USER_PASS
Secret=lldap-database-url,type=env,target=LLDAP_DATABASE_URL
Secret=lldap-jwt-key,type=env,target=LLDAP_JWT_SECRET
```
