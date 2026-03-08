# Oracle Cloud Homelab — Server Setup

![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![Nginx](https://img.shields.io/badge/nginx-%23009639.svg?style=for-the-badge&logo=nginx&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/postgres-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-%234ea94b.svg?style=for-the-badge&logo=mongodb&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Oracle](https://img.shields.io/badge/Oracle-F80000?style=for-the-badge&logo=oracle&logoColor=white)

Production-ready deployment kit for a self-hosted homelab on **Oracle Free Tier** (`VM.Standard.A1.Flex` — 4 ARM OCPUs, 24 GB RAM, 200 GB Storage).

## What's Included

| Service        | Purpose                      | Subdomain                  |
| -------------- | ---------------------------- | -------------------------- |
| **Nginx**      | Reverse proxy + static sites | `yourdomain.com`           |
| **N8N**        | Workflow automation          | `n8n.yourdomain.com`       |
| **Portainer**  | Container management         | `portainer.yourdomain.com` |
| **Homepage**   | Dashboard                    | `home.yourdomain.com`      |
| **Jellyfin**   | Music streaming              | `media.yourdomain.com`     |
| **Syncthing**  | Phone-to-server file sync    | `sync.yourdomain.com`      |
| **PostgreSQL** | Relational database          | Internal only              |
| **MongoDB**    | Document database            | Internal only              |
| **Qdrant**     | Vector database              | Internal only              |

## Project Structure

```
Server-Setup/
├── Setup.md                    # Architecture plan (reference)
├── Deployment-Guide.md         # Step-by-step deployment guide
├── docker-compose.yml          # All 9 containers
├── .env                        # Secrets template (⚠ fill before deploy)
├── daemon.json                 # Docker daemon config → /etc/docker/daemon.json
├── nginx/
│   ├── nginx.conf              # Main Nginx config → /data/nginx/nginx.conf
│   └── conf.d/
│       ├── health.conf         # OCI LB health endpoint + catch-all
│       ├── n8n.conf            # n8n reverse proxy
│       ├── portainer.conf      # Portainer reverse proxy
│       ├── homepage.conf       # Homepage reverse proxy
│       ├── jellyfin.conf       # Jellyfin reverse proxy
│       ├── syncthing.conf      # Syncthing reverse proxy
│       └── portfolio.conf      # Static site server block
├── postgres-init/
│   └── init-databases.sql      # Creates n8n_backend & project_data DBs
├── homepage/
│   ├── services.yaml           # Dashboard service definitions
│   ├── settings.yaml           # Theme & layout settings
│   └── docker.yaml             # Docker socket integration
├── scripts/
│   └── backup-data-volume.sh   # Automated OCI block volume backup
├── websites/
│   └── index.html              # Placeholder landing page
├── .gitignore                  # Prevents .env from being committed
└── README.md                   # This file
```

## Quick Start

1. **Read** [`Deployment-Guide.md`](Deployment-Guide.md) — follow every phase in order.
2. **Fill in** `.env` with your passwords and generated keys.
3. **Replace** `yourdomain.com` in all Nginx configs and `.env` with your actual domain.
4. **Copy** files to the server at `/data/` and deploy with `docker compose up -d`.

## Security Notes

- `.env` contains all secrets — **never commit it** (already in `.gitignore`).
- Databases are on an isolated Docker network (`internal-net`) with no internet access.
- Port 80 is restricted to the OCI Load Balancer's subnet via VCN Security List.
- SSH access is via OCI Bastion only — no port 22 rule exists.

## Architecture

```mermaid
graph TD
    %% Define Styles
    classDef external fill:#f9f,stroke:#333,stroke-width:2px;
    classDef proxy fill:#fcf,stroke:#333,stroke-width:2px;
    classDef db fill:#bbf,stroke:#333,stroke-width:2px;
    classDef app fill:#d5f4e6,stroke:#333,stroke-width:2px;

    %% External
    Users((Internet Users)):::external

    %% OCI Infrastructure
    subgraph OCI [Oracle Cloud Infrastructure]
        LB[OCI Load Balancer <br> HTTPS:443]:::proxy

        %% Docker Host
        subgraph VM [VM.Standard.A1.Flex Ubuntu Host]
            Nginx{Nginx Reverse Proxy}:::proxy

            %% Public Network
            subgraph PublicNet [public-net bridge]
                N8N[n8n Workflow]:::app
                Portainer[Portainer Mgt]:::app
                Homepage[Homepage Dashboard]:::app
                Jellyfin[Jellyfin Media]:::app
                Syncthing[Syncthing Sync]:::app
            end

            %% Internal Network
            subgraph InternalNet [internal-net bridge]
                Postgres[(PostgreSQL 16)]:::db
                Mongo[(MongoDB 7.0)]:::db
                Qdrant[(Qdrant Vector)]:::db
            end

            %% Storage Volumes
            subgraph HostStorage [Attached Block Volume /data/*]
                VolApp[/App Configs/]
                VolDB[/Database Storage/]
                VolMedia[/Media Files/]
            end
        end
    end

    %% Connections
    Users -->|HTTPS| LB
    LB -->|HTTP:80| Nginx

    %% Proxy to Apps
    Nginx -->|Proxy| N8N
    Nginx -->|Proxy| Portainer
    Nginx -->|Proxy| Homepage
    Nginx -->|Proxy| Jellyfin
    Nginx -->|Proxy| Syncthing

    %% Apps to DBs (Internal only)
    N8N -->|Read/Write| Postgres

    %% Persistent Storage maps
    N8N -.-> VolApp
    Portainer -.-> VolApp
    Homepage -.-> VolApp
    Postgres -.-> VolDB
    Mongo -.-> VolDB
    Qdrant -.-> VolDB
    Jellyfin -.-> VolMedia
    Syncthing -.-> VolMedia
```

## License

Private — personal homelab configuration.
