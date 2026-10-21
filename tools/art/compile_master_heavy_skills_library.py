"""Compile the manually edited master skill atlases into their runtime library."""
import json
from pathlib import Path

WORK = Path(__file__).resolve().parents[3]
ASSETS = WORK / "homeing-star-game/assets/generated/combat_vfx/master/heavy_skills"
manifest = json.loads((ASSETS / "manifest.json").read_text(encoding="utf-8"))
pages = sorted({page for clip in manifest["clips"].values() for page in clip["pages"]})
lines = [f"[gd_resource type=\"Resource\" load_steps={len(pages) + 1} format=3]", ""]
for index, page in enumerate(pages, 1):
    resource_path = f"res://assets/generated/combat_vfx/master/heavy_skills/{page}"
    lines.append(f'[ext_resource type="Texture2D" path="{resource_path}" id="{index}"]')
lines += [
    "",
    "[resource]",
    "metadata/manifest = "
    + json.dumps(json.dumps(manifest, ensure_ascii=False, separators=(",", ":")), ensure_ascii=False),
    "metadata/textures = {",
]
lines += [
    json.dumps(page) + f': ExtResource("{index}")' + ("," if index < len(pages) else "")
    for index, page in enumerate(pages, 1)
]
lines += ["}", ""]
(ASSETS / "library.tres").write_text("\n".join(lines), encoding="utf-8")
print(f"Compiled {len(manifest['clips'])} master clips, {len(pages)} texture dependencies")
