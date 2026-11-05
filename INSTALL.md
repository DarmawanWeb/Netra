# Installing NETRA

NETRA is one application: the command center's service and its dashboard, with its database.
Install it on a computer that stays on, on the same network as the robots. Then finish the setup
in a browser. (Indonesian: [INSTALL.id.md](INSTALL.id.md).)

## What you receive from EZRA Robotics

| Item | |
|---|---|
| Installer | `NETRA-Setup-<version>-x64.exe` (Windows), `netra_<version>_amd64.deb` (Ubuntu/Debian), `NETRA-<version>-macos.pkg` (macOS), or the Docker image `ghcr.io/darmawanweb/netra` |
| License | `<client>.lic`, issued for your server's installation ID (see [License](#license)) |
| Guides | this guide and the operator guide (PDF) |

## Requirements

- 64-bit Windows 10/11 or Windows Server 2019+, Ubuntu 22.04/24.04 or Debian 12, or macOS 13+.
- 4 CPU cores, 8 GB of memory, 50 GB of free disk (photos and maps grow with use).
- A fixed address on the robots' network (set a DHCP reservation in the router).
- Optional, for AI verification: [Ollama](https://ollama.com) with a vision model; a GPU or
  16 GB of memory for the 7B models.

## Install

**Windows.** Run `NETRA-Setup-<version>-x64.exe` as an administrator. It installs NETRA and
its database, starts the **NETRA** service (it starts with Windows), opens port 8080 in the
firewall, and opens the browser at the end. Configuration and data:
`C:\ProgramData\NETRA` (`netra.env`, `data\`, `logs\`).

**Ubuntu or Debian.**

```bash
sudo apt install ./netra_<version>_amd64.deb
```

It installs PostgreSQL when missing, creates the `netra` database and starts the `netra`
service. Configuration: `/etc/netra/netra.env`. Data and backups: `/var/lib/netra`.
Logs: `journalctl -u netra -f`.

**macOS.** Open `NETRA-<version>-macos.pkg` (the first time: right-click > Open). Configuration
and data: `/Library/Application Support/NETRA`.

**Docker.** For servers already run with Docker: the Netra repository's `docker-compose.yml`
with the image `ghcr.io/darmawanweb/netra` ([README](README.md#deploy-on-a-server)).

## First-time setup

Open `http://<server address>:8080` in a browser on the same network. A new installation opens
the setup:

1. **Installation**: the installation ID of this server, such as `NETRA-7KQ3-M9XD-2WPA`. Copy
   it: your license is issued for it.
2. **Administrator**: the first account; it manages users, robots and the license.
3. **License**: paste the license or choose the `.lic` file. Without one you can continue: the
   core runs with one robot until the license is installed.

## License

The license names your organisation and decides the modules, the kind of map, the number of
robots and the validity. It works only on the server whose installation ID it names, without
internet.

- No license yet: send the installation ID to EZRA Robotics, then install the file you receive.
- Install or replace a license: **Settings › License** (administrators), at any time, without a
  restart. Or put the file at the license path of `netra.env` and restart the service.
- Settings › License shows the status, the modules, the robots against the limit and the expiry.
  Before it expires, ask for a renewal; after the expiry the modules keep working for 14 days.
- A new server (or a new database) has a new installation ID and needs a new license.

## Connect the robots

In **Settings › Robots**, add each robot. Copy its token, shown once, into the robot's
configuration with the address of this server (`CC_URL`), as the robot's guide describes.

## Configuration

`netra.env` holds the settings; restart the service after a change.

- Windows: services.msc > NETRA > Restart.
- Linux: `sudo systemctl restart netra`.
- macOS: `sudo launchctl kickstart -k system/id.ezrarobotics.netra`.

| Setting | |
|---|---|
| `NETRA_ADDR` | port (`:8080`); `:80` to open the dashboard without a port |
| `NETRA_PUBLIC_URL` | the address robots and phones use, e.g. `http://192.168.1.10:8080` |
| `NETRA_TLS=self-signed` | HTTPS with a certificate made by NETRA (browsers ask once to trust it); or `NETRA_TLS_CERT` and `NETRA_TLS_KEY` for your own |
| `NETRA_OLLAMA_URL` | AI verification on Ollama, e.g. `http://localhost:11434` (license module needed) |
| `NETRA_TELEGRAM_TOKEN`, `NETRA_TELEGRAM_CHAT_ID` | Telegram alerts (license module needed) |
| `NETRA_BACKUP_KEEP_DAYS`, `NETRA_BACKUP_AT` | daily database backups: days kept, time |

## Backups

NETRA backs up its database every day (02:30 by default) into the `backups` folder of its data
and keeps 14 days. The **System** page (administrators) lists the backups, makes one now and
downloads them, and shows the disk space.
Photos and maps are files in the data folder: copy that folder to another disk regularly.

Restore, with the service stopped:

```bash
netra restore -yes <data>/backups/netra-YYYYMMDD-HHMMSS.dump
```

## Update

Install the new version over the old one (the same installer or package). The data, the
configuration and the license stay; the database is upgraded at the next start.

## Forgotten administrator password

On the server, as an administrator:

- Windows: `"C:\Program Files\NETRA\netra.exe" reset-password admin`
- Linux: `sudo -u netra netra reset-password admin`
- macOS: `sudo -u _netra "/Library/NETRA/netra" -config "/Library/Application Support/NETRA/netra.env" reset-password admin`

It prints a new password and signs the account out everywhere.

## Commands

`netra version`, `netra installation-id`, `netra backup`, `netra restore -yes <file>`,
`netra license <file.lic>` (checks a license against this server),
`netra reset-password <user> [password]`.

## Troubleshooting

| Symptom | Check |
|---|---|
| The page does not open | the service runs (services.msc, `systemctl status netra`); the firewall allows the port; the address is the server's |
| Robots stay offline | the robot reaches the server: `curl http://<server>:8080/healthz` on the robot; the token is the one shown when the robot was added |
| "Not in your license" | the module is not in the license: Settings › License, then EZRA Robotics |
| License refused: "for another installation" | the license was issued for another server's ID; send this server's ID |
| Logs | Windows: `C:\ProgramData\NETRA\logs`; Linux: `journalctl -u netra`; macOS: `/Library/Application Support/NETRA/logs` |

## Uninstall

Windows: Settings > Apps > NETRA. Linux: `sudo apt remove netra` (`purge` also removes the
configuration). The data folder and the database stay until you delete them.
