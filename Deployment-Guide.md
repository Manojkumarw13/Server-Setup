# 🏠 Your Server Setup — The Complete Beginner's Handbook

> **What are we building?** A personal cloud server on Oracle's free tier that hosts 9 apps — databases, a website, music streaming, file sync, automation workflows, and a management dashboard — all accessible via `yourdomain.com` subdomains with HTTPS.

---

# 📖 Chapter 1: What Is All This Stuff? (Jargon Buster)

Before touching any file, let's learn the vocabulary. Every term below will appear in your files.

| Term                     | Real-World Analogy                                                                                                                                  |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Server**               | A computer that's always on, waiting to serve files/apps to anyone who asks. Your Oracle VM is this computer.                                       |
| **VM (Virtual Machine)** | A pretend computer running inside a real computer. Oracle gives you one for free.                                                                   |
| **ARM / aarch64**        | The type of processor (like Apple M-series chips). Your Oracle VM uses ARM, so all software must be ARM-compatible.                                 |
| **SSH**                  | A secure tunnel to type commands on your server from your laptop. Like a remote control for a computer.                                             |
| **Bastion**              | A security guard that sits between you and your server. You can't SSH directly — you go through the Bastion first.                                  |
| **Docker**               | A tool that runs apps in isolated "boxes" (containers). Each app gets its own box with its own stuff, so they don't interfere with each other.      |
| **Container**            | One isolated box running one app. You have 9 containers.                                                                                            |
| **Docker Compose**       | A recipe file (`.yml`) that tells Docker: "create these 9 containers with these settings." One command starts everything.                           |
| **Image**                | A pre-built template for a container. Like a frozen meal — Docker "microwaves" (runs) it into a live container.                                     |
| **Volume**               | A folder on your server that a container can read/write. Without volumes, data is lost when a container restarts.                                   |
| **Network (Docker)**     | A private communication channel between containers. `internal-net` = databases only talk to each other. `public-net` = apps the internet can reach. |
| **Nginx**                | A traffic cop (reverse proxy). When someone visits `n8n.yourdomain.com`, Nginx forwards them to the n8n container.                                  |
| **Reverse Proxy**        | A middleman that receives all web traffic and routes it to the right app based on the domain name.                                                  |
| **Load Balancer (LB)**   | Oracle's front door. It receives HTTPS traffic from the internet and passes it (as HTTP) to your Nginx. It also handles SSL certificates.           |
| **SSL / HTTPS**          | Encryption that makes websites secure (the 🔒 in your browser). The OCI Load Balancer handles this for you.                                         |
| **DNS**                  | The internet's phone book. It translates `yourdomain.com` → your server's IP address.                                                               |
| **VCN**                  | Virtual Cloud Network — Oracle's private network that your server lives inside. Like a gated community.                                             |
| **Security List**        | The gate rules for your VCN. "Allow traffic on port 80 from the Load Balancer only."                                                                |
| **Port**                 | A numbered door on your server. Port 80 = web traffic. Port 22 = SSH. Port 5432 = PostgreSQL.                                                       |
| **iSCSI**                | A way to connect a separate hard drive to your server over a network cable. Your 150 GB data drive connects this way.                               |
| **Block Volume**         | Oracle's name for an extra hard drive you can attach to your VM.                                                                                    |
| **Swap**                 | Using hard drive space as fake RAM when real RAM runs out. A safety net.                                                                            |
| **`.env` file**          | A text file holding secrets (passwords, API keys). Apps read from it so passwords aren't written in the main config.                                |
| **YAML (`.yaml`)**       | A human-readable config format using indentation. Used by Docker Compose and Homepage.                                                              |
| **SQL**                  | The language databases understand. Your init script uses SQL to create databases.                                                                   |
| **Cron**                 | A built-in scheduler on Linux. "Run this backup script every Sunday at 3 AM."                                                                       |
| **`sudo`**               | "Super User DO" — gives you admin permission for one command. Like saying "pretty please" to Linux.                                                 |
| **`tee`**                | A command that writes text to a file. `sudo tee /data/.env` = "write this text into `/data/.env` as admin."                                         |
| **`chmod`**              | Changes who can read/write/execute a file. `chmod 600` = "only the owner can read/write this."                                                      |
| **`chown`**              | Changes who owns a file. `chown ubuntu:ubuntu` = "make the ubuntu user the owner."                                                                  |

