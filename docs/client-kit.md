# Delivering NETRA to a client

What EZRA Robotics hands over for each deployment, and in which order. The client-facing guide
is [INSTALL.md](../INSTALL.md) ([Indonesian](../INSTALL.id.md)); licenses are explained in
[netra-fleet-be licensing](https://github.com/DarmawanWeb/netra-fleet-be/blob/main/docs/licensing.md)
and issued with the
[License Manager](https://github.com/DarmawanWeb/netra-fleet-be/blob/main/docs/license-manager.md)
(`make license-manager` in netra-fleet-be, on EZRA's own computer).

## What the client gets

| Item | From | Notes |
|---|---|---|
| Installer for their server | the GitHub release of the version | Windows `NETRA-Setup-<v>-x64.exe`, Ubuntu/Debian `netra_<v>_<arch>.deb`, macOS `NETRA-<v>-macos.pkg`, Docker image `ghcr.io/darmawanweb/netra:<v>`; with `SHA256SUMS` |
| License file | the License Manager | bound to the server's installation ID; edition, tier, modules, map mode, robot limit, validity, branding |
| Install guide | `INSTALL.md` / `INSTALL.id.md` | install, first-time setup, license, robots, backups, updates, recovery |
| Operator guide | `docs/NETRA-Panduan-Operator.pdf` | daily use (mall edition today) |
| Robot settings | the client's Settings › Robots | each robot's token, shown once, and the server address |

Never send the signing key, the License Manager, the `netra-license` tool or a license issued for
another client.

## Steps

1. **Agree** on the edition (mall, substation), the tier (basic, pro, enterprise), extra modules,
   the map mode (floor plan, robot map, GPS), the number of robots, the validity, and the
   branding (application name, colours, logo as SVG or PNG up to 256 KB).
2. **Prepare the server** with the client: a computer that stays on, a fixed address on the
   robots' network, the requirements of INSTALL.md.
3. **Install** the version's installer. The browser opens the setup at `http://<server>:8080`.
4. **Activate**: the setup shows the installation ID (`NETRA-XXXX-XXXX-XXXX`). The client sends
   it; issue the license bound to it in the License Manager (the client's deployment record keeps
   the ID) and send the `.lic` file. The client installs it in the setup or later in
   Settings › License. No internet is needed on site.
5. **Configure**: users and roles, robots and their tokens, the map (floor plan, robot map or
   GPS site map), patrol routes and schedules; the AI model on Ollama if `ai.final` is included.
6. **Hand over**: the operator guide, a walk through backups and the System page, the support
   contact; note the installation ID, version and license expiry in the client's record.

## Afterwards

- **Renewal**: the License Manager lists licenses expiring in the next 30 days. Renew (same terms,
  new dates) and send the file; the client installs it in Settings › License, no restart.
- **Upgrade or downgrade** of tier or modules: a new license with the change. Data of a module
  that goes away stays in the database and comes back with the module.
- **New server or reinstallation on an empty database**: a new installation ID, so a new license.
  Restoring a backup keeps the installation ID.
- **Updates**: the new version's installer over the old one; the data, configuration and license
  stay. Read the release notes for anything to do on site.
- **Support**: ask for the System page (version, installation ID, disk, backups), the license
  status and the logs (INSTALL.md lists where they are).
