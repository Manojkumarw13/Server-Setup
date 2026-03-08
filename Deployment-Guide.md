# Oracle Cloud Server - Complete Deployment Guide

> **Reference Architecture:** [Setup.md](file:///p:/Project/Server-Setup/Setup.md)
> **Server:** Oracle Free Tier VM.Standard.A1.Flex (4 ARM OCPUs, 24 GB RAM, 200 GB Storage)

---

## Project Files Overview

This repository contains all configuration files needed for deployment. Instead of copying commands manually, you can transfer these files directly to the server.

| File                               | Server Location            | Purpose                               |
| ---------------------------------- | -------------------------- | ------------------------------------- |
| `docker-compose.yml`               | `/data/docker-compose.yml` | All 9 containers (version-pinned)     |
| `.env`                             | `/data/.env`               | Secrets template — fill before deploy |
| `daemon.json`                      | `/etc/docker/daemon.json`  | Docker engine config                  |
| `nginx/nginx.conf`                 | `/data/nginx/nginx.conf`   | Main Nginx config                     |
| `nginx/conf.d/*.conf`              | `/data/nginx/conf.d/`      | 7 server block configs                |
| `postgres-init/init-databases.sql` | `/data/postgres-init/`     | Auto-creates DBs on first boot        |
| `homepage/*.yaml`                  | `/data/homepage/`          | Dashboard config (3 files)            |
| `scripts/backup-data-volume.sh`    | `/usr/local/bin/`          | Automated weekly backup               |
| `websites/index.html`              | `/data/websites/`          | Placeholder landing page              |

> [!TIP]
> **Two deployment methods:** You can either (A) follow this guide step-by-step, copying each config inline, or (B) clone this repo and copy the pre-built files to `/data/` on the server. Both methods produce the same result — the guide shows inline commands for learning, while the standalone files are ready for direct deployment.

# Phase 1: Oracle Cloud Account & Infrastructure

This phase sets up your Oracle Cloud account and provisions the virtual machine, networking, and storage.

---

## Step 1.1 — Create Oracle Cloud Account

1. Go to [cloud.oracle.com](https://cloud.oracle.com) and click **Sign Up**.
2. Enter your email, name, and country. Choose your **Home Region** (closest to you — e.g., `ap-mumbai-1` for India).

> [!CAUTION]
> Your Home Region is **permanent** and cannot be changed. Free Tier ARM instances are only available in specific regions. Choose wisely.

3. Enter a valid credit/debit card (needed for verification only — you won't be charged on the Free Tier).
4. Wait for the account activation email (can take 1–30 minutes).
5. Sign in to the OCI Console at [cloud.oracle.com](https://cloud.oracle.com).

---

## Step 1.2 — Create VCN (Virtual Cloud Network)

1. In the OCI Console, go to **Networking → Virtual Cloud Networks**.
2. Click **Start VCN Wizard → Create VCN with Internet Connectivity** → Start.
3. Name: `homelab-vcn`. Leave default CIDR blocks.
4. Click **Next → Create**.
5. Once created, go to the VCN → **Security Lists → Default Security List**.
6. **Add an Ingress Rule** for Port 80:
   - Source CIDR: Your LB's Subnet CIDR (NOT `0.0.0.0/0`) — you'll update this after creating the LB.
   - Destination Port: `80`
   - Protocol: TCP
7. **Add an Ingress Rule** for Syncthing Sync Protocol:
   - Source CIDR: `0.0.0.0/0`
   - Destination Port: `22000`
   - Protocol: TCP
8. **Duplicate Step 7** for UDP:
   - Source CIDR: `0.0.0.0/0`
   - Destination Port: `22000`
   - Protocol: UDP
9. **DELETE** the default SSH rule (Port 22 from `0.0.0.0/0`) — Bastion will replace this.

---

## Step 1.3 — Create the Compute Instance (VM)

1. Go to **Compute → Instances → Create Instance**.
2. **Name:** `homelab`
3. **Image:** Canonical Ubuntu 24.04 LTS (aarch64).
4. **Shape:** `VM.Standard.A1.Flex` → **4 OCPUs, 24 GB RAM**.

> [!IMPORTANT]
> If the shape is greyed out or unavailable, the region is temporarily out of ARM capacity. Retry later or use the OCI CLI script to auto-retry: `oci compute instance launch ...` in a cron loop.

5. **Networking:** Select your `homelab-vcn` public subnet. Assign a public IPv4.
6. **Boot Volume:** Set to **50 GB**.
7. **SSH Key:** Paste your `.pub` SSH key (generate one with `ssh-keygen -t ed25519` if you don't have one).
8. Click **Create**.
9. Wait for the instance status to become **Running**. Note the **Public IP** address.

---

## Step 1.4 — Create & Attach Block Volume (150 GB Data Drive)

1. Go to **Storage → Block Volumes → Create Block Volume**.
2. **Name:** `homelab-data`. **Size:** 150 GB.
3. **Availability Domain:** Must match the compute instance's AD.
4. Click **Create**.
5. Go to **Compute → Instances → homelab → Attached Block Volumes → Attach Block Volume**.
6. Select `homelab-data`. Attachment type: **iSCSI**. Click **Attach**.
7. Click the three dots (⋮) on the attached volume → **iSCSI Commands & Information**.
8. Copy the **Connect** commands — you will run these on the server in Phase 2.

---

## Step 1.5 — Create OCI Bastion

1. Go to **Identity & Security → Bastion → Create Bastion**.
2. **Name:** `homelab-bastion`. Select the `homelab-vcn` public subnet.
3. **CIDR Allowlist:** Add your home public IP (find it at [whatismyip.com](https://whatismyip.com)) as `YOUR_IP/32`.
4. Click **Create Bastion**.

---

## Step 1.6 — Enable Bastion Plugin on the VM

1. Go to **Compute → Instances → homelab → Oracle Cloud Agent** tab.
2. Find **Bastion** in the plugins list → Toggle it to **Enabled**.
3. Wait 5 minutes for the agent to activate.

---

## Step 1.7 — Create a Bastion Session (SSH Tunnel)

1. Go to **Bastion → homelab-bastion → Create Session**.
2. **Session Type:** Managed SSH Session.
3. **Target Instance:** `homelab`. **Username:** `ubuntu`. Upload your SSH public key.
4. Click **Create Session**.
5. Once active, click the three dots (⋮) → **Copy SSH Command**.
6. Paste and run the command in your local terminal. You are now connected.

---

# Phase 2: Server OS & Storage Configuration

This phase prepares the Ubuntu server with storage, kernel tuning, and essential packages.

---

## Step 2.1 — First Boot Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y curl wget gnupg lsb-release ca-certificates

# Set hostname
sudo hostnamectl set-hostname homelab
```

---

## Step 2.2 — Attach iSCSI Block Volume

Run the iSCSI connect commands you copied from Step 1.4 (Step 8). They look like:

```bash
sudo iscsiadm -m node -o new -T <IQN> -p <IP>:<PORT>
sudo iscsiadm -m node -o update -T <IQN> -n node.startup -v automatic
sudo iscsiadm -m node -T <IQN> -p <IP>:<PORT> -l
```

Verify the disk is visible:

```bash
lsblk
# You should see a new 150GB disk, e.g., /dev/sdb
```

---

## Step 2.3 — Format & Mount Data Volume

```bash
# Format the drive
sudo mkfs.ext4 /dev/sdb

# Create mount point
sudo mkdir -p /data

# Get the UUID
sudo blkid /dev/sdb
# Note the UUID="xxxx-xxxx-xxxx"

# Add to fstab (replace UUID)
echo 'UUID=xxxx-xxxx-xxxx /data ext4 defaults,nofail,_netdev 0 2' | sudo tee -a /etc/fstab

# Mount it
sudo mount -a

# Verify
df -h /data
# Should show ~150GB
```

> [!CAUTION]
> **Always map Docker volumes to _subdirectories_ of `/data/`, never to `/data/` itself.**
> The ext4 format creates a `lost+found` directory at the root. If you mount `/data:/var/lib/postgresql/data`, PostgreSQL will refuse to initialize because the directory is not empty. Always use `/data/postgres:/var/lib/postgresql/data` (already done correctly in Step 4.1).

---

## Step 2.4 — Create All Host Directories

```bash
# Create all data subdirectories
sudo mkdir -p /data/{docker,postgres,postgres-init,mongo,qdrant,n8n,nginx/conf.d,portainer,homepage,jellyfin/config,syncthing/config,media/music,websites}

# Set ownership for PUID/PGID containers (Jellyfin, Syncthing)
sudo chown -R 1000:1000 /data/media /data/jellyfin /data/syncthing

# Set web asset permissions
sudo chmod -R 755 /data/websites
```

---

## Step 2.5 — Create Swap File

```bash
# Create 6GB swap file (boot volume is 50 GB; 6 GB swap leaves ~44 GB for OS + packages, which is safe)
sudo fallocate -l 6G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make it persistent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Verify
free -h
```

---

## Step 2.6 — Kernel Tuning

```bash
# Prevent iSCSI swapping freeze
# Uses grep guard to avoid duplicate entries on re-runs
grep -q 'vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

# Phase 3: Docker Engine Installation

This phase installs Docker and configures the engine with the production settings from the architecture plan.

---

## Step 3.1 — Install Docker Engine

```bash
# Add Docker's official GPG key and repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=arm64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add your user to docker group (avoid sudo for docker commands)
sudo usermod -aG docker $USER

# Log out and back in for group change to take effect
exit
```

> [!NOTE]
> After exiting, create a new Bastion session (Step 1.7) and reconnect.

---

## Step 3.2 — Configure Docker Daemon

> [!NOTE]
> The daemon configuration is also available as a standalone file: [`daemon.json`](file:///p:/Project/Server-Setup/daemon.json)

```bash
sudo cp daemon.json /etc/docker/daemon.json
```

Or create it manually:

```bash
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "journald",
  "data-root": "/data/docker",
  "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF
```

> [!WARNING]
> **Do NOT install or enable `ufw` (Uncomplicated Firewall) on this server.** Docker bypasses `ufw` rules by modifying `iptables` directly, so any `ufw` rules you set for container ports will be silently ignored. All port-level network security is handled by the OCI VCN Security List.

---

## Step 3.3 — Force Docker to Wait for Data Mount

```bash
sudo systemctl edit docker
```

Add the following between the comments:

```ini
[Unit]
After=data.mount
Requires=data.mount
```

Save and exit (`:wq` in nano/vi).

```bash
# Restart Docker with new settings
sudo systemctl daemon-reload
sudo systemctl restart docker

# Verify data-root moved
docker info | grep "Docker Root Dir"
# Should show: /data/docker
```

---

## Step 3.4 — Cap Journald Log Size

```bash
# Uses grep guard to avoid duplicate entries on re-runs
grep -q 'SystemMaxUse' /etc/systemd/journald.conf || echo 'SystemMaxUse=5G' | sudo tee -a /etc/systemd/journald.conf

sudo systemctl restart systemd-journald
```

---

## Step 3.5 — Create Global Environment File

> [!NOTE]
> The environment file is also available as a standalone template: [`.env`](file:///p:/Project/Server-Setup/.env)

Copy from the repo or create manually:

```bash
sudo cp .env /data/.env
```

Or create it inline:

```bash
sudo tee /data/.env << 'EOF'
TZ=Asia/Kolkata
COMPOSE_PROJECT_NAME=homelab

# ── Secrets ── Fill these in before running docker compose up ──
# Use a strong, unique password. The same POSTGRES_PASSWORD must be used
# in both the postgres and n8n sections below.
POSTGRES_PASSWORD=CHANGE_ME_STRONG_PASSWORD
MONGO_PASSWORD=CHANGE_ME_STRONG_PASSWORD
# Generate with: openssl rand -hex 16
N8N_ENCRYPTION_KEY=GENERATE_A_RANDOM_32_CHAR_STRING_HERE
# Generate with: openssl rand -hex 32
QDRANT_API_KEY=GENERATE_A_RANDOM_64_CHAR_STRING_HERE
# Update this to your actual n8n subdomain after DNS is configured (Step 6.7)
N8N_WEBHOOK_URL=https://n8n.yourdomain.com/
EOF
```

> [!CAUTION]
> **Fill in all secrets in `/data/.env` before running `docker compose up`.** This file contains all sensitive credentials. Set its permissions to restrict access:
>
> ```bash
> sudo chmod 600 /data/.env
> ```

---

# Phase 4: Docker Compose Stack Deployment

This phase creates and launches all 9 containers as a single docker-compose stack.

---

## Step 4.1 — Create Docker Compose File

> [!NOTE]
> The production-ready compose file is available at [`docker-compose.yml`](file:///p:/Project/Server-Setup/docker-compose.yml). It includes pinned image versions, `mem_limit` enforcement, `name: homelab`, `depends_on` for Nginx, and removes `env_file` from services that don't need secrets. **Use the standalone file for deployment** — the inline version below is for reference only.

```bash
# Recommended: copy the pre-built file from the repo
sudo cp docker-compose.yml /data/docker-compose.yml
```

<details>
<summary>📄 Click to expand inline reference (may be behind the standalone file)</summary>

```bash
sudo tee /data/docker-compose.yml << 'COMPOSE'
# ============================================================
# Homelab Docker Compose Stack
# Server: Oracle Free Tier VM.Standard.A1.Flex (4 ARM OCPUs, 24 GB RAM)
# Reference: Deployment-Guide.md
#
# ── Before starting: ────────────────────────────────────────
#   1. Copy this file to /data/docker-compose.yml on the server
#   2. Create /data/.env and fill in all secrets (see Step 3.5)
#   3. Run: sudo chmod 600 /data/.env
#   4. Run: sudo chown ubuntu:ubuntu /data/docker-compose.yml /data/.env
#   5. Run: docker compose up -d
#
# ── Image version pinning (as of 2026-03-06): ──────────────
#   All images are pinned to specific stable versions.
#   To update, check Docker Hub / GHCR for newer ARM64 tags,
#   test in staging, then update the tag here.
# ============================================================

name: homelab

networks:
  internal-net:
    driver: bridge
    internal: true
  public-net:
    driver: bridge

services:

  # ──────────────── DATABASES ────────────────

  postgres:
    image: postgres:16-bookworm
    container_name: postgres
    restart: unless-stopped
    env_file: /data/.env
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: default_db
    command: >
      postgres
        -c shared_buffers=1GB
        -c work_mem=16MB
        -c maintenance_work_mem=256MB
        -c max_connections=100
    volumes:
      - /data/postgres:/var/lib/postgresql/data
      - /data/postgres-init:/docker-entrypoint-initdb.d:ro
      - /etc/localtime:/etc/localtime:ro
    networks:
      - internal-net
    mem_limit: 2560m
    deploy:
      resources:
        limits:
          memory: 2560M
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U admin"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

  mongo:
    image: mongo:7.0-jammy
    container_name: mongo
    restart: unless-stopped
    env_file: /data/.env
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_PASSWORD}
    volumes:
      - /data/mongo:/data/db
      - /etc/localtime:/etc/localtime:ro
    networks:
      - internal-net
    mem_limit: 2560m
    deploy:
      resources:
        limits:
          memory: 2560M
    healthcheck:
      test:
        [
          "CMD-SHELL",
          'mongosh --eval "db.runCommand({ping:1})" --quiet || exit 1',
        ]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

  qdrant:
    image: qdrant/qdrant:v1.16.3
    container_name: qdrant
    restart: unless-stopped
    env_file: /data/.env
    environment:
      QDRANT__SERVICE__API_KEY: ${QDRANT_API_KEY}
      QDRANT__HNSW_INDEX__ON_DISK: "true"
    volumes:
      - /data/qdrant:/qdrant/storage
      - /etc/localtime:/etc/localtime:ro
    networks:
      - internal-net
    mem_limit: 5120m
    deploy:
      resources:
        limits:
          memory: 5120M
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "wget --no-verbose --tries=1 --spider http://localhost:6333/healthz || exit 1",
        ]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 20s

  # ──────────────── AUTOMATION ────────────────

  n8n:
    image: n8nio/n8n:2.11.0
    container_name: n8n
    restart: unless-stopped
    env_file: /data/.env
    environment:
      NODE_OPTIONS: "--max-old-space-size=3584"
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: n8n_backend
      DB_POSTGRESDB_USER: admin
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      WEBHOOK_URL: ${N8N_WEBHOOK_URL}
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
    volumes:
      - /data/n8n:/home/node/.n8n
      - /etc/localtime:/etc/localtime:ro
    networks:
      - internal-net
      - public-net
    mem_limit: 4096m
    deploy:
      resources:
        limits:
          memory: 4096M
    depends_on:
      postgres:
        condition: service_healthy

  # ──────────────── WEB SERVER ────────────────

  nginx:
    image: nginx:1.28.2-alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - /data/nginx/conf.d:/etc/nginx/conf.d:ro
      - /data/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - /data/websites:/var/www/html:ro
      - /etc/localtime:/etc/localtime:ro
    networks:
      - public-net
    mem_limit: 256m
    deploy:
      resources:
        limits:
          memory: 256M
    depends_on:
      - n8n
      - portainer
      - homepage
      - jellyfin
      - syncthing

  # ──────────────── MANAGEMENT ────────────────

  portainer:
    image: portainer/portainer-ce:2.39.0
    container_name: portainer
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /data/portainer:/data
      - /etc/localtime:/etc/localtime:ro
    networks:
      - public-net
    mem_limit: 256m
    deploy:
      resources:
        limits:
          memory: 256M

  homepage:
    image: ghcr.io/gethomepage/homepage:v1.10.1
    container_name: homepage
    restart: unless-stopped
    volumes:
      - /data/homepage:/app/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /etc/localtime:/etc/localtime:ro
    networks:
      - public-net
    mem_limit: 128m
    deploy:
      resources:
        limits:
          memory: 128M

  # ──────────────── MEDIA & SYNC ────────────────

  jellyfin:
    image: lscr.io/linuxserver/jellyfin:10.11.6
    container_name: jellyfin
    restart: unless-stopped
    environment:
      PUID: 1000
      PGID: 1000
    volumes:
      - /data/jellyfin/config:/config
      - /data/media:/data/media:ro
      - /etc/localtime:/etc/localtime:ro
    networks:
      - public-net
    mem_limit: 2048m
    deploy:
      resources:
        limits:
          memory: 2048M

  syncthing:
    image: lscr.io/linuxserver/syncthing:v2.0.14-ls209
    container_name: syncthing
    restart: unless-stopped
    environment:
      PUID: 1000
      PGID: 1000
    ports:
      - "22000:22000/tcp"
      - "22000:22000/udp"
    volumes:
      - /data/syncthing/config:/config
      - /data/media/music:/data/media/music
      - /etc/localtime:/etc/localtime:ro
    networks:
      - public-net
    mem_limit: 512m
    deploy:
      resources:
        limits:
          memory: 512M
COMPOSE
```

</details>

---

## Step 4.2 — Create PostgreSQL Init Script

This script auto-creates the two databases on first boot.

> [!NOTE]
> Also available as a standalone file: [`postgres-init/init-databases.sql`](file:///p:/Project/Server-Setup/postgres-init/init-databases.sql)

```bash
# Recommended: copy from the repo
sudo cp postgres-init/init-databases.sql /data/postgres-init/
```

Or create it manually:

```bash
sudo mkdir -p /data/postgres-init

sudo tee /data/postgres-init/init-databases.sql << 'SQL'
CREATE DATABASE n8n_backend;
CREATE DATABASE project_data;
SQL
```

---

## Step 4.3 — Generate All Secrets

```bash
# Generate N8N Encryption Key (128-bit key, expressed as 32 hex characters = 16 random bytes)
openssl rand -hex 16

# Generate Qdrant API Key (256-bit key, expressed as 64 hex characters = 32 random bytes)
openssl rand -hex 32
```

Edit `/data/.env` and replace the placeholder values with the generated keys and your passwords:

```bash
sudo nano /data/.env
```

> [!CAUTION]
> **Save both generated keys permanently** (e.g., in a password manager). If you lose `N8N_ENCRYPTION_KEY` and recreate the container, all saved API credentials inside n8n become permanently undecryptable.

---

## Step 4.4 — Verify Secrets in .env File

> [!NOTE]
> All passwords and secrets are stored in `/data/.env` — **not** in `docker-compose.yml`. This keeps sensitive credentials out of the compose file and any related version control.

```bash
sudo nano /data/.env
```

Verify all placeholder values have been replaced:

- `POSTGRES_PASSWORD=` — a strong, unique password
- `MONGO_PASSWORD=` — a strong, unique password
- `N8N_ENCRYPTION_KEY=` — output from `openssl rand -hex 16`
- `QDRANT_API_KEY=` — output from `openssl rand -hex 32`
- `N8N_WEBHOOK_URL=` — your actual n8n subdomain (e.g., `https://n8n.yourdomain.com/`)

Then secure the file:

```bash
sudo chmod 600 /data/.env
```

---

## Step 4.5 — Launch the Stack

```bash
cd /data

# Ensure the compose file is readable by the docker group user (not just root).
# Files created with sudo tee are owned by root by default.
sudo chown ubuntu:ubuntu /data/docker-compose.yml /data/.env

docker compose up -d
```

Monitor startup:

```bash
# Watch all containers come up healthy
docker compose ps

# Watch real-time logs
docker compose logs -f

# Check individual container health
docker inspect --format='{{.State.Health.Status}}' postgres
docker inspect --format='{{.State.Health.Status}}' mongo
docker inspect --format='{{.State.Health.Status}}' qdrant
```

> [!NOTE]
> First launch may take 5–10 minutes as Docker pulls all ARM64 images (~8 GB total). Postgres must report `healthy` before n8n will start (n8n depends only on Postgres).

---

# Phase 5: Nginx Reverse Proxy Configuration

This phase configures Nginx to route subdomain traffic to each container.

> [!NOTE]
> **Why no HTTP-to-HTTPS redirect in Nginx?** HTTPS termination is handled entirely by the OCI Load Balancer (Phase 6). Nginx only ever sees plain HTTP from the LB. The OCI VCN Security List (Step 6.6) restricts port 80 access to the LB's subnet only, so external users cannot reach Nginx over plain HTTP directly. The LB enforces HTTPS externally.

---

## Step 5.1 — Create Main Nginx Config

> [!NOTE]
> All Nginx configuration files are available in the project repo under [`nginx/`](file:///p:/Project/Server-Setup/nginx/). You can copy the entire directory at once:

```bash
# Recommended: copy all configs from the repo
sudo cp nginx/nginx.conf /data/nginx/nginx.conf
sudo cp nginx/conf.d/*.conf /data/nginx/conf.d/
```

Or create the main config manually:

```bash
sudo tee /data/nginx/nginx.conf << 'NGINX'
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    # Custom MIME types for 3D assets (appended after mime.types so they ADD
    # to the default set rather than replacing it).
    types {
        model/gltf+json  gltf;
        model/gltf-binary glb;
    }
    default_type  application/octet-stream;

    sendfile        on;
    keepalive_timeout  65;
    client_max_body_size 1G;

    # Docker internal DNS resolver — required so Nginx re-resolves container IPs
    # after container restarts instead of caching a stale IP.
    resolver 127.0.0.11 valid=10s ipv6=off;

    # Global proxy headers
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    # OCI LB terminates SSL and forwards plain HTTP to Nginx, so $scheme is always 'http'.
    # The LB sends 'X-Forwarded-Proto: https' — $http_x_forwarded_proto preserves the
    # client's original protocol, which apps like n8n need for correct redirect URLs.
    proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;

    # Security headers
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    # Gzip (text-based only, NOT binary .glb)
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml model/gltf+json;
    gzip_min_length 256;

    # Trust OCI Load Balancer IP range
    set_real_ip_from 10.0.0.0/16;
    real_ip_header X-Forwarded-For;

    include /etc/nginx/conf.d/*.conf;
}
NGINX
```

---

## Step 5.2 — Create Health Check & Subdomain Configs

> [!NOTE]
> If you already copied all configs from the repo in Step 5.1, you can **skip this step** — all `.conf` files are already in place. The commands below are shown for manual creation.

```bash
# Health endpoint for OCI Load Balancer
# This is the default_server — catches ALL unmatched requests (bot scans, direct IP hits).
sudo tee /data/nginx/conf.d/health.conf << 'NGINX'
server {
    listen 80 default_server;
    server_name _;

    location /health {
        add_header Content-Type text/plain;
        access_log off;
        return 200 'OK';
    }

    # Silently drop all other unmatched requests (e.g., bot scans hitting the raw IP).
    location / {
        return 444;
    }
}
NGINX

# N8N — n8n.yourdomain.com
sudo tee /data/nginx/conf.d/n8n.conf << 'NGINX'
server {
    listen 80;
    server_name n8n.yourdomain.com;

    location / {
        proxy_pass http://n8n:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
NGINX

# Portainer — portainer.yourdomain.com
sudo tee /data/nginx/conf.d/portainer.conf << 'NGINX'
server {
    listen 80;
    server_name portainer.yourdomain.com;

    location / {
        proxy_pass http://portainer:9000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX

# Homepage Dashboard — home.yourdomain.com
sudo tee /data/nginx/conf.d/homepage.conf << 'NGINX'
server {
    listen 80;
    server_name home.yourdomain.com;

    location / {
        proxy_pass http://homepage:3000;
    }
}
NGINX

# Jellyfin — media.yourdomain.com
sudo tee /data/nginx/conf.d/jellyfin.conf << 'NGINX'
server {
    listen 80;
    server_name media.yourdomain.com;

    location / {
        proxy_pass http://jellyfin:8096;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX

# Syncthing — sync.yourdomain.com
sudo tee /data/nginx/conf.d/syncthing.conf << 'NGINX'
server {
    listen 80;
    server_name sync.yourdomain.com;

    location / {
        proxy_pass http://syncthing:8384;
    }
}
NGINX

# Portfolio / Websites — yourdomain.com / www.yourdomain.com
sudo tee /data/nginx/conf.d/portfolio.conf << 'NGINX'
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;

    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
NGINX
```

---

## Step 5.3 — Reload Nginx

```bash
docker exec nginx nginx -t          # Test config for errors
docker exec nginx nginx -s reload   # Apply new config without downtime
```

---

## Step 5.4 — Deploy Website Files

Nginx serves your portfolio/static site from `/data/websites/` on the host (mapped to `/var/www/html` inside the container). You must place your web files there before the portfolio site will display anything.

**Option A — Copy from local machine (via SCP through the Bastion tunnel):**

> [!NOTE]
> Bastion sessions don't support direct SCP. You must create a port-forwarding session instead: in the Bastion console, create a **Port Forwarding Session** targeting the VM on port 22, then use that tunnel for SCP.

```bash
# From your local machine, copy your build files to the server
scp -i ~/.ssh/id_ed25519 -P <TUNNEL_PORT> -r ./dist/* ubuntu@127.0.0.1:/tmp/website/

# On the server, move them into place
sudo cp -r /tmp/website/* /data/websites/
sudo chmod -R 755 /data/websites/
```

**Option B — Clone or pull from Git:**

```bash
# On the server
git clone https://github.com/yourusername/your-portfolio.git /tmp/portfolio
sudo cp -r /tmp/portfolio/dist/* /data/websites/
sudo chmod -R 755 /data/websites/
```

Verify the site is live:

```bash
curl -I http://localhost/
# Should return 200 if an index.html exists in /data/websites/
```

---

# Phase 6: OCI Load Balancer & DNS

This phase exposes your server to the internet with HTTPS via OCI's free Load Balancer and SSL certificates.

---

## Step 6.1 — Create OCI Load Balancer

1. Go to **Networking → Load Balancers → Create Load Balancer**.
2. **Name:** `homelab-lb`. **Shape:** Flexible (free tier). **Min/Max Bandwidth:** 10 Mbps.
3. **Subnet:** Select the public subnet in your `homelab-vcn`.
4. Click **Next**.

---

## Step 6.2 — Configure Backend Set

1. **Backend Set Name:** `homelab-backend`.
2. **Health Check:** HTTP, Port `80`, Path `/health`.
3. Click **Next**.
4. **Add Backend:** Select the `homelab` instance, Port `80`.
5. Click **Next**.

---

## Step 6.3 — Create OCI Certificate

1. Go to **Identity & Security → Certificates → Create Certificate**.
2. Choose **Let's Encrypt** or **Imported** (if you have your own).
3. Add your domain: `yourdomain.com` and `*.yourdomain.com` (wildcard).
4. Complete the DNS challenge validation.

---

## Step 6.4 — Configure LB Listeners

**Listener 1 — HTTP (Port 80) for health checks and backend communication:**

1. Go to **Listeners → Create Listener**.
2. **Name:** `http-listener`. **Protocol:** HTTP. **Port:** 80.
3. **Backend Set:** `homelab-backend`.
4. Click **Create**.

> [!NOTE]
> The port 80 HTTP listener is required for the OCI LB backend health check to reach Nginx. Without it, the LB cannot verify the backend is healthy and will mark it as DOWN. This listener is protected from public HTTPS traffic by the VCN Security List (Step 6.6).

**Listener 2 — HTTPS (Port 443) for public traffic:**

1. Back in **Listeners → Create Listener**.
2. **Name:** `https-listener`. **Protocol:** HTTPS. **Port:** 443.
3. **SSL Certificate:** Select the certificate from Step 6.3.
4. **Backend Set:** `homelab-backend`.
5. Click **Create**.

---

## Step 6.5 — Update LB Idle Timeout

1. Go to the Load Balancer → **Edit Details**.
2. Set **Idle Timeout** to `3600` seconds.
3. Click **Save**.

---

## Step 6.6 — Update VCN Security List for LB

Now that the LB exists, lock down Port 80:

1. Go to **Networking → VCN → Security Lists → Default Security List**.
2. Edit the Port 80 ingress rule you created in Step 1.2.
3. Change Source CIDR from any placeholder to the **LB's Subnet CIDR** (e.g., `10.0.0.0/24`).
4. Save.

---

## Step 6.7 — Configure DNS

1. Go to **Networking → DNS Management → Create Zone**.
2. **Zone Name:** `yourdomain.com`.
3. Add these DNS records:

| Record Type | Name  | Value            |
| ----------- | ----- | ---------------- |
| A           | `@`   | `<LB Public IP>` |
| A           | `*`   | `<LB Public IP>` |
| CNAME       | `www` | `yourdomain.com` |

4. Point your domain registrar's nameservers to OCI's nameservers (shown in the Zone details).
5. Wait for DNS propagation (5 min – 48 hours).

---

## Step 6.8 — Verify HTTPS

```bash
curl -I https://yourdomain.com/health
# Should return: HTTP/2 200
```

Visit each subdomain in your browser:

- `https://n8n.yourdomain.com`
- `https://portainer.yourdomain.com`
- `https://home.yourdomain.com`
- `https://media.yourdomain.com`
- `https://sync.yourdomain.com`

---

# Phase 7: Container Configuration & First-Time Setup

This phase walks through the initial setup of each container after they are live.

---

## Step 7.1 — Portainer (Container Management)

**Access:** `https://portainer.yourdomain.com`

1. On first visit, create an **admin account** with a strong password.
2. Click **Get Started** → Select **Local** environment.
3. **Enable 2FA:** Go to **My Account → Security → Enable 2FA** using an authenticator app.
4. **How to Use:**
   - Dashboard shows all running containers, images, volumes, and networks.
   - Click any container to view logs, restart, or access its console.
   - Use **Stacks** to manage docker-compose files visually.

---

## Step 7.2 — N8N (Workflow Automation)

**Access:** `https://n8n.yourdomain.com`

1. On first visit, create your **owner account** (email + password).
2. **How to Use:**
   - Click **+ New Workflow** to create automation pipelines.
   - Add nodes by clicking **+** in the canvas (HTTP, PostgreSQL, MongoDB, AI, Webhook, etc.).
   - Connect to your databases using these internal hostnames (Docker DNS):
     - PostgreSQL: `postgres:5432` (user: `admin`)
     - MongoDB: `mongo:27017` (user: `admin`)
     - Qdrant: `qdrant:6333` (API key: value of `QDRANT_API_KEY` from `.env`)
   - Set webhook URL to `https://n8n.yourdomain.com/webhook/...`
   - Toggle workflows **Active** to make them run automatically.

---

## Step 7.3 — Homepage (Dashboard)

**Access:** `https://home.yourdomain.com`

1. Homepage reads its configuration from files in `/data/homepage/` on the server.

> [!NOTE]
> Pre-built config files are available in the project repo under [`homepage/`](file:///p:/Project/Server-Setup/homepage/). Copy them to the server:
>
> ```bash
> sudo cp homepage/*.yaml /data/homepage/
> ```

2. The config files are:
   - `services.yaml` — Define your service links, icons, and Docker widgets.
   - `settings.yaml` — Customize theme (dark), title, layout.
   - `docker.yaml` — Configure Docker socket integration for live container status.
3. **Example `services.yaml`:**

```yaml
- Infrastructure:
    - Portainer:
        href: https://portainer.yourdomain.com
        icon: portainer.png
        description: Container Management
    - N8N:
        href: https://n8n.yourdomain.com
        icon: n8n.png
        description: Workflow Automation

- Media:
    - Jellyfin:
        href: https://media.yourdomain.com
        icon: jellyfin.png
        description: Music Streaming
    - Syncthing:
        href: https://sync.yourdomain.com
        icon: syncthing.png
        description: File Sync
```

3. **Example `docker.yaml`:**

```yaml
my-docker:
  socket: /var/run/docker.sock
```

---

## Step 7.4 — Jellyfin (Music Streaming)

**Access:** `https://media.yourdomain.com`

1. Complete the **Setup Wizard**: choose language, create admin user.
2. **Add Music Library:**
   - Click **Add Media Library** → Type: **Music**.
   - Folder: `/data/media/music` (this is where Syncthing will deliver files).
   - Click **OK**.
3. **Disable Audio Transcoding:**
   - Go to **Dashboard → Playback → Transcoding**.
   - Uncheck **Enable audio transcoding**.
   - This forces **Direct Play** — saves CPU and preserves audio quality.
4. **How to Use:**
   - Open Jellyfin in any browser or phone app to stream music.
   - Library auto-updates when Syncthing adds new songs.

---

## Step 7.5 — Syncthing (Phone-to-Server File Sync)

**Access:** `https://sync.yourdomain.com`

1. On first visit, go to **Actions → Settings → GUI**.
   - Set a **GUI Authentication User** and **Password**. Save.
2. **Fix the Host Header (required for reverse-proxy access):**
   - SSH into the server. Edit Syncthing's config:

   ```bash
   sudo nano /data/syncthing/config/config.xml
   ```

   - Find the `<gui>` section and add:

   ```xml
   <insecureSkipHostcheck>true</insecureSkipHostcheck>
   ```

   > [!WARNING]
   > `insecureSkipHostcheck` disables Syncthing's CSRF host header check — this is required when accessing via a reverse proxy because the proxy rewrites the `Host` header. This is safe **only if** you have set a strong GUI password (Step 1 above) and Syncthing's web UI is not exposed without authentication.
   - Restart: `docker restart syncthing`

3. **Disable Local Discovery:**
   - Go to **Actions → Settings → Connections**.
   - Uncheck **Local Discovery**. Save.
4. **Connect Your Phone:**
   - Install **Syncthing** app on your Android phone.
   - On your phone app, note the **Device ID** (Settings → Show ID).
   - On the web UI, click **Add Remote Device** → paste the phone's Device ID.
   - On your phone, accept the connection request.
5. **Share a Folder:**
   - On your phone, go to the Music folder → **Share with** the server device.
   - On the server web UI, accept the folder share → set the path to `/data/media/music`.
   - Songs will now auto-sync from your phone to the server, and Jellyfin will detect them.

---

## Step 7.6 — Databases (Internal Access Only)

The databases are **not exposed to the internet** — they are on `internal-net` only. Access them through:

**From n8n workflows:** Use Docker service names as hostnames:

| Database   | Hostname   | Port    | Auth                                  |
| ---------- | ---------- | ------- | ------------------------------------- |
| PostgreSQL | `postgres` | `5432`  | `admin` / your password               |
| MongoDB    | `mongo`    | `27017` | `admin` / your password               |
| Qdrant     | `qdrant`   | `6333`  | API key: `QDRANT_API_KEY` from `.env` |

**From SSH (emergency debugging):**

```bash
# PostgreSQL
docker exec -it postgres psql -U admin -d project_data

# MongoDB
docker exec -it mongo mongosh -u admin -p YOUR_PASSWORD

# Qdrant REST API (requires API key)
docker exec -it qdrant wget -qO- --header="api-key: YOUR_QDRANT_API_KEY" http://localhost:6333/collections
```

---

# Phase 8: Post-Deployment Hardening & Maintenance

This phase covers ongoing operations, backups, monitoring, and updates.

---

## Step 8.1 — Set Up OCI Monitoring Alarms

1. Go to **Observability → Alarms → Create Alarm**.
2. Create alarms for:
   - **CPU > 80%** sustained for 5 minutes.
   - **Memory > 90%** sustained for 5 minutes.
3. Set notification to your email via **ONS (OCI Notification Service)**.

---

## Step 8.2 — Configure OCI Logging

1. Go to **Observability → Logging → Logs → Enable Service Log**.
2. Select the compute instance. Log type: **Custom**. Source: `journald`.
3. Logs from all Docker containers will flow into OCI Logging automatically.

---

## Step 8.3 — Set Up Automated Backups

**Option A — OCI Console (Manual scheduling):**

1. Go to **Storage → Block Volumes → homelab-data**.
2. Click **Create Backup**. Name: `weekly-backup`.
3. Repeat weekly or set a reminder.

**Option B — Automated via Cron (Recommended):**

```bash
# Install OCI CLI
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"

# Configure CLI
oci setup config

# Create backup script (or copy from repo: sudo cp scripts/backup-data-volume.sh /usr/local/bin/)
sudo tee /usr/local/bin/backup-data-volume.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
VOLUME_OCID="ocid1.volume.oc1.REGION.YOUR_VOLUME_OCID"
BACKUP_NAME="auto-backup-$(date +%Y%m%d)"
LOG_FILE="/var/log/backup-data-volume.log"
echo "[$(date)] Starting backup: ${BACKUP_NAME}" >> "${LOG_FILE}"
if oci bv backup create --volume-id "${VOLUME_OCID}" --display-name "${BACKUP_NAME}" --type INCREMENTAL >> "${LOG_FILE}" 2>&1; then
    echo "[$(date)] Backup completed successfully: ${BACKUP_NAME}" >> "${LOG_FILE}"
else
    echo "[$(date)] ERROR: Backup failed for ${BACKUP_NAME}" >> "${LOG_FILE}"
    exit 1
fi
SCRIPT

sudo chmod +x /usr/local/bin/backup-data-volume.sh

# Schedule weekly backup every Sunday at 3 AM
(crontab -l 2>/dev/null; echo "0 3 * * 0 /usr/local/bin/backup-data-volume.sh") | crontab -
```

**Option C — Test Restore (Required Before Going Live):**

> [!IMPORTANT]
> **Always test a restore before you go live.** A backup you have never restored is an untested backup. Run a restore test at least once while the server is still empty to confirm the process works end-to-end.

```bash
# 1. List your backups
oci bv backup list --compartment-id <COMPARTMENT_OCID>

# 2. Create a restore volume from a backup
oci bv volume create \
  --availability-domain <AD> \
  --compartment-id <COMPARTMENT_OCID> \
  --source-details '{"type": "volumeBackup", "id": "<BACKUP_OCID>"}' \
  --display-name "restore-test"

# 3. Attach the restored volume to the instance (follow Step 1.4 again) and mount it.
# 4. Verify your /data directory contents are intact.
# 5. Detach and delete the test volume once confirmed.
```

---

## Step 8.4 — Update Containers

```bash
cd /data

# Pull latest images
docker compose pull

# Recreate only containers with new images
docker compose up -d

# Clean up old unused images
docker image prune -f
```

> [!WARNING]
> Before updating, verify that the new image versions don't contain breaking changes (especially for PostgreSQL and MongoDB major version upgrades).

---

## Step 8.5 — Useful Operational Commands

```bash
# View all container status
docker compose ps

# View logs for a specific container
docker compose logs -f n8n

# Restart a single container
docker compose restart jellyfin

# Access a container shell
docker exec -it nginx sh

# Check system resources
htop
df -h /data
free -h

# Check Docker disk usage
docker system df
```

---

# Quick Reference Card

| Service        | URL                                | Internal Address   |
| -------------- | ---------------------------------- | ------------------ |
| Portfolio      | `https://yourdomain.com`           | Nginx static files |
| N8N            | `https://n8n.yourdomain.com`       | `n8n:5678`         |
| Portainer      | `https://portainer.yourdomain.com` | `portainer:9000`   |
| Dashboard      | `https://home.yourdomain.com`      | `homepage:3000`    |
| Jellyfin       | `https://media.yourdomain.com`     | `jellyfin:8096`    |
| Syncthing      | `https://sync.yourdomain.com`      | `syncthing:8384`   |
| Syncthing Sync | Direct (port 22000)                | `syncthing:22000`  |
| PostgreSQL     | Internal only                      | `postgres:5432`    |
| MongoDB        | Internal only                      | `mongo:27017`      |
| Qdrant         | Internal only                      | `qdrant:6333`      |
