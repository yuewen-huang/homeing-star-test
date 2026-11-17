"""Package unchanged native Godot captures as a compact animated preview."""
from pathlib import Path
import argparse
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    args = parser.parse_args()
    paths = sorted(args.folder.glob('movie_*.png'))
    assert len(paths) >= 67
    fps = 12 if len(paths) == 67 else 24
    frames = [Image.open(path).convert('RGB').resize((960, 540), Image.Resampling.NEAREST) for path in paths]
    # Use one palette across the movie to keep the grid/UI colors stable.
    reference = Image.new('RGB', (960, 540 * 8))
    selected = [round((len(frames) - 1) * index / 7) for index in range(8)]
    for index, frame_index in enumerate(selected):
        reference.paste(frames[frame_index], (0, 540 * index))
    palette = reference.quantize(colors=256)
    animated = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    durations = [round((i + 1) * 100 / fps) * 10 - round(i * 100 / fps) * 10 for i in range(len(frames))]
    durations[-1] += 250
    destination = args.folder / '双子登场_原生Godot预览.gif'
    animated[0].save(destination, save_all=True, append_images=animated[1:], duration=durations,
                     loop=0, disposal=2, optimize=False)
    print(destination)


if __name__ == '__main__':
    main()
