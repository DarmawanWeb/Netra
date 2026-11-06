"""Seed a substation demo on a running NETRA with the fleet simulator (fleet.py gps) already running:
equipment by bay, inspection points on the robots' routes and two weeks of captures with synthetic
thermal, visual and acoustic images. Stories: a disconnector clamp heating up to priority 1, partial
discharge on a transformer bushing escalating to 2, a CT clamp at 3 in hand, a coupler clamp repaired.

usage: NETRA_URL=http://127.0.0.1:4492 [NETRA_ROBOT_URL=...] python seed.py (after fleet.py gps)
"""
import datetime as dt
import json
import os
import random
import subprocess
import sys
import time

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render  # noqa: E402

API = os.environ.get('NETRA_URL', 'http://127.0.0.1:4492')
ROBOT = os.environ.get('NETRA_ROBOT_URL', API)
WIB = dt.timezone(dt.timedelta(hours=7))
DAYS = 14
rng = random.Random(7)

s = requests.Session()
s.headers['Authorization'] = 'Bearer ' + s.post(f'{API}/api/v1/auth/login', json={'username': os.environ.get('NETRA_USER', 'admin'), 'password': os.environ.get('NETRA_PASSWORD', 'admin')}).json()['token']
SUB = f'{API}/api/v1/substation'


def ok(r, what):
    if r.status_code >= 300:
        sys.exit(f'{what}: {r.status_code} {r.text[:300]}')
    return r.json()


# ---- equipment, bay by bay (bay centres from scene.py)
BAYS = {
    'Penghantar Cibatu 1': (20, -14), 'Penghantar Cibatu 2': (36, -14), 'Kopel': (52, -14), 'Trafo 1': (68, -14),
    'Penghantar Cikarang 1': (20, 14), 'Penghantar Cikarang 2': (36, 14), 'Trafo 2': (52, 14), 'Trafo 3': (68, 14),
}
ASSETS = [
    ('PMS-CBT1-B', 'PMS bus Cibatu 1', 'disconnector', 'Penghantar Cibatu 1', -2.5),
    ('PMT-CBT1', 'PMT Cibatu 1', 'breaker', 'Penghantar Cibatu 1', 0),
    ('CT-CBT1', 'CT Cibatu 1', 'current_transformer', 'Penghantar Cibatu 1', 1.5),
    ('LA-CBT1', 'LA Cibatu 1', 'surge_arrester', 'Penghantar Cibatu 1', 3),
    ('PMS-CBT2-B', 'PMS bus Cibatu 2', 'disconnector', 'Penghantar Cibatu 2', -2.5),
    ('PMT-CBT2', 'PMT Cibatu 2', 'breaker', 'Penghantar Cibatu 2', 0),
    ('CT-CBT2', 'CT Cibatu 2', 'current_transformer', 'Penghantar Cibatu 2', 1.5),
    ('PMS-KPL-A', 'PMS kopel bus A', 'disconnector', 'Kopel', -2),
    ('PMT-KPL', 'PMT kopel', 'breaker', 'Kopel', 1),
    ('TRF-1', 'Trafo 1 150/20 kV 60 MVA', 'transformer', 'Trafo 1', 0),
    ('PMT-TRF1', 'PMT Trafo 1', 'breaker', 'Trafo 1', -3),
    ('LA-TRF1', 'LA Trafo 1', 'surge_arrester', 'Trafo 1', 3),
    ('PMS-CKR1-L', 'PMS line Cikarang 1', 'disconnector', 'Penghantar Cikarang 1', 2.5),
    ('CT-CKR1', 'CT Cikarang 1', 'current_transformer', 'Penghantar Cikarang 1', 0),
    ('CVT-CKR1', 'CVT Cikarang 1', 'voltage_transformer', 'Penghantar Cikarang 1', -2),
    ('PMT-CKR2', 'PMT Cikarang 2', 'breaker', 'Penghantar Cikarang 2', 0),
    ('CT-CKR2', 'CT Cikarang 2', 'current_transformer', 'Penghantar Cikarang 2', 1.5),
    ('TRF-2', 'Trafo 2 150/20 kV 60 MVA', 'transformer', 'Trafo 2', 0),
    ('PMT-TRF2', 'PMT Trafo 2', 'breaker', 'Trafo 2', -3),
    ('TRF-3', 'Trafo 3 150/20 kV 60 MVA', 'transformer', 'Trafo 3', 0),
    ('LA-TRF3', 'LA Trafo 3', 'surge_arrester', 'Trafo 3', 3),
    ('BUS-A', 'Busbar 150 kV A', 'busbar', 'Busbar 150 kV', 0),
    ('BUS-B', 'Busbar 150 kV B', 'busbar', 'Busbar 150 kV', 0),
]
NOTES = {'TRF-1': 'Unindo 2009, ONAN/ONAF. Uji DGA terakhir Juli 2026.', 'PMS-CBT1-B': 'Merek Coelme, operasi motor.'}
have = {a['tag']: a for a in s.get(f'{SUB}/assets', params={'archived': 'true'}).json()}
asset = {}
for tag, name, kind, bay, dx in ASSETS:
    if tag in have:
        asset[tag] = have[tag]
        continue
    if bay == 'Busbar 150 kV':
        x, y = 45.0, -8.0 if tag.endswith('A') else 8.0
    else:
        bx, by = BAYS[bay]
        x, y = bx + dx, by
    body = {'tag': tag, 'name': name, 'kind': kind, 'bay': bay, 'voltage_kv': 150, 'x': x, 'y': y, 'notes': NOTES.get(tag, '')}
    if kind in ('disconnector', 'breaker', 'current_transformer', 'surge_arrester', 'voltage_transformer'):
        body['phase'] = 'R S T'
    asset[tag] = ok(s.post(f'{SUB}/assets', json=body), f'asset {tag}')
