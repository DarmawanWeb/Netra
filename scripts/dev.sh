#!/usr/bin/env bash
# NETRA development: the be and fe submodules on their dev branch, the API with hot reload, the
# dashboard on next dev, PostgreSQL in Docker, development licenses, simulated robots and a VS Code
# workspace. Guide: DEVELOPMENT.md.
#
#   scripts/dev.sh setup                     tools, submodules on dev, packages, database, license, editor
#   scripts/dev.sh up | down | restart       API :4492 (reloads on save) and dashboard :4493
#   scripts/dev.sh api | web                 one of them in this terminal (VS Code tasks, tmux panes)
#   scripts/dev.sh demo                      simulated robots; on a substation license two weeks of data
#   scripts/dev.sh license <profile> [flags] gardu, mall, core, all, ... (scripts/dev.sh licenses)
#   scripts/dev.sh licenses                  the profiles and the license in use
#   scripts/dev.sh new <branch>              a branch from origin/dev in be and fe
#   scripts/dev.sh check                     what CI runs, before a push
#   scripts/dev.sh status | logs [name] | open | reset
#
# Works with the bash 3.2 that ships with macOS.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT=$PWD

API_PORT=${NETRA_API_PORT:-4492}
WEB_PORT=${NETRA_WEB_PORT:-4493}
DB_PORT=${NETRA_DB_PORT:-55432}
DB=netra-dev-db
BE=$ROOT/be
FE=$ROOT/fe
STATE=$ROOT/.dev
RUN=$STATE/run
LICDIR=$BE/.dev # the backend's development key and license (ignored by git, as for make run-licensed)
ENVF=$LICDIR/dev.env
API_URL=http://127.0.0.1:$API_PORT

if [[ -t 1 ]]; then
    B=$'\033[1m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' C=$'\033[36m' D=$'\033[2m' N=$'\033[0m'
else
    B='' G='' Y='' R='' C='' D='' N=''
