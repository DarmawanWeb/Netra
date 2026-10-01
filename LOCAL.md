# Run NETRA Fleet on a Mac

The whole command center runs on one Mac; robots on the same Wi-Fi connect to it directly.
The vision model runs in a native Ollama on macOS so it can use the Apple GPU.

```
 Robot(s) ── Wi-Fi ──> Mac :80 (Caddy) ─┬─ /api, robot WebSocket ─> api ─┬─> TimescaleDB
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
cd netra-fleet
git submodule update --init --recursive   # be/ and fe/
scripts/local.sh setup                    # checks, .env with generated passwords, Ollama + model
scripts/local.sh up                       # builds and starts everything (first build: a few minutes)
scripts/local.sh awake                    # keep the Mac awake for schedules and robots
```

Open <http://localhost> and log in as `admin` with the password printed by `setup` (it is also
`NETRA_ADMIN_PASSWORD` in `.env`). Grafana is at <http://localhost/grafana>.

## Connect a robot over Wi-Fi

1. Put the robot and the Mac on the same Wi-Fi.
2. Register it on the Mac:

   ```bash
   scripts/local.sh robot l1w-01 "L1W 01"
   ```

   It prints the two lines for the robot:

   ```
   CC_URL=http://<your-mac>.local
   CC_TOKEN=...
   ```

3. On the robot: put them in `/etc/pashupati/pashupati.env`, then
   `sudo systemctl restart pashupati`. The robot appears online on the map within seconds.

`<your-mac>.local` keeps working when the Mac gets a new IP. If the robot cannot resolve `.local`
names (`ping <your-mac>.local` fails on the robot), use `CC_URL=http://<Mac IP>` instead and
reserve that IP for the Mac in the router (`ipconfig getifaddr en0` shows it).

Phones on the same Wi-Fi can open the dashboard and the Telegram links at the same address.

## Everyday commands

| Command | |
|---|---|
| `scripts/local.sh up` | start or update (rebuilds changed images) |
| `scripts/local.sh status` | containers and API health |
| `scripts/local.sh logs [api\|ai\|web\|db\|...]` | follow logs |
| `scripts/local.sh doctor` | check Docker, Ollama, model, AI link, LAN reachability, firewall, sleep |
| `scripts/local.sh down` | stop (data is kept) and allow sleep again |
| `scripts/local.sh reset` | stop and delete all data |

Data lives in Docker volumes (`db-data`, `api-data` for photos and floor plans, `grafana-data`);
daily database dumps go to `backups/`.

## Configuration (`.env`)

| Variable | |
|---|---|
| `NETRA_PUBLIC_URL` | address for robots, phones and Telegram links (`http://<mac>.local`) |
| `NETRA_ADMIN_PASSWORD` | first admin password (used when the database is created) |
| `NETRA_AI_MODEL` | Ollama vision model (`qwen2.5vl:7b`, `qwen2.5vl:3b`, `minicpm-v`, ...) |
| `NETRA_TELEGRAM_TOKEN`, `NETRA_TELEGRAM_CHAT_ID` | Telegram alerts (optional) |
| `NETRA_LANG` | language of Telegram captions (`en`, `id`) |

After editing `.env`: `scripts/local.sh up`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `doctor`: AI container cannot reach Ollama | `brew services stop ollama && OLLAMA_HOST=0.0.0.0 ollama serve` |
| Robot stays offline | `doctor` must show "reachable on http://<IP>"; on the robot `curl http://<mac>.local/healthz`; allow Docker in the macOS firewall |
| Port 80 already in use | stop the other web server (`sudo lsof -i :80`) |
| Anomalies stay "Analyzing" for long | the model is loading or too large for the RAM: use `qwen2.5vl:3b` |
| Schedules did not run | the Mac slept: `scripts/local.sh awake`, keep the lid open or use an external display |

## Moving to a server later

Remove `COMPOSE_FILE` from `.env`, set `NETRA_DOMAIN` to the real domain and follow the README:
the same stack then runs with HTTPS and the Ollama container (GPU server recommended).
