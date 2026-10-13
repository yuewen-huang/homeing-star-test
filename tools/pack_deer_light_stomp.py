"""Package native Godot captures without adding or altering game effects."""
from pathlib import Path
import sys
from PIL import Image

root = Path(sys.argv[1])
for name in ("normal", "slow"):
    paths = sorted((root / name).glob("*.png"))
    frames = [Image.open(path).convert("RGB") for path in paths]
    sample = Image.new("RGB", (1280, 720 * 8))
    for i in range(8):
        sample.paste(frames[min(len(frames) - 1, int(len(frames) * i / 8))], (0, i * 720))
    palette = sample.quantize(colors=256)
    indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    indexed[0].save(root / f"{name}.gif", save_all=True, append_images=indexed[1:],
                    duration=[50] * (len(indexed) - 1) + [650], loop=0, optimize=True)
    print(name, len(frames), "frames", (root / f"{name}.gif").stat().st_size, "bytes")

normal = sorted((root / "normal").glob("*.png"))
sheet = Image.new("RGB", (1024, 680))
for i, frame in enumerate((10, 12, 14, 18)):
    source = Image.open(normal[frame]).crop((560, 250, 1072, 590))
    sheet.paste(source, ((i % 2) * 512, (i // 2) * 340))
sheet.save(root / "keyframes.png")