print('assets', len(asset), flush=True)

# ---- the robots' routes (fleet.py) and their tokens
routes = {r['robot_id']: r for r in s.get(f'{API}/api/v1/routes').json() if r['robot_id'] in ('gi-01', 'gi-02')}
if len(routes) < 2:
    sys.exit('run fleet.py gps first')
heads = {}
for rid in ('gi-01', 'gi-02'):
    tok = ok(s.post(f'{API}/api/v1/robots/{rid}/token'), 'token')['token']
    heads[rid] = {'Authorization': f'Bearer {tok}', 'X-Robot-Id': rid}


def clamp_targets(tag, keys=('r', 's', 't'), group='clamp', label='Klem fasa'):
    out = []
    for k, pos in zip(keys, ('r', 's', 't')):
        out.append({'key': k, 'label': f'{label} {k.upper()}' if len(k) == 1 else f'{label} {k[1:]}',
                    'phase': k.upper() if len(k) == 1 else '', 'group': group, 'asset_id': asset[tag]['id'],
                    'roi': render.CLAMP_ROI[pos]})
    return out


def bushing_targets(tag):
    return [{'key': k, 'label': f'Terminal bushing {k.upper()}', 'phase': k.upper(), 'group': 'bushing',
             'asset_id': asset[tag]['id'], 'roi': render.BUSHING_ROI[k], 'limit_c': 105} for k in ('r', 's', 't')]


# name, kind, asset, robot, stop, scene, targets, ptz, settings
POINTS = [
    ('PMS bus Cibatu 1 — klem', 'thermal', 'PMS-CBT1-B', 'gi-01', 0, 'clamps', clamp_targets('PMS-CBT1-B'), (34, 12, 6)),
    ('PMT Cibatu 1 — terminal', 'thermal', 'PMT-CBT1', 'gi-01', 0, 'clamps', clamp_targets('PMT-CBT1', label='Terminal'), (52, 10, 5)),
    ('Trafo 1 — bushing 150 kV', 'thermal', 'TRF-1', 'gi-01', 1, 'bushings', bushing_targets('TRF-1'), (-128, 18, 4)),
    ('Trafo 1 — PD bushing', 'pd', 'TRF-1', 'gi-01', 1, 'pd', [], (-128, 18, 4)),
    ('Trafo 3 — bushing 150 kV', 'thermal', 'TRF-3', 'gi-01', 2, 'bushings', bushing_targets('TRF-3'), (-150, 16, 4)),
    ('PMS line Cikarang 1 — klem', 'thermal', 'PMS-CKR1-L', 'gi-01', 3, 'clamps', clamp_targets('PMS-CKR1-L'), (-40, 12, 6)),
    ('CT Cikarang 1 — klem', 'thermal', 'CT-CKR1', 'gi-01', 3, 'clamps', clamp_targets('CT-CKR1'), (-28, 10, 6)),
    ('PMS kopel bus A — klem', 'thermal', 'PMS-KPL-A', 'gi-02', 0, 'clamps', clamp_targets('PMS-KPL-A'), (-62, 12, 5)),
    ('Busbar A — sambungan', 'thermal', 'BUS-A', 'gi-02', 0, 'clamps',
     clamp_targets('BUS-A', keys=('j1', 'j2', 'j3'), group='joint', label='Sambungan'), (-90, 20, 3)),
    ('Trafo 2 — bushing 150 kV', 'thermal', 'TRF-2', 'gi-02', 1, 'bushings', bushing_targets('TRF-2'), (-160, 16, 4)),
    ('PMT Cikarang 2 — terminal', 'thermal', 'PMT-CKR2', 'gi-02', 2, 'clamps', clamp_targets('PMT-CKR2', label='Terminal'), (48, 10, 5)),
]
existing = {p['name']: p for p in s.get(f'{SUB}/points').json()}
points = []
for name, kind, tag, rid, stop, scene, targets, (pan, tilt, zoom) in POINTS:
    body = {'name': name, 'kind': kind, 'asset_id': asset[tag]['id'], 'route_id': routes[rid]['id'], 'stop_index': stop,
            'ptz': {'pan_deg': pan, 'tilt_deg': tilt, 'zoom': zoom},
            'settings': {'emissivity': 0.9, 'distance_m': 9} if kind == 'thermal' else {}, 'targets': targets}
    p = existing.get(name) or ok(s.post(f'{SUB}/points', json=body), f'point {name}')
    points.append({**p, 'scene': scene, 'robot': rid, 'tag': tag})
