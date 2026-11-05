"""Encode the real, fixed-step Godot thorn captures without altering artwork."""
from pathlib import Path
import argparse
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("capture_dir", type=Path)
args = parser.parse_args()
for kind, name in [(1, "stomp_eruption"), (2, "sky_vines")]:
    paths = [p for p in sorted(args.capture_dir.glob(f"thorn_{kind}_*.png"))
             if int(p.stem.split("_")[-1]) % 3 == 0]
    assert len(paths) == 150, f"Expected 7.5 seconds at 20 fps, got {len(paths)}"
    frames = [Image.open(p).convert("RGB") for p in paths]
    assert all(im.size == (1280, 720) for im in frames)
    output = args.capture_dir / f"{name}.webp"
    frames[0].save(output, save_all=True, append_images=frames[1:],
                   duration=50, loop=0, quality=88, method=4)
    with Image.open(output) as preview:
        duration = 0
        for index in range(preview.n_frames):
            preview.seek(index)
            preview.load()
            duration += preview.info.get("duration", 0)
        assert duration == 7500, duration
    print(f"{output}: {duration} ms, {output.stat().st_size} bytes")
