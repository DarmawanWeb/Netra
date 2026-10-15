# Run NETRA Fleet on a Mac

The whole command center runs on one Mac; robots on the same network (Wi-Fi, hotspot or cable)
connect to it directly, with or without internet. The vision model runs in a native Ollama on
macOS so it can use the Apple GPU.

```
 Robot(s) ── LAN ──> Mac :80 (Caddy) ─┬─ /api, robot WebSocket ─> api ─┬─> TimescaleDB
                                       ├─ /grafana ─> grafana          ├─> NATS
                                       └─ /* ─> web (dashboard)        └─> ai ─> Ollama (native, Metal GPU)
```

## Requirements

- macOS on Apple Silicon (Intel works, the model is slower), 16 GB RAM recommended
  (8 GB: the setup picks the smaller `qwen2.5vl:3b` model).
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) with Compose 2.24+,
  Settings → Resources → Memory at least 4 GB.
- [Homebrew](https://brew.sh) (the setup installs Ollama with it).

## Start

```bash
cd Netra
git submodule update --init --recursive   # be/ and fe/
scripts/local.sh setup                    # checks, .env with generated passwords, Ollama + model
scripts/local.sh up                       # builds and starts everything (first build: a few minutes)
scripts/local.sh awake                    # keep the Mac awake for schedules and robots
```

Open <http://localhost> and log in as `admin` with the password printed by `setup` (it is also
`NETRA_ADMIN_PASSWORD` in `.env`). Grafana is at <http://localhost/grafana>.

## Connect a robot

1. Put the robot and the Mac on the same network: the same Wi-Fi, the robot's own Wi-Fi, a phone
   hotspot or a cable.
2. Register it on the Mac:

   ```bash
   scripts/local.sh robot l1w-01 "L1W 01"
   ```

   It prints the lines for the robot and every address of the Mac:

   ```
   ROBOT_ID=l1w-01
   CC_URL=http://<your-mac>.local
   CC_TOKEN=...
   ```

3. On the robot: check the address first (`curl http://<address>/healthz` answers `{"status":"ok"}`),
   put the lines in `/etc/pashupati/pashupati.env`, then `sudo systemctl restart pashupati`.
   The robot appears online on the dashboard within seconds.

`<your-mac>.local` keeps working when the Mac gets a new IP. If the robot cannot resolve `.local`
names (`ping <your-mac>.local` fails on the robot), use the IP that `scripts/local.sh lan` lists for
the robot's network and reserve it for the Mac in the router.

Phones on the same network can open the dashboard and the Telegram links at the same address.

## Demo: the command center on a laptop

For a demo away from the server (no internet, no tunnel), the laptop runs its own NETRA with a
copy of the server data: the same floor plans, routes, robots and robot tokens. On the robot only
`CC_URL` changes.

**Before the demo, with internet** (images are built and the model is pulled only once):

```bash
# on the server (Mac mini)
scripts/local.sh export                       # -> exports/netra-YYYYMMDD-HHMM.tar.gz

# on the laptop
git clone --recursive git@github.com:DarmawanWeb/Netra.git && cd Netra
scripts/local.sh setup && scripts/local.sh up
scripts/local.sh import netra-YYYYMMDD-HHMM.tar.gz   # copied from the server (AirDrop, USB, scp)
```

Log in on the laptop with `admin` / the laptop's `NETRA_ADMIN_PASSWORD`; other users keep their
passwords. Turn Wi-Fi off once and open <http://localhost> to be sure everything runs offline.

**At the demo:**

1. Connect the laptop and the robot to one network. In order of preference:
   - the robot's own Wi-Fi or network (the laptop joins it, for example `192.168.234.x`);
   - a phone hotspot or a travel router;
   - the venue Wi-Fi (often blocks devices from reaching each other: use one of the above).
2. `scripts/local.sh start` (no rebuild, so no internet needed), `scripts/local.sh awake`, then
   `scripts/local.sh lan` lists the laptop's address on that network, e.g. `http://192.168.234.57`.
3. On the robot (SSH):

   ```bash
   curl http://192.168.234.57/healthz          # must answer {"status":"ok"}
   sudo sed -i 's|^CC_URL=.*|CC_URL=http://192.168.234.57|' /etc/pashupati/pashupati.env
   sudo systemctl restart pashupati
   ```

   Started by hand instead of systemd: add `cc_url:=http://192.168.234.57 cc_token:=<token>
   robot_id:=<id>` to the `ros2 launch pashupati robot.launch.py` command.
