#!/usr/bin/env bash
# NETRA Fleet on a Mac — robots connect over the same network (Wi-Fi, hotspot or cable).
#
#   scripts/local.sh setup             check tools, create .env, start Ollama, pull the AI model
#   scripts/local.sh up                build and start the stack, print the addresses
#   scripts/local.sh robot <id> [name] register a robot and print its /etc/pashupati/pashupati.env
#   scripts/local.sh lan               addresses robots and phones can use on each network
#   scripts/local.sh export [file]     all data (database, photos, floor plans) into one file
#   scripts/local.sh import <file>     replace the data here with an export (demo laptop)
#   scripts/local.sh status | logs [service] | doctor | awake | down | reset
#
# Works with the bash 3.2 that ships with macOS.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ENV_FILE=.env
TEMPLATE=.env.local.example
AWAKE_PID=.awake.pid
EXPORTS=exports
API_UID=65532 # nonroot user of the netra-api image, owner of the data volume

WORK=''
cleanup() {
    [[ -n $WORK ]] && rm -rf "$WORK"
    return 0
}
trap cleanup EXIT

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
mdns_name() { echo "$(scutil --get LocalHostName 2>/dev/null || hostname -s).local"; }
random() { openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | cut -c "1-${1:-24}"; }
ram_gb() { echo $(($(sysctl -n hw.memsize) / 1073741824)); }
size_of() { du -h "$1" | cut -f1 | tr -d ' '; }

# Port of the dashboard and robot API on this computer (NETRA_LAN_PORT, default 80).
lan_port() {
    local port
    port=$(envget NETRA_LAN_PORT)
    echo "${port:-80}"
}
port_suffix() { [[ $(lan_port) == 80 ]] || echo ":$(lan_port)"; }
BASE_URL="http://localhost$(port_suffix)"

# "interface address" for every IPv4 address a robot could reach (no loopback or VPN tunnels).
lan_addrs() {
    ifconfig 2>/dev/null | awk '
        /^[a-z]/ { iface = $1; sub(/:$/, "", iface) }
        $1 == "inet" && iface !~ /^(lo|utun|gif|stf|awdl|llw|anpi|ipsec|ppp)/ { print iface, $2 }'
}

# Name of an interface as System Settings shows it: "Wi-Fi", "USB 10/100/1000 LAN", ...
iface_label() {
    local name=''
    case $1 in
    bridge1*) name='Internet Sharing / VM network' ;;
    *)
        name=$(networksetup -listallhardwareports 2>/dev/null | awk -v dev="$1" '
            /^Hardware Port:/ { sub(/^Hardware Port: /, ""); port = $0 }
            /^Device:/ && $2 == dev { print port; exit }') || true
        ;;
    esac
    echo "${name:-$1}"
}

# Wi-Fi network name of an interface; empty when unknown (macOS may hide it).
wifi_name() { ipconfig getsummary "$1" 2>/dev/null | awk -F ' SSID : ' '/ SSID : / { print $2; exit }' || true; }

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
    title "NETRA Fleet is running"
    printf '  Dashboard   %s%s%s   (admin / see NETRA_ADMIN_PASSWORD in .env)\n' "$B" "$BASE_URL" "$N"
    printf '  Grafana     %s/grafana   (admin / GRAFANA_PASSWORD)\n' "$BASE_URL"
    print_lan
    printf '\n  Add a robot: %sscripts/local.sh robot l1w-01 "L1W 01"%s\n' "$B" "$N"
}

