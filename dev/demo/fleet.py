"""Simulated robots for development: set up the map scene (robot maps in pgm, the georeferenced
substation yard in gps), register two robots with a route each, start their patrols, report a few
anomalies and a crowd window, then drive them over the robot WebSocket until stopped.

usage: NETRA_URL=http://127.0.0.1:4492 [NETRA_ROBOT_URL=...] python fleet.py pgm|gps <maps dir>
"""
import base64
import json
import math
import os
import sys
import threading
import time
import uuid

import requests
import websocket

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scene  # noqa: E402

API = os.environ.get('NETRA_URL', 'http://127.0.0.1:4492')
ROBOT = os.environ.get('NETRA_ROBOT_URL', API)
MODE, DIR = sys.argv[1], sys.argv[2]
JPEG = base64.b64decode(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tiny.jpg.b64')).read())

s = requests.Session()
s.headers['Authorization'] = 'Bearer ' + s.post(f'{API}/api/v1/auth/login', json={'username': os.environ.get('NETRA_USER', 'admin'), 'password': os.environ.get('NETRA_PASSWORD', 'admin')}).json()['token']

PGM_ROUTES = {
    'l1w-01': [(-9, -6, 0, 0), (3.5, -6, 90, 8), (3.5, 0.5, 180, 0), (-9, 0.5, -90, 8), (-9, -6, 0, 0)],
    'l1w-02': [(6, 0, -90, 0), (6, -2.2, 0, 0), (16, -2.2, -90, 6), (16, -6.9, 180, 0), (6, -6.9, 90, 6), (6, 0, 90, 0)],
}
ROBOTS = {
    'pgm': [('l1w-01', 'L1W Patrol 01', PGM_ROUTES['l1w-01'], False), ('l1w-02', 'L1W Patrol 02', PGM_ROUTES['l1w-02'], False)],
    'gps': [('gi-01', 'GI Patrol 01', scene.ROUTES['gi-01'], True), ('gi-02', 'GI Patrol 02', scene.ROUTES['gi-02'], False)],
}[MODE]
ANOMALIES = {
    'pgm': [('l1w-01', 'trash', -4.0, -6.0), ('l1w-02', 'floor_damage', 12.0, -2.2), ('l1w-02', 'spill', 16.0, -4.5)],
    'gps': [('gi-01', 'unknown', 36.0, -20.0), ('gi-02', 'floor_damage', 44.0, 0.0), ('gi-02', 'trash', 86.0, 14.0)],
}[MODE]

if MODE == 'pgm':
    have = {p['name'] for p in s.get(f'{API}/api/v1/floorplans').json()}
    for name, base in (('Warehouse ground floor', 'warehouse'), ('Loading dock', 'dock')):
        if name not in have:
            r = s.post(f'{API}/api/v1/floorplans/pgm', data={'name': name, 'yaml': open(f'{DIR}/{base}.yaml').read()},
                       files={'image': (f'{base}.pgm', open(f'{DIR}/{base}.pgm', 'rb'))})
            print('robot map', name, r.status_code, r.text[:120], flush=True)
    plan = next(p for p in s.get(f'{API}/api/v1/floorplans').json() if p['name'] == 'Warehouse ground floor')
else:
    r = s.put(f'{API}/api/v1/geo', json={'points': scene.control_points(), 'basemap': {'kind': os.environ.get('BASEMAP', 'none')}})
    print('geo', r.status_code, json.dumps(r.json().get('transform'))[:200], flush=True)
    bounds = json.load(open(f'{DIR}/site.json'))
    r = s.post(f'{API}/api/v1/geo/overlay', data={**bounds, 'opacity': 1},
               files={'image': ('substation.jpg', open(f'{DIR}/site.jpg', 'rb'), 'image/jpeg')})
    print('overlay', r.status_code, flush=True)


def path_length(pts):
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:]))


