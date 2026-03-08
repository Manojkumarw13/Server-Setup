Hardware :-

• Oracle Free Tier: VM.Standard.A1.Flex (ARM)

• Hardware: 4 ARM OCPUs, 24 GB RAM, 200 GB Total Storage.

• OS: Ubuntu 24.04 LTS (After first boot: `sudo apt update && sudo apt upgrade -y && sudo apt install -y curl wget gnupg lsb-release ca-certificates` | Set hostname via `sudo hostnamectl set-hostname homelab`)

Storage & Memory :-

• System RAM: 3 GB reserved for OS (+ 5 GB buffer for OS cache/overhead = 8 GB total for OS)

• Boot Volume: 50 GB (Create 4GB-8GB swap file and set `vm.swappiness=10` in `/etc/sysctl.conf` to prevent iSCSI network freezing)

• Data Volume: 150 GB (Format ext4, mount via /etc/fstab with nofail, \_netdev flags to prevent boot freezes, pre-create/chown host directories for permissions. Map Docker volumes to subdirectories like `/data/postgres` to avoid `lost+found` init script failures! Ensure static web asset folders have `chmod -R 755` permissions for Nginx to read 3D models)

Oracle Native Services (Networking, Management, Logging, Monitoring) :-

• Networking: OCI Flexible Load Balancer & OCI Certificates (Routes HTTPS traffic to Nginx. Configure LB to ping a custom `/health` endpoint so it doesn't fail. Increase LB Idle Timeout to 3600s for WebSockets/SSE. In VCN Security List, restrict Port 80 specifically to the LB's internal Subnet CIDR, not 0.0.0.0/0). Configure OCI DNS Zone for wildcard subdomain resolution (`*.yourdomain.com`).

• Management: OCI Bastion (Zero-trust SSH tunnel, delete port 22 internet rule | Explicitly ENABLE Bastion plugin in the VM's Oracle Cloud Agent settings).

• Logging: OCI Logging (Pulls from Docker journald).

• Monitoring: OCI Alarms & Notifications (Email alerts for high CPU/RAM).

• Backup: Schedule weekly OCI Block Volume backups via `oci bv backup create` CLI or OCI Console policy (automate with cron). Test restore procedure at least once before going live.

• Docker - For isolation & to build containers. Use arm64/aarch64 images. (Configure `/etc/docker/daemon.json` to use `"log-driver": "journald"`, `"data-root": "/data/docker"`, and `"dns": ["8.8.8.8", "1.1.1.1"]` preventing container DNS resolution failures—also run `sudo systemctl edit docker` to add `After=data.mount` and `Requires=data.mount` preventing mount race conditions. Limit `/etc/systemd/journald.conf` with `SystemMaxUse=5G`. Create a global `.env` file with `TZ=Asia/Kolkata`, explicitly declare `env_file: .env` in docker-compose, and map `- /etc/localtime:/etc/localtime:ro` to perfectly sync timezones. Set `restart: unless-stopped` on ALL containers for crash recovery. Define two compose networks: `internal-net` (internal, no external access) and `public-net` (for LB-facing services). Rely on OCI VCN for port security; do NOT use `ufw` as Docker silently bypasses it).

Containers (16GB Total RAM) :-

• Database (PostgreSQL); To store the databases of my projects | 2.5GB RAM (internal-net | Use `command: postgres -c shared_buffers=1GB -c work_mem=16MB -c maintenance_work_mem=256MB -c max_connections=100` to correctly tune RAM limit | Map persistent host volume `/data/postgres:/var/lib/postgresql/data` | Add healthcheck: `pg_isready -U $POSTGRES_USER` with extended timeout/retries | Mount init script to split `n8n_backend` & `project_data`)

• Database (MongoDB); To store the databases of my projects | 2.5GB RAM (internal-net | Pin image to `mongo:7.0-jammy` or `8.0-jammy` for ARM | Map persistent host volume `/data/mongo:/data/db` | Add healthcheck: `mongosh --eval 'db.runCommand("ping")'`)

• Database (qdrant); To store the database of my projects | 5GB RAM (internal-net | Must explicitly map persistent host volume `/data/qdrant:/qdrant/storage` to prevent data loss | Configure `on_disk: true` for HNSW indices to prevent mmap OOM kills | Add healthcheck: `wget --no-verbose --tries=1 --spider http://localhost:6333/healthz || exit 1`)

• Automation (N8N); To publish the workflows | 4GB RAM (public & internal-net | ENV `NODE_OPTIONS="--max-old-space-size=3584"`, `DB_TYPE=postgresdb`, `WEBHOOK_URL=https://...`, `N8N_ENCRYPTION_KEY=<generate-random-32-char>` (persist this key! losing it = all credentials become undecryptable) | Map persistent host volume `/data/n8n:/home/node/.n8n` | Add proper compose v2 `depends_on: condition: service_healthy` for Postgres, MongoDB, and Qdrant)

• Web (Nginx); To host websites | 256MB RAM (public-net | Bind port `80:80` to host for OCI LB | Remove HTTP-to-HTTPS redirect | Add `location /health { add_header Content-Type text/plain; access_log off; return 200 'OK'; }` for OCI LB | Configure `set_real_ip_from` & `X-Forwarded-For` AND pass `$http_x_forwarded_proto` for SSL termination | Add global `proxy_set_header Host $host;` and security headers `X-Content-Type-Options nosniff`, `X-Frame-Options SAMEORIGIN`, `Referrer-Policy strict-origin-when-cross-origin` in the `http {}` block | Add MIME types/Gzip for 3D .gltf models (avoid gzipping binary .glb) | Pass WebSocket Upgrade headers AND set `proxy_read_timeout 3600; proxy_send_timeout 3600;` to match LB timeout | Add `client_max_body_size 1G;` | Map config volume `/data/nginx/conf.d:/etc/nginx/conf.d:ro` for persistent config | Use subdomains instead of subpaths for robust routing)

• Container Management (Portainer); To manage the containers | 256MB RAM (public-net | Map full docker.sock | Map persistent host volume `/data/portainer:/data` | Secure with 2FA and strong passwords to protect root-level access)

• Dashboard (Homepage); For accessing the containers using this dashboard | 128MB RAM (public-net | Map config volume `/data/homepage:/app/config` and read-only docker.sock for auto-discovery)

• Media (Jellyfin); To stream music only | 1GB RAM (public-net | Route through Nginx/LB for SSL security | Set PUID=1000 & PGID=1000 AND pre-run `sudo chown -R 1000:1000 /data/media /data/jellyfin` on host | Map `/data/jellyfin/config:/config` for persistent library metadata AND `/data/media:/data/media:ro` for media files | Must use `lscr.io/linuxserver/jellyfin` image | Disable audio transcoding in UI to force Direct Play)

• Sync (Syncthing); To sync my songs from my phone to the server | 256MB RAM (public-net | Route Web UI through Nginx/LB for SSL with `proxy_set_header Host $host;` and set `<insecureSkipHostcheck>true</insecureSkipHostcheck>` in config.xml | Expose port 22000 explicitly via VCN & Docker ports for BOTH TCP & UDP | Set PUID=1000 & PGID=1000 | Map `/data/syncthing/config:/config` for persistent device keys AND sync folder directly to `/data/media/music` (sharing Jellyfin's pre-chowned directory) | Must use `lscr.io/linuxserver/syncthing` image | Disable "Local Discovery" in UI | Set strong administrator password to secure Web UI)
