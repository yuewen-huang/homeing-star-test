"""Export actual GDScript comic crops and compact contact sheets for visual QA."""
import json
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "homeing-star-game"
OUT = ROOT / "homeing-star-test/artifacts/comic-crop-audit"
SCRIPTS = ["back_alley_entry_comic", "back_alley_pill_comic", "navigation_hall_entry_comic", "navigation_hall_exit_comic", "aberration_escape_comic"]

def collect():
    result = []
    for name in SCRIPTS:
        text = (GAME / f"scripts/sideview/{name}.gd").read_text(encoding="utf-8")
        textures = dict(re.findall(r'const (\w+) := preload\(\s*"res://([^\"]+)"\)', text))
        block = text.split("const PANELS := [", 1)[1].split("\n]", 1)[0]
        panels = []
        for line in block.splitlines():
            match = re.search(r"Rect2\(([^)]+)\)", line)
            if not match:
                continue
            rect = [int(float(n.strip())) for n in match[1].split(",")]
            texture = next((key for key in textures if re.search(r"\b" + key + r"\b", line)), "COMIC")
            panels.append({"texture": textures[texture], "rect": rect})
        result.append({"script": name, "panels": panels})
    return result

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", default="before")
    parser.add_argument("--rendered-dir", type=Path, help="Also build contact sheets from Godot captures")
    args = parser.parse_args()
    folder = OUT / args.label
    folder.mkdir(parents=True, exist_ok=True)
    data = collect()
    for comic in data:
        count = len(comic["panels"])
        sheet = Image.new("RGB", (1200, ((count + 2) // 3) * 280), "#333333")
        draw = ImageDraw.Draw(sheet)
        for i, panel in enumerate(comic["panels"]):
            with Image.open(GAME / panel["texture"]) as page:
                x, y, w, h = panel["rect"]
                crop = page.crop((x, y, x + w, y + h)).convert("RGB")
                crop.save(folder / f'{comic["script"]}-{i + 1:02d}.png')
                crop.thumbnail((388, 245))
                left, top = (i % 3) * 400, (i // 3) * 280
                sheet.paste(crop, (left + (400 - crop.width) // 2, top + 28))
                draw.text((left + 8, top + 6), f'{i + 1:02d} {panel["rect"]}', fill="white")
        sheet.save(folder / f'{comic["script"]}-sheet.png')
        if args.rendered_dir:
            runtime = Image.new("RGB", sheet.size, "#333333")
            labels = ImageDraw.Draw(runtime)
            for i in range(count):
                capture = args.rendered_dir / f'crop_{comic["script"]}_{i + 1:02d}.png'
                with Image.open(capture) as frame:
                    frame.thumbnail((388, 245))
                    left, top = (i % 3) * 400, (i // 3) * 280
                    runtime.paste(frame, (left + (400 - frame.width) // 2, top + 28))
                    labels.text((left + 8, top + 6), f'{i + 1:02d} Godot', fill="white")
            runtime.save(folder / f'{comic["script"]}-runtime-sheet.png')
    (folder / "manifest.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"Exported {sum(len(c['panels']) for c in data)} crops to {folder}")

if __name__ == "__main__":
    main()
