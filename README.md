# jazz-docker

Deploy IBM Engineering Lifecycle Management (ELM) 7.0.3 with Oracle 19c, JAS SSO, and LDAP -- fully automated via Docker Compose. Zero to working ELM in under 45 minutes.

## What You Get

A single `docker compose up -d` provisions:

- **Oracle 19c Enterprise** -- 11 per-app schemas (JTS, CCM, QM, RM, GC, RELM, DCC, LQE, LDX, DM, DW) + OAuth2 schema
- **IBM ELM 7.0.3 + iFix021** -- All applications on a single Liberty server
- **Jazz Authentication Server (JAS)** -- OIDC SSO with LDAP user/group integration
- **Traefik v3.6** -- Reverse proxy with automatic Let's Encrypt TLS certificates
- **Automated LDAP sync** -- Users and groups imported from your OpenLDAP directory

## Prerequisites

- Docker Engine 24+ with Compose v2
- 12+ GB RAM, 40+ GB disk, 4+ CPU cores (Linux or macOS host)
- [Oracle Container Registry](https://container-registry.oracle.com) account (free -- accept license for `database/enterprise`)
- IBM ELM 7.0.3 media from [IBM Passport Advantage](https://www.ibm.com/software/passportadvantage/), hosted at HTTP-accessible URLs
- DNS A-record for your chosen FQDN pointing to the host IP
- OpenLDAP directory with Jazz groups (`JazzAdmins`, `JazzUsers`, `JazzProjectAdmins`, `JazzGuests`) using `groupOfUniqueNames` + `uniqueMember`
- LDAP server reachable from the Docker host (install [Tailscale](https://tailscale.com) on the host if LDAP is on a private network)

## Quick Start

```bash
git clone https://github.com/lonniev/jazz-docker.git
cd jazz-docker

# 1. Authenticate to Oracle Container Registry
docker login container-registry.oracle.com

# 2. Configure
cp .env.template .env
vi .env   # Set FQDN, passwords, media URLs, LDAP settings

# 3. Open firewall ports
# tcp/80 (Let's Encrypt), tcp/9443 (ELM), tcp/9643 (JAS)

# 4. Deploy
docker compose up -d

# 5. Watch progress (~45 min first run)
docker compose logs -f jazz_clm

# 6. Done when you see:
#    "Done. Leaving the Jazz Services running."
```

Browse to `https://YOUR_FQDN:9443/jts` and log in with your LDAP credentials.

## Architecture

```
Internet --:80-->  Traefik v3.6 (Let's Encrypt TLS)
           :9443->    |
           :9643->    |
                      +-- Jazz ELM (Liberty) :9443
                      |     +-- JTS, CCM, QM, RM, GC, RELM, DCC
                      |     +-- LQE, LDX, RS
                      |     +-- ldapUserRegistry.xml --> OpenLDAP
                      |
                      +-- Jazz Auth Server (JAS) :9643
                      |     +-- OIDC/OAuth2 provider
                      |     +-- ldapUserRegistry.xml --> OpenLDAP
                      |     +-- Oracle-backed OAuth token store
                      |
                      +-- Oracle 19c Enterprise :1521
                            +-- PDB: JAZZPDB
                            +-- 11 app schemas (APP_JAZZ pattern)
                            +-- OAUTHDBSCHEMA
```

### Docker Volumes

| Volume | Contents | Purpose |
|--------|----------|---------|
| `oracle-data` | Oracle datafiles, redo logs | Database persistence across restarts |
| `jazz-home` | `/home/jazz_admin` | Jazz admin home, setup marker file |
| `jazz-installed` | `/opt/IBM` | Installed ELM server + JAS binaries |

### Docker Networks

| Network | Members | Purpose |
|---------|---------|---------|
| `traefik_network` | traefik, whoami, jazz_clm | External-facing traffic routing |
| `service_network` | traefik, jazz_oracle, jazz_clm | Internal service communication |

## Configuration

All site-specific settings live in `.env`. See [.env.template](.env.template) for the full list with inline documentation.

### Password Rules

Passwords flow through bash, SQL, JDBC URLs, and XML without additional escaping. Keep them simple:
- 8+ characters, at least 1 uppercase, 1 lowercase, 1 digit
- No special characters (`! @ # $ % ^ & * ' " ; \`)
- Example: `OrangeTiger42runs`

### LDAP Requirements

Your LDAP directory must have:

| Requirement | Detail |
|-------------|--------|
| Groups OU | `ou=Groups` under your base DN |
| Group objectClass | `groupOfUniqueNames` |
| Member attribute | `uniqueMember` (full DN values) |
| Users OU | `ou=Users` under your base DN |
| User objectClass | `posixAccount` |
| Required groups | `JazzAdmins`, `JazzUsers`, `JazzProjectAdmins`, `JazzGuests` |
| Admin user | `JAZZ_USER` must exist in LDAP and be in `JazzAdmins` |
| DN consistency | The `uniqueMember` DN in the group must match the user's actual entry DN (same OU) |

**IBM documentation for Jazz LDAP properties:**
- [How to check/edit Jazz LDAP configuration](https://www.ibm.com/support/pages/how-check-or-edit-your-configuration-jazz-team-server-ldap)
- [Manually configuring LDAP for ELM 7.0.3](https://www.ibm.com/docs/en/elm/7.0.3?topic=SSYMRC_7.0.3/com.ibm.jazz.install.doc/topics/t_manually_config_tomcat_ldap.htm)

## Provisioning Timeline

| Phase | Duration | Log Indicator |
|-------|----------|---------------|
| Oracle DB creation | 15-20 min | `8% complete` ... `100% complete` |
| Oracle schema creation | 1-2 min | `=== Jazz CLM: All Oracle schemas ready ===` |
| ELM install + iFix overlay | 5-10 min | `userinstc Installation...` |
| LDAP validation | instant | `LDAP bind and user lookup succeeded.` |
| Oracle readiness probe | 0-20 min | `Phase N/9: port open, waiting for PDB/schemas` |
| repotools -setup | 15-25 min | `Executing step: Configure Database` ... `Setup completed successfully` |
| JAS SSO migration | 3-5 min | `CRJAZ2868I The application was successfully migrated` |
| LDAP config injection | instant | `Configuring Jazz LDAP user registry` |
| LDAP user sync | 1-2 min | `User synchronization has been successfully requested` |

## Day-2 Operations

```bash
# Stop (data preserved in volumes)
docker compose down

# Restart (skips provisioning, ~2 min)
docker compose up -d

# Full reset (destroys all data, rebuilds from scratch)
docker compose down -v
docker compose build --no-cache jazz_clm
docker compose up -d

# Apply a new iFix
# Update JAZZ_IFIX_URL in .env, then:
docker compose down -v
docker compose build --no-cache jazz_clm
docker compose up -d
```

## Troubleshooting

See [PLAYBOOK.md](PLAYBOOK.md) for the detailed deployment walkthrough with monitoring commands and troubleshooting for Oracle, JDBC, LDAP, JAS SSO, LTPA keys, and user registry issues.

## Third-Party Software

| Software | License |
|----------|---------|
| IBM ELM 7.0.3 | Commercial -- [IBM Passport Advantage](https://www.ibm.com/software/passportadvantage/) |
| Oracle 19c EE | Commercial -- [Oracle License Terms](https://www.oracle.com/downloads/licenses/standard-license.html) |
| Traefik Proxy | [MIT License](https://github.com/traefik/traefik/blob/master/LICENSE.md) |
| ojdbc8 driver | [Oracle Free Use Terms](https://www.oracle.com/downloads/licenses/oracle-free-license.html) |

## License

The orchestration code in this repository is licensed under Apache License 2.0. See [LICENSE](LICENSE). This does **not** cover IBM ELM, Oracle Database, or other commercial software deployed by this project. You are responsible for obtaining appropriate licenses.
