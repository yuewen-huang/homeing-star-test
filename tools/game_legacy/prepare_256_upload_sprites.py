from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path("PendingArt/character/师傅/BOSS形态")
IDLE_SOURCE = ROOT / "combat-idle-keyframes/master-boss-phase1-combat-idle-start-v2-128x144.png"
DASH_RAW = Path(
    "D:/CodexData/.codex/generated_images/01a08bf6-53aa-78c1-824b-9c341b6c0f6c/exec-64e6bcc9-c3aa-4d85-a16f-24773d1d821f.png"
)
IDLE_OUTPUT = ROOT / "combat-idle-keyframes/master-boss-phase1-combat-idle-start-v2-256x256-bottom-left.png"
DASH_OUTPUT = ROOT / "采用/冲刺/dash-frame11-redraw-v1-256x256.png"


def remove_checkerboard(rgb: Image.Image) -> Image.Image:
    data = np.asarray(rgb).astype(np.int16)
    maximum = data.max(axis=2)
    minimum = data.min(axis=2)
    # The baked checkerboard is bright neutral gray. Start with unmistakable
    # colored/dark subject pixels, then fill enclosed pale fur/sword interiors.
    foreground = ((maximum - minimum) > 20) | (minimum < 110)
    mask = Image.fromarray((foreground * 255).astype(np.uint8), "L")
    mask = mask.filter(ImageFilter.MaxFilter(3))
    flooded = mask.copy()
    for seed in ((0, 0), (flooded.width - 1, 0), (0, flooded.height - 1),
                 (flooded.width - 1, flooded.height - 1)):
        ImageDraw.floodfill(flooded, seed, 128, thresh=0)
    values = np.asarray(flooded)
    alpha = np.where(values == 128, 0, 255).astype(np.uint8)
    result = rgb.convert("RGBA")
    result.putalpha(Image.fromarray(alpha, "L"))
    return result


def main() -> None:
    idle = Image.open(IDLE_SOURCE).convert("RGBA")
    idle_canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    idle_canvas.alpha_composite(idle, (0, 256 - idle.height))
    idle_canvas.save(IDLE_OUTPUT)

    dash = remove_checkerboard(Image.open(DASH_RAW).convert("RGB"))
    bbox = dash.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError("Dash foreground extraction failed")
    dash = dash.crop(bbox)
    max_content = (248, 240)
    scale = min(max_content[0] / dash.width, max_content[1] / dash.height)
    size = (max(1, round(dash.width * scale)), max(1, round(dash.height * scale)))
    dash = dash.resize(size, Image.Resampling.NEAREST)

    dash_canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    x = (256 - dash.width) // 2
    # Match the padded idle's visible-foot baseline: source bbox bottom 139,
    # pasted at y=112, so the last visible row is y=250 (bbox bottom 251).
    y = 251 - dash.height
    dash_canvas.alpha_composite(dash, (x, y))
    dash_canvas.save(DASH_OUTPUT)

    print(f"idle={IDLE_OUTPUT} bbox={idle_canvas.getchannel('A').getbbox()}")
    print(f"dash={DASH_OUTPUT} bbox={dash_canvas.getchannel('A').getbbox()} scaled={size}")


if __name__ == "__main__":
    main()
