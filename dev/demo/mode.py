"""Print the map mode of a running NETRA and whether it has the substation module: "gps substation"."""
import os

import requests

API = os.environ.get('NETRA_URL', 'http://127.0.0.1:4492')
s = requests.Session()
r = s.post(f'{API}/api/v1/auth/login', json={'username': os.environ.get('NETRA_USER', 'admin'),
                                             'password': os.environ.get('NETRA_PASSWORD', 'admin')})
if r.status_code != 200:
    raise SystemExit(f'login failed ({r.status_code}): set NETRA_USER and NETRA_PASSWORD')
s.headers['Authorization'] = 'Bearer ' + r.json()['token']
info = s.get(f'{API}/api/v1/info').json()
print(info.get('map_mode', 'floorplan'), 'substation' if 'substation' in info.get('features', []) else '-')
