"""Write a SLAM-looking ROS map (map.pgm + map.yaml): rooms, corridors, pillars, unknown outside."""
import math
import random
import sys

out = sys.argv[1]
DOCK = len(sys.argv) > 2 and sys.argv[2] == 'dock'
W, H, RES = (360, 240, 0.05) if DOCK else (640, 420, 0.05)
ORIGIN = (-3.0, -2.5, 0.0) if DOCK else (-12.0, -9.0, 0.0)
random.seed(7)
UNK, FREE, OCC = 205, 254, 0
img = [[UNK] * W for _ in range(H)]

def to_px(x, y):
    """Map metres to pixel (col, row from top)."""
    c = (x - ORIGIN[0]) / RES
    r = H - (y - ORIGIN[1]) / RES
    return int(c), int(r)

def rect(x0, y0, x1, y1, v):
    c0, r1 = to_px(x0, y0)
    c1, r0 = to_px(x1, y1)
    for r in range(max(0, r0), min(H, r1)):
        for c in range(max(0, c0), min(W, c1)):
            img[r][c] = v

# free space: a hall, two rooms and a corridor (metres)
spaces = [(-2.2, -1.8, 14.0, 8.5)] if DOCK else [(-10.5, -7.5, 4.5, 1.5), (-10.5, 1.5, -3.0, 7.5), (0.5, 1.5, 17.0, 7.0), (4.5, -7.5, 17.0, -1.5), (-3.0, 3.0, 0.5, 5.0), (4.5, -1.5, 8.0, 1.5)]
for s in spaces:
    rect(*s, FREE)
# walls: outline every free region with a 0.1 m wall where it borders unknown
grid = [row[:] for row in img]
for r in range(1, H - 1):
    for c in range(1, W - 1):
        if grid[r][c] == FREE:
            for dr in (-2, -1, 0, 1, 2):
                for dc in (-2, -1, 0, 1, 2):
                    rr, cc = r + dr, c + dc
                    if 0 <= rr < H and 0 <= cc < W and grid[rr][cc] == UNK:
                        img[rr][cc] = OCC
# pillars and shelves
for (x, y) in ([] if DOCK else [(-6, -4), (-2, -4), (2, -4), (-6, -1), (-2, -1), (2, -1)]):
    rect(x - 0.3, y - 0.3, x + 0.3, y + 0.3, OCC)
if DOCK:
    for i in range(5):
        rect(1 + i * 2.5, 1.0, 1.8 + i * 2.5, 6.5, OCC)
else:
    for i in range(4):
        rect(7 + i * 2.4, -6.5, 7.6 + i * 2.4, -3.0, OCC)
    rect(9, 3, 15, 3.4, OCC)
    rect(9, 5, 15, 5.4, OCC)
# scan noise: speckles of unknown in free space near walls, a few stray hits
for _ in range(2500):
    r, c = random.randrange(H), random.randrange(W)
    if img[r][c] == FREE and random.random() < 0.15:
        img[r][c] = UNK
for _ in range(400):
    r, c = random.randrange(H), random.randrange(W)
    if img[r][c] == FREE and random.random() < 0.3:
        img[r][c] = OCC
with open(out + '.pgm', 'wb') as f:
    f.write(f'P5\n# CREATOR: map_saver.cpp {RES:.3f} m/pix\n{W} {H}\n255\n'.encode())
    f.write(bytes(v for row in img for v in row))
with open(out + '.yaml', 'w') as f:
    f.write(f'image: {out.split("/")[-1]}.pgm\nmode: trinary\nresolution: {RES}\n'
            f'origin: [{ORIGIN[0]}, {ORIGIN[1]}, {ORIGIN[2]}]\nnegate: 0\noccupied_thresh: 0.65\nfree_thresh: 0.196\n')
print('wrote', out)