---

# 📁 Chapter 2: Your Files — What Each One Does

## 2.1 The Big Picture

Your project is like a blueprint packet for building a house. Each file is a different page of instructions:

```
Server-Setup/
├── docker-compose.yml          ← 🏗️ The master blueprint (defines ALL 9 apps)
├── .env                        ← 🔑 The keychain (all passwords & secrets)
├── daemon.json                 ← ⚙️ Docker engine settings
├── Deployment-Guide.md         ← 📘 The instruction manual (what you're reading now)
├── Setup.md                    ← 📋 Architecture summary (quick reference)
├── nginx/
│   ├── nginx.conf              ← 🚦 Traffic cop master config
│   └── conf.d/
│       ├── health.conf         ← 💚 "I'm alive" check for Oracle
│       ├── n8n.conf            ← 🔀 Route n8n.yourdomain.com → n8n app
│       ├── portainer.conf      ← 🔀 Route portainer.yourdomain.com → portainer
│       ├── homepage.conf       ← 🔀 Route home.yourdomain.com → dashboard
│       ├── jellyfin.conf       ← 🔀 Route media.yourdomain.com → jellyfin
│       ├── syncthing.conf      ← 🔀 Route sync.yourdomain.com → syncthing
│       └── portfolio.conf      ← 🔀 Route yourdomain.com → your website
├── homepage/
│   ├── services.yaml           ← 📋 Dashboard: which apps to show
│   ├── settings.yaml           ← 🎨 Dashboard: theme & layout
│   └── docker.yaml             ← 🔌 Dashboard: Docker connection
├── postgres-init/
│   └── init-databases.sql      ← 🗄️ Auto-create databases on first boot
├── scripts/
│   └── backup-data-volume.sh   ← 💾 Weekly backup automation
└── websites/
    └── index.html              ← 🌐 Placeholder "Coming Soon" page
```

---

## 2.2 File-by-File Deep Dive

### 📄 `docker-compose.yml` — The Master Blueprint

**What it is:** A YAML recipe that defines all 9 apps (containers) your server will run.

**Where it goes on the server:** `/data/docker-compose.yml`

**Line-by-line breakdown:**

| Lines                    | What It Does                                    | Plain English                                                                     |
| ------------------------ | ----------------------------------------------- | --------------------------------------------------------------------------------- |
| `name: homelab`          | Sets the project name                           | All containers will be prefixed with "homelab" no matter what folder you run from |
| `networks: internal-net` | Creates a private network with `internal: true` | Databases live here — invisible to the internet                                   |
| `networks: public-net`   | Creates a public network                        | Apps like Nginx, n8n, Jellyfin live here — can talk to the internet               |

**The 9 Services (Apps):**

| #   | Service       | Image                                  | RAM    | Network  | Purpose                           |
| --- | ------------- | -------------------------------------- | ------ | -------- | --------------------------------- |
| 1   | **postgres**  | `postgres:16-bookworm`                 | 2.5 GB | internal | SQL database for projects & n8n   |
| 2   | **mongo**     | `mongo:7.0-jammy`                      | 2.5 GB | internal | Document database for projects    |
| 3   | **qdrant**    | `qdrant/qdrant:v1.16.3`                | 5 GB   | internal | AI vector database for embeddings |
| 4   | **n8n**       | `n8nio/n8n:2.11.0`                     | 4 GB   | both     | Workflow automation (like Zapier) |
| 5   | **nginx**     | `nginx:1.28.2-alpine`                  | 256 MB | public   | Traffic cop / web server          |
| 6   | **portainer** | `portainer/portainer-ce:2.39.0`        | 256 MB | public   | Visual Docker management          |
| 7   | **homepage**  | `ghcr.io/gethomepage/homepage:v1.10.1` | 128 MB | public   | Dashboard with all your app links |
| 8   | **jellyfin**  | `linuxserver/jellyfin:10.11.6`         | 2 GB   | public   | Music streaming (like Spotify)    |
| 9   | **syncthing** | `linuxserver/syncthing:v2.0.14`        | 512 MB | public   | Sync files from phone to server   |

