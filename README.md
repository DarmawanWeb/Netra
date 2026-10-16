# NETRA Fleet

Patrol command center for Pashupati robots: live fleet on the mall floor plan, patrol scheduling,
anomaly validation with AI final detection and Telegram alerts, crowd analytics, PDF/Excel reports,
role-based access and an audit trail.

This repository is the **deployment root**: infrastructure at the top level, the application code
in two submodules.

| Path | |
|---|---|
| [`be/`](https://github.com/DarmawanWeb/netra-fleet-be) | `netra-api` (Go) + `netra-ai` (FastAPI, vision-language model) |
| [`fe/`](https://github.com/DarmawanWeb/netra-fleet-fe) | `netra-web` (Next.js dashboard) |
| `docker-compose.yml` | the whole stack |
| `Caddyfile` | HTTPS, `/api` → API, `/grafana` → Grafana, rest → dashboard |
| `monitoring/` | Prometheus scrape config, Grafana datasources (Prometheus, TimescaleDB) and dashboard |
| `scripts/deploy.sh` | server: pull, update submodules, pull images, restart, pull the AI model |
| `docker-compose.local.yml`, `Caddyfile.local`, `.env.local.example`, `scripts/local.sh` | running on a Mac (LOCAL.md) |
| `docker-compose.tunnel.yml`, `Caddyfile.tunnel` | a Mac behind a Cloudflare Tunnel, LAN port kept for robots |

```
internet ─443─> caddy ─┬─ /api ──> api ──┬─> TimescaleDB (state, telemetry, audit)
                       │                 ├─> NATS JetStream (domain events)
                       │                 └─> ai ──> Ollama (vision-language model)
                       ├─ /grafana ─> grafana <─ prometheus (api, ai metrics)
                       └─ /* ─────> web
robots ──WebSocket/HTTPS──> /api/v1/robot/*
```

## Run on a Mac (robots on the same network)

See **[LOCAL.md](LOCAL.md)**: `scripts/local.sh setup && scripts/local.sh up`, then
`scripts/local.sh robot <id>` prints the robot's connection settings. For a demo on a laptop,
`scripts/local.sh export` on the server and `scripts/local.sh import` on the laptop copy the data
over, so robots keep their tokens and only change `CC_URL`
([Demo: the command center on a laptop](LOCAL.md#demo-the-command-center-on-a-laptop)).

## Deploy on a server

```bash
git clone --recursive git@github.com:DarmawanWeb/Netra.git && cd Netra
cp .env.example .env            # domain, passwords, Telegram, AI model
docker compose up -d --build    # or with CI images: docker compose pull && docker compose up -d
docker compose exec ollama ollama pull qwen2.5vl:7b
```

Then open `https://<domain>`, log in as `NETRA_ADMIN_USER`, add users (roles viewer / operator /
supervisor / admin), register robots, upload the floor plan. Grafana is at `/grafana`.

Updates: `scripts/deploy.sh` (images from GHCR) or `scripts/deploy.sh --build`. The `deploy`
workflow runs it over SSH on `v*` tags (secrets `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_KEY`,
`DEPLOY_PATH`).

Backups: daily `pg_dump` into `backups/` (kept `BACKUP_KEEP_DAYS`); restore with
`docker compose exec -T db pg_restore -U netra -d netra --clean < backups/netra-YYYY-MM-DD.dump`.
Anomaly photos and floor plans are in the `api-data` volume.

## Integration API (third-party apps)

Other systems read the anomalies (with their original photos), robots, patrols, routes and floor
plans over `https://<domain>/api/ext/v1`, with OAuth2 client credentials. An admin creates a client
in **Settings → API clients** (scopes; the secret is shown once) and gives the third party the
`client_id`, the `client_secret`, the guide
[INTEGRATION.md](https://github.com/DarmawanWeb/netra-fleet-be/blob/main/INTEGRATION.md) and the
interactive docs at `https://<domain>/api/ext/docs` (OpenAPI: `/api/ext/v1/openapi.yaml`).

## Develop

```bash
git submodule update --init --recursive
lefthook install          # in the root and in each submodule
```

See `be/README.md` and `fe/README.md`.
