#!/usr/bin/env bash
# NETRA Fleet on a Mac — robots connect over the same Wi-Fi.
#
#   scripts/local.sh setup            check tools, create .env, start Ollama, pull the AI model
#   scripts/local.sh up               build and start the stack, print the addresses
#   scripts/local.sh robot <id> [name] register a robot and print its /etc/pashupati/pashupati.env
#   scripts/local.sh status | logs [service] | doctor | awake | down | reset
#
# Works with the bash 3.2 that ships with macOS.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ENV_FILE=.env
TEMPLATE=.env.local.example
AWAKE_PID=.awake.pid
BASE_URL=http://localhost

if [[ -t 1 ]]; then
    B=$'\033[1m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' D=$'\033[2m' N=$'\033[0m'
else
    B='' G='' Y='' R='' D='' N=''
fi
ok() { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
bad() { printf '  %s✗%s %s\n' "$R" "$N" "$*" >&2; }
die() {
    bad "$*"
    exit 1
}
title() { printf '\n%s%s%s\n' "$B" "$*" "$N"; }

envget() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- || true; }
lan_ip() { ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo ""; }
mdns_name() { echo "$(scutil --get LocalHostName 2>/dev/null || hostname -s).local"; }
random() { openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | cut -c "1-${1:-24}"; }
ram_gb() { echo $(($(sysctl -n hw.memsize) / 1073741824)); }