print('points', len(points), flush=True)


# ---- the stories: extra heat (°C over its similar targets) or pd level, by day (0 = today, 13 = two weeks ago)
def ramp(day, pts):
    """Linear interpolation over (day, value) pairs, days descending."""
    pts = sorted(pts)
    if day <= pts[0][0]:
        return pts[0][1]
    for (d0, v0), (d1, v1) in zip(pts, pts[1:]):
        if d0 <= day <= d1:
            return v0 + (v1 - v0) * (day - d0) / (d1 - d0)
    return pts[-1][1]


def extra(point, key, day):
    name = point['name']
    if name.startswith('PMS bus Cibatu 1') and key == 't':
        return ramp(day, [(0, 17.6), (1, 15.8), (2, 12.9), (3, 8.6), (5, 6.7), (6, 4.6), (7, 2.9), (10, 2.1), (13, 1.6)])
    if name.startswith('CT Cikarang 1') and key == 's':
        return 0.8 if day > 9 else ramp(day, [(0, 6.4), (4, 5.8), (9, 5.1)])
    if name.startswith('PMS kopel') and key == 'r':
        return ramp(day, [(9, 9.6), (13, 7.8)]) if day >= 9 else 0.3
    if name.startswith('Trafo 2') and key == 't':
        return ramp(day, [(0, 5.6), (2, 4.4)]) if day <= 2 else 0.4
    if name.startswith('Trafo 1 — bushing') and key == 's':
        return 1.6
    return 0.0


def pd_level(day, rnd):
    if day >= 8:
        return (rnd.uniform(3, 6), day < 11)
    return (ramp(day, [(0, 23.4), (1, 22.1), (2, 20.6), (4, 16.2), (7, 11.2)]) + rnd.uniform(-0.6, 0.6), True)


def capture(p, when, day, rnd, patrol=None):
    afternoon = when.astimezone(WIB).hour >= 12
    ambient = round((32.8 if afternoon else 28.6) + rnd.uniform(-0.9, 0.9), 1)
    meta = {'uid': f"demo-{p['id']}-{int(when.timestamp())}", 'point_id': p['id'], 'ts': when.timestamp(),
            'ambient_c': ambient, 'pose': {'x': 0, 'y': 0, 'yaw': 0}}
    if p.get('stance'):
        meta['pose'] = {'x': p['stance']['x'] + rnd.uniform(-0.05, 0.05), 'y': p['stance']['y'] + rnd.uniform(-0.05, 0.05),
                        'yaw': 0}
    if patrol:
        meta['patrol_id'] = patrol
    files = {}
    if p['kind'] == 'pd':
        db, detected = pd_level(day, rnd)
        meta['pd'] = {'db': round(db, 1), 'detected': detected, 'kind': 'corona' if db < 15 else 'surface'}
        files['acoustic'] = ('acoustic.jpg', render.acoustic(db, detected, p['id'] + day), 'image/jpeg')
        _, vis = render.bushings({'r': 30, 's': 30, 't': 30}, ambient + 10, ambient, p['id'])
        files['visual'] = ('visual.jpg', vis, 'image/jpeg')
    else:
        load = (7.4 if afternoon else 5.2) + rnd.uniform(-0.4, 0.4)
        if p['scene'] == 'bushings':
            load += 3
        temps, readings = {}, []
        for i, tg in enumerate(p['targets']):
            v = ambient + load + rnd.uniform(-0.35, 0.35) + extra(p, tg['key'], day)
            temps[('r', 's', 't')[i]] = v
            readings.append({'key': tg['key'], 'max_c': round(v, 1), 'avg_c': round(v - 2.4, 1)})
        meta['thermal'] = readings
        if p['scene'] == 'bushings':
            th, vis = render.bushings(temps, ambient + 13, ambient, p['id'])
        else:
            th, vis = render.clamps(temps, ambient, p['id'])
        files['thermal'] = ('thermal.jpg', th, 'image/jpeg')
        files['visual'] = ('visual.jpg', vis, 'image/jpeg')
    files['meta'] = (None, json.dumps(meta))
    r = requests.post(f'{ROBOT}/api/v1/robot/inspections', headers=heads[p['robot']], files=files)
    return ok(r, f"upload {p['name']}")