**Key patterns you'll see repeated in every service:**

- `restart: unless-stopped` → "If this app crashes, restart it automatically. Only stay stopped if I manually stopped it."
- `volumes:` → Folders shared between host and container (data survives restarts)
- `env_file: /data/.env` → "Read passwords from this file"
- `mem_limit: 2560m` → "Never use more than 2.5 GB RAM"
- `healthcheck:` → Docker periodically checks if the app is alive. If it fails, Docker restarts it.
- `/etc/localtime:/etc/localtime:ro` → Sync the container's clock with the server's clock (read-only)
- `depends_on:` → "Don't start me until these other containers are running"

---

### 📄 `.env` — The Keychain

**What it is:** A plain text file holding every password and secret. Apps read from this instead of having passwords written directly in config files.

**Where it goes:** `/data/.env`

**⚠️ Critical:** You must replace ALL placeholder values before deploying!

| Variable             | What It Is                                     | How to Generate                                                    |
| -------------------- | ---------------------------------------------- | ------------------------------------------------------------------ |
| `TZ=Asia/Kolkata`    | Timezone setting                               | Already set for India                                              |
| `POSTGRES_PASSWORD`  | Database password for PostgreSQL               | Make up a strong password (20+ chars, letters + numbers + symbols) |
| `MONGO_PASSWORD`     | Database password for MongoDB                  | Make up a different strong password                                |
| `N8N_ENCRYPTION_KEY` | Key that encrypts saved credentials inside n8n | Run: `openssl rand -hex 16` on the server                          |
| `QDRANT_API_KEY`     | API key to access the vector database          | Run: `openssl rand -hex 32` on the server                          |
| `N8N_WEBHOOK_URL`    | The public URL for n8n webhooks                | `https://n8n.yourdomain.com/` (replace with your actual domain)    |

---

### 📄 `daemon.json` — Docker Engine Settings

**What it is:** Tells the Docker engine itself (not individual containers) how to behave.

**Where it goes:** `/etc/docker/daemon.json`

| Setting                         | What It Does                                                                                |
| ------------------------------- | ------------------------------------------------------------------------------------------- |
| `"log-driver": "journald"`      | Send all container logs to Linux's built-in log system (instead of writing giant log files) |
| `"data-root": "/data/docker"`   | Store all Docker data on the big 150 GB drive instead of the small 50 GB boot drive         |
| `"dns": ["8.8.8.8", "1.1.1.1"]` | Use Google and Cloudflare DNS servers so containers can look up website addresses           |

---

### 📄 `nginx/nginx.conf` — Traffic Cop Master Config

**What it is:** The main settings file for Nginx. It defines global behavior that applies to ALL websites.

**Where it goes:** `/data/nginx/nginx.conf`

| Setting                            | What It Does                                                                            |
| ---------------------------------- | --------------------------------------------------------------------------------------- |
| `worker_processes auto`            | "Use as many workers as there are CPU cores" (4 on your server)                         |
| `worker_connections 1024`          | Each worker can handle 1024 simultaneous visitors                                       |
| `client_max_body_size 1G`          | Allow file uploads up to 1 GB                                                           |
| `resolver 127.0.0.11`              | Use Docker's internal "phone book" so Nginx always finds containers even after restarts |
| `proxy_set_header` lines           | Pass visitor info (IP address, HTTPS status) to the backend apps                        |
| Security headers                   | Prevent clickjacking, MIME-type sniffing, and referrer leaking                          |
| `gzip on`                          | Compress text files before sending (faster loading for visitors)                        |
| `set_real_ip_from 10.0.0.0/16`     | Trust the Load Balancer's IP so Nginx logs show real visitor IPs                        |
| `include /etc/nginx/conf.d/*.conf` | "Load all the individual site configs from the conf.d folder"                           |

