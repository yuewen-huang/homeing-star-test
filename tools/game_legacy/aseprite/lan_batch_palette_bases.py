"""Generate non-destructive Lan action palette bases from character-only sheets."""
from __future__ import annotations

from collections import Counter
from pathlib import Path
import csv
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "PendingArt" / "character" / ("\u4e3b\u89d2-\u5c9a")
OUT = SOURCE_ROOT / "palette-bases"
OUT.mkdir(parents=True, exist_ok=True)

# Source RGB -> target RGB. Positions and alpha never change.
PALETTE = {
    "FFFFFF": "FEE6A5", "FFFFCC": "FEE6A5",
    "B2B2FF": "F5C477", "9EA0FA": "E0C09C", "AD5FAD": "DA9A51",
    "0321BC": "315B60", "1C154D": "27484C", "40225F": "20383D",
    "2F1850": "27484C", "151037": "192B30", "321D70": "27484C",
    "FF8C5E": "F4C477", "A96E67": "AB703C", "E05E2B": "D99B50",
    "882323": "79482F", "580303": "482E26", "8C2309": "AE926C",
    "A64B0A": "AE926C", "FF0E00": "A36138", "4D2F1E": "482E26",
    "FFA303": "D9C49D", "51373F": "482E26", "431500": "AB703C",
    "91584C": "79482F", "43A?": "000000",  # removed below; protects typo from silent use
    "007F26": "238678", "006E22": "185A50", "97C0FF": "A7D7C6",
    "2B7A4C": "238678", "277148": "185A50", "FBF9F5": "A7D7C6",
    "0F121B": "192B30",
}
del PALETTE["43A?"]

SKIP_PARTS = ("\u5907\u4efd", "palette-bases", "\u6a21\u677f")
SKIP_NAMES = ("fx", "merged", "smoke", "fall", "illusion", "hit fx")
KEEP_EXACT = {
    "aerial dash_without illusion.png", "back dodge.png", "crouching.png",
    "hard hit.png", "normal hit.png", "double jump_forward.png",
    "double jump_vertical.png", "jump.png", "roll landing.png", "hang idle.png",
    "hang.png", "up.png", "run.png", "run_start.png", "run_stop.png",
    "run_turn.png", "wall jump.png", "wall slide.png",
    "01_ladder climb start.png", "02_ladder climb up.png", "03_ladder climb end.png",
    "05_ladder slide end.png",
}

def eligible(path: Path) -> bool:
    relative = path.relative_to(SOURCE_ROOT)
    lowered_parts = [part.lower() for part in relative.parts]
    if any(part in SKIP_PARTS for part in relative.parts):
        return False
    name = path.name.lower()
    if any(token in name for token in SKIP_NAMES):
        return False
    return "_char" in name or path.name in KEEP_EXACT

def rgb_hex(pixel: tuple[int, int, int, int]) -> str:
    return f"{pixel[0]:02X}{pixel[1]:02X}{pixel[2]:02X}"

rows: list[dict[str, object]] = []
unknown: Counter[str] = Counter()
for source in sorted(path for path in SOURCE_ROOT.rglob("*.png") if eligible(path)):
    relative = source.relative_to(SOURCE_ROOT)
    destination = OUT / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    image = Image.open(source).convert("RGBA")
    output = image.copy()
    changed = opaque = 0
    local_unknown: Counter[str] = Counter()
    for y in range(image.height):
        for x in range(image.width):
            pixel = image.getpixel((x, y))
            if not pixel[3]:
                continue
            opaque += 1
            source_hex = rgb_hex(pixel)
            target_hex = PALETTE.get(source_hex)
            if target_hex is None:
                local_unknown[source_hex] += 1
                unknown[source_hex] += 1
                continue
            target_rgb = tuple(bytes.fromhex(target_hex))
            replacement = target_rgb + (pixel[3],)
            output.putpixel((x, y), replacement)
            changed += replacement != pixel
    assert output.size == image.size
    assert output.getchannel("A").tobytes() == image.getchannel("A").tobytes()
    output.save(destination)
    rows.append({
        "source": relative.as_posix(), "output": destination.relative_to(SOURCE_ROOT).as_posix(),
        "width": image.width, "height": image.height, "opaque_pixels": opaque,
        "changed_rgb_pixels": changed, "unknown_rgb_pixels": sum(local_unknown.values()),
        "unknown_colors": " ".join(f"#{c}:{n}" for c, n in local_unknown.most_common()),
    })

with (OUT / "action-base-manifest.csv").open("w", newline="", encoding="utf-8-sig") as f:
    writer = csv.DictWriter(f, fieldnames=rows[0].keys())
    writer.writeheader(); writer.writerows(rows)
with (OUT / "unmapped-colors.csv").open("w", newline="", encoding="utf-8-sig") as f:
    writer = csv.writer(f); writer.writerow(["source_color", "opaque_pixels"])
    writer.writerows((f"#{color}", count) for color, count in unknown.most_common())
print(f"PASS: generated {len(rows)} character-only palette bases in {OUT}")
for row in rows:
    print(f"{row['source']} -> {row['width']}x{row['height']}; changed={row['changed_rgb_pixels']}; unknown={row['unknown_rgb_pixels']}")