# The addresses of this computer on every network it is connected to, and whether NETRA answers there.
print_lan() {
    local iface ip label ssid url public found=''
    title "Robots and phones on the same network use"
    while read -r iface ip; do
        [[ -n $ip ]] || continue
        found=1
        label=$(iface_label "$iface")
        ssid=$(wifi_name "$iface")
        [[ -n $ssid ]] && label="$label \"$ssid\""
        url="http://$ip$(port_suffix)"
        if curl -fsS --max-time 2 "$url/healthz" >/dev/null 2>&1; then
            printf '  %s%-28s%s %s   %s(%s)%s\n' "$B" "$url" "$N" "$label" "$D" "$iface" "$N"
        else
            printf '  %-28s %s   %s(%s, NETRA does not answer here)%s\n' "$url" "$label" "$D" "$iface" "$N"
        fi
    done < <(lan_addrs)
    [[ -n $found ]] || warn "no network connection: join the robot's Wi-Fi, a hotspot or plug in a cable"
    printf '  %-28s %s\n' "http://$(mdns_name)$(port_suffix)" "any of them, if the robot resolves .local names"
    public=$(envget NETRA_PUBLIC_URL)
    if [[ $public == https://* ]]; then
        printf '  %-28s %s\n' "$public" "through the internet (Cloudflare Tunnel)"
    fi
}

cmd_lan() {
    need_env
    print_lan
    printf '\n  On the robot: %sCC_URL=<one of these addresses>%s in /etc/pashupati/pashupati.env, then\n' "$B" "$N"
    printf '  sudo systemctl restart pashupati. Check from the robot first: curl <address>/healthz\n'
}

cmd_down() {
    docker compose down
    cmd_sleep_ok
}

cmd_status() {
    need_env
    docker compose ps --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'
    if curl -fsS --max-time 3 "$BASE_URL/healthz" >/dev/null 2>&1; then ok "API healthy"; else bad "API not reachable on $BASE_URL"; fi
}

cmd_logs() { docker compose logs -f --tail=150 "$@"; }

api_login() {
    local user pass reply
    user=$(envget NETRA_ADMIN_USER)
    pass=$(envget NETRA_ADMIN_PASSWORD)
    reply=$(curl -fsS -X POST "$BASE_URL/api/v1/auth/login" -H 'Content-Type: application/json' \
        -d "{\"username\":\"${user:-admin}\",\"password\":\"$pass\"}") || die "login failed (is the stack up? scripts/local.sh status)"
    echo "$reply" | sed -E 's/.*"token":"([^"]+)".*/\1/'
}

cmd_robot() {
    need_env
    local id=${1:-} name=${2:-${1:-}} session reply token code url
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
    url=$(envget NETRA_PUBLIC_URL)
    title "Robot $id registered"
    printf '  On the robot, set these in %s/etc/pashupati/pashupati.env%s and restart:\n\n' "$B" "$N"
    printf '    ROBOT_ID=%s\n    CC_URL=%s\n    CC_TOKEN=%s\n' "$id" "${url:-$BASE_URL}" "$token"
    print_lan
    printf '\n  %sCC_URL can be any address above that the robot reaches (curl <address>/healthz on the robot).%s\n' "$D" "$N"
    printf '  Then: sudo systemctl restart pashupati  — the robot shows up online on the dashboard.\n'
}

# --------------------------------------------------------------------------------- export / import

container_of() {
    local id
    id=$(docker compose ps -a -q "$1" 2>/dev/null | head -1)
    [[ -n $id ]] || die "the stack was never started here: scripts/local.sh up"
    echo "$id"
}

# An image that is already on this computer (works offline) and has sh and tar: the database image.
helper_image() { docker inspect -f '{{.Image}}' "$(container_of db)"; }

db_ready() { docker compose exec -T db pg_isready -U netra -d netra >/dev/null 2>&1; }

wait_db() {
    for _ in $(seq 60); do
        db_ready && return 0
        sleep 1
    done
    return 1
}

psql_db() { docker compose exec -T db psql -X -q -v ON_ERROR_STOP=1 -U netra "$@"; }

cmd_export() {
    need_env
    local out=${1:-$EXPORTS/netra-$(date +%Y%m%d-%H%M).tar.gz} api
    db_ready || die "the database is not running: scripts/local.sh up"
    api=$(container_of api)
    mkdir -p "$EXPORTS" "$(dirname "$out")"
    WORK=$(mktemp -d "$EXPORTS/.export-XXXXXX")
    title "Exporting NETRA data"
    if ! docker compose exec -T db pg_dump -U netra -d netra -Fc >"$WORK/netra.dump" 2>"$WORK/dump.log"; then
        cat "$WORK/dump.log" >&2
        die "database dump failed"
    fi
    ok "database ($(size_of "$WORK/netra.dump"))"
    docker run --rm --volumes-from "$api" --entrypoint tar "$(helper_image)" cf - -C /data . >"$WORK/data.tar" ||
        die "copying photos and floor plans failed"
    ok "photos and floor plans ($(size_of "$WORK/data.tar"))"
    printf 'netra-export 1\ncreated %s\nhost %s\n' "$(date '+%Y-%m-%d %H:%M %Z')" "$(hostname -s)" >"$WORK/MANIFEST"
    tar czf "$out" -C "$WORK" MANIFEST netra.dump data.tar
    ok "$out ($(size_of "$out"))"
    printf '\n  Copy it to the demo laptop (AirDrop, USB, scp), then there:\n'
    printf '    %sscripts/local.sh import %s%s\n' "$B" "$out" "$N"
}

cmd_import() {
    need_env
    local file=${1:-} api host created timescale counts log answer
    [[ -n $file ]] || die "usage: scripts/local.sh import exports/netra-YYYYMMDD-HHMM.tar.gz"
    [[ -f $file ]] || die "$file not found"
    docker info >/dev/null 2>&1 || die "Docker Desktop is not running: open -a Docker"
    api=$(container_of api)
    mkdir -p "$EXPORTS"
    WORK=$(mktemp -d "$EXPORTS/.import-XXXXXX")
    if ! tar xzf "$file" -C "$WORK" MANIFEST netra.dump data.tar 2>/dev/null ||
        ! grep -q '^netra-export 1$' "$WORK/MANIFEST"; then
        die "$file is not a NETRA export"
    fi
    host=$(sed -n 's/^host //p' "$WORK/MANIFEST")
    created=$(sed -n 's/^created //p' "$WORK/MANIFEST")

    printf '%sReplace ALL NETRA data on this computer with the export of %s (%s)?%s Type "import": ' \
        "$R" "$host" "$created" "$N"
    read -r answer
    [[ $answer == import ]] || exit 0

    title "Importing"
    docker compose up -d db >/dev/null
    wait_db || die "the database does not start: scripts/local.sh logs db"
    # Nothing may write while the database is replaced; the API comes back after the restore.
    docker compose stop api backup grafana >/dev/null 2>&1 || true
    psql_db -d postgres -c 'DROP DATABASE IF EXISTS netra WITH (FORCE)' -c 'CREATE DATABASE netra' ||
        die "could not recreate the database"
    timescale=$(docker compose exec -T db psql -X -tA -U netra -d netra \
        -c "SELECT count(*) FROM pg_available_extensions WHERE name = 'timescaledb'") || die "the new database does not answer"
    timescale=$(echo "$timescale" | tr -d '[:space:]')
    if [[ $timescale == 1 ]]; then
        # TimescaleDB restore procedure: hypertable catalogs come back intact, background jobs pause.
        psql_db -d netra -c 'CREATE EXTENSION IF NOT EXISTS timescaledb' -c 'SELECT timescaledb_pre_restore()' >/dev/null ||
            die "timescaledb_pre_restore failed"
    fi
    log="$EXPORTS/import-$(date +%Y%m%d-%H%M%S).log"
    if docker compose exec -T db pg_restore -U netra -d netra --no-owner <"$WORK/netra.dump" >"$log" 2>&1; then
        rm -f "$log"
    else
        warn "pg_restore reported problems, see $log"
    fi
    if [[ $timescale == 1 ]]; then
        psql_db -d netra -c 'SELECT timescaledb_post_restore()' >/dev/null || die "timescaledb_post_restore failed"
    fi
    counts=$(docker compose exec -T db psql -X -tA -U netra -d netra -c "SELECT
        (SELECT count(*) FROM robots) || ' robots, ' || (SELECT count(*) FROM routes) || ' routes, ' ||
        (SELECT count(*) FROM floor_plans) || ' floor plans, ' || (SELECT count(*) FROM anomalies) || ' anomalies'") ||
        die "the restored database is incomplete, see $log"
    ok "database: $counts"

    docker run --rm -i --volumes-from "$api" --entrypoint sh "$(helper_image)" -c \
        "find /data -mindepth 1 -maxdepth 1 -exec rm -rf {} + && tar xf - -C /data && chown -R $API_UID:$API_UID /data" \
        <"$WORK/data.tar" || die "restoring photos and floor plans failed"
    ok "photos and floor plans"

    docker compose up -d
    wait_healthy || die "API not healthy after the import: scripts/local.sh logs api"
    ok "imported from $host"
    printf '\n  Log in with %sadmin / NETRA_ADMIN_PASSWORD of this computer%s; other users keep their passwords.\n' "$B" "$N"
    printf '  Robots keep their tokens: on a robot only CC_URL changes to an address of this computer.\n'
    print_lan
}

# ------------------------------------------------------------------------------------------ doctor

cmd_doctor() {
    title "Docker"
    if docker info >/dev/null 2>&1; then ok "Docker Desktop running"; else bad "Docker Desktop not running"; fi
    if compose_ok; then ok "Compose $(docker compose version --short)"; else bad "Compose 2.24+ required"; fi
    local mem
    mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
    if [[ $((mem / 1073741824)) -ge 4 ]]; then ok "Docker memory $((mem / 1073741824)) GB"; else warn "Docker memory below 4 GB (Settings → Resources)"; fi

    title "AI"
    if ollama_up; then ok "Ollama on the Mac"; else bad "Ollama not running (brew services start ollama)"; fi
    local model
    model=$(envget NETRA_AI_MODEL)
    if ollama list 2>/dev/null | awk '{print $1}' | grep -q "^$model"; then
        ok "model $model"
    else
        bad "model $model missing (ollama pull $model)"
    fi
    if docker compose exec -T ai python -c "import urllib.request;urllib.request.urlopen('http://host.docker.internal:11434/api/tags',timeout=3)" >/dev/null 2>&1; then
        ok "AI container reaches Ollama"
    else
        bad "AI container cannot reach Ollama: brew services stop ollama && OLLAMA_HOST=0.0.0.0 ollama serve"
    fi

    title "Stack"
    if curl -fsS --max-time 3 "$BASE_URL/healthz" >/dev/null 2>&1; then
        ok "API healthy on $BASE_URL"
    else
        bad "API not reachable (scripts/local.sh up)"
    fi

    title "Network (robots on the same network)"
    local iface ip any='' fw
    while read -r iface ip; do
        [[ -n $ip ]] || continue
        any=1
        if curl -fsS --max-time 3 "http://$ip$(port_suffix)/healthz" >/dev/null 2>&1; then
            ok "reachable on http://$ip$(port_suffix) ($(iface_label "$iface"))"
        else
            warn "not reachable on http://$ip$(port_suffix) ($(iface_label "$iface"))"
        fi
    done < <(lan_addrs)
    [[ -n $any ]] || bad "no network connection (join the robot's Wi-Fi, a hotspot or plug in a cable)"
    if [[ $(envget NETRA_LAN_BIND) == 127.0.0.1 ]]; then
        warn "NETRA_LAN_BIND=127.0.0.1: only this computer and the tunnel reach NETRA"
    fi
    fw=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || true)
    if echo "$fw" | grep -qi enabled; then
        warn "macOS firewall on: allow incoming connections for Docker when asked"
    else
        ok "macOS firewall off"
    fi
    if [[ -f $AWAKE_PID ]] && kill -0 "$(cat $AWAKE_PID)" 2>/dev/null; then
        ok "kept awake"
    else
        warn "the Mac may sleep: scripts/local.sh awake"
    fi
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
lan) cmd_lan ;;
export) shift && cmd_export "$@" ;;
import) shift && cmd_import "$@" ;;
doctor) cmd_doctor ;;
awake) cmd_awake ;;
reset) cmd_reset ;;
*) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