---

### 📄 `nginx/conf.d/*.conf` — Individual Site Routes (7 files)

Each `.conf` file tells Nginx: "When someone visits THIS domain, send them to THIS container."

| File             | Domain                     | Sends Traffic To                 | Special Features                                          |
| ---------------- | -------------------------- | -------------------------------- | --------------------------------------------------------- |
| `health.conf`    | Any unmatched request      | Returns "OK" or drops connection | Oracle LB pings `/health` to check if server is alive     |
| `n8n.conf`       | `n8n.yourdomain.com`       | `n8n:5678`                       | WebSocket support (for real-time updates), 1-hour timeout |
| `portainer.conf` | `portainer.yourdomain.com` | `portainer:9000`                 | WebSocket support, 24-hour timeout                        |
| `homepage.conf`  | `home.yourdomain.com`      | `homepage:3000`                  | Simple proxy                                              |
| `jellyfin.conf`  | `media.yourdomain.com`     | `jellyfin:8096`                  | WebSocket + no buffering (for smooth music streaming)     |
| `syncthing.conf` | `sync.yourdomain.com`      | `syncthing:8384`                 | Simple proxy                                              |
| `portfolio.conf` | `yourdomain.com`           | Static HTML files                | Serves files from `/var/www/html/` directly               |

---

### 📄 `homepage/*.yaml` — Dashboard Configuration (3 files)

**`services.yaml`** — Lists every app on your dashboard with icons, links, and live Docker status widgets.

**`settings.yaml`** — Sets the theme to dark mode, title to "Homelab Dashboard", and arranges sections in rows.

**`docker.yaml`** — Tells Homepage to connect to the Docker socket to show real-time container status (running/stopped).

**Where they go:** `/data/homepage/`

---

### 📄 `postgres-init/init-databases.sql` — Database Creator

**What it is:** A tiny SQL script that runs once — the very first time PostgreSQL starts. It creates two extra databases: `n8n_backend` (for n8n) and `project_data` (for your projects).

**Where it goes:** `/data/postgres-init/init-databases.sql`

---

### 📄 `scripts/backup-data-volume.sh` — Backup Robot

**What it is:** A bash script that creates a backup (snapshot) of your entire 150 GB data drive using Oracle's CLI tool. It runs automatically every Sunday at 3 AM via cron.

**Where it goes:** `/usr/local/bin/backup-data-volume.sh`

---

### 📄 `websites/index.html` — Placeholder Website

**What it is:** A beautiful dark-themed "Coming Soon" page with purple gradient text and glowing background effects. This is what visitors see at `yourdomain.com` until you replace it with your real portfolio.

**Where it goes:** `/data/websites/index.html`

---

# 🗺️ Chapter 3: The Where — File Placement Map

Every file from your PC goes to a specific location on the server:

| File on Your PC                    | Location on Server         | How to Get It There                         |
| ---------------------------------- | -------------------------- | ------------------------------------------- |
| `docker-compose.yml`               | `/data/docker-compose.yml` | Copy via repo clone or paste via `sudo tee` |
| `.env`                             | `/data/.env`               | Copy + edit with real passwords             |
| `daemon.json`                      | `/etc/docker/daemon.json`  | Copy before starting Docker                 |
| `nginx/nginx.conf`                 | `/data/nginx/nginx.conf`   | Copy entire nginx folder                    |
| `nginx/conf.d/*.conf` (7 files)    | `/data/nginx/conf.d/`      | Copy entire conf.d folder                   |
| `homepage/*.yaml` (3 files)        | `/data/homepage/`          | Copy entire homepage folder                 |
| `postgres-init/init-databases.sql` | `/data/postgres-init/`     | Copy before first PostgreSQL boot           |
| `scripts/backup-data-volume.sh`    | `/usr/local/bin/`          | Copy + make executable                      |
| `websites/index.html`              | `/data/websites/`          | Copy or replace later with real site        |

