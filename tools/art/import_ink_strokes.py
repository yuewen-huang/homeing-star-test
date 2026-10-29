"""Lossless import of the user's six Studio ink-editor packages."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
KINDS = {"横": "horizontal", "竖": "vertical", "撇": "left_falling",
         "捺": "right_falling", "点": "dot", "勾": "hook"}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    destination = ROOT / "homeing-star-game/assets/shared/combat_fx/ink_strokes"
    archive = ROOT / "homeing-star-temp-assert/PendingArt/mirror_lake/ink_strokes"
    entries = {}
    # Validate all packages before writing any runtime files.
    for chinese, kind in KINDS.items():
        folder = args.source / chinese
        document = json.loads((folder / "letter.ink.json").read_text(encoding="utf-8-sig"))
        assert document["format"] == "ink_effect" and document["version"] == 1
        assert document["mode"] == "strokes" and document["strokes"]
        art = folder / document["art"]
        assert hashlib.sha256(art.read_bytes()).hexdigest() == document["art_sha256"], kind
        image = Image.open(art)
        assert list(image.size) == document["size"], kind
        assert "A" in image.getbands() or "transparency" in image.info, kind
        bbox = image.convert("RGBA").getchannel("A").getbbox()
        assert bbox is not None
        entries[kind] = {"name": chinese, "file": f"{kind}/letter.ink.json",
                         "bounds": list(bbox), "sha256": {}}
        for filename in ["letter.ink.json", document["art"], document["travel"]]:
            raw = (folder / filename).read_bytes()
            entries[kind]["sha256"][filename] = hashlib.sha256(raw).hexdigest()
    for chinese, kind in KINDS.items():
        folder = args.source / chinese
        target = destination / kind
        target.mkdir(parents=True, exist_ok=True)
        for filename in entries[kind]["sha256"]:
            shutil.copy2(folder / filename, target / filename)
        shutil.copytree(folder, archive / kind, dirs_exist_ok=True)
    studio = ROOT / "combat-vfx-studio/vfx/ink_playback.gdshader"
    shader = ROOT / "homeing-star-game/assets/shared/shaders/ink_stroke_playback.gdshader"
    shutil.copy2(studio, shader)
    manifest = {"version": 1, "source": str(args.source), "strokes": entries,
                "shader_sha256": hashlib.sha256(studio.read_bytes()).hexdigest()}
    (destination / "library.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print("Imported six ink packages unchanged; verified artwork hashes, dimensions and alpha.")
    for kind, entry in entries.items(): print(kind, entry["bounds"])

if __name__ == "__main__":
    main()
