"""Encode native Godot viewport frames. Does not modify source artwork."""
from pathlib import Path
import argparse
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("capture_dir", type=Path)
args = parser.parse_args()
paths = sorted(args.capture_dir.glob("growth_*.png"))
if not paths:
    raise SystemExit("No native growth frames found")
frames = [Image.open(path).convert("RGB") for path in paths]
output = args.capture_dir / "rooted_growth.webp"
frames[0].save(output, save_all=True, append_images=frames[1:],
               duration=50, loop=0, quality=88, method=4)
with Image.open(output) as preview:
    assert preview.n_frames == len(frames), (preview.n_frames, len(frames))
    assert preview.size == (1280, 720), preview.size
print(f"{output}: {len(frames)} native frames, 20 fps, {output.stat().st_size} bytes")
