# Releasing NETRA

A release is a tag on this repository (`vX.Y.Z`, or `vX.Y.Z-rc1` for a pre-release) with the
`be` and `fe` submodules on the commits to ship. The [release workflow](../.github/workflows/release.yml)
builds everything a client installs and publishes a GitHub release.

## Before tagging

1. `be` and `fe` are on their `main` commits with green CI; move the submodules here:
   `git submodule update --remote be fe && git commit -am "chore: update be and fe"`.
2. The trusted public key is in `be/internal/license/keys/` (no key: every installation runs the
   core only).
3. The secret `NETRA_REPO_TOKEN` exists in this repository: a token that can read
   `netra-fleet-be` and `netra-fleet-fe`, for the submodules.
4. Try the version on a test server: install the previous release, update with the new one,
   check the setup, a license, a robot, a backup and a restore.

## What the workflow builds

| Job | Output |
|---|---|
| `web` | the dashboard export (`fe/out`) |
| `binaries` | `netra-<os>-<arch>` for linux/amd64, linux/arm64, windows/amd64, darwin/amd64, darwin/arm64, with the dashboard inside and the version |
| `deb` | `netra_<version>_amd64.deb`, `netra_<version>_arm64.deb` ([packaging/linux](../packaging/linux)) |
| `windows` | `NETRA-Setup-<version>-x64.exe`: Inno Setup, WinSW service, PostgreSQL binaries ([packaging/windows](../packaging/windows)) |
| `macos` | `NETRA-<version>-macos.pkg`: universal binary, PostgreSQL binaries, launchd service ([packaging/macos](../packaging/macos)); not signed |
| `image` | `ghcr.io/<owner>/netra:<version>` and `:main`, linux/amd64 and arm64 ([Dockerfile](../Dockerfile)) |
| `release` | the GitHub release with the files above and `SHA256SUMS` |

Run it by hand (Actions > release > Run workflow, with a version) to build the files without
publishing a release.

## Build by hand

```bash
git submodule update --init
(cd fe && npm ci && npm run build)
rm -rf be/internal/web/dist && cp -r fe/out be/internal/web/dist
(cd be && go build -tags webui -ldflags "-X github.com/DarmawanWeb/netra-fleet-be/internal/version.Version=v1.2.0" -o ../netra ./cmd/netra)
packaging/linux/build-deb.sh netra v1.2.0 amd64 dist      # needs dpkg-deb
docker build --build-arg VERSION=v1.2.0 -t netra .        # the single image
```

## Installers in detail

- **Linux**: `/usr/bin/netra`, the systemd unit `netra.service` (user `netra`,
  `/var/lib/netra`), `/etc/netra/netra.env` (kept on upgrade). The postinst creates the `netra`
  role and database in the local PostgreSQL; the service connects through the socket with peer
  authentication, so no password is stored.
- **Windows**: `C:\Program Files\NETRA` (netra.exe, the WinSW wrapper `netra-service.exe`,
  `pgsql\`), `C:\ProgramData\NETRA` (netra.env, data, logs). The service runs as Network Service;
  NETRA runs its own PostgreSQL in `data\pgdata` on 127.0.0.1:5433. Upgrades stop the service
  first and keep netra.env.
- **macOS**: `/Library/NETRA`, the LaunchDaemon `id.ezrarobotics.netra` running as the hidden
  user `_netra`, `/Library/Application Support/NETRA`; its own PostgreSQL like Windows. Sign it
  with a Developer ID (`productsign`) to avoid the Gatekeeper warning.
- **Docker**: the compose file of this repository; the database is the `db` service and the
  `backup` service dumps it.