class Robot:
    def __init__(self, rid, name, route, gps):
        self.id, self.name, self.route, self.gps = rid, name, route, gps
        r = s.post(f'{API}/api/v1/robots', json={'id': rid, 'name': name})
        if r.status_code != 201:
            r = s.post(f'{API}/api/v1/robots/{rid}/token')
        self.token = r.json()['token']
        self.h = {'Authorization': f'Bearer {self.token}', 'X-Robot-Id': rid}
        csv = '# x,y,yaw_deg,dwell_sec\n' + ''.join(f'{x},{y},{yaw},{d}\n' for x, y, yaw, d in route)
        meta = {'uid': f'{MODE}-{rid}-route', 'name': f'{name} round', 'recorded_at': time.time() - 86400,
                'length_m': round(path_length(route), 1), 'stops': sum(1 for p in route if p[3] > 0), 'closed': True}
        self.route_id = requests.post(f'{ROBOT}/api/v1/robot/routes', headers=self.h, data={'meta': json.dumps(meta)},
                                      files={'route.csv': ('route.csv', csv, 'text/csv')}).json()['id']
        self.patrol = None
        self.ws = websocket.create_connection(ROBOT.replace('http', 'ws') + '/api/v1/robot/ws',
                                              header=[f'{k}: {v}' for k, v in self.h.items()])
        self.lock = threading.Lock()
        self.send({'type': 'hello', 'robot_id': rid, 'version': 1})
        threading.Thread(target=self.listen, daemon=True).start()

    def send(self, msg):
        with self.lock:
            self.ws.send(json.dumps(msg))

    def listen(self):
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get('type') != 'command':
                continue
            self.send({'type': 'ack', 'id': msg['id'], 'ok': True, 'msg': 'ok'})
            if msg['name'] == 'start_patrol':
                self.patrol = msg['args']['patrol_id']
                self.send({'type': 'patrol_event', 'event': 'started', 'patrol_id': self.patrol, 'route_id': self.route_id, 'ts': time.time()})

    def pose_at(self, t, speed=0.9):
        """Position along the closed route at time t, dwelling at stops."""
        legs = []
        for a, b in zip(self.route, self.route[1:]):
            legs.append(('move', a, b, math.hypot(b[0] - a[0], b[1] - a[1]) / speed))
            if b[3] > 0:
                legs.append(('dwell', b, b, b[3]))
        total = sum(leg[3] for leg in legs)
        t %= total
        for kind, a, b, dur in legs:
            if t <= dur:
                if kind == 'dwell':
                    return a[0], a[1], math.radians(a[2]), 'DWELLING'
                k = t / dur if dur else 0
                return a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, math.atan2(b[1] - a[1], b[0] - a[0]), 'FOLLOWING'
            t -= dur
        return self.route[0][0], self.route[0][1], 0, 'FOLLOWING'

    def tick(self, t, offset):
        x, y, yaw, state = self.pose_at(t + offset)
        tel = {'type': 'telemetry', 'ts': time.time(), 'pose': {'x': round(x, 3), 'y': round(y, 3), 'yaw': round(yaw, 4)},
               'mode': 'auto', 'nav': {'state': state, 'message': ''}, 'mission': 'patrol', 'localization': 'ok',
               'battery': {'pct': round(78 - (t % 600) / 60), 'v': 52.1, 'a': -3.2, 'temp': 31}, 'driver': None, 'people': 0,
               'health': {'ok': True, 'level': 'ok', 'issues': [], 'cpu_percent': 38, 'gpu_percent': 21, 'memory_percent': 54,
                          'memory_used_gb': 8.4, 'memory_total_gb': 15.6, 'cpu_temp_c': 56},
               'patrol': {'patrol_id': self.patrol, 'route_id': self.route_id} if self.patrol else None,
               'estop': False, 'field': 'clear'}
        if self.gps:
            lat, lon = scene.to_latlon(x, y)
            tel['gps'] = {'lat': round(lat, 8), 'lon': round(lon, 8), 'fix': 'rtk_fixed', 'hdop': 0.6}
        self.send(tel)


robots = [Robot(*r) for r in ROBOTS]
t0 = time.time()
offsets = {r.id: 25 + i * 37.0 for i, r in enumerate(robots)}
if MODE == 'pgm':
    for r in robots:
        s.put(f'{API}/api/v1/robots/{r.id}', json={'name': r.name, 'floor_plan_id': plan['id']})
for r in robots:
    r.tick(time.time() - t0, offsets[r.id])
time.sleep(0.5)
for r in robots:
    print('patrol', s.post(f'{API}/api/v1/patrols', json={'robot_id': r.id, 'route_id': r.route_id}).status_code, flush=True)
time.sleep(0.5)
by_id = {r.id: r for r in robots}
for rid, cat, x, y in ANOMALIES:
    rb = by_id[rid]
    meta = {'uid': f'{MODE}-{rid}-{cat}-{x}', 'category': cat, 'confidence': 0.87, 'description': 'test', 'ts': time.time(),
            'pose': {'x': x, 'y': y, 'yaw': 0}, 'patrol_id': rb.patrol, 'route_id': rb.route_id}
    r = requests.post(f'{ROBOT}/api/v1/robot/anomalies', headers=rb.h, data={'meta': json.dumps(meta)},
                      files={'image.jpg': ('image.jpg', JPEG, 'image/jpeg')})
    print('anomaly', cat, r.status_code, flush=True)
# A crowd window per robot: people counted on 1 m cells around a few places of its route.
CROWD = {'pgm': [(-6, -5), (-2, 0), (12, -2)], 'gps': [(30, 0), (44, -1), (86, 20)]}[MODE]
for i, rb in enumerate(robots):
    cells = [[cx + dx, cy + dy, max(1, 4 - abs(dx) - abs(dy) + i)] for cx, cy in CROWD for dx in range(-2, 3) for dy in range(-1, 2)]
    rb.send({'type': 'crowd', 'ts_start': time.time() - 60, 'ts_end': time.time(), 'cell_size': 1.0, 'cells': cells,
             'peak_people': max(c[2] for c in cells), 'patrol_id': rb.patrol, 'route_id': rb.route_id})
print('fleet running', flush=True)
while True:
    t = time.time() - t0
    for r in robots:
        r.tick(t, offsets[r.id])
    time.sleep(1)
