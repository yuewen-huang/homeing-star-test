from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "PendingArt" / "character" / "师傅" / "手工绑骨作业区" / "最终成品" / "风魔法FX"
OUTPUT_DIR = ROOT / "assets" / "sideview" / "effects" / "master_wind"

FILES = {
    "my-art-atak1.png": "attack_1_fx_576x256_11f.png",
    "my-art-atak2.png": "attack_2_fx_576x256_19f.png",
    "my-art-atak3.png": "attack_3_fx_576x256_28f.png",
    "my-art-sp-atak.png": "special_attack_fx_576x256_18f.png",
}

# Approved palette C: blue-violet storm shadows with a restrained icy edge.
# Keep the same mapping as the reviewed sample so the final sheets match it.
RAMP_POSITIONS = np.array([0.0, 0.22, 0.50, 0.76, 1.0], dtype=np.float32)
RAMP_COLORS = np.array([
    [18, 17, 54],
    [43, 55, 117],
    [60, 121, 174],
    [126, 196, 221],
    [218, 235, 239],
], dtype=np.float32)


def recolor(source: Image.Image) -> Image.Image:
    rgba = np.asarray(source.convert("RGBA"), dtype=np.uint8)
    rgb = rgba[..., :3].astype(np.float32) / 255.0
    alpha = rgba[..., 3].copy()

    luminance = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    value = rgb.max(axis=2)
    energy = np.clip(0.52 * value + 0.48 * luminance, 0.0, 1.0)

    mapped = np.empty((*energy.shape, 3), dtype=np.float32)
    for channel in range(3):
        mapped[..., channel] = np.interp(energy, RAMP_POSITIONS, RAMP_COLORS[:, channel])

    output = np.zeros_like(rgba)
    output[..., :3] = np.clip(np.rint(mapped), 0, 255).astype(np.uint8)
    output[..., 3] = alpha
    output[alpha == 0, :3] = 0
    return Image.fromarray(output, "RGBA")


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for source_name, output_name in FILES.items():
        source_path = SOURCE_DIR / source_name
        output_path = OUTPUT_DIR / output_name
        source = Image.open(source_path).convert("RGBA")
        result = recolor(source)
        result.save(output_path)
        print(f"{output_name}: {result.width}x{result.height}, alpha preserved")


if __name__ == "__main__":
    main()