compose_ok() {
    local v major minor
    v=$(docker compose version --short 2>/dev/null | sed 's/^v//') || return 1
    major=${v%%.*}
    minor=${v#*.}
    minor=${minor%%.*}
    [[ $major -gt 2 || ($major -eq 2 && $minor -ge 24) ]]
}

need_env() { [[ -f $ENV_FILE ]] || die "no .env yet: run scripts/local.sh setup"; }

ollama_up() { curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; }

start_ollama() {
    ollama_up && return 0
    if command -v brew >/dev/null && brew list ollama >/dev/null 2>&1; then
        brew services start ollama >/dev/null
    elif [[ -d /Applications/Ollama.app ]]; then
        open -a Ollama
    else
        (nohup ollama serve >/tmp/ollama.log 2>&1 &)
    fi
    for _ in $(seq 30); do
        ollama_up && return 0
        sleep 1
    done
    return 1
}

wait_healthy() {
    printf '  waiting for the API'
    for _ in $(seq 90); do
        if curl -fsS --max-time 2 "$BASE_URL/healthz" >/dev/null 2>&1; then
            printf ' %s✓%s\n' "$G" "$N"
            return 0
        fi
        printf '.'
        sleep 2
    done
    printf '\n'
    return 1
}

cmd_setup() {
    title "Tools"
    command -v docker >/dev/null || die "Docker Desktop is not installed: https://www.docker.com/products/docker-desktop/"
    docker info >/dev/null 2>&1 || die "Docker Desktop is not running: open -a Docker"
    ok "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
    compose_ok || die "Docker Compose 2.24+ required (Docker Desktop update): $(docker compose version --short 2>/dev/null)"
    ok "Compose $(docker compose version --short)"
    if ! command -v ollama >/dev/null; then
        command -v brew >/dev/null || die "install Ollama from https://ollama.com/download or Homebrew first"
        warn "installing Ollama with Homebrew"
        brew install ollama
    fi
    ok "Ollama $(ollama --version 2>/dev/null | awk '{print $NF}')"

    title "Configuration"
    local model
    if [[ $(ram_gb) -ge 16 ]]; then model=qwen2.5vl:7b; else model=qwen2.5vl:3b; fi
    if [[ -f $ENV_FILE ]]; then
        ok ".env exists, keeping it"
    else
        local admin
        admin=$(random 12)
        sed -e "s|__PUBLIC_URL__|http://$(mdns_name)|" \
            -e "s|__POSTGRES_PASSWORD__|$(random 28)|" \
            -e "s|__GRAFANA_PASSWORD__|$(random 16)|" \
            -e "s|__ADMIN_PASSWORD__|$admin|" \
            -e "s|__AI_MODEL__|$model|" "$TEMPLATE" >"$ENV_FILE"
        chmod 600 "$ENV_FILE"
        ok ".env created (RAM $(ram_gb) GB → $model)"
        printf '    dashboard login: %sadmin / %s%s (also in .env)\n' "$B" "$admin" "$N"
    fi

    title "AI model"
    start_ollama || die "Ollama does not answer on 127.0.0.1:11434"
    ok "Ollama running"
    model=$(envget NETRA_AI_MODEL)
    if ollama list | awk '{print $1}' | grep -q "^$model"; then
        ok "$model present"
    else
        warn "pulling $model (several GB, one time)"
        ollama pull "$model"
    fi
    printf '\nNext: %sscripts/local.sh up%s\n' "$B" "$N"
}

cmd_up() {
    need_env
    docker info >/dev/null 2>&1 || die "Docker Desktop is not running: open -a Docker"
    start_ollama || warn "Ollama is not running: final detection falls back to the robot result"
    title "Starting NETRA Fleet (first build takes a few minutes)"
    docker compose up -d --build --remove-orphans
    wait_healthy || die "API not healthy: scripts/local.sh logs api"
    cmd_addresses
}

cmd_addresses() {
    local ip
    ip=$(lan_ip)
    title "NETRA Fleet is running"
    printf '  Dashboard   %s%s%s   (admin / see NETRA_ADMIN_PASSWORD in .env)\n' "$B" "$BASE_URL" "$N"
    printf '  Grafana     %s/grafana   (admin / GRAFANA_PASSWORD)\n' "$BASE_URL"
    printf '  On Wi-Fi    %s  or  http://%s\n' "$(envget NETRA_PUBLIC_URL)" "${ip:-<no Wi-Fi IP>}"
    printf '\n  Add a robot: %sscripts/local.sh robot l1w-01 "L1W 01"%s\n' "$B" "$N"
}

cmd_down() {
    docker compose down
    cmd_sleep_ok
}

cmd_status() {
    need_env
    docker compose ps --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
    curl -fsS --max-time 3 "$BASE_URL/healthz" >/dev/null 2>&1 && ok "API healthy" || bad "API not reachable on $BASE_URL"
}

cmd_logs() { docker compose logs -f --tail=150 "$@"; }

api_login() {
    local user pass reply
    user=$(envget NETRA_ADMIN_USER)
    pass=$(envget NETRA_ADMIN_PASSWORD)
    reply=$(curl -fsS -X POST "$BASE_URL/api/v1/auth/login" -H 'Content-Type: application/json' \
        -d "{\"username\":\"${user:-admin}\",\"password\":\"$pass\"}") || die "login failed (admin password changed in the dashboard?)"
    echo "$reply" | sed -E 's/.*"token":"([^"]+)".*/\1/'
}

cmd_robot() {
    need_env
    local id=${1:-} name=${2:-${1:-}} session reply token code ip url
    [[ -n $id ]] || die "usage: scripts/local.sh robot <id> [name]   e.g. robot l1w-01 \"L1W 01\""
    session=$(api_login)
    reply=$(curl -sS -w '\n%{http_code}' -X POST "$BASE_URL/api/v1/robots" -H "Authorization: Bearer $session" \
        -H 'Content-Type: application/json' -d "{\"id\":\"$id\",\"name\":\"$name\"}")
    code=$(echo "$reply" | tail -1)
    if [[ $code == 409 ]]; then
        printf '%s already exists. Issue a new token (the old one stops working)? [y/N] ' "$id"
        read -r answer
        [[ $answer == y || $answer == Y ]] || exit 0
        reply=$(curl -sS -w '\n%{http_code}' -X POST "$BASE_URL/api/v1/robots/$id/token" -H "Authorization: Bearer $session")
        code=$(echo "$reply" | tail -1)
    fi
    [[ $code == 200 || $code == 201 ]] || die "API answered $code: $(echo "$reply" | head -1)"
    token=$(echo "$reply" | head -1 | sed -E 's/.*"token":"([^"]+)".*/\1/')
    ip=$(lan_ip)
    url=$(envget NETRA_PUBLIC_URL)
    title "Robot $id registered"
    printf '  On the robot, set these in %s/etc/pashupati/pashupati.env%s and restart:\n\n' "$B" "$N"
    printf '    CC_URL=%s\n    CC_TOKEN=%s\n\n' "$url" "$token"
    printf '  %sIf the robot cannot resolve .local names use CC_URL=http://%s (reserve that IP in the router).%s\n' "$D" "${ip:-<Mac IP>}" "$N"
    printf '  Then: sudo systemctl restart pashupati  — the robot shows up online on the map.\n'
}

cmd_doctor() {
    title "Docker"
    docker info >/dev/null 2>&1 && ok "Docker Desktop running" || bad "Docker Desktop not running"
    compose_ok && ok "Compose $(docker compose version --short)" || bad "Compose 2.24+ required"
    local mem
    mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
    if [[ $((mem / 1073741824)) -ge 4 ]]; then ok "Docker memory $((mem / 1073741824)) GB"; else warn "Docker memory below 4 GB (Settings → Resources)"; fi

    title "AI"
    ollama_up && ok "Ollama on the Mac" || bad "Ollama not running (brew services start ollama)"
    local model
    model=$(envget NETRA_AI_MODEL)
    ollama list 2>/dev/null | awk '{print $1}' | grep -q "^$model" && ok "model $model" || bad "model $model missing (ollama pull $model)"
    if docker compose exec -T ai python -c "import urllib.request;urllib.request.urlopen('http://host.docker.internal:11434/api/tags',timeout=3)" >/dev/null 2>&1; then
        ok "AI container reaches Ollama"
    else
        bad "AI container cannot reach Ollama: brew services stop ollama && OLLAMA_HOST=0.0.0.0 ollama serve"
    fi

    title "Stack"
    curl -fsS --max-time 3 "$BASE_URL/healthz" >/dev/null 2>&1 && ok "API healthy" || bad "API not reachable (scripts/local.sh up)"

    title "Network (robots on the same Wi-Fi)"
    local ip fw
    ip=$(lan_ip)
    [[ -n $ip ]] && ok "Mac Wi-Fi IP $ip, name $(mdns_name)" || bad "no Wi-Fi IP (connect to the robot network)"
    [[ -n $ip ]] && curl -fsS --max-time 3 "http://$ip/healthz" >/dev/null 2>&1 && ok "reachable on http://$ip" || warn "not reachable on the LAN IP yet"
    fw=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || true)
    if echo "$fw" | grep -qi enabled; then
        warn "macOS firewall on: allow incoming connections for Docker when asked"
    else
        ok "macOS firewall off"
    fi
    [[ -f $AWAKE_PID ]] && kill -0 "$(cat $AWAKE_PID)" 2>/dev/null && ok "kept awake" || warn "the Mac may sleep: scripts/local.sh awake"
}