---

# 🚀 Chapter 4: Step-by-Step Deployment

## Phase 1: Oracle Cloud Account & Infrastructure

> **What you're doing:** Creating your free cloud computer and its virtual network.

### Step 1.1 — Create Oracle Cloud Account

1. Open your browser. Go to [cloud.oracle.com](https://cloud.oracle.com)
2. Click the **Sign Up** button
3. Fill in: email, name, country
4. **Choose your Home Region** — pick the one closest to you (e.g., `ap-mumbai-1` for India)

> ⚠️ **Your Home Region is PERMANENT.** You can never change it. Choose carefully!

5. Enter a credit/debit card (verification only — you will NOT be charged)
6. Wait for the activation email (1–30 minutes)
7. Sign in at [cloud.oracle.com](https://cloud.oracle.com)

### Step 1.2 — Create VCN (Your Private Network)

1. In the console, click the ☰ hamburger menu → **Networking** → **Virtual Cloud Networks**
2. Click **Start VCN Wizard** → **Create VCN with Internet Connectivity** → **Start**
3. Name it: `homelab-vcn`. Leave everything else default. Click **Next** → **Create**
4. Once created, click into the VCN → click **Security Lists** → **Default Security List**
5. Click **Add Ingress Rules** and create these 3 rules:

| Source CIDR                              | Port    | Protocol | Purpose                        |
| ---------------------------------------- | ------- | -------- | ------------------------------ |
| `10.0.0.0/24` (update after LB creation) | `80`    | TCP      | Web traffic from Load Balancer |
| `0.0.0.0/0`                              | `22000` | TCP      | Syncthing file sync            |
| `0.0.0.0/0`                              | `22000` | UDP      | Syncthing file sync            |

6. **DELETE** the default SSH rule (Port 22 from `0.0.0.0/0`) — Bastion replaces this

### Step 1.3 — Create the VM

1. ☰ → **Compute** → **Instances** → **Create Instance**
2. **Name:** `homelab`
3. **Image:** Click **Change Image** → search `Ubuntu` → select **Canonical Ubuntu 24.04 (aarch64)**
4. **Shape:** Click **Change Shape** → select **VM.Standard.A1.Flex** → set **4 OCPUs, 24 GB RAM**
5. **Networking:** Select your `homelab-vcn`, public subnet. Check "Assign a public IPv4 address"
6. **Boot Volume:** Click **Specify custom boot volume size** → set to **50 GB**
7. **SSH Key:** Click **Paste public keys** → paste your SSH public key
   - Don't have one? On your PC, open terminal and type: `ssh-keygen -t ed25519` then press Enter through all prompts. Copy the contents of `~/.ssh/id_ed25519.pub`
8. Click **Create**. Wait for status = **Running**. Note the **Public IP address**

### Step 1.4 — Create 150 GB Data Drive

1. ☰ → **Storage** → **Block Volumes** → **Create Block Volume**
2. **Name:** `homelab-data`. **Size:** `150` GB
3. **Availability Domain:** Must match your VM's AD
4. Click **Create**
5. Go to **Compute** → **Instances** → **homelab** → **Attached Block Volumes** → **Attach Block Volume**
6. Select `homelab-data`. Type: **iSCSI**. Click **Attach**
7. Click the ⋮ dots → **iSCSI Commands & Information** → Copy the **Connect** commands (you'll need them in Phase 2)

### Step 1.5 — Create Bastion (Secure SSH)

1. ☰ → **Identity & Security** → **Bastion** → **Create Bastion**
2. **Name:** `homelab-bastion`. Select `homelab-vcn` public subnet
3. **CIDR Allowlist:** Go to [whatismyip.com](https://whatismyip.com), copy your IP, enter it as `YOUR_IP/32`
4. Click **Create**

### Step 1.6 — Enable Bastion Plugin on VM

1. ☰ → **Compute** → **Instances** → **homelab** → **Oracle Cloud Agent** tab
2. Find **Bastion** → Toggle it **ON**
3. Wait 5 minutes

### Step 1.7 — Connect to Your Server!

1. ☰ → **Bastion** → **homelab-bastion** → **Create Session**
2. Type: **Managed SSH Session**. Instance: `homelab`. Username: `ubuntu`. Upload your SSH public key
3. Click **Create Session**
4. Once active, click ⋮ → **Copy SSH Command**
5. Open your PC's terminal. Paste the command. Press Enter. **You're now on the server!** 🎉

---

## Phase 2: Preparing the Server

> **What you're doing:** Setting up storage, creating folders, and tuning the OS.

### Step 2.1 — Update the System

Type each line below into the terminal, then press Enter:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget gnupg lsb-release ca-certificates
sudo hostnamectl set-hostname homelab
```

### Step 2.2 — Connect the 150 GB Drive

Paste the 3 iSCSI commands you copied from Step 1.4. Then verify:

```bash
lsblk
```

You should see a new ~150 GB disk (e.g., `/dev/sdb`)

### Step 2.3 — Format & Mount the Drive

```bash
sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /data
sudo blkid /dev/sdb
```

Note the `UUID=xxxx-xxxx-xxxx` from the output. Then:

```bash
echo 'UUID=xxxx-xxxx-xxxx /data ext4 defaults,nofail,_netdev 0 2' | sudo tee -a /etc/fstab
sudo mount -a
df -h /data
```

Replace `xxxx-xxxx-xxxx` with your actual UUID. You should see ~150 GB available.

### Step 2.4 — Create All Folders

```bash
sudo mkdir -p /data/{docker,postgres,postgres-init,mongo,qdrant,n8n,nginx/conf.d,portainer,homepage,jellyfin/config,syncthing/config,media/music,websites}
sudo chown -R 1000:1000 /data/media /data/jellyfin /data/syncthing
sudo chmod -R 755 /data/websites
```

### Step 2.5 — Create Swap (Safety Net RAM)

```bash
sudo fallocate -l 6G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h
```

### Step 2.6 — Kernel Tuning

```bash
grep -q 'vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## Phase 3: Install Docker

### Step 3.1 — Install Docker Engine

```bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=arm64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER
exit
```

> After `exit`, create a new Bastion session (Step 1.7) and reconnect.

### Step 3.2 — Configure Docker

```bash
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "journald",
  "data-root": "/data/docker",
  "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF
```

### Step 3.3 — Make Docker Wait for Data Drive

```bash
sudo systemctl edit docker
```

A text editor opens. Type this between the comment lines:

```ini
[Unit]
After=data.mount
Requires=data.mount
```

Save and exit (press `Ctrl+X`, then `Y`, then `Enter` in nano). Then:

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
docker info | grep "Docker Root Dir"
```

Should show: `/data/docker`

### Step 3.4 — Cap Log Size

```bash
grep -q 'SystemMaxUse' /etc/systemd/journald.conf || echo 'SystemMaxUse=5G' | sudo tee -a /etc/systemd/journald.conf
sudo systemctl restart systemd-journald
```

### Step 3.5 — Create Secrets File & Generate Keys

```bash
sudo tee /data/.env << 'EOF'
TZ=Asia/Kolkata
COMPOSE_PROJECT_NAME=homelab
POSTGRES_PASSWORD=CHANGE_ME_STRONG_PASSWORD
MONGO_PASSWORD=CHANGE_ME_STRONG_PASSWORD
N8N_ENCRYPTION_KEY=GENERATE_A_RANDOM_32_CHAR_STRING_HERE
QDRANT_API_KEY=GENERATE_A_RANDOM_64_CHAR_STRING_HERE
N8N_WEBHOOK_URL=https://n8n.yourdomain.com/
EOF
```

Now generate real keys:

```bash
openssl rand -hex 16
openssl rand -hex 32
```

Edit the file and paste in the generated values:

```bash
sudo nano /data/.env
```

Replace all placeholder values, then press `Ctrl+X` → `Y` → `Enter` to save.

Lock it down:

```bash
sudo chmod 600 /data/.env
```

> 🔴 **Save your N8N_ENCRYPTION_KEY somewhere safe!** If you lose it, all saved credentials in n8n are permanently lost.

---

## Phase 4: Deploy All Containers

### Step 4.1 — Get Files onto the Server

**Option A — Clone the repo (easiest):**

```bash
cd /tmp
git clone https://github.com/Manojkumarw13/Server-Setup.git
sudo cp /tmp/Server-Setup/docker-compose.yml /data/
sudo cp /tmp/Server-Setup/postgres-init/init-databases.sql /data/postgres-init/
sudo cp /tmp/Server-Setup/nginx/nginx.conf /data/nginx/
sudo cp /tmp/Server-Setup/nginx/conf.d/*.conf /data/nginx/conf.d/
sudo cp /tmp/Server-Setup/homepage/*.yaml /data/homepage/
sudo cp /tmp/Server-Setup/websites/index.html /data/websites/
sudo cp /tmp/Server-Setup/scripts/backup-data-volume.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/backup-data-volume.sh
```

### Step 4.2 — Replace Domain Placeholders

In every Nginx config, replace `yourdomain.com` with your actual domain:

```bash
sudo sed -i 's/yourdomain.com/YOUR_ACTUAL_DOMAIN/g' /data/nginx/conf.d/*.conf
sudo sed -i 's/yourdomain.com/YOUR_ACTUAL_DOMAIN/g' /data/homepage/services.yaml
```

### Step 4.3 — Launch Everything!

```bash
cd /data
sudo chown ubuntu:ubuntu /data/docker-compose.yml /data/.env
docker compose up -d
```

Watch the progress:

```bash
docker compose ps
docker compose logs -f
```

> First launch takes 5–10 minutes as Docker downloads ~8 GB of images. Wait for all containers to show "running" and databases to show "healthy".

Check database health:

```bash
docker inspect --format='{{.State.Health.Status}}' postgres
docker inspect --format='{{.State.Health.Status}}' mongo
docker inspect --format='{{.State.Health.Status}}' qdrant
```

All three should say `healthy`.

---

## Phase 5: Nginx Already Configured ✅

Since you copied all Nginx files in Step 4.1, test them:

```bash
docker exec nginx nginx -t
docker exec nginx nginx -s reload
```

---

## Phase 6: Load Balancer, SSL & DNS

> **What you're doing:** Making your apps accessible via `https://yourdomain.com`.

### Step 6.1–6.2 — Create Load Balancer

1. ☰ → **Networking** → **Load Balancers** → **Create Load Balancer**
2. **Name:** `homelab-lb`. **Shape:** Flexible. **Bandwidth:** 10 Mbps. Select public subnet. **Next**
3. **Backend Set:** Name: `homelab-backend`. Health Check: HTTP, Port `80`, Path `/health`. **Next**
4. **Add Backend:** Select `homelab` instance, Port `80`. **Next** → **Create**

### Step 6.3 — Create SSL Certificate

1. ☰ → **Identity & Security** → **Certificates** → **Create Certificate**
2. Choose **Let's Encrypt**. Add: `yourdomain.com` and `*.yourdomain.com`
3. Complete DNS challenge validation

### Step 6.4 — Add HTTPS Listener

1. Go to your Load Balancer → **Listeners** → **Create Listener**
2. Create HTTP listener: name `http-listener`, port `80`, backend `homelab-backend`
3. Create HTTPS listener: name `https-listener`, port `443`, SSL cert from Step 6.3, backend `homelab-backend`

### Step 6.5 — Increase Timeout

Load Balancer → **Edit Details** → Idle Timeout: `3600` → **Save**

### Step 6.6 — Lock Down Port 80

VCN → Security Lists → Edit Port 80 rule → Change source to LB's Subnet CIDR (e.g., `10.0.0.0/24`)

### Step 6.7 — Configure DNS

1. ☰ → **Networking** → **DNS Management** → **Create Zone**: `yourdomain.com`
2. Add records: `A @ → LB IP`, `A * → LB IP`, `CNAME www → yourdomain.com`
3. Point your domain registrar's nameservers to OCI's nameservers
4. Wait for DNS propagation (5 min – 48 hours)

### Step 6.8 — Verify!

```bash
curl -I https://yourdomain.com/health
```

Should return `HTTP/2 200`. Visit all your subdomains in a browser! 🎉

---

## Phase 7: First-Time App Setup

| App           | URL                                | First-Time Action                                                                                               |
| ------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| **Portainer** | `https://portainer.yourdomain.com` | Create admin account → Get Started → Local → Enable 2FA                                                         |
| **N8N**       | `https://n8n.yourdomain.com`       | Create owner account → Start building workflows                                                                 |
| **Homepage**  | `https://home.yourdomain.com`      | Already configured from YAML files — just verify                                                                |
| **Jellyfin**  | `https://media.yourdomain.com`     | Setup wizard → Add Music library at `/data/media/music` → Disable audio transcoding                             |
| **Syncthing** | `https://sync.yourdomain.com`      | Set GUI password → Edit config.xml to add `<insecureSkipHostcheck>true</insecureSkipHostcheck>` → Connect phone |

---

## Phase 8: Maintenance

### Backup (automated — already set up in Step 4.1)

Edit the script to add your Volume OCID:

```bash
sudo nano /usr/local/bin/backup-data-volume.sh
```

Replace `ocid1.volume.oc1.REGION.YOUR_VOLUME_OCID` with your actual volume ID.

Schedule it:

```bash
(crontab -l 2>/dev/null; echo "0 3 * * 0 /usr/local/bin/backup-data-volume.sh") | crontab -
```

### Updating Containers

```bash
cd /data
docker compose pull
docker compose up -d
docker image prune -f
```

### Useful Commands Cheat Sheet

| Command                           | What It Does                     |
| --------------------------------- | -------------------------------- |
| `docker compose ps`               | Show status of all containers    |
| `docker compose logs -f n8n`      | Watch live logs for n8n          |
| `docker compose restart jellyfin` | Restart one container            |
| `docker exec -it nginx sh`        | Open a shell inside nginx        |
| `htop`                            | Show live CPU/RAM usage          |
| `df -h /data`                     | Show how much disk space is left |
| `free -h`                         | Show RAM usage                   |

---

# ✅ You're Done!

Your server is now running 9 apps, all accessible via your subdomains with HTTPS. Here's your quick reference:

| Service       | URL                                |
| ------------- | ---------------------------------- |
| 🌐 Portfolio  | `https://yourdomain.com`           |
| ⚡ N8N        | `https://n8n.yourdomain.com`       |
| 🐳 Portainer  | `https://portainer.yourdomain.com` |
| 🏠 Dashboard  | `https://home.yourdomain.com`      |
| 🎵 Jellyfin   | `https://media.yourdomain.com`     |
| 🔄 Syncthing  | `https://sync.yourdomain.com`      |
| 🗄️ PostgreSQL | Internal only (`postgres:5432`)    |
| 🗄️ MongoDB    | Internal only (`mongo:27017`)      |
| 🗄️ Qdrant     | Internal only (`qdrant:6333`)      |
