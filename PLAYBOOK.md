# Jazz ELM 7.0.3 Deployment Playbook

This playbook walks through configuring and running the Docker Compose stack to provision a fully operational IBM Engineering Lifecycle Management (ELM) 7.0.3 instance backed by Oracle 19c.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Obtain IBM ELM Installation Media](#2-obtain-ibm-elm-installation-media)
3. [Configure the Environment](#3-configure-the-environment)
4. [Build the Docker Images](#4-build-the-docker-images)
5. [Deploy the Stack](#5-deploy-the-stack)
6. [Monitor the Provisioning](#6-monitor-the-provisioning)
7. [Verify the Deployment](#7-verify-the-deployment)
8. [Enable Let's Encrypt TLS (Production)](#8-enable-lets-encrypt-tls-production)
9. [Day-2 Operations](#9-day-2-operations)
10. [Troubleshooting](#10-troubleshooting)

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
- **gcloud CLI** (if hosting ELM media on Google Cloud Storage)

### Accounts

- **Oracle Account** (free) — required to pull the Oracle 19c Docker image
  1. Go to [oracle.com/account](https://profile.oracle.com/myprofile/account/create-account.jspx) and create a free Oracle account (Oracle SSO) using your email address
  2. Visit [container-registry.oracle.com](https://container-registry.oracle.com) and sign in with your new Oracle SSO credentials
  3. Search for `database/enterprise` in the registry catalog
  4. Click on the repository and review the **Oracle Standard Terms and Restrictions** license agreement
  5. Click **Accept** — this is a one-time step; it unlocks `docker pull` access for the `database/enterprise` images
  6. On your Docker host, authenticate:
     ```bash
     docker login container-registry.oracle.com
     # Username: your Oracle SSO email
     # Password: your Oracle SSO password
     ```
  7. Verify access:
     ```bash
     docker pull container-registry.oracle.com/database/enterprise:19.3.0.0
     ```

  > **Note:** If you receive "denied" or "unauthorized" errors, confirm you accepted the license agreement at container-registry.oracle.com for the specific image repository (`database/enterprise`). Simply having an Oracle account is not enough — the license must be explicitly accepted per repository.

- **IBM Passport Advantage** account (licensed) to download ELM 7.0.3 media

### Network Ports

Open the following ports on your host firewall:

| Port | Purpose |
|------|---------|
| 80/tcp | Traefik HTTP (Let's Encrypt ACME challenge) |
| 9443/tcp | Jazz ELM web UI (HTTPS) |
| 9643/tcp | Jazz Authentication Server (HTTPS) |

### Network Connectivity to LDAP and Other Internal Services

Docker containers route external traffic through the host's network stack. If your LDAP server, SMTP server, or other services are on a private network (VPN, Tailscale, WireGuard, etc.), the Docker **host** must have connectivity to those services — not the containers themselves.

**If your LDAP server is behind a Tailscale network:**

1. Install Tailscale on the Docker host:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```

2. Verify the host can reach the LDAP server:
   ```bash
   ldapsearch -x -H ldap://YOUR_LDAP_HOST:389 -b "dc=example,dc=com" -s base "(objectclass=*)"
   ```

3. Verify from inside a container:
   ```bash
   docker exec jazz-clm-container bash -c "echo | timeout 5 bash -c 'cat < /dev/tcp/YOUR_LDAP_HOST/389' && echo 'OK' || echo 'FAIL'"
   ```

If the host can reach LDAP but containers cannot, check that Docker's default bridge network allows external routing (it does by default, but custom iptables rules or firewall policies may block it).

> **Common symptom:** JAS logs show `javax.naming.CommunicationException: activity.intercax.com:389 [connect timed out]` and all `CRJAZ2871E` errors during SSO migration. This means the JAS Liberty server inside the container cannot reach the LDAP server. Fix the host's network routing first.

---

## 2. Obtain IBM ELM Installation Media

Download the following from IBM Passport Advantage and host them on an HTTP-accessible URL (e.g., a GCS bucket):

| File | Description |
|------|-------------|
| `JTS-DCM-CCM-QM-RM-JRS-ENI-repo-7.0.3.zip` | ELM 7.0.3 server repository |
| `JazzAuthServer-offering-repo-7.0.3.zip` | Jazz Authentication Server |
| `ELM-Web-Installer-Linux-7.0.3.zip` | IBM Installation Manager (web installer) |
| `ELM_703_iFix021.zip` | Latest iFix (optional but recommended) |
| `Rhapsody-DM-Servers-6.0.6.1.zip` | Rhapsody Design Manager (optional) |

### Upload to Google Cloud Storage (example)

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

gcloud storage cp JTS-DCM-CCM-QM-RM-JRS-ENI-repo-7.0.3.zip gs://ibm_jazz/
gcloud storage cp JazzAuthServer-offering-repo-7.0.3.zip gs://ibm_jazz/
gcloud storage cp ELM-Web-Installer-Linux-7.0.3.zip gs://ibm_jazz/
gcloud storage cp ELM_703_iFix021.zip gs://ibm_jazz/

# Make files publicly accessible for Docker ADD
gcloud storage objects update gs://ibm_jazz/JTS-DCM-CCM-QM-RM-JRS-ENI-repo-7.0.3.zip --add-acl-grant=entity=allUsers,role=READER
# Repeat for each file...
```

---

## 3. Configure the Environment

### Clone the repository

```bash
git clone https://github.com/lonniev/jazz-docker.git
cd jazz-docker
```

### Edit `.env`

All site-specific configuration lives in `.env`. Edit these values:

```bash
# --- Required: Your Jazz server's public hostname ---
CLM_FQDN="your-elm-server.example.com"

# --- Required: Passwords (change these!) ---
ORACLE_PASSWORD="YourOraclePassword"
ORACLE_SYS_PASSWORD="YourSysPassword"
JAZZ_ADMIN_PASSWORD="YourJazzPassword"

# --- Required: URLs to your hosted ELM media ---
JAZZ_DISTRO_URL="https://storage.googleapis.com/your-bucket/JTS-DCM-CCM-QM-RM-JRS-ENI-repo-7.0.3.zip"
JAZZ_JAS_URL="https://storage.googleapis.com/your-bucket/JazzAuthServer-offering-repo-7.0.3.zip"
IBMWEBINSTALLER_DISTRO_URL="https://storage.googleapis.com/your-bucket/ELM-Web-Installer-Linux-7.0.3.zip"
JAZZ_IFIX_URL="https://storage.googleapis.com/your-bucket/ELM_703_iFix021.zip"

# --- Required: LDAP configuration ---
LDAP_FQDN="your-ldap-server.example.com"
LDAP_PORT=389
LDAP_BASE_DN="dc=example,dc=com"

# --- Optional ---
ACME_EMAIL="you@example.com"
JAZZ_USER="jazz_admin"
```

### Log into Oracle Container Registry

```bash
docker login container-registry.oracle.com
# Enter your Oracle SSO email and password
```

### Set up Let's Encrypt directory (if using ACME later)

```bash
mkdir -p letsencrypt
touch letsencrypt/acme.json
chmod 600 letsencrypt/acme.json
```

---

## 4. Build the Docker Images

```bash
docker compose build
```

This takes 15-30 minutes on first run. The Jazz CLM image build:
- Downloads ~5 GB of ELM installation media via the URLs in `.env`
- Downloads the Oracle JDBC driver (`ojdbc8.jar`) from Maven Central
- Installs IBM Installation Manager
- Installs ELM 7.0.3 and JAS via silent install
- Applies the iFix overlay

The Oracle image is pulled directly from Oracle Container Registry (no local build).

---

## 5. Deploy the Stack

### Option A: All at once

```bash
docker compose up -d
```

The `depends_on` conditions handle ordering:
- **traefik** starts first
- **jazz_oracle** starts next, marked healthy only after schemas are created
- **jazz_clm** starts last, after Oracle is healthy

### Option B: Step by step (recommended for first run)

```bash
# 1. Start the reverse proxy
docker compose up -d traefik

# 2. Start Oracle — first run takes 15-20 minutes to create the database
docker compose up -d jazz_oracle

# 3. Watch Oracle progress
docker compose logs -f jazz_oracle

# Wait for: "=== Jazz CLM: All Oracle schemas ready ==="
# Then: "DATABASE IS READY TO USE!"

# 4. Start Jazz ELM
docker compose up -d jazz_clm

# 5. Watch Jazz progress
docker compose logs -f jazz_clm
```

---

## 6. Monitor the Provisioning

### What to expect in the logs

The full provisioning takes approximately **45-60 minutes** on first run:

| Phase | Duration | What's happening | Log indicator |
|-------|----------|------------------|---------------|
| Oracle DB creation | 15-20 min | Creating CDB, PDB, datafiles | `8% complete`... `100% complete` |
| Oracle schema creation | 1-2 min | Creating 11 Jazz schemas + OAuth | `=== Jazz CLM: All Oracle schemas ready ===` |
| ELM install + iFix | 5-10 min | Silent install via IBM IM | `userinstc Installation...` |
| Oracle readiness wait | 0-20 min | JDBC probe backoff loop | `Phase N/9: port open...` |
| Liberty server start | 2-3 min | Starting CLM Liberty server | `Server clm created` |
| repotools -setup | 15-25 min | Database table creation, app registration | `Executing step: Configure Database` |
| JAS SSO migration | 3-5 min | Preparing apps for SSO | `CRJAZ2884I ... successfully prepared` |
| Final server start | 2-3 min | Starting JAS + Liberty | `Done. Leaving the Jazz Services running.` |

### Useful monitoring commands

```bash
# Watch all containers
docker compose logs -f

# Watch just Jazz
docker compose logs -f jazz_clm

# Watch Liberty server log (detailed setup progress)
docker exec jazz-clm-container tail -f \
  /opt/IBM/JazzTeamServer/server/liberty/servers/clm/logs/console.log

# Check Oracle health
docker inspect --format='{{.State.Health.Status}}' jazz-oracle-container

# Check Oracle alert log
docker exec jazz-oracle-container tail -f \
  /opt/oracle/diag/rdbms/orclcdb/ORCLCDB/trace/alert_ORCLCDB.log
```

---

## 7. Verify the Deployment

### From the Docker host

```bash
# Jazz Team Server
curl -k https://localhost:9443/jts/web

# Jazz Authentication Server
curl -k https://localhost:9643/oidc/endpoint/jazzop/.well-known/openid-configuration
```

### From a browser (requires DNS or /etc/hosts)

Add to your `/etc/hosts` (for local testing):
```
127.0.0.1  jas-elm703.intercax.com
```

Then browse to:

| URL | Purpose |
|-----|---------|
| `https://CLM_FQDN:9443/jts` | Jazz Team Server admin |
| `https://CLM_FQDN:9443/ccm` | Change and Configuration Management |
| `https://CLM_FQDN:9443/rm` | Requirements Management (DOORS Next) |
| `https://CLM_FQDN:9443/qm` | Quality Management (ETM) |
| `https://CLM_FQDN:9443/gc` | Global Configuration Management |
| `https://CLM_FQDN:9443/relm` | Engineering Lifecycle Optimization |
| `https://CLM_FQDN:9643/oidc/endpoint/jazzop/.well-known/openid-configuration` | JAS OIDC discovery |

Default admin credentials: the `JAZZ_USER` / `JAZZ_ADMIN_PASSWORD` from `.env`.

---

## 8. Enable Let's Encrypt TLS (Production)

When deploying to a host with real public DNS:

1. Ensure `CLM_FQDN` in `.env` has a DNS A record pointing to your host's public IP

2. Uncomment the ACME lines in `docker-compose.yml`:
   ```yaml
   # In traefik command section, uncomment:
   - "--certificatesresolvers.myresolver.acme.httpchallenge=true"
   - "--certificatesresolvers.myresolver.acme.httpchallenge.entrypoint=traefik-entry-http_open"
   - "--certificatesresolvers.myresolver.acme.email=${ACME_EMAIL}"
   - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
   ```

3. Uncomment the certresolver labels on `jazz_clm`:
   ```yaml
   traefik.http.routers.traefix-router-jazz_auth.tls.certresolver: "myresolver"
   traefik.http.routers.traefix-router-jazz_app.tls.certresolver: "myresolver"
   ```

4. Ensure `letsencrypt/acme.json` has `chmod 600` permissions

5. Restart traefik:
   ```bash
   docker compose restart traefik
   ```

---

## 9. Day-2 Operations

### Stop the stack (preserving data)

```bash
docker compose down
```

### Restart the stack (data persists in volumes)

```bash
docker compose up -d
```

Oracle restarts in ~30 seconds on subsequent runs (vs. 15-20 minutes on first run). Jazz detects the existing setup and skips provisioning.

### Full reset (destroy all data)

```bash
docker compose down -v
```

This removes the `oracle-data`, `jazz-home`, and `jazz-installed` volumes. Next `up` will re-provision everything from scratch.

### View running containers

```bash
docker compose ps
```

### Enter a container shell

```bash
docker exec -it jazz-clm-container bash
docker exec -it jazz-oracle-container bash
```

### Rebuild after configuration changes

```bash
# If you changed .env, Dockerfile, or templates:
docker compose build jazz_clm
docker compose up -d jazz_clm

# If you changed oracle/createschema.sh (mounted as volume):
# No rebuild needed — just restart Oracle:
docker compose restart jazz_oracle
```

### Apply a new iFix

1. Upload the new iFix zip to your GCS bucket
2. Update `JAZZ_IFIX_URL` in `.env`
3. Rebuild and redeploy:
   ```bash
   docker compose build jazz_clm
   docker compose down
   docker compose up -d
   ```

---

## 10. Troubleshooting

### Oracle: "DATABASE SETUP WAS NOT SUCCESSFUL"

**ORA-01157: cannot identify/lock data file** — Tablespace datafiles were created with relative paths. Fixed in current version. Solution: `docker compose down -v` and start fresh.

### Jazz: "CRJAZ1840W ... oracle.jdbc.OracleDriver"

The JDBC driver is not at the expected location. Verify:
```bash
docker exec jazz-clm-container ls -la /opt/IBM/JazzTeamServer/server/oracle/ojdbc8.jar
```

### Jazz: "CRJAZ2654E ... SQLCODE: 17067"

Invalid Oracle JDBC URL. The `db.jdbc.location` in `parameters.properties` must be in IBM's format:
```
thin:username/{password}@//hostname:port/servicename
```
Jazz prepends `jdbc:oracle:` to this value.

### Jazz: "CRJAZ1860E ... could not be established with the following URI"

Jazz can't reach itself via `CLM_FQDN`. The `extra_hosts` entry in `docker-compose.yml` maps it to `127.0.0.1` for local dev. Verify:
```bash
docker exec jazz-clm-container getent hosts jas-elm703.intercax.com
```

### Oracle readiness probe times out

Oracle first-time init can take 15-20+ minutes. The backoff schedule allows ~30 minutes. If still timing out, check Oracle logs:
```bash
docker compose logs jazz_oracle | tail -50
```

### log4j OSGI NullPointerException in repotools

Harmless. IBM repotools runs outside the Liberty OSGI container; log4j's service loader throws a benign NPE. Filtered from output in current version.

### Need a completely clean start

```bash
docker compose down -v
docker rmi clm-jazz:latest
docker compose build
docker compose up -d
```

---

## Architecture Reference

```
                    +----------------------------------+
  Internet --:80--> |          Traefik v3.6             |
             :9443->|   (TLS termination, ACME certs)   |
             :9643->|                                    |
                    +------+----------------+-----------+
                           |                |
                    traefik_network   traefik_network
                           |                |
                    +------v------+  +------v----------+
                    |  Jazz ELM   |  |  Jazz Auth      |
                    |  (Liberty)  |  |  Server (JAS)   |
                    |  :9443      |  |  :9643           |
                    +------+------+  +------+----------+
                           |                |
                       service_network------+
                           |
                    +------v------------------+
                    |   Oracle 19c EE         |
                    |   PDB: JAZZPDB          |
                    |   :1521                 |
                    |   11 schemas + OAuth    |
                    +-------------------------+
```

### Docker Volumes

| Volume | Contents | Purpose |
|--------|----------|---------|
| `oracle-data` | Oracle datafiles, redo logs | Database persistence across restarts |
| `jazz-home` | `/home/jazz_admin` | Jazz admin user home, setup marker file |
| `jazz-installed` | `/opt/IBM` | Installed Jazz server + JAS binaries |

### Docker Networks

| Network | Members | Purpose |
|---------|---------|---------|
| `traefik_network` | traefik, whoami, jazz_clm | External-facing traffic routing |
| `service_network` | traefik, jazz_oracle, jazz_clm | Internal service communication |
