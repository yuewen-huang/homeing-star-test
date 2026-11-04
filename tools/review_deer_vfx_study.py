"""Assemble native Godot captures; never paints or substitutes effect artwork."""
from pathlib import Path
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "artifacts/deer-vfx-catalog-20261104"
CASES = [("cleave", 7), ("ribbon", 10), ("ground", 13), ("greatblade", 20),
         ("fire", 22), ("vortex", 22), ("leaves", 30), ("swords", 35)]


def main():
    compositions = "--compositions" in sys.argv
    root = ROOT.with_name("deer-vfx-compositions-20261104") if compositions else ROOT
    cases = [("rush",20),("sweep",19),("drop",28),("leaf",37)] if compositions else CASES
    sheet = Image.new("RGB", (1280, ((len(cases)+1)//2)*360), "#20262d")
    sequences = []
    for i, (name, peak) in enumerate(cases):
        folder = root / name
        frames = []
        for source in sorted(folder.glob("frame_*.png")):
            with Image.open(source) as frame:
                frames.append(frame.convert("RGB").resize((768, 432), Image.Resampling.LANCZOS))
        assert len(frames) >= 61, (name, len(frames))
        frames[0].save(root / f"{name}.gif", save_all=True, append_images=frames[1:],
                       duration=[42 if n % 3 else 41 for n in range(len(frames))], loop=0)
        sequences.append(frames)
        with Image.open(folder / f"frame_{peak:03d}.png") as frame:
            sheet.paste(frame.convert("RGB").resize((640, 360), Image.Resampling.LANCZOS),
                        (i % 2 * 640, i // 2 * 360))
    sheet.save(root / "catalog_sheet.jpg", quality=94)
    if compositions:
        comparison = []
        for frame in range(max(map(len,sequences))):
            canvas = Image.new("RGB", (1024,576), "#20262d")
            for i, seq in enumerate(sequences):
                canvas.paste(seq[min(frame,len(seq)-1)].resize((512,288), Image.Resampling.LANCZOS),
                             (i%2*512,i//2*288))
            comparison.append(canvas)
        comparison[0].save(root / "four_moves.gif", save_all=True, append_images=comparison[1:],
                           duration=[42 if n%3 else 41 for n in range(len(comparison))], loop=0)
    print(root / "catalog_sheet.jpg")


if __name__ == "__main__":
    main()
