from pathlib import Path
from PIL import Image

ROOT = Path(r"C:\Users\P6063166\.codex\visualizations\2026\10\10\01a123df-d0fc-7331-96ec-48167310c626\mist_redo")


def compose(prefix: str) -> None:
    paths = sorted(ROOT.glob(f"{prefix}_[0-9][0-9][0-9].png"))
    assert paths, f"No Godot captures for {prefix}"
    frames = []
    for path in paths:
        with Image.open(path) as source:
            frames.append(source.convert("RGB").crop((200, 220, 1000, 580)))
    palette_samples = Image.new("RGB", (256 * 8, 116))
    for i in range(8):
        sample = frames[round(i * (len(frames) - 1) / 7)]
        palette_samples.paste(sample.resize((256, 116)), (i * 256, 0))
    palette = palette_samples.quantize(colors=256)
    indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    target = ROOT / f"{prefix}_preview.gif"
    indexed[0].save(target, save_all=True, append_images=indexed[1:], duration=50, loop=0, disposal=1, optimize=True)
    frames[0].save(ROOT / f"{prefix}_preview.webp", save_all=True, append_images=frames[1:], duration=50, loop=0, quality=90, method=4)
    sheet = Image.new("RGB", (800, 360))
    for i in range(4):
        sheet.paste(frames[round(i * (len(frames) - 1) / 3)].resize((400, 180), Image.Resampling.NEAREST), ((i % 2) * 400, (i // 2) * 180))
    sheet.save(ROOT / f"{prefix}_contact_sheet.png")
    print(f"{target}: {len(frames)} frames, {target.stat().st_size} bytes")


compose("wave")
compose("snare")
