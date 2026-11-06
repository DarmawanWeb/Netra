# Developing NETRA

One command sets up a working copy for development on a Mac:

- the backend and the dashboard on their `dev` branch;
- the API rebuilding itself on every save;
- the dashboard on `next dev`;
- PostgreSQL in Docker;
- a development license of any edition;
- simulated robots;
- a VS Code workspace with the debugger ready.

Everything runs through [`scripts/dev.sh`](scripts/dev.sh).

```
 browser ──► dashboard  next dev  :4493 ──/api, WebSocket──►  API  netra-api  :4492 ──► PostgreSQL :55432
                fe/  (hot reload)                              be/  (air: rebuild on save)   Docker netra-dev-db
                                                                 ▲
                                    simulated robots (dev/demo) ─┘  robot WebSocket and uploads
```

## Contents

- [Quick start](#quick-start)
- [Commands](#commands)
- [Licenses](#licenses)
- [Demo data](#demo-data)
- [VS Code](#vs-code)
- [Daily work: branches and pull requests](#daily-work-branches-and-pull-requests)
- [Real robots against the development API](#real-robots-against-the-development-api)
- [Ports and files](#ports-and-files)
- [Troubleshooting](#troubleshooting)

## Quick start

Tools: Git with SSH access to GitHub, Go 1.22+, Node 20, Python 3 and Docker Desktop.

```bash
brew install go node@20 python@3.12          # what is missing
brew install --cask visual-studio-code docker # if not installed

git clone --recurse-submodules git@github.com:DarmawanWeb/Netra.git && cd Netra
scripts/dev.sh setup     # submodules on dev, packages, database, license "gardu", VS Code workspace
scripts/dev.sh up        # API :4492 + dashboard :4493
scripts/dev.sh demo      # two robots patrolling, and two weeks of substation inspections
code netra.code-workspace
```

Open <http://localhost:4493> and sign in as **admin / admin**.

`setup` can run again at any time. It keeps the license, the branches you are on and the data.

## Commands

| Command | What it does |
|---|---|
| `scripts/dev.sh setup` | Checks the tools, installs `air`, moves `be/` and `fe/` to `dev`, runs `go mod download` and `npm ci`, starts the database, issues the first license, writes the VS Code workspace |
| `scripts/dev.sh up` | Starts the API and the dashboard in the background, waits until they answer |
| `scripts/dev.sh down` | Stops the API, the dashboard and the robots; the database keeps running |
| `scripts/dev.sh restart` | `down` then `up` |
| `scripts/dev.sh api` | The API in this terminal, rebuilt on every saved `.go` or `.sql` file |
| `scripts/dev.sh web` | The dashboard in this terminal (`next dev`, `/api` and the WebSocket sent to the API) |
| `scripts/dev.sh demo` | Simulated robots on the license's map; on a substation license also equipment, inspection points and two weeks of captures |
| `scripts/dev.sh license <profile> [flags]` | Issues a development license and restarts the API if it runs ([Licenses](#licenses)) |
| `scripts/dev.sh licenses` | The profiles, the extra flags and the license in use |
| `scripts/dev.sh new <branch>` | Creates the same branch from `origin/dev` in `be/` and `fe/` |
| `scripts/dev.sh check` | What CI runs: gofmt, go vet, `go test -race`, golangci-lint, Prettier, ESLint, tsc |
| `scripts/dev.sh status` | Processes, database, API, license, branches |
| `scripts/dev.sh logs [api\|web\|fleet]` | Follows the logs (all of them without a name) |
| `scripts/dev.sh open` | Opens the dashboard in the browser |
| `scripts/dev.sh reset` | Deletes the database and the data (photos, maps); asks first; code and license stay |

## Licenses

What the dashboard shows depends on the license, exactly as at a client. A license has three parts:

- the **edition**, which brings the product modules;
- the **tier**, which brings the premium modules;
- the **map mode**.

`-add` and `-remove` change single modules on top of that. The development key in `be/.dev/` signs the licenses below. Only development builds trust that key.

| Part | Values |
|---|---|
| Core (always) | robots, live map, commands, routes, patrols, schedules, floor plans, users, patrol PDF |
| Edition | `mall`: anomaly, crowd · `substation`: substation · `custom`: none |
| Tier | `basic`: none · `pro`: reports.export, alerts.telegram, audit · `enterprise`: pro + ai.final, integration, multisite |
| Map | `floorplan` (default for mall and custom) · `pgm` robot maps · `gps` (default for substation) |

### Profiles

| Profile | License | For |
|---|---|---|
| `gardu` | substation / basic, GPS | substation inspection (HotDog) |
| `gardu-pro` | substation / pro, GPS | + report exports, Telegram alerts, audit log |
| `gardu-enterprise` | substation / enterprise, GPS | + server AI, integration API, multi-site |
| `mall` | mall / basic, robot maps | anomalies and crowd (Pashupati) |
| `mall-pro` | mall / pro, robot maps | + report exports, Telegram alerts, audit log |
| `mall-enterprise` | mall / enterprise, robot maps | + server AI, integration API, multi-site |
| `mall-floorplan` | mall / pro, floor plan | a calibrated floor plan, as most malls run (no demo robots) |
| `core` | custom / basic | the core only |
| `all` | mall / enterprise + substation, GPS | every module at once |
| `none` | no license | the core with one robot, as an unlicensed install |

### Extra flags

Flags after the profile go to `netra-license issue`. Coming last, they override the profile:

```bash
scripts/dev.sh license gardu-pro -map pgm                    # substation on robot maps
scripts/dev.sh license gardu-pro -add anomaly                # substation with the anomaly queue
scripts/dev.sh license mall-pro -remove crowd                # mall without crowd analytics
scripts/dev.sh license mall-pro -robots 2                    # the robot limit
scripts/dev.sh license mall-floorplan -name "NETRA Lippo" -color "#b91c1c" -color-dark "#f87171" -logo ~/lippo.svg
scripts/dev.sh license gardu -days 1                         # a license about to expire
scripts/dev.sh license core -add reports.export,audit        # pick modules by hand
```

Modules: `anomaly` `crowd` `substation` `reports.export` `alerts.telegram` `audit` `ai.final` `integration` `multisite`.

The data stays when the license changes. For a clean view of the new edition, run `scripts/dev.sh reset`, then `up` and `demo`.

### Client licenses

Client licenses are not made here. They are signed with EZRA's own key and bound to the client's installation ID: use the License Manager or `netra-license issue -installation NETRA-…` ([licensing](https://github.com/DarmawanWeb/netra-fleet-be/blob/main/docs/licensing.md), [client kit](docs/client-kit.md)).

## Demo data

`scripts/dev.sh demo` uses the tools in [`dev/demo/`](dev/demo). It installs them into a Python virtual environment in `.dev/venv` and drives robots until `scripts/dev.sh down`.

| License map | What appears |
|---|---|
| `gps` | The substation yard: control points, an aerial image. Robots `gi-01` and `gi-02` patrol their routes. |
| `gps` with `substation` | Also, by [`seed.py`](dev/demo/seed.py): 23 pieces of equipment in 8 bays, 11 inspection points and two weeks of thermal and partial discharge captures (see below). |
| `pgm` | Two robot maps (warehouse, loading dock). Robots `l1w-01` and `l1w-02` patrol on them, with anomalies and a crowd window. |
| `floorplan` | Nothing. The robots need a GPS site or robot maps. |

The captures follow four findings:
- a disconnector clamp heating up to P1;
- partial discharge on a transformer bushing rising to P2, acknowledged;
- a CT clamp at P3, in hand;
- a coupler clamp repaired and resolved.

| File | |
|---|---|
| `fleet.py` | Registers the robots, uploads a route each, starts the patrols, reports anomalies and a crowd window, sends telemetry every second |
| `scene.py` | The substation site: the map-to-WGS84 transform, the routes, the aerial image |
| `mkpgm.py` | SLAM-looking robot maps (`map.yaml` + `map.pgm`) |
| `seed.py`, `render.py` | Substation equipment, points and captures with synthetic thermal, visual and acoustic images |
| `mode.py` | The map mode and modules of the running server |

## VS Code

`setup` writes `netra.code-workspace` with three folders: NETRA, netra-fleet-be and netra-fleet-fe. Open it with `code netra.code-workspace` and install the recommended extensions when asked: Go, Prettier, ESLint, Tailwind CSS and Python.

- **Run and Debug › API (debug)**: the API under the debugger, with breakpoints, the development license and `be/.dev/dev.env`. Stop `scripts/dev.sh api` first, because both need port 4492.
- **Run and Debug › Dashboard (next dev)**: the dashboard in a terminal.
- **Terminal › Run Task**:
  - `NETRA: API + dashboard`
  - `NETRA: demo robots`
  - `NETRA: license profiles`
  - `NETRA: check (like CI)`
- **Format on save**: gofmt and organised imports for Go, Prettier for TypeScript and CSS. These are the same rules CI checks.
- **Tests from the editor**: `go test` reads `be/.dev/dev.env`.

## Daily work: branches and pull requests

`be/` and `fe/` are ordinary clones of [netra-fleet-be](https://github.com/DarmawanWeb/netra-fleet-be) and [netra-fleet-fe](https://github.com/DarmawanWeb/netra-fleet-fe). Commit and push inside them.

```bash
scripts/dev.sh new feat/hotdog-inspection   # the branch in be/ and fe/, from origin/dev
# code, save (the API and the dashboard reload), try it with scripts/dev.sh demo
scripts/dev.sh check                        # before every push
git -C be push -u origin feat/hotdog-inspection
gh pr create -R DarmawanWeb/netra-fleet-be --base dev --head feat/hotdog-inspection --fill
gh pr merge <n> -R DarmawanWeb/netra-fleet-be --merge   # merge commits, branches kept
```

The flow:

1. Feature branches go into `dev` through pull requests.
2. `dev` goes into `main` through a pull request. CI runs on that PR and on `main`.
3. This repository then points `be/` and `fe/` at the new `main` with a `chore: update be and fe` pull request.

A conventional commit per change, one line.

## Real robots against the development API

The API listens on 127.0.0.1 only.

1. To let a robot on the network reach it, run `NETRA_DEV_ADDR=0.0.0.0 scripts/dev.sh license <profile>`. This rewrites `be/.dev/dev.env`.
2. Run `scripts/dev.sh restart`.
3. In the dashboard, register the robot in **Settings › Robots** and copy its token.
4. Point the robot at `http://<this Mac>:4492`.

## Ports and files

| | |
|---|---|
| `:4493` | dashboard (`next dev`, 127.0.0.1) |
| `:4492` | API (`netra-api`) |
| `:55432` | PostgreSQL 16 + TimescaleDB, container `netra-dev-db`, volume `netra-dev-db`, user and password `netra`, database `netra_dev` |
| `NETRA_API_PORT`, `NETRA_WEB_PORT`, `NETRA_DB_PORT` | other ports, for example next to the stacks of the Mac mini ([LOCAL.md](LOCAL.md#next-to-other-stacks)) |
| `be/.dev/` | development key, license, `dev.env` (ignored by git, as for `make run-licensed`) |
| `be/data/` | photos, floor plans, inspection images |
| `be/bin/` | `netra-license`, air's builds and `air.toml` |
| `.dev/` | process logs and pids, the demo's virtual environment and maps |
| `netra.code-workspace` | written by `setup` (ignored by git) |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `missing: go …` | `brew install go node@20 python@3.12`, then open a new terminal |
| `Docker Desktop is not running` | `open -a Docker`, wait for the whale, then run the command again |
| `port 4492 is used by …` | `scripts/dev.sh down`; if the port belongs to another stack, use another one: `NETRA_API_PORT=4496 NETRA_WEB_PORT=4497 scripts/dev.sh up` |
| `admin / admin` refused | The database already has users from before. Either reset the password with `cd be && set -a && . .dev/dev.env && set +a && go run ./cmd/netra reset-password admin admin`, or start over with `scripts/dev.sh reset` |
| The API does not reload | `air` is missing (`go install github.com/air-verse/air@latest`, with `~/go/bin` in `PATH`); `scripts/dev.sh logs api` |
| The header says "Offline" (Terputus) | The API is not answering on 4492: `scripts/dev.sh status`, `scripts/dev.sh logs api` |
| Modules missing in the menu | That is the license: `scripts/dev.sh licenses`, then `scripts/dev.sh license all` |
| `the demo robots drive on a GPS site or on robot maps` | The license uses a floor plan: `scripts/dev.sh license mall` or `gardu` |
| `golangci-lint v1 not found` | CI uses v1.61 with this repository's config: `go install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.61.0` |