4. The robot is online on the dashboard; start a patrol from the dashboard as usual.

Afterwards set `CC_URL` on the robot back to the server address. What happened during the demo
(patrols, anomalies) stays on the laptop.

A robot without internet keeps the clock it booted with; NETRA measures the offset from its
telemetry and puts the robot's anomaly, crowd and route times on the laptop's clock
(`clock_skew_s` in `GET /api/v1/robots`).

## Behind a Cloudflare Tunnel

To reach a Mac command center from the internet, add `docker-compose.tunnel.yml`:

```bash
# .env
COMPOSE_FILE=docker-compose.yml:docker-compose.local.yml:docker-compose.tunnel.yml
NETRA_PUBLIC_URL=https://netra.example.com
```

and point the tunnel hostname at `http://localhost:8088` in `~/.cloudflared/config.yml`.
Cloudflare terminates TLS. The LAN port stays open, so robots on the same network as the Mac can
still use `http://<Mac IP>` and keep working when the internet is down (`NETRA_LAN_BIND=127.0.0.1`
closes it).

## Everyday commands

| Command | |
|---|---|
| `scripts/local.sh up` | start or update (rebuilds changed images) |
| `scripts/local.sh start` | start the images built before, without internet (demo day) |
| `scripts/local.sh status` | containers and API health |
| `scripts/local.sh lan` | the Mac's address on every network, for `CC_URL` and phones |
| `scripts/local.sh logs [api\|ai\|web\|db\|...]` | follow logs |
| `scripts/local.sh doctor` | check Docker, Ollama, model, AI link, LAN reachability, firewall, sleep |
| `scripts/local.sh export [file]` | database, photos and floor plans in one file |
| `scripts/local.sh import <file>` | replace all data here with an export (asks first) |
| `scripts/local.sh down` | stop (data is kept) and allow sleep again |
| `scripts/local.sh reset` | stop and delete all data |

Data lives in Docker volumes (`db-data`, `api-data` for photos and floor plans, `grafana-data`);
daily database dumps go to `backups/`, exports to `exports/`.

## Configuration (`.env`)

| Variable | |
|---|---|
| `NETRA_PUBLIC_URL` | address for robots, phones and Telegram links (`http://<mac>.local`) |
| `NETRA_ADMIN_PASSWORD` | admin password, set again at every start of the API |
| `NETRA_AI_MODEL` | Ollama vision model (`qwen2.5vl:7b`, `qwen2.5vl:3b`, `minicpm-v`, ...) |
| `NETRA_TELEGRAM_TOKEN`, `NETRA_TELEGRAM_CHAT_ID` | Telegram alerts (optional, need internet) |
| `NETRA_LANG` | language of Telegram captions (`en`, `id`) |
| `NETRA_LAN_PORT` | port for the dashboard and robots (80); add it to `NETRA_PUBLIC_URL` when changed |
| `NETRA_TUNNEL_PORT`, `NETRA_LAN_BIND` | tunnel only: local port for cloudflared (8088), LAN side (`0.0.0.0`) |

After editing `.env`: `scripts/local.sh up`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `doctor`: AI container cannot reach Ollama | `brew services stop ollama && OLLAMA_HOST=0.0.0.0 ollama serve` |
| Robot stays offline | on the robot `curl http://<address>/healthz`; no answer: other network, venue Wi-Fi isolating devices, or the macOS firewall (allow Docker); `401` in `logs api`: wrong `CC_TOKEN` |
| Port 80 already in use | stop the other web server (`sudo lsof -i :80`) or set `NETRA_LAN_PORT` |
| `git pull` refuses: untracked `docker-compose.tunnel.yml` / `Caddyfile.tunnel` | delete the two hand-made files, the repository has them now |
| Anomalies stay "Analyzing" for long | the model is loading or too large for the RAM: use `qwen2.5vl:3b` |
| Schedules did not run | the Mac slept: `scripts/local.sh awake`, keep the lid open or use an external display |

## Moving to a server later

Remove `COMPOSE_FILE` from `.env`, set `NETRA_DOMAIN` to the real domain and follow the README:
the same stack then runs with HTTPS and the Ollama container (GPU server recommended).