cmd_awake() {
    if [[ -f $AWAKE_PID ]] && kill -0 "$(cat $AWAKE_PID)" 2>/dev/null; then
        ok "already kept awake"
        return
    fi
    (nohup caffeinate -dimsu >/dev/null 2>&1 &
        echo $! >"$AWAKE_PID")
    ok "the Mac stays awake until scripts/local.sh down (keep the lid open or use an external display)"
}

cmd_sleep_ok() {
    if [[ -f $AWAKE_PID ]]; then
        kill "$(cat $AWAKE_PID)" 2>/dev/null || true
        rm -f "$AWAKE_PID"
    fi
}

cmd_reset() {
    printf '%sDelete every NETRA container AND all data (database, photos, Grafana)?%s Type "reset": ' "$R" "$N"
    read -r answer
    [[ $answer == reset ]] || exit 0
    docker compose down -v
    ok "all data removed; scripts/local.sh up starts fresh"
}

case "${1:-help}" in
setup) cmd_setup ;;
up) cmd_up ;;
down) cmd_down ;;
status) cmd_status ;;
logs) shift && cmd_logs "$@" ;;
robot) shift && cmd_robot "$@" ;;
doctor) cmd_doctor ;;
awake) cmd_awake ;;
reset) cmd_reset ;;
*) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