def sql(q):
    """Backdate a follow-up: through NETRA_PSQL, default the database of scripts/dev.sh."""
    cmd = os.environ.get('NETRA_PSQL', 'docker exec -i netra-dev-db psql -U netra -d netra_dev -qtAc').split()
    subprocess.run(cmd + [q], check=True)


def finding(point_name, key):
    p = next(x for x in points if x['name'] == point_name)
    return next(f for f in s.get(f'{SUB}/findings', params={'point_id': p['id']}).json()
                if f['target_key'] == key)


now = dt.datetime.now(WIB)
midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
rounds = []
for day in range(DAYS - 1, -1, -1):
    for hour in (9, 14):
        start = midnight - dt.timedelta(days=day) + dt.timedelta(hours=hour, minutes=rng.randint(0, 25))
        if start < now - dt.timedelta(minutes=40):
            rounds.append((day, start))
n = 0
t0 = time.time()
for day, start in rounds:
    for rid, minute in (('gi-01', 0), ('gi-02', 50)):
        for i, p in enumerate(x for x in points if x['robot'] == rid):
            when = start + dt.timedelta(minutes=minute + 4 * p['stop_index'] + i * 0.7, seconds=rng.randint(0, 40))
            capture(p, when, day, random.Random(f"{p['id']}-{when.isoformat()}"))
            n += 1
    # Follow-up by the operators, at the time it happened
    if day == 8 and start.hour == 14:
        f = finding('CT Cikarang 1 — klem', 's')
        s.post(f"{SUB}/findings/{f['id']}/acknowledge", json={'note': 'Masuk rencana pemeliharaan Desember (WO-2026-1187).'})
        sql(f"UPDATE findings SET acknowledged_at = '{(start + dt.timedelta(hours=2)).isoformat()}' WHERE id = {f['id']}")
    if day == 8 and start.hour == 9:
        f = finding('PMS kopel bus A — klem', 'r')
        s.post(f"{SUB}/findings/{f['id']}/resolve", json={'note': 'Klem fasa R dikencangkan ulang, torsi sesuai SOP. Termovisi ulang normal.'})
        sql(f"UPDATE findings SET resolved_at = '{(start + dt.timedelta(hours=4)).isoformat()}' WHERE id = {f['id']}")
    if day == 1 and start.hour == 14:
        f = finding('Trafo 1 — PD bushing', 'pd')
        s.post(f"{SUB}/findings/{f['id']}/acknowledge", json={'note': 'Tim har sudah dihubungi, uji PD offline dijadwalkan.'})
        sql(f"UPDATE findings SET acknowledged_at = '{(start + dt.timedelta(hours=1, minutes=12)).isoformat()}' WHERE id = {f['id']}")
print('captures', n, f'{time.time() - t0:.0f}s', flush=True)

# ---- the patrol running now: gi-01 has done its first three stops
patrols = s.get(f'{API}/api/v1/patrols', params={'robot_id': 'gi-01'}).json()
live = next((p for p in (patrols if isinstance(patrols, list) else patrols.get('patrols', [])) if not p.get('ended_at')), None)
if live:
    for i, p in enumerate(x for x in points if x['robot'] == 'gi-01' and x['stop_index'] <= 2):
        capture(p, now - dt.timedelta(minutes=30 - 4 * i), 0, random.Random(f"live-{p['id']}"), patrol=live['id'])
    print('live patrol', live['id'], flush=True)
print(json.dumps(s.get(f'{SUB}/summary').json(), indent=1)[:1500])
