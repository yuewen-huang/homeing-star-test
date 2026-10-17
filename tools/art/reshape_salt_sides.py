"""One-time authoring edit; preserve all non-side resource/node blocks verbatim."""
from pathlib import Path
import base64
import datetime
import json
import re
import shutil
import struct

ROOT = Path(__file__).resolve().parents[3]
GAME = ROOT / "homeing-star-game"
PROFILE = GAME / "scripts/sideview/salt_field_perimeter.gd"
SCENES = GAME / "scenes/sideview"
MARKER = "metadata/irregular_sides_authored = true"
profile_text = PROFILE.read_text(encoding="utf-8")
profiles = []
for name in ("LEFT", "RIGHT"):
    body = re.search(rf"const {name} := \[(.*?)\]", profile_text, re.S).group(1)
    profiles.append([(float(y), float(x)) for y, x in re.findall(r"Vector2\(([-\d.]+),\s*([-\d.]+)\)", body)])

def inset(side, depth):
    points = profiles[side]
    for (y0, x0), (y1, x1) in zip(points, points[1:]):
        if depth <= y1:
            t = max(0, min(1, (depth-y0)/(y1-y0)))
            return x0+(x1-x0)*t*t*(3-2*t)
    return points[-1][1]

def logical_depth(screen_y):
    q = max(0, min(1, screen_y/1080))
    return 1800*q/(0.6+0.4*q)

def shift(side, screen_y):
    y = logical_depth(screen_y)
    return inset(side, y)*0.6/(1-0.4*y/1800)*(1 if side == 0 else -1)

def transform(text, base):
    blocks = re.split(r"(?=^\[)", text, flags=re.M)
    side_meshes = {}
    for block in blocks:
        header = block.split("\n", 1)[0]
        wall = re.search(r'parent="Boundary/Wall_(\d+)"', header)
        if wall and int(wall[1]) >= 5:
            mesh = re.search(r'mesh = SubResource\("([^"]+)"\)', block)
            if mesh:
                side_meshes[mesh[1]] = (int(wall[1])-5) % 2
    changed_meshes = changed_rocks = 0
    for i, block in enumerate(blocks):
        original = block
        header = block.split("\n", 1)[0]
        resource = re.match(r'\[sub_resource type="ArrayMesh" id="([^"]+)"', header)
        if resource and resource[1] in side_meshes:
            side = side_meshes[resource[1]]
            match = re.search(r'"vertex_data": PackedByteArray\("([^"]+)"\)', block)
            values = list(struct.unpack("<12f", base64.b64decode(match[1])))
            for k, bottom in ((0, 0), (1, 1), (2, 1), (3, 0)):
                values[k*3] += shift(side, values[bottom*3+1])
            encoded = base64.b64encode(struct.pack("<12f", *values)).decode("ascii")
            block = block[:match.start(1)]+encoded+block[match.end(1):]
            xs, ys = values[0::3], values[1::3]
            aabb = f'AABB({min(xs):.8f}, {min(ys):.8f}, 0, {max(xs)-min(xs):.8f}, {max(ys)-min(ys):.8f}, 1e-05)'
            block = re.sub(r'AABB\([^)]*\)', aabb, block, count=1)
            changed_meshes += 1
        elif header.startswith("[node ") and re.search(r'parent="(?:Environment/)?Boundary/(?:LeftBanks|RightBanks)"', header):
            side = 0 if 'LeftBanks"' in header else 1
            match = re.search(r'^position = Vector2\(([-\d.eE+]+),\s*([-\d.eE+]+)\)', block, re.M)
            if match:
                x, y = map(float, match.groups())
                delta = shift(side, y)
                if abs(delta) > 0.000001:
                    block = block[:match.start()]+f'position = Vector2({x+delta:.8f}, {y:.8f})'+block[match.end():]
                    changed_rocks += 1
        else:
            assert block == original
        blocks[i] = block
    result = "".join(blocks)
    if base:
        result = result.replace('build_at_runtime = false', 'build_at_runtime = false\n'+MARKER, 1)
    return result, {"wall_slices": changed_meshes, "rock_positions": changed_rocks}

paths = [SCENES / "chapter_2_salt_environment.tscn", SCENES / "chapter_2_salt_field.tscn"]
originals = [p.read_text(encoding="utf-8") for p in paths]
if MARKER in originals[0]:
    raise SystemExit("Sides already authored; edit saved nodes or restore this tool's backup before rerunning.")
backup = ROOT / "homeing-star-test/artifacts" / ("salt-irregular-sides-"+datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
backup.mkdir(parents=True)
report = {}
for index, (path, original) in enumerate(zip(paths, originals)):
    shutil.copy2(path, backup / path.name)
    updated, counts = transform(original, index == 0)
    path.write_text(updated, encoding="utf-8", newline="\n")
    report[path.name] = counts
report["preserved"] = "All north-wall, coast, sky, ground, texture, scale and other node/resource blocks unchanged."
(backup / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report, indent=2))
print("BACKUP:", backup)
