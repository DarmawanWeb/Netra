# NETRA Fleet

Patrol command center for Pashupati robots: live fleet on the mall floor plan, patrol scheduling,
anomaly validation with AI final detection and Telegram alerts, crowd analytics, PDF/Excel reports,
role-based access and an audit trail.

This repository is the **deployment root**: infrastructure at the top level, the application code
in two submodules.

| Path | |
|---|---|
| [`be/`](https://github.com/DarmawanRobotics/netra-fleet-be) | `netra-api` (Go) + `netra-ai` (FastAPI, vision-language model) |
| [`fe/`](https://github.com/DarmawanRobotics/netra-fleet-fe) | `netra-web` (Next.js dashboard) |
| `docker-compose.yml` | the whole stack |
| `Caddyfile` | HTTPS, `/api` → API, `/grafana` → Grafana, rest → dashboard |
| `monitoring/` | Prometheus scrape config, Grafana datasources (Prometheus, TimescaleDB) and dashboard |
| `scripts/deploy.sh` | pull, update submodules, pull images, restart, pull the AI model |

```
internet ─443─> caddy ─┬─ /api ──> api ──┬─> TimescaleDB (state, telemetry, audit)
                       │                 ├─> NATS JetStream (domain events)
                       │                 └─> ai ──> Ollama (vision-language model)
                       ├─ /grafana ─> grafana <─ prometheus (api, ai metrics)
                       └─ /* ─────> web
robots ──WebSocket/HTTPS──> /api/v1/robot/*
```

## Deploy

```bash
git clone --recursive git@github.com:DarmawanRobotics/netra-fleet.git && cd netra-fleet
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

## Develop

```bash
git submodule update --init --recursive
lefthook install          # in the root and in each submodule
```

See `be/README.md` and `fe/README.md`.