fi
title() { printf '\n%s%s%s\n' "$B" "$*" "$N"; }
ok() { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die() {
    printf '  %s✗%s %s\n' "$R" "$N" "$*" >&2
    exit 1
}

# ---------------------------------------------------------------- tools

need() {
    local t missing=''
    for t in git go node npm docker python3 curl; do
        command -v "$t" >/dev/null || missing="$missing $t"
    done
    if [[ -n $missing ]]; then
        printf '  %s✗%s missing:%s\n' "$R" "$N" "$missing" >&2
        printf '    brew install go node@20 python@3.12; Docker Desktop: https://www.docker.com/products/docker-desktop/\n' >&2
        exit 1
    fi
    docker info >/dev/null 2>&1 || die "Docker Desktop is not running: open -a Docker"
    go version | grep -qE 'go1\.(2[2-9]|[3-9][0-9])' || die "Go 1.22 or newer: $(go version)"
    node -e 'process.exit(+process.versions.node.split(".")[0] >= 18 ? 0 : 1)' || die "Node 18.17 or newer (CI: 20): $(node -v)"
}

air_bin() {
    if command -v air >/dev/null; then
        command -v air
    elif [[ -x $(go env GOPATH)/bin/air ]]; then
        echo "$(go env GOPATH)/bin/air"
    fi
}

# ---------------------------------------------------------------- sources

# A submodule on its dev branch, tracking origin/dev (submodules check out a detached commit).
on_dev() {
    local dir=$1 name
    name=$(basename "$dir")
    git -C "$dir" fetch -q origin dev
    if [[ -n $(git -C "$dir" branch --show-current) ]]; then
        ok "$name on $(git -C "$dir" branch --show-current) (left as it is)"
    elif git -C "$dir" show-ref -q --verify refs/heads/dev; then
        git -C "$dir" switch -q dev && git -C "$dir" merge -q --ff-only origin/dev
        ok "$name on dev"
    else
        git -C "$dir" switch -q -c dev --track origin/dev
        ok "$name on dev"
    fi
}

# ---------------------------------------------------------------- database

database() {
    local i
    if ! docker ps --format '{{.Names}}' | grep -qx "$DB"; then
        if docker ps -a --format '{{.Names}}' | grep -qx "$DB"; then
            docker start "$DB" >/dev/null
        else
            docker run -d --name "$DB" --restart unless-stopped \
                -e POSTGRES_USER=netra -e POSTGRES_PASSWORD=netra -e POSTGRES_DB=netra_dev \
                -p "127.0.0.1:$DB_PORT:5432" -v netra-dev-db:/var/lib/postgresql/data \
                timescale/timescaledb:latest-pg16 >/dev/null
        fi
    fi
    for i in $(seq 1 60); do
        docker exec "$DB" pg_isready -U netra -q 2>/dev/null && break
        [[ $i == 60 ]] && die "PostgreSQL did not start: docker logs $DB"
        sleep 1
    done
}

# ---------------------------------------------------------------- licenses

# Profile name, its netra-license flags, what it is for.
PROFILES='gardu|-edition substation -tier basic -name NETRA-Gardu|substation inspection, GPS map
gardu-pro|-edition substation -tier pro -name NETRA-Gardu|+ report exports, Telegram alerts, audit log
gardu-enterprise|-edition substation -tier enterprise -name NETRA-Gardu|+ server AI, integration API, multi-site
mall|-edition mall -tier basic -map pgm -name NETRA-Mall|anomalies and crowd, robot maps (pgm)
mall-pro|-edition mall -tier pro -map pgm -name NETRA-Mall|+ report exports, Telegram alerts, audit log
mall-enterprise|-edition mall -tier enterprise -map pgm -name NETRA-Mall|+ server AI, integration API, multi-site
mall-floorplan|-edition mall -tier pro -name NETRA-Mall|mall on a calibrated floor plan (no demo robots)
core|-edition custom -tier basic|the core only: robots, map, routes, patrols, schedules
all|-edition mall -tier enterprise -add substation -map gps -name NETRA|every module, GPS map
none|-|no license: the core with one robot'

profile_flags() { printf '%s\n' "$PROFILES" | awk -F'|' -v p="$1" '$1 == p { print $2 }'; }

license_tool() {
    mkdir -p "$LICDIR" "$BE/bin"
    (cd "$BE" && go build -o bin/netra-license ./cmd/netra-license)
    [[ -f $LICDIR/dev.key ]] || "$BE/bin/netra-license" keygen -out "$LICDIR/dev" >/dev/null
}

write_env() {
    local lic=$1 ollama=''
    curl -fsS --max-time 1 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && ollama=http://127.0.0.1:11434
    cat >"$ENVF" <<EOF
# Written by scripts/dev.sh; the API, the VS Code debugger and go test read it.
NETRA_ADDR=${NETRA_DEV_ADDR:-127.0.0.1}:$API_PORT
NETRA_DATABASE_URL=postgres://netra:netra@127.0.0.1:$DB_PORT/netra_dev?sslmode=disable
NETRA_DATA_DIR=$BE/data
NETRA_LICENSE_FILE=$lic
NETRA_ADMIN_USER=admin
NETRA_ADMIN_PASSWORD=admin
NETRA_PUBLIC_URL=http://localhost:$WEB_PORT
NETRA_ALLOWED_ORIGIN=*
NETRA_TZ=Asia/Jakarta
NETRA_FINAL_DETECTOR_URL=
NETRA_OLLAMA_URL=$ollama
EOF
}

# license <profile> [netra-license flags]: issue it with the development key, restart the API if it runs.
cmd_license() {
    local profile=${1:-} flags name
    [[ -n $profile ]] || {
        cmd_licenses
        exit 0
    }
    shift
    flags=$(profile_flags "$profile")
    [[ -n $flags ]] || die "unknown profile $profile: scripts/dev.sh licenses"
    license_tool
    if [[ $flags == - ]]; then
        write_env ''
        ok "no license: the core with one robot"
    else
        # Profile names use - for spaces in -name; extra flags come last and win.
        name=$(printf '%s\n' "$flags" | sed -n 's/.*-name \([^ ]*\).*/\1/p' | tr - ' ')
        flags=$(printf '%s\n' "$flags" | sed 's/ -name [^ ]*//')
        # shellcheck disable=SC2086 # the profile's flags are words
        "$BE/bin/netra-license" issue -key "$LICDIR/dev.key" -client Development -days 90 \
            ${name:+-name "$name"} $flags "$@" -out "$LICDIR/dev.lic" >/dev/null
        write_env "$LICDIR/dev.lic"
        echo "$profile $*" >"$LICDIR/profile"
        ok "license $B$profile$N $* $D(90 days, $LICDIR/dev.lic)$N"
        printf '    %s\n' "$(license_summary)"
    fi
    [[ $profile == none ]] && echo none >"$LICDIR/profile"
    if running api; then
        restart_api
    fi
}

cmd_licenses() {
    title "License profiles (scripts/dev.sh license <profile> [netra-license flags])"
    printf '%s\n' "$PROFILES" | while IFS='|' read -r p _ what; do
        printf '  %s%-17s%s %s\n' "$C" "$p" "$N" "$what"
    done
    title "Extra flags (added after the profile, they win)"
    printf '  -map floorplan|pgm|gps   -robots N   -add a,b   -remove a,b   -name "NETRA Lippo"\n'
    printf '  -color "#b91c1c" -color-dark "#f87171" -logo logo.svg   -days N\n'
    printf '  modules: anomaly crowd substation reports.export alerts.telegram audit ai.final integration multisite\n'
    title "In use"
    if [[ -f $LICDIR/profile ]]; then
        printf '  %s\n' "$(cat "$LICDIR/profile")"
        if [[ -f $LICDIR/dev.lic && $(cut -d' ' -f1 "$LICDIR/profile") != none ]]; then
            printf '  %s\n' "$(license_summary)"
        fi
    else
        printf '  none yet: scripts/dev.sh setup\n'
    fi
    return 0
}

# One line about the license in use: edition/tier, map, modules, name, expiry.
license_summary() {
    "$BE/bin/netra-license" inspect -pub "$LICDIR/dev.pub" "$LICDIR/dev.lic" 2>/dev/null | python3 -c '
import json, sys
t = sys.stdin.read()
j = json.loads(t[t.index("{"):t.rindex("}") + 1])
parts = [j["edition"] + "/" + j["tier"], "map " + j["map"], " ".join(j.get("features") or []) or "core only"]
if (j.get("branding") or {}).get("name"):
    parts.append(j["branding"]["name"])
if j.get("max_robots"):
    parts.append(str(j["max_robots"]) + " robots")
parts.append("until " + (j.get("expires_at") or "never")[:10])
print(" · ".join(parts))
' 2>/dev/null || true
}

build_key() { echo "-X github.com/DarmawanWeb/netra-fleet-be/internal/license.BuildKey=$(cat "$LICDIR/dev.pub")"; }

# ---------------------------------------------------------------- editor

workspace() {
    cat >"$ROOT/netra.code-workspace" <<EOF
{
  "folders": [
    { "name": "NETRA", "path": "." },
    { "name": "netra-fleet-be", "path": "be" },
    { "name": "netra-fleet-fe", "path": "fe" }
  ],
  "settings": {
    "editor.formatOnSave": true,
    "files.exclude": { "be": true, "fe": true, ".dev": true },
    "go.lintTool": "golangci-lint",
    "go.testEnvFile": "\${workspaceFolder:netra-fleet-be}/.dev/dev.env",
    "[go]": { "editor.defaultFormatter": "golang.go", "editor.codeActionsOnSave": { "source.organizeImports": "explicit" } },
    "[typescript]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
    "[typescriptreact]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
    "[css]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
    "[python]": { "editor.formatOnSave": false },
    "eslint.workingDirectories": [{ "pattern": "fe" }],
    "typescript.tsdk": "fe/node_modules/typescript/lib",
    "tailwindCSS.experimental.configFile": "fe/tailwind.config.ts"
  },
  "launch": {
    "version": "0.2.0",
    "configurations": [
      {
        "name": "API (debug)",
        "type": "go",
        "request": "launch",
        "mode": "debug",
        "program": "\${workspaceFolder:netra-fleet-be}/cmd/netra-api",
        "envFile": "\${workspaceFolder:netra-fleet-be}/.dev/dev.env",
        "buildFlags": "-ldflags=-X=github.com/DarmawanWeb/netra-fleet-be/internal/license.BuildKey=$(cat "$LICDIR/dev.pub")"
      },
      {
        "name": "Dashboard (next dev)",
        "type": "node-terminal",
        "request": "launch",
        "command": "$ROOT/scripts/dev.sh web"
      }
    ]
  },
  "tasks": {
    "version": "2.0.0",
    "tasks": [
      { "label": "NETRA: API (reload on save)", "type": "shell", "command": "$ROOT/scripts/dev.sh api", "isBackground": true, "problemMatcher": [], "presentation": { "panel": "dedicated" } },
      { "label": "NETRA: dashboard", "type": "shell", "command": "$ROOT/scripts/dev.sh web", "isBackground": true, "problemMatcher": [], "presentation": { "panel": "dedicated" } },
      { "label": "NETRA: API + dashboard", "dependsOn": ["NETRA: API (reload on save)", "NETRA: dashboard"], "problemMatcher": [] },
      { "label": "NETRA: demo robots", "type": "shell", "command": "$ROOT/scripts/dev.sh demo", "problemMatcher": [] },
      { "label": "NETRA: license profiles", "type": "shell", "command": "$ROOT/scripts/dev.sh licenses", "problemMatcher": [] },
      { "label": "NETRA: check (like CI)", "type": "shell", "command": "$ROOT/scripts/dev.sh check", "problemMatcher": [], "group": "test" }
    ]
  },
  "extensions": {
    "recommendations": ["golang.go", "esbenp.prettier-vscode", "dbaeumer.vscode-eslint", "bradlc.vscode-tailwindcss", "ms-python.python"]
  }
}
EOF
}

# ---------------------------------------------------------------- processes

running() { [[ -f $RUN/$1.pid ]] && kill -0 "$(cat "$RUN/$1.pid")" 2>/dev/null; }

# A process and everything it started (air and the API, next and its workers, go run and its binary).
kill_tree() {
    local child
    for child in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$child"; done
    kill "$1" 2>/dev/null || true
}

stop() {
    [[ -f $RUN/$1.pid ]] || return 0
    kill_tree "$(cat "$RUN/$1.pid")"
    rm -f "$RUN/$1.pid"
}

background() {
    local name=$1
    shift
    mkdir -p "$RUN"
    nohup "$ROOT/scripts/dev.sh" "$@" >"$RUN/$name.log" 2>&1 </dev/null &
    echo $! >"$RUN/$name.pid"
}

wait_api() {
    local i
    for i in $(seq 1 180); do
        curl -fsS --max-time 2 "$API_URL/readyz" >/dev/null 2>&1 && return 0
        running api || {
            tail -15 "$RUN/api.log" >&2
            die "the API stopped: $RUN/api.log"
        }
        [[ $i == 180 ]] && die "the API is not ready after 3 minutes: $RUN/api.log"
        sleep 1
    done
}

restart_api() {
    stop api
    background api api
    wait_api
    ok "API restarted with the new license"
}

port_free() { ! lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

# ---------------------------------------------------------------- commands

cmd_setup() {
    title "Tools"
    need
    ok "$(go version | awk '{print $3}'), node $(node -v), Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
    if [[ -n $(air_bin) ]]; then
        ok "air (API hot reload)"
    elif go install github.com/air-verse/air@latest >/dev/null 2>&1; then
        ok "air installed in $(go env GOPATH)/bin"
    else
        warn "air could not be installed: the API runs with go run (restart it by hand)"
    fi

    title "Sources"
    [[ -f $BE/go.mod && -f $FE/package.json ]] || git submodule update --init
    on_dev "$BE"
    on_dev "$FE"

    title "Packages"
    (cd "$BE" && go mod download) && ok "Go modules"
    (cd "$FE" && npm ci --no-audit --no-fund --loglevel=error >/dev/null) && ok "npm packages"

    title "Database"
    database
    ok "PostgreSQL 16 + TimescaleDB, container $DB on 127.0.0.1:$DB_PORT (netra / netra, netra_dev)"

    title "License"
    if [[ -f $LICDIR/profile ]]; then
        ok "keeping $(cat "$LICDIR/profile") (scripts/dev.sh license <profile> to change)"
        license_tool
    else
        cmd_license gardu
    fi

    title "Editor"
    workspace
    ok "netra.code-workspace (API debugger, tasks, formatters)"

    printf '\n  Next: %sscripts/dev.sh up%s, then %scode netra.code-workspace%s\n' "$B" "$N" "$B" "$N"
}

# The API in this terminal, rebuilt on every saved .go or .sql file (air), else go run.
cmd_api() {
    local air
    [[ -f $ENVF ]] || die "scripts/dev.sh setup first"
    database
    set -a
    # shellcheck disable=SC1090 # written by write_env
    . "$ENVF"
    set +a
    cd "$BE"
    air=$(air_bin)
    if [[ -n $air ]]; then
        # Config in bin/ (ignored by git); entrypoint for current air, bin for older ones.
        mkdir -p bin/air
        cat >bin/air.toml <<EOF
root = "."
tmp_dir = "bin/air"
[build]
cmd = "go build -ldflags '$(build_key)' -o bin/air/netra-api ./cmd/netra-api"
entrypoint = "bin/air/netra-api"
bin = "bin/air/netra-api"
include_ext = ["go", "sql"]
exclude_dir = ["bin", "data", "ai", "scripts", "docs", "internal/web/dist", ".dev"]
delay = 500
[misc]
clean_on_exit = true
EOF
        exec "$air" -c bin/air.toml
    fi
    exec go run -ldflags "$(build_key)" ./cmd/netra-api
}

# The dashboard in this terminal: next dev, /api (REST and the live WebSocket) sent to the API.
cmd_web() {
    cd "$FE"
    NETRA_API_URL=$API_URL exec node_modules/.bin/next dev -H 127.0.0.1 -p "$WEB_PORT"
}

cmd_up() {
    local p
    [[ -f $ENVF ]] || die "scripts/dev.sh setup first"
    running api && running web && {
        ok "already running: http://localhost:$WEB_PORT"
        return 0
    }
    for p in "$API_PORT" "$WEB_PORT"; do
        port_free "$p" || die "port $p is used by $(lsof -nP -iTCP:"$p" -sTCP:LISTEN | awk 'NR==2{print $1}') (scripts/dev.sh down, or NETRA_API_PORT / NETRA_WEB_PORT)"
    done
    database
    background api api
    background web web
    printf '  %swaiting for the API (the first build takes a minute)%s\n' "$D" "$N"
    wait_api
    ok "API       $API_URL"
    for _ in $(seq 1 90); do
        curl -fsS --max-time 2 -o /dev/null "http://127.0.0.1:$WEB_PORT/login" 2>/dev/null && break
        sleep 1
    done
    ok "dashboard http://localhost:$WEB_PORT"
    printf '\n  %sLogin%s      admin / admin\n' "$B" "$N"
    printf '  %sLicense%s    %s\n' "$B" "$N" "$(cat "$LICDIR/profile" 2>/dev/null || echo none)"
    printf '  %sNext%s       scripts/dev.sh demo · scripts/dev.sh logs · scripts/dev.sh licenses\n' "$B" "$N"
}

cmd_down() {
    stop fleet
    stop web
    stop api
    ok "API, dashboard and robots stopped (the database keeps running: docker stop $DB)"
}

cmd_restart() {
    cmd_down
    cmd_up
}

cmd_demo() {
    local py=$STATE/venv/bin/python maps=$STATE/maps mode sub
    curl -fsS --max-time 2 "$API_URL/readyz" >/dev/null 2>&1 || die "start NETRA first: scripts/dev.sh up"
    title "Demo"
    [[ -x $py ]] || python3 -m venv "$STATE/venv"
    "$STATE/venv/bin/pip" install -q --disable-pip-version-check -r dev/demo/requirements.txt
    read -r mode sub < <(NETRA_URL=$API_URL "$py" dev/demo/mode.py)
    ok "map $mode, substation module: $sub"
    rm -rf "$maps" && mkdir -p "$maps"
    case $mode in
    gps) (cd "$maps" && "$py" -c "import json, sys; sys.path.insert(0, '$ROOT/dev/demo'); import scene; json.dump(scene.overlay('site.jpg'), open('site.json', 'w'))") ;;
    pgm) "$py" dev/demo/mkpgm.py "$maps/warehouse" >/dev/null && "$py" dev/demo/mkpgm.py "$maps/dock" dock >/dev/null ;;
    *) die "the demo robots drive on a GPS site or on robot maps; this license uses $mode (scripts/dev.sh license mall or gardu)" ;;
    esac
    stop fleet
    (
        cd dev/demo
        NETRA_URL=$API_URL nohup "$py" fleet.py "$mode" "$maps" >"$RUN/fleet.log" 2>&1 </dev/null &
        echo $! >"$RUN/fleet.pid"
    )
    for _ in $(seq 1 30); do
        grep -q 'fleet running' "$RUN/fleet.log" 2>/dev/null && break
        running fleet || {
            tail -5 "$RUN/fleet.log" >&2
            die "the robot simulator stopped: $RUN/fleet.log"
        }
        sleep 1
    done
    if [[ $mode == gps ]]; then ok "gi-01 and gi-02 patrolling the substation yard"; else ok "l1w-01 and l1w-02 patrolling the warehouse map"; fi
    if [[ $sub == substation && $mode == gps ]]; then
        printf '  %sequipment, inspection points and two weeks of captures (about a minute)%s\n' "$D" "$N"
        (cd dev/demo && NETRA_URL=$API_URL NETRA_PSQL="docker exec -i $DB psql -U netra -d netra_dev -qtAc" "$py" seed.py |
            grep -E '^(assets|points|captures)' | sed 's/^/    /')
        ok "substation demo"
    fi
    printf '\n  Open %shttp://localhost:%s%s%s · robots stop with scripts/dev.sh down\n' "$B" "$WEB_PORT" "$([[ $sub == substation ]] && echo /substation)" "$N"
}

