"""The demo substation site: the WGS84 transform of internal/geo, the yard drawn as an aerial overlay,
control points with GPS noise and the robots' routes, all in one map frame."""
import math
import random

A = 6378137.0
F = 1 / 298.257223563
E2 = F * (2 - F)
DEG = math.pi / 180

# The true placement of the substation's robot map: map x heads 60° from north, origin at the gate.
TRUE = dict(ref_lat=-6.2000, ref_lon=106.8160, scale=1.0, rot=(90 - 60) * DEG, east=0.0, north=0.0)


def ecef(lat, lon, h=0.0):
    s, c = math.sin(lat * DEG), math.cos(lat * DEG)
    n = A / math.sqrt(1 - E2 * s * s)
    return (n + h) * c * math.cos(lon * DEG), (n + h) * c * math.sin(lon * DEG), (n * (1 - E2) + h) * s


def from_ecef(x, y, z):
    p = math.hypot(x, y)
    phi = math.atan2(z, p * (1 - E2))
    for _ in range(10):
        s = math.sin(phi)
        n = A / math.sqrt(1 - E2 * s * s)
        phi = math.atan2(z + E2 * n * s, p)
    s, c = math.sin(phi), math.cos(phi)
    return phi / DEG, math.atan2(y, x) / DEG, p * c + z * s - A * math.sqrt(1 - E2 * s * s)


class Plane:
    def __init__(self, lat, lon):
        self.sl, self.cl = math.sin(lat * DEG), math.cos(lat * DEG)
        self.so, self.co = math.sin(lon * DEG), math.cos(lon * DEG)
        self.o = ecef(lat, lon)

    def local(self, lat, lon):
        x, y, z = ecef(lat, lon)
        dx, dy, dz = x - self.o[0], y - self.o[1], z - self.o[2]
        return -self.so * dx + self.co * dy, -self.sl * self.co * dx - self.sl * self.so * dy + self.cl * dz

    def geodetic(self, e, n):
        u = 0.0
        for _ in range(5):
            x = self.o[0] - self.so * e - self.sl * self.co * n + self.cl * self.co * u
            y = self.o[1] + self.co * e - self.sl * self.so * n + self.cl * self.so * u
            z = self.o[2] + self.cl * n + self.sl * u
            lat, lon, h = from_ecef(x, y, z)
            if abs(h) < 1e-9:
                break
            u -= h
        return lat, lon


PLANE = Plane(TRUE['ref_lat'], TRUE['ref_lon'])


def to_latlon(x, y, t=TRUE):
    c, s = math.cos(t['rot']), math.sin(t['rot'])
    e = t['scale'] * (c * x - s * y) + t['east']
    n = t['scale'] * (s * x + c * y) + t['north']
    return PLANE.geodetic(e, n)


# ---- the substation in map metres: yard, roads, equipment, the gate at the origin
YARD = [(0, -22), (96, -22), (96, 34), (0, 34)]
ROADS = [((-60, -1.5), (0, 1.5)), ((0, -2), (96, 2)), ((6, -22), (10, 34)), ((84, -22), (88, 34)), ((0, 26), (96, 30)),
         ((0, -22), (96, -18))]
BAYS = [(x, y) for x in (20, 36, 52, 68) for y in (-14, 14)]
BUILDING = [(-26, 8), (-8, 8), (-8, 20), (-26, 20)]

# Control points: gate, building corner, yard corners, with GPS-grade noise (a few decimetres).
CONTROL = [('Gate', 0.0, 0.0), ('Control building', -8.0, 8.0), ('Yard NE corner', 96.0, 34.0), ('Yard SE corner', 96.0, -22.0)]


def control_points(noise=0.25, seed=3):
    rng = random.Random(seed)
    out = []
    for label, x, y in CONTROL:
        lat, lon = to_latlon(x, y)
        e, n = PLANE.local(lat, lon)
        lat, lon = PLANE.geodetic(e + rng.gauss(0, noise), n + rng.gauss(0, noise))
        out.append({'label': label, 'x': x, 'y': y, 'lat': round(lat, 7), 'lon': round(lon, 7)})
    return out


