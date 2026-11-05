# License

Put the license of this deployment here as `netra.lic` (the one line `NETRA-LIC-1....` from EZRA
Robotics). The API reads it at start (`NETRA_LICENSE_FILE=/license/netra.lic`, mounted read-only),
so after replacing it run `docker compose up -d api`. An admin can also install a license in the
dashboard, Settings › License, without a restart.

Without a valid license NETRA runs the core only (robots, live map, routes, patrols, schedules,
floor plans, users, patrol reports) with one robot. The license decides the edition (mall,
substation), the tier (basic, pro, enterprise), the modules, the robot limit and the branding;
Settings › License shows what it includes.

License files are ignored by git (`*.lic`). How licenses work and how they are issued:
[netra-fleet-be licensing](https://github.com/DarmawanWeb/netra-fleet-be/blob/main/docs/licensing.md).
