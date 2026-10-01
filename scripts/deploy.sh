#!/usr/bin/env bash
# Update and (re)start NETRA Fleet on the server: scripts/deploy.sh [--build]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ -f .env ]] || { echo "create .env from .env.example first"; exit 1; }
git pull --ff-only
git submodule update --init --recursive
if [[ "${1:-}" == "--build" ]]; then
    docker compose up -d --build --remove-orphans
else
    docker compose pull --ignore-buildable
    docker compose up -d --remove-orphans
fi
docker compose exec -T ollama ollama pull "$(grep -E '^NETRA_AI_MODEL=' .env | cut -d= -f2 || echo qwen2.5vl:7b)"
docker image prune -f >/dev/null
docker compose ps
