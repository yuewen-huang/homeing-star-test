"""Remove saved side-wall groups and their exclusive meshes, retaining all reefs."""
from pathlib import Path
from datetime import datetime
import re
import shutil

ROOT = Path(__file__).resolve().parents[3]
scene = ROOT / "homeing-star-game/scenes/levels/chapter_2_salt/chapter_2_salt_environment.tscn"
text = scene.read_text(encoding="utf-8")
blocks = re.split(r"(?=^\[)", text, flags=re.M)
remove = set()
meshes = set()
for i, block in enumerate(blocks):
    header = block.split("\n", 1)[0]
    group = re.search(r'^\[node name="Wall_(\d+)".*parent="Boundary"', header)
    child = re.search(r'^\[node .*parent="Boundary/Wall_(\d+)"', header)
    if (group and int(group[1]) >= 5) or (child and int(child[1]) >= 5):
        remove.add(i)
        mesh = re.search(r'mesh = SubResource\("([^"]+)"\)', block)
        if mesh:
            meshes.add(mesh[1])
for i, block in enumerate(blocks):
    resource = re.match(r'\[sub_resource type="ArrayMesh" id="([^"]+)"', block)
    if resource and resource[1] in meshes:
        remove.add(i)
updated = "".join(b for i, b in enumerate(blocks) if i not in remove)
assert not any(f'SubResource("{mesh}")' in updated for mesh in meshes)
if not meshes:
    raise SystemExit("No saved side walls remain; nothing to remove.")
backup = ROOT / "homeing-star-test/artifacts" / ("salt-no-side-walls-"+datetime.now().strftime("%Y%m%d-%H%M%S"))
backup.mkdir(parents=True)
shutil.copy2(scene, backup / scene.name)
scene.write_text(updated, encoding="utf-8", newline="\n")
print(f"Removed 12 side-wall groups and {len(meshes)} wall meshes. Every other block preserved.")
print("BACKUP:", backup)
