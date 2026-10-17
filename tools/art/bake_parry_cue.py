"""Bake Lan's closing parry ring with supersampled antialiasing."""
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "homeing-star-game/assets/sideview/effects/combat_baked"
SCALE = 4
CELL = 120
COLS = 8
CAPACITY = 64
APPEAR = 0.70
PRESS = 0.24
FPS = 60.0

times = {round(i / FPS, 8) for i in range(round(APPEAR * FPS) + 1)}
times.add(round(APPEAR - PRESS, 8))
times = sorted(times)
frames = []
for elapsed in times:
    contact = APPEAR - elapsed
    frame = Image.new("RGBA", (CELL * SCALE, CELL * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(frame)
    cx = cy = CELL * SCALE / 2

    def ring(radius: float, color: tuple[int, int, int], alpha: float) -> None:
        r = radius * SCALE
        draw.ellipse((cx-r, cy-r, cx+r, cy+r), outline=(*color, round(255 * alpha)), width=3 * SCALE)

    def disc(radius: float, color: tuple[int, int, int], alpha: float) -> None:
        r = radius * SCALE
        draw.ellipse((cx-r, cy-r, cx+r, cy+r), fill=(*color, round(255 * alpha)))

    if contact >= PRESS:
        closing = (contact - APPEAR) / (PRESS - APPEAR)
        radius = 46.0 + (12.0 - 46.0) * closing
        alpha = 0.3 + (0.95 - 0.3) * closing
        ring(radius, (79, 184, 255), alpha)
        disc(4.0, (79, 184, 255), 0.5 * closing)
    else:
        fade = contact / PRESS
        disc(12.0 + 8.0 * (1.0 - fade), (79, 184, 255), 0.45 * fade)
        disc(7.0, (223, 244, 255), fade)
        ring(12.0, (79, 184, 255), fade)
    frame = frame.resize((CELL, CELL), Image.Resampling.LANCZOS)
    frames.append(frame)

page = "lan/parry/guard_closing_ring/lan_parry_guard_closing_ring_00.png"
(ASSETS / Path(page).parent).mkdir(parents=True, exist_ok=True)
atlas = Image.new("RGBA", (COLS * CELL, ((len(frames) + COLS - 1) // COLS) * CELL), (0, 0, 0, 0))
for i, frame in enumerate(frames):
    atlas.alpha_composite(frame, ((i % COLS) * CELL, (i // COLS) * CELL))
atlas.save(ASSETS / page, optimize=True)

spec = {"palette": "parry_cue", "shape": "parry_cue", "pixel_size": 1.0, "appear_lead": APPEAR, "press_lead": PRESS, "fps": FPS}
key = hashlib.sha256(json.dumps(spec, sort_keys=True, separators=(",", ":")).encode()).hexdigest()[:24]
manifest_path = ASSETS / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["clips"][key] = {
    "capacity": CAPACITY,
    "cell": [CELL, CELL],
    "columns": COLS,
    "duration": APPEAR,
    "frames": len(frames),
    "name": "lan_parry_guard_closing_ring",
    "asset_path": "lan/parry/guard_closing_ring/lan_parry_guard_closing_ring",
    "pages": [page],
    "pivot": [CELL / 2, CELL / 2],
    "pixel_size": 1.0,
    "spec": spec,
    "times": times,
}
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Baked {len(frames)} parry cue frames as {page}; clip key {key}")