cmd_new() {
    local branch=${1:-} dir
    [[ -n $branch ]] || die "usage: scripts/dev.sh new <branch>, e.g. feat/hotdog-inspection"
    for dir in "$BE" "$FE"; do
        [[ -z $(git -C "$dir" status --porcelain) ]] || die "$(basename "$dir") has uncommitted changes"
    done
    for dir in "$BE" "$FE"; do
        git -C "$dir" fetch -q origin dev
        git -C "$dir" switch -q -c "$branch" origin/dev
        ok "$(basename "$dir"): $branch from origin/dev"
    done
}

cmd_check() {
    title "netra-fleet-be"
    (
        cd "$BE"
        test -z "$(gofmt -l .)" || die "gofmt: $(gofmt -l . | tr '\n' ' ')"
        ok "gofmt"
        go vet ./... && ok "go vet"
        go test -race ./... >/dev/null && ok "go test -race"
        # The repository's .golangci.yml is for golangci-lint v1 (CI: v1.61); v2 cannot read it.
        if command -v golangci-lint >/dev/null && golangci-lint version 2>/dev/null | grep -q 'version v\{0,1\}1\.'; then
            golangci-lint run ./... && ok "golangci-lint"
        else
            warn "golangci-lint v1 not found (CI: v1.61): go install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.61.0"
        fi
    )
    title "netra-fleet-fe"
    (
        cd "$FE"
        npm run -s format:check >/dev/null && ok "prettier"
        npm run -s lint >/dev/null && ok "eslint"
        npm run -s typecheck && ok "tsc"
    )
}

