"""Render the flat paper-board terrain layers used beneath the playable network.

One-off asset builder, not a runtime system. It reads the authoritative layouts in
assets/maps/layouts/*.json (and scenarios/practice_demo.json for the practice
board), keeps every playable corridor and node clear, and paints a quiet city:
pale land, an optional river traced from the archived illustration, a few street
blocks, simplified buildings and small parks. Playable roads, node pieces, names
and status are NOT painted here; NetworkView draws them above this layer.

Output sizes match each layout's registered image_size, so no coordinates change.
The previous illustrated artwork is archived in output/illustrated-city-v1/.

Requires Pillow and NumPy:  python3 tools/build_board_terrain.py
"""
import json
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "output/illustrated-city-v1"
SS = 2  # supersampling factor

LAND = "#E9E2CE"
PLAZA = "#EFE9DA"
STREET = "#F4EFE2"
LOT = "#E2D9C2"
PARK = "#D3D9BC"
TREE = "#BAC59E"
TREE_EDGE = "#A9B48C"
WATER = "#BCD0D2"
BANK = "#A3BABD"
DECK = "#E6DECA"
DECK_EDGE = "#B8AD96"
ROOFS = ["#D2C6AE", "#D8C1AC", "#C8CBBE", "#D6CDBA"]
BASE = "#BCB099"

# Per-map tone: grid spacing (world units), rotation (degrees), random seed.
MAPS = {
    "riverside": {"spacing": 118, "angle": 7, "seed": 11, "river": True},
    "twin_districts": {"spacing": 112, "angle": 0, "seed": 23, "river": True},
    "lifeline": {"spacing": 120, "angle": -5, "seed": 37, "river": False},
    "crossfire": {"spacing": 116, "angle": 0, "seed": 41, "river": False},
    "practice": {"spacing": 120, "angle": 0, "seed": 5, "river": False},
}


def practice_layout():
    data = json.loads((ROOT / "scenarios/practice_demo.json").read_text())
    nodes = {k: {"anchor": v} for k, v in data["node_positions"].items()}
    edges = {}
    for a, b in data["edges"]:
        eid = f"{a}-{b}"
        line = [data["node_positions"][a]] + data.get("road_bends", {}).get(eid, []) + [data["node_positions"][b]]
        edges[eid] = {"centerline": line, "corridor_width": 34}
    return {"world_size": data["world_size"], "image_size": [1499, 1049], "nodes": nodes, "edges": edges}