# Patrol routes (x, y, yaw_deg, dwell_s): along the roads, stopping at the bays.
ROUTES = {
    'gi-01': [(2, 0, 0, 0), (8, 0, 0, 0), (8, -12, -90, 8), (8, -20, -90, 0), (86, -20, 0, 8), (86, 0, 90, 0),
              (86, 28, 90, 8), (8, 28, 180, 8), (8, 0, -90, 0), (2, 0, 180, 0)],
    'gi-02': [(10, 0, 0, 0), (44, 0, 0, 10), (80, 0, 0, 0), (86, 6, 90, 0), (86, 26, 90, 10), (44, 28, 180, 0),
              (10, 28, 180, 10), (8, 10, -90, 0), (10, 0, 0, 0)],
}


def overlay(path, px_per_m=6.0, margin=(-70, -40, 110, 50)):
    """Draw the yard as seen from above, north up; returns its bounds (north, south, east, west)."""
    from PIL import Image, ImageDraw, ImageFilter

    x0, y0, x1, y1 = margin
    corners = [to_latlon(x, y) for x in (x0, x1) for y in (y0, y1)]
    north, south = max(c[0] for c in corners), min(c[0] for c in corners)
    east, west = max(c[1] for c in corners), min(c[1] for c in corners)
    ne, nn = PLANE.local(north, east)
    sw, sn = PLANE.local(south, west)
    w, h = int((ne - sw) * px_per_m), int((nn - sn) * px_per_m)

    def px(x, y):
        lat, lon = to_latlon(x, y)
        return (lon - west) / (east - west) * w, (north - lat) / (north - south) * h

    rng = random.Random(11)
    img = Image.new('RGB', (w, h), (78, 104, 58))
    d = ImageDraw.Draw(img)
    for _ in range(9000):  # grass texture
        cx, cy = rng.random() * w, rng.random() * h
        r = rng.random() * 6 + 1
        g = rng.randint(-22, 22)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(78 + g, 104 + g, 56 + g // 2))
    for _ in range(140):  # trees
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        if -4 < x < 100 and -26 < y < 38 or -30 < x < -4 and 4 < y < 24:
            continue
        cx, cy = px(x, y)
        r = rng.uniform(10, 22)
        d.ellipse((cx - r + 5, cy - r + 6, cx + r + 5, cy + r + 6), fill=(36, 50, 28))
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(44 + rng.randint(0, 20), 82 + rng.randint(0, 25), 40))
    d.polygon([px(x, y) for x, y in YARD], fill=(158, 152, 138))
    for _ in range(26000):  # gravel
        x, y = rng.uniform(0, 96), rng.uniform(-22, 34)
        cx, cy = px(x, y)
        g = rng.randint(-26, 26)
        d.point((cx, cy), fill=(158 + g, 152 + g, 138 + g))
    for (a, b) in ROADS:
        d.polygon([px(a[0], a[1]), px(b[0], a[1]), px(b[0], b[1]), px(a[0], b[1])], fill=(64, 66, 70))
    d.polygon([px(*p) for p in BUILDING], fill=(206, 208, 212))
    d.polygon([px(-25, 9), px(-9, 9), px(-9, 14), px(-25, 14)], fill=(186, 188, 194))
    for (x, y) in BAYS:
        d.polygon([px(x - 4.5, y - 3.5), px(x + 4.5, y - 3.5), px(x + 4.5, y + 3.5), px(x - 4.5, y + 3.5)], fill=(52, 56, 52))
        d.polygon([px(x - 3.5, y - 2.5), px(x + 3.5, y - 2.5), px(x + 3.5, y + 2.5), px(x - 3.5, y + 2.5)], fill=(96, 112, 100))
        for k in (-2.4, 0, 2.4):
            cx, cy = px(x + k, y + 4.8)
            d.ellipse((cx - 3, cy - 3, cx + 3, cy + 3), fill=(220, 220, 214))
    for y in (-16, -8, 8, 16):  # busbars
        d.line([px(14, y), px(76, y)], fill=(208, 206, 196), width=2)
    fence = YARD + [YARD[0]]
    d.line([px(*p) for p in fence], fill=(232, 228, 214), width=2)
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    img.save(path, quality=88)
    return dict(north=north, south=south, east=east, west=west)