cmd_status() {
    local name
    title "NETRA development"
    for name in api web fleet; do
        if running "$name"; then ok "$name running"; else printf '  %s·%s %s stopped\n' "$D" "$N" "$name"; fi
    done
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB"; then ok "database $DB"; else warn "database $DB stopped"; fi
    if curl -fsS --max-time 2 "$API_URL/readyz" >/dev/null 2>&1; then ok "API ready on :$API_PORT"; else warn "API not answering on :$API_PORT"; fi
    printf '  license  %s\n' "$(cat "$LICDIR/profile" 2>/dev/null || echo none)"
    printf '  be       %s\n  fe       %s\n' "$(git -C "$BE" branch --show-current)" "$(git -C "$FE" branch --show-current)"
}

cmd_logs() {
    mkdir -p "$RUN"
    if [[ -n ${1:-} ]]; then tail -n 60 -f "$RUN/$1.log"; else tail -n 30 -f "$RUN"/*.log; fi
}

cmd_open() { open "http://localhost:$WEB_PORT" 2>/dev/null || printf 'http://localhost:%s\n' "$WEB_PORT"; }

cmd_reset() {
    printf 'Delete the development database and data (photos, maps)? Code and licenses stay. [y/N] '
    read -r a
    [[ $a == y || $a == Y ]] || exit 0
    cmd_down
    docker rm -f "$DB" >/dev/null 2>&1 || true
    docker volume rm netra-dev-db >/dev/null 2>&1 || true
    rm -rf "$BE/data" "$STATE/maps"
    ok "reset: scripts/dev.sh up starts on an empty database"
}

case ${1:-} in
setup) cmd_setup ;;
up) cmd_up ;;
down) cmd_down ;;
restart) cmd_restart ;;
api) cmd_api ;;
web) cmd_web ;;
demo) cmd_demo ;;
license) shift && cmd_license "$@" ;;
licenses) cmd_licenses ;;
new) cmd_new "${2:-}" ;;
check) cmd_check ;;
status) cmd_status ;;
logs) cmd_logs "${2:-}" ;;
open) cmd_open ;;
reset) cmd_reset ;;
*) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0" ;;
esac