def river_mask(name, size):
    """Trace the water from the archived illustration, then smooth it to a calm shape."""
    source = Image.open(ARCHIVE / f"{name}.png").convert("RGB").resize(size, Image.BILINEAR)
    rgb = np.asarray(source).astype(int)
    water = (rgb[..., 2] > rgb[..., 0] + 28) & (rgb[..., 2] > 110) & (rgb[..., 1] > rgb[..., 0])
    mask = Image.fromarray((water * 255).astype(np.uint8))
    for _ in range(2):
        mask = mask.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))
    mask = mask.filter(ImageFilter.MinFilter(7)).filter(ImageFilter.MaxFilter(7))
    mask = mask.filter(ImageFilter.GaussianBlur(22 * SS)).point(lambda v: 255 if v > 118 else 0)
    # Keep only large connected water bodies (drops pools and stray roofs).
    arr = np.asarray(mask) > 0
    from collections import deque
    seen = np.zeros_like(arr)
    keep = np.zeros_like(arr)
    h, w = arr.shape
    for y in range(0, h, 8):
        for x in range(0, w, 8):
            if arr[y, x] and not seen[y, x]:
                queue = deque([(y, x)])
                seen[y, x] = True
                region = []
                while queue:
                    cy, cx = queue.popleft()
                    region.append((cy, cx))
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and arr[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            queue.append((ny, nx))
                if len(region) > h * w * 0.01:
                    ys, xs = zip(*region)
                    keep[list(ys), list(xs)] = True
    return Image.fromarray((keep * 255).astype(np.uint8))


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def build(name, layout, out_path):
    spec = MAPS[name]
    rng = random.Random(spec["seed"])
    w, h = layout["image_size"]
    W, H = w * SS, h * SS
    k = W / layout["world_size"][0]  # world unit -> canvas pixel

    def P(p):
        return (p[0] * k, p[1] * k)

    # Clear zones: playable corridors and node plazas never receive scenery.
    blocked = Image.new("L", (W, H), 0)
    bd = ImageDraw.Draw(blocked)
    for e in layout["edges"].values():
        line = [P(p) for p in e["centerline"]]
        width = (e.get("corridor_width", 34) + 14) * k
        bd.line(line, fill=255, width=int(width), joint="curve")
        for p in line:
            r = width / 2
            bd.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=255)
    for n in layout["nodes"].values():
        x, y = P(n["anchor"])
        r = 46 * k
        bd.ellipse((x - r, y - r, x + r, y + r), fill=255)
    water = river_mask(name, (W, H)) if spec["river"] else Image.new("L", (W, H), 0)
    blocked_all = Image.composite(Image.new("L", (W, H), 255), blocked, water.filter(ImageFilter.MaxFilter(2 * int(9 * k) + 1)))
    free = blocked_all.point(lambda v: 0 if v > 0 else 255)
    free_arr = np.asarray(free) > 0

    canvas = Image.new("RGB", (W, H), LAND)
    draw = ImageDraw.Draw(canvas)

    # Quiet street grid: paper-coloured lanes, lighter than land, never on corridors.
    streets = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(streets)
    angle = math.radians(spec["angle"])
    ca, sa = math.cos(angle), math.sin(angle)
    spacing = spec["spacing"]
    cx, cy = layout["world_size"][0] / 2, layout["world_size"][1] / 2

    def rot(u, v):
        return (cx + u * ca - v * sa, cy + u * sa + v * ca)

    span = 900
    offsets_u = [i * spacing + rng.uniform(-10, 10) for i in range(-8, 9)]
    offsets_v = [i * spacing + rng.uniform(-10, 10) for i in range(-8, 9)]
    lane = 9 * k
    for u in offsets_u:
        sd.line([P(rot(u, -span)), P(rot(u, span))], fill=255, width=int(lane))
    for v in offsets_v:
        sd.line([P(rot(-span, v)), P(rot(span, v))], fill=255, width=int(lane))
    lots_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lots_layer)
    buildings = []
    parks = []
    inset = 13
    for i in range(len(offsets_u) - 1):
        for j in range(len(offsets_v) - 1):
            u0, u1 = offsets_u[i] + inset, offsets_u[i + 1] - inset
            v0, v1 = offsets_v[j] + inset, offsets_v[j + 1] - inset
            corners = [P(rot(u0, v0)), P(rot(u1, v0)), P(rot(u1, v1)), P(rot(u0, v1))]
            centre = P(rot((u0 + u1) / 2, (v0 + v1) / 2))
            if not (0 <= centre[0] < W and 0 <= centre[1] < H):
                continue
            park = rng.random() < 0.2
            ld.polygon(corners, fill=PARK if park else LOT)
            if park:
                parks.append((u0, u1, v0, v1))
                continue
            # One to three simple masses per lot, generously spaced.
            count = rng.choice([1, 1, 2, 2, 3])
            du, dv = u1 - u0, v1 - v0
            if count == 1:
                slots = [(u0 + du * 0.2, u1 - du * 0.2, v0 + dv * 0.22, v1 - dv * 0.22)]
            elif count == 2:
                mid = (u0 + u1) / 2
                slots = [(u0 + 8, mid - 6, v0 + 10, v1 - 12), (mid + 6, u1 - 8, v0 + 14, v1 - 8)]
            else:
                mu, mv = (u0 + u1) / 2, (v0 + v1) / 2
                slots = [(u0 + 8, mu - 6, v0 + 8, mv - 5), (mu + 6, u1 - 8, v0 + 8, mv - 5), (u0 + 8, u1 - 8, mv + 6, v1 - 8)]
            for s in slots:
                shrink = rng.uniform(0, 6)
                buildings.append((s[0] + shrink, s[1] - shrink, s[2] + shrink * 0.6, s[3] - shrink * 0.6, rng.choice(ROOFS)))

    # Clip lots and streets to the free area, softened so cuts read as kerbs.
    free_soft = free.filter(ImageFilter.MinFilter(2 * int(4 * k) + 1)).filter(ImageFilter.GaussianBlur(1.2 * SS))
    lots_alpha = Image.fromarray(np.minimum(np.asarray(lots_layer.split()[3]), np.asarray(free_soft)))
    canvas.paste(Image.new("RGB", (W, H), STREET), mask=Image.fromarray(np.minimum(np.asarray(streets), np.asarray(free_soft)) // 1))
    canvas.paste(lots_layer.convert("RGB"), mask=lots_alpha)

    def inside(points, margin=3):
        for x, y in points:
            xi, yi = int(x), int(y)
            for ox, oy in ((0, 0), (margin * k, 0), (-margin * k, 0), (0, margin * k), (0, -margin * k)):
                px, py = int(xi + ox), int(yi + oy)
                if not (0 <= px < W and 0 <= py < H) or not free_arr[py, px]:
                    return False
        return True

    draw = ImageDraw.Draw(canvas)
    depth = 3.2 * k
    for u0, u1, v0, v1, roof in buildings:
        if u1 - u0 < 14 or v1 - v0 < 12:
            continue
        pts = [P(rot(u0, v0)), P(rot(u1, v0)), P(rot(u1, v1)), P(rot(u0, v1))]
        samples = pts + [P(rot((u0 + u1) / 2, (v0 + v1) / 2))]
        if not inside(samples, 6):
            continue
        base = [(x, y + depth) for x, y in pts]
        draw.polygon(base, fill=BASE)
        draw.polygon(pts, fill=roof)
        # A single ridge line keeps the miniature-building read without texture.
        if (u1 - u0) > (v1 - v0):
            a, b = P(rot(u0 + 5, (v0 + v1) / 2)), P(rot(u1 - 5, (v0 + v1) / 2))
        else:
            a, b = P(rot((u0 + u1) / 2, v0 + 5)), P(rot((u0 + u1) / 2, v1 - 5))
        draw.line([a, b], fill=BASE, width=max(1, int(1.1 * k)))
    for u0, u1, v0, v1 in parks:
        for _ in range(rng.randint(2, 4)):
            u, v = rng.uniform(u0 + 14, u1 - 14), rng.uniform(v0 + 14, v1 - 14)
            r = rng.uniform(9, 14)
            x, y = P(rot(u, v))
            if not inside([(x, y)], r + 3):
                continue
            rr = r * k
            draw.ellipse((x - rr, y - rr + depth * 0.6, x + rr, y + rr + depth * 0.6), fill=TREE_EDGE)
            draw.ellipse((x - rr, y - rr, x + rr, y + rr), fill=TREE)

    if spec["river"]:
        bank = water.filter(ImageFilter.MaxFilter(2 * int(2.2 * k) + 1))
        canvas.paste(Image.new("RGB", (W, H), BANK), mask=bank)
        canvas.paste(Image.new("RGB", (W, H), WATER), mask=water)
        # Plain decks wherever a playable corridor crosses water.
        decks = Image.new("L", (W, H), 0)
        dd = ImageDraw.Draw(decks)
        edges_l = Image.new("L", (W, H), 0)
        ed = ImageDraw.Draw(edges_l)
        for e in layout["edges"].values():
            line = [P(p) for p in e["centerline"]]
            ed.line(line, fill=255, width=int(38 * k))
            dd.line(line, fill=255, width=int(32 * k))
        bank_wide = water.filter(ImageFilter.MaxFilter(2 * int(5 * k) + 1))
        canvas.paste(Image.new("RGB", (W, H), DECK_EDGE), mask=Image.fromarray(np.minimum(np.asarray(edges_l), np.asarray(bank_wide))))
        canvas.paste(Image.new("RGB", (W, H), DECK), mask=Image.fromarray(np.minimum(np.asarray(decks), np.asarray(bank_wide))))

    canvas = canvas.resize((w, h), Image.LANCZOS)
    canvas.save(out_path, optimize=True)
    print("wrote", out_path.relative_to(ROOT), canvas.size)


if __name__ == "__main__":
    import sys
    only = set(sys.argv[1:])
    for name in ["riverside", "twin_districts", "lifeline", "crossfire"]:
        if only and name not in only:
            continue
        layout = json.loads((ROOT / f"assets/maps/layouts/{name}.json").read_text())
        build(name, layout, ROOT / layout["texture"].removeprefix("res://"))
    if not only or "practice" in only:
        build("practice", practice_layout(), ROOT / "assets/maps/practice.png")
