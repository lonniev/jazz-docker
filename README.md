# jazz-docker

Infrastructure as code for deploying IBM Engineering Lifecycle Management (ELM) 7.0.3 with Oracle 19c via Docker Compose.

## Overview

This project automates the installation and configuration of IBM Jazz ELM 7.0.3 (formerly CLM) using Docker containers. It provisions:

- **Traefik v3.3** — Reverse proxy with automatic Let's Encrypt TLS certificates
- **Oracle 19c Enterprise Edition** — Database backend using a single Pluggable Database (PDB) with per-application schemas for all 11 Jazz databases
- **IBM ELM 7.0.3 + iFix021** — Liberty-based application server running JTS, CCM, QM, RM, GC, RELM, DCC, LQE, LDX, DM, plus Jazz Authentication Server (JAS) with LDAP integration

## Prerequisites

- Docker Engine 24+ and Docker Compose v2
- Access to [Oracle Container Registry](https://container-registry.oracle.com) (requires Oracle SSO account)
- IBM ELM 7.0.3 installation media (from IBM Passport Advantage), hosted on a URL-accessible location
- A public-facing VM with at minimum 12 GB RAM
- DNS A-record pointing your chosen FQDN to the VM's IP

## Quick Start

1. Clone this repository
2. Log into Oracle Container Registry:
   ```bash
   docker login container-registry.oracle.com
   ```
3. Edit `.env` — set your FQDN, passwords, and ELM media URLs
4. Open firewall ports: `tcp/80`, `tcp/9443`, `tcp/9643`
5. Build and deploy:
   ```bash
   docker compose build
   docker compose up -d traefik
   docker compose up -d jazz_oracle    # wait for healthy (~5-10 min)
   docker compose up -d jazz_clm       # full setup takes ~45 min
   ```
6. Verify at `https://YOUR_FQDN:9443/jts`

## Architecture

Three Docker services form an isolated network:

```
                    ┌──────────────────────────────────┐
  Internet ──:80──► │          Traefik v3.3             │
             :9443─►│   (TLS termination, ACME certs)   │
             :9643─►│                                    │
                    └──────┬──────────────┬─────────────┘
                           │              │
                    traefik_network   traefik_network
                           │              │
                    ┌──────▼──────┐ ┌─────▼──────────┐
                    │  Jazz ELM   │ │  Jazz Auth     │
                    │  (Liberty)  │ │  Server (JAS)  │
                    │  :9443      │ │  :9643         │
                    └──────┬──────┘ └─────┬──────────┘
                           │              │
                       service_network────┘
                           │
                    ┌──────▼──────────────┐
                    │   Oracle 19c EE     │
                    │   PDB: JAZZPDB      │
                    │   :1521             │
                    │   (11 schemas + OAuth)│
                    └─────────────────────┘
```

## Third-Party Software

This project orchestrates the deployment of the following third-party software. Each is subject to its own license terms:

- **IBM Engineering Lifecycle Management (ELM)** — Copyright IBM Corporation. ELM is commercial software available under IBM license terms via [IBM Passport Advantage](https://www.ibm.com/software/passportadvantage/). You must hold valid IBM licenses to use ELM.
- **Oracle Database 19c Enterprise Edition** — Copyright Oracle Corporation. Oracle Database is commercial software available under [Oracle license terms](https://www.oracle.com/downloads/licenses/standard-license.html). You must hold valid Oracle licenses for production use. The container image is provided via [Oracle Container Registry](https://container-registry.oracle.com) under the Oracle Standard Terms and Restrictions.
- **Traefik Proxy** — Copyright Traefik Labs. Licensed under the [MIT License](https://github.com/traefik/traefik/blob/master/LICENSE.md).
- **Oracle JDBC Driver (ojdbc8)** — Downloaded from Maven Central. Licensed under the [Oracle Free Use Terms and Conditions](https://www.oracle.com/downloads/licenses/oracle-free-license.html).

## License

The orchestration code, Dockerfiles, shell scripts, and configuration templates in this repository are licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.

This license applies **only to the orchestration code in this repository**, not to the third-party software it deploys. You are responsible for obtaining appropriate licenses for IBM ELM, Oracle Database, and any other commercial software used.
