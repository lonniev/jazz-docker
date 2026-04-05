# Jazz ELM 7.0.3 Deployment Playbook

Zero to fully operational IBM ELM 7.0.3 with Oracle 19c, JAS SSO, and LDAP in under 45 minutes.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Obtain IBM ELM Installation Media](#2-obtain-ibm-elm-installation-media)
3. [Configure the Environment](#3-configure-the-environment)
4. [Build and Deploy](#4-build-and-deploy)
5. [Monitor the Provisioning](#5-monitor-the-provisioning)
6. [Verify the Deployment](#6-verify-the-deployment)
7. [Day-2 Operations](#7-day-2-operations)
8. [Troubleshooting](#8-troubleshooting)
9. [How It Works](#9-how-it-works)

---

## 1. Prerequisites

### Host Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 12 GB | 16 GB |
| Disk | 40 GB free | 80 GB free |
| CPU | 4 cores | 8 cores |
| OS | Linux (Ubuntu 22.04) or macOS | Ubuntu 22.04 LTS |

### Software

- **Docker Engine** 24+ and **Docker Compose** v2
- **Git**
- **gcloud CLI** (optional, if hosting ELM media on Google Cloud Storage)

### Accounts

- **Oracle Account** (free) -- required to pull the Oracle 19c Docker image
  1. Create a free account at [oracle.com/account](https://profile.oracle.com/myprofile/account/create-account.jspx)
  2. Visit [container-registry.oracle.com](https://container-registry.oracle.com), sign in, search for `database/enterprise`
  3. **Accept the license agreement** (one-time step per repository)
  4. Authenticate on your Docker host:
     ```bash
     docker login container-registry.oracle.com
     ```

  > If you get "denied" errors, confirm you accepted the license at container-registry.oracle.com for `database/enterprise`. An Oracle account alone is not enough.

- **IBM Passport Advantage** account (licensed) to download ELM 7.0.3 media

### Network

Open these firewall ports:

| Port | Purpose |
|------|---------|
| 80/tcp | Let's Encrypt ACME HTTP challenge |
| 9443/tcp | Jazz ELM web UI (HTTPS) |
| 9643/tcp | Jazz Authentication Server (HTTPS) |

### LDAP Connectivity

Docker containers route through the host's network stack. If your LDAP server is on a private network (VPN, Tailscale, WireGuard), the **Docker host** must have connectivity:

```bash
# Install Tailscale on the host if needed
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Verify LDAP is reachable from the host
ldapsearch -x -H ldap://YOUR_LDAP_HOST:389 -b "dc=example,dc=com" -s base "(objectclass=*)"
```

### LDAP Directory Requirements

Your OpenLDAP must have these groups and structure:

| Requirement | Detail |
|-------------|--------|
| Groups OU | `ou=Groups` under your base DN |
| Group objectClass | `groupOfUniqueNames` |
| Member attribute | `uniqueMember` with full DN values |
| Users OU | `ou=Users` under your base DN |
| User objectClass | `posixAccount` |
| Required groups | `JazzAdmins`, `JazzUsers`, `JazzProjectAdmins`, `JazzGuests` |
| Admin user | Must exist in LDAP, be in `JazzAdmins`, and the `uniqueMember` DN must match the user's actual entry DN |

Verify your admin user's group membership:
```bash
ldapsearch -x -H ldap://YOUR_LDAP:389 \
  -b "ou=Groups,dc=example,dc=com" \
  "(uniqueMember=uid=jazz_admin,ou=Users,dc=example,dc=com)" cn
# Should return: JazzAdmins (and optionally JazzUsers)
```

---

## 2. Obtain IBM ELM Installation Media

Download from IBM Passport Advantage and host on HTTP-accessible URLs:

| File | Description | Size |
|------|-------------|------|
| `JTS-DCM-CCM-QM-RM-JRS-ENI-repo-7.0.3.zip` | ELM 7.0.3 server repository | ~4 GB |
| `JazzAuthServer-offering-repo-7.0.3.zip` | Jazz Authentication Server | ~200 MB |
| `ELM-Web-Installer-Linux-7.0.3.zip` | IBM Installation Manager | ~100 MB |
| `ELM_703_iFix021.zip` | Latest iFix (recommended) | ~500 MB |

### Upload to Google Cloud Storage (example)

```bash
gcloud auth login
gcloud storage cp *.zip gs://YOUR_BUCKET/

# Make publicly accessible for Docker ADD
for f in JTS-DCM-CCM-QM-RM-JRS-ENI-repo-7.0.3.zip \
         JazzAuthServer-offering-repo-7.0.3.zip \
         ELM-Web-Installer-Linux-7.0.3.zip \
         ELM_703_iFix021.zip; do
  gcloud storage objects update "gs://YOUR_BUCKET/$f" \
    --add-acl-grant=entity=allUsers,role=READER
done
```

---

## 3. Configure the Environment

```bash
git clone https://github.com/lonniev/jazz-docker.git
cd jazz-docker
cp .env.template .env
vi .env
```

Edit these required values in `.env`:

```bash
CLM_FQDN="your-elm-server.example.com"

ORACLE_PASSWORD="YourOraclePass42"
ORACLE_SYS_PASSWORD="YourSysPass42"
JAZZ_ADMIN_PASSWORD="your_ldap_password"

JAZZ_DISTRO_URL="https://storage.googleapis.com/YOUR_BUCKET/JTS-DCM-CCM-QM-RM-JRS-ENI-repo-7.0.3.zip"
JAZZ_JAS_URL="https://storage.googleapis.com/YOUR_BUCKET/JazzAuthServer-offering-repo-7.0.3.zip"
IBMWEBINSTALLER_DISTRO_URL="https://storage.googleapis.com/YOUR_BUCKET/ELM-Web-Installer-Linux-7.0.3.zip"
JAZZ_IFIX_URL="https://storage.googleapis.com/YOUR_BUCKET/ELM_703_iFix021.zip"

LDAP_FQDN="your-ldap-server.example.com"
LDAP_BASE_DN="dc=example,dc=com"
LDAP_BIND_DN="uid=jazz_admin,ou=Users,dc=example,dc=com"
LDAP_BIND_PASSWORD="your_ldap_password"

ACME_EMAIL="you@example.com"
```

**Important:** `JAZZ_ADMIN_PASSWORD` must match the LDAP password for `JAZZ_USER` (default: `jazz_admin`).

### Prepare Let's Encrypt

```bash
mkdir -p letsencrypt
touch letsencrypt/acme.json
chmod 600 letsencrypt/acme.json
```

---

## 4. Build and Deploy

```bash
# Build the Jazz CLM image (~15-30 min, downloads ~5 GB of ELM media)
docker compose build

# Deploy everything
docker compose up -d
```

The `depends_on` conditions handle ordering automatically:
1. **traefik** starts first
2. **jazz_oracle** starts, healthcheck waits for schemas (~15-20 min on first run)
3. **jazz_clm** starts after Oracle is healthy, runs full provisioning (~25-35 min)

---

## 5. Monitor the Provisioning

```bash
# Watch the full provisioning
docker compose logs -f jazz_clm
```

### What to expect

| Log Message | Meaning |
|-------------|---------|
| `LDAP bind and user lookup succeeded.` | LDAP credentials validated early |
| `Oracle is ready` | JDBC connection to Oracle confirmed |
| `Server clm created` | Liberty server initialized |
| `Setup completed successfully` | All databases created, apps registered |
| `CRJAZ2868I ... successfully migrated` | JAS SSO migration complete (all 7 apps) |
| `LTPA keys synced from JAS to CLM` | Shared token keys for SSO |
| `Configuring Jazz LDAP user registry` | LDAP properties injected |
| `User synchronization has been successfully requested` | LDAP users/groups synced |
| `Done. Leaving the Jazz Services running.` | Provisioning complete |

### Other monitoring commands

```bash
# Oracle progress
docker compose logs -f jazz_oracle

# Liberty server log (detailed)
docker exec jazz-clm-container tail -f \
  /opt/IBM/JazzTeamServer/server/liberty/servers/clm/logs/console.log

# Oracle health status
docker inspect --format='{{.State.Health.Status}}' jazz-oracle-container

# JAS log
docker exec jazz-clm-container cat \
  /opt/IBM/JazzAuthServer/wlp/usr/servers/jazzop/logs/messages.log
```

---

## 6. Verify the Deployment

### Browser

Navigate to these URLs (replace `CLM_FQDN` with your hostname):

| URL | Application |
|-----|-------------|
| `https://CLM_FQDN:9443/jts` | Jazz Team Server (admin) |
| `https://CLM_FQDN:9443/ccm` | Engineering Workflow Management |
| `https://CLM_FQDN:9443/rm` | DOORS Next (Requirements) |
| `https://CLM_FQDN:9443/qm` | Engineering Test Management |
| `https://CLM_FQDN:9443/gc` | Global Configuration Management |
| `https://CLM_FQDN:9443/relm` | Engineering Insights |
| `https://CLM_FQDN:9443/dcc` | Data Collection Component |
| `https://CLM_FQDN:9443/lqe` | Lifecycle Query Engine |

Log in with any LDAP user that is in the `JazzUsers` or `JazzAdmins` group.

### CLI verification

```bash
# JTS health
curl -sk https://localhost:9443/jts/web | head -5

# JAS OIDC discovery
curl -sk https://localhost:9643/oidc/endpoint/jazzop/.well-known/openid-configuration | python3 -m json.tool

# Verify LDAP registry type
docker exec jazz-clm-container grep 'registry.type' \
  /opt/IBM/JazzTeamServer/server/conf/jts/teamserver.properties
# Should show: com.ibm.team.repository.user.registry.type=LDAP
```

---

## 7. Day-2 Operations

### Stop / restart (data preserved)

```bash
docker compose down      # stop
docker compose up -d     # restart (~2 min, skips provisioning)
```

### Full reset

```bash
docker compose down -v                      # destroy volumes
docker compose build --no-cache jazz_clm    # rebuild image
docker compose up -d                        # fresh provisioning
```

### Apply a new iFix

```bash
# 1. Upload new iFix to your hosting location
# 2. Update JAZZ_IFIX_URL in .env
# 3. Rebuild
docker compose down -v
docker compose build --no-cache jazz_clm
docker compose up -d
```

### Enter container shells

```bash
docker exec -it jazz-clm-container bash
docker exec -it jazz-oracle-container bash
```

---

## 8. Troubleshooting

### CRRTC8030E: Data warehouse creation failed

**Cause:** Oracle DW_JAZZ user lacks `CREATE TABLESPACE` privilege, or `db.base.folder` path doesn't exist locally.

**Check:** Oracle alert log for ORA-1031:
```bash
docker exec jazz-oracle-container grep 'ORA-1031' \
  /opt/oracle/diag/rdbms/*/*/trace/alert_*.log
```

**Fix:** Current version grants DBA to DW_JAZZ and creates the db.base.folder directory locally.

### CRJAZ2871E: JAS auth invalid during SSO migration

**Cause:** JAS `appConfig.xml` was overwritten by `start-jazz` with defaults that include `localUserRegistry.xml` instead of our `ldapUserRegistry.xml`.

**Check:** Verify our config was restored:
```bash
docker exec jazz-clm-container grep 'ldapUserRegistry\|localUserRegistry' \
  /opt/IBM/JazzAuthServer/wlp/usr/servers/jazzop/appConfig.xml
```

### CRJAZ1394E: User not in repository group

**Cause:** Jazz's `teamserver.properties` has `user.registry.type=UNSUPPORTED` (DETECT failed during setup because Liberty had basicUserRegistry).

**Check:**
```bash
docker exec jazz-clm-container grep 'registry.type' \
  /opt/IBM/JazzTeamServer/server/conf/jts/teamserver.properties
```

**Fix:** Must be `type=LDAP` with the correct `com.ibm.team.repository.ldap.*` properties. Current version injects these automatically after setup.

### CRJAZ2902E: Insufficient permissions (syncUsers)

**Cause:** Jazz admin user can authenticate but isn't recognized as JazzAdmin. Usually means LDAP group membership DN doesn't match the user's entry DN.

**Check:**
```bash
# Verify the admin user's group membership DN matches
ldapsearch -x -H ldap://YOUR_LDAP:389 \
  -b "ou=Groups,dc=example,dc=com" \
  "(uniqueMember=uid=jazz_admin,ou=Users,dc=example,dc=com)" cn
```

### CWWKS4001I: Security token cannot be validated

**Cause:** LTPA keys differ between JAS and CLM Liberty servers.

**Check:**
```bash
docker exec jazz-clm-container md5sum \
  /opt/IBM/JazzAuthServer/wlp/usr/servers/jazzop/resources/security/ltpa.keys \
  /opt/IBM/JazzTeamServer/server/liberty/servers/clm/resources/security/ltpa.keys
```

**Fix:** Current version copies JAS LTPA keys to CLM before final startup.

### LDAP error code 49 - Invalid Credentials

**Cause:** LDAP bind DN or password in `.env` is wrong.

**Check:** The early validation will catch this:
```
LDAP validation failed: FAIL_BIND: ...
```

### Oracle readiness probe times out

Oracle first-time init can take 15-20+ minutes. The backoff schedule allows ~30 minutes. Check Oracle logs:
```bash
docker compose logs jazz_oracle | tail -50
```

### Complete clean start

```bash
docker compose down -v
docker rmi clm-jazz:latest
docker compose build --no-cache
docker compose up -d
```

---

## 9. How It Works

The provisioning script (`getItBuildItRunIt.sh`) runs inside the `jazz_clm` container at startup and executes these phases:

### Phase 1: Install ELM
- Unzips ELM and JAS installation media
- Runs IBM Installation Manager (`userinstc`) for silent install
- Applies iFix overlay (file patches + WAR replacements)
- Relocates installed files to `/opt/IBM`

### Phase 2: Validate dependencies
- Validates LDAP credentials early (bind + user search)
- Waits for Traefik (port 8080)
- Waits for Oracle with backoff probe (up to ~30 min)
- Installs Oracle JDBC driver to JAS and CLM

### Phase 3: Configure and setup
- Generates `parameters.properties` from template (Oracle JDBC, DW, LDAP, licenses)
- Starts CLM Liberty server
- Runs `repotools-jts.sh -setup` (creates all databases, registers apps, configures DW)
- Creates `jazz_admin` user with JazzAdmins role
- Prepares all 7 apps for JAS SSO migration
- Fixes full-text index paths to absolute

### Phase 4: JAS SSO
- Switches CLM Liberty from `basicUserRegistry` to `ldapUserRegistry`
- Generates JAS `appConfig.xml` (Oracle datasource + LDAP)
- Starts JAS, restores custom config after `start-jazz` overwrites it, restarts JAS
- Runs `migrateToJsaSso` for all 7 apps (JTS, CCM, RM, GC, QM, RELM, DCC)
- Syncs LTPA keys from JAS to CLM

### Phase 5: LDAP integration
- Injects Jazz LDAP properties into `teamserver.properties`:
  - `com.ibm.team.repository.user.registry.type=LDAP`
  - `com.ibm.team.repository.ldap.baseGroupDN`, `baseUserDN`, `registryLocation`
  - `com.ibm.team.repository.ldap.findGroupsForUserQuery=uniqueMember={USER-DN}`
  - `com.ibm.team.repository.ldap.membersOfGroup=uniqueMember`
  - `com.ibm.team.repository.ldap.userSearchObjectClassFilter=objectClass=posixAccount`
- Starts JAS and CLM for production
- Runs `repotools-jts.sh -syncUsers` to import LDAP users/groups

### On subsequent restarts
The script checks for `/home/jazz_admin/jazzIsSetup` and skips all provisioning phases, going directly to server startup.
