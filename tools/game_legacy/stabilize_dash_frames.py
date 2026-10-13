from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path("PendingArt/character/师傅/BOSS形态/采用/冲刺")
INPUT_DIR = ROOT / "dash-frames-aligned-v1"
OUTPUT_DIR = ROOT / "dash-frames-root-aligned-v2"
FRAME_SIZE = (512, 384)
PIVOT = (256, 336)
PELVIS_PROXY_TARGET = (256, 215)


def pelvis_proxy(image: Image.Image) -> tuple[int, int]:
    """Locate the belt/sash warm-color mass, excluding boots and upper effects."""
    rgba = np.asarray(image.convert("RGBA"))
    red, green, blue, alpha = [rgba[:, :, i] for i in range(4)]
    yy, xx = np.indices(alpha.shape)
    warm = (
        (alpha > 128)
        & (red > 120)
        & (green > 55)
        & (green < 155)
        & (blue < 70)
        & (xx > 150)
        & (xx < 360)
        & (yy > 120)
        & (yy < 280)
    )
    ys, xs = np.where(warm)
    if len(xs) < 100:
        raise RuntimeError("Not enough belt/sash pixels to determine pelvis proxy")
    return int(round(float(np.median(xs)))), int(round(float(np.median(ys))))


def translate(image: Image.Image, dx: int, dy: int) -> Image.Image:
    result = Image.new("RGBA", FRAME_SIZE, (0, 0, 0, 0))
    result.alpha_composite(image, (dx, dy))
    return result


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    source_frames = sorted(INPUT_DIR.glob("dash_??.png"))
    if len(source_frames) != 16:
        raise RuntimeError(f"Expected 16 frames, found {len(source_frames)}")

    output_frames: list[Image.Image] = []
    records: list[dict] = []
    for index, path in enumerate(source_frames, start=1):
        source = Image.open(path).convert("RGBA")
        detected = pelvis_proxy(source)
        dx = PELVIS_PROXY_TARGET[0] - detected[0]
        dy = PELVIS_PROXY_TARGET[1] - detected[1]
        output = translate(source, dx, dy)
        filename = f"dash_{index:02d}.png"
        output.save(OUTPUT_DIR / filename)
        output_frames.append(output)
        records.append(
            {
                "frame": index,
                "detected_pelvis_proxy": detected,
                "translation": [dx, dy],
            }
        )

    sheet = Image.new("RGBA", (FRAME_SIZE[0] * 4, FRAME_SIZE[1] * 4))
    for index, frame in enumerate(output_frames):
        sheet.alpha_composite(frame, ((index % 4) * FRAME_SIZE[0], (index // 4) * FRAME_SIZE[1]))
    sheet.save(OUTPUT_DIR / "dash_root_aligned_sheet_4x4.png")

    preview_frames = []
    for frame in output_frames:
        preview = Image.new("RGBA", FRAME_SIZE, (24, 24, 24, 255))
        preview.alpha_composite(frame)
        preview_frames.append(preview.convert("RGB"))
    preview_frames[0].save(
        OUTPUT_DIR / "dash_root_aligned_preview.gif",
        save_all=True,
        append_images=preview_frames[1:],
        duration=100,
        loop=0,
        disposal=2,
    )

    metadata = {
        "frame_size": FRAME_SIZE,
        "pivot": PIVOT,
        "pelvis_proxy_target": PELVIS_PROXY_TARGET,
        "frames": records,
    }
    (OUTPUT_DIR / "anchors.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
    )


if __name__ == "__main__":
    main()
