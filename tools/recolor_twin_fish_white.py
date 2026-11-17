"""Export the white twin's atlases and PNG frames from the black fish artwork."""

import argparse
from pathlib import Path
from tempfile import TemporaryDirectory

import numpy as np
from PIL import Image


ART = Path(__file__).resolve().parents[2] / 'homeing-star-temp-assert/PendingArt/character/双子'
FRAME_SIZE = 256
COLUMNS = 6
FRAME_COUNT = 32

# Calibrated against the paired black/white walk references in 双子/新建文件夹.
# The near-black fin folds take the blue ramp. The brighter body and fin tips
# take the ivory ramp. Interpolation keeps shading in the unindexed sheets.
PALETTE = (
    (0, (33, 107, 166)),
    (18, (57, 153, 219)),
    (34, (119, 190, 229)),
    (44, (143, 198, 225)),
    (64, (180, 202, 213)),
    (82, (220, 229, 219)),
    (100, (252, 226, 213)),
    (122, (255, 234, 213)),
    (155, (255, 242, 222)),
)


def recolor(source):
    pixels = np.array(source)
    visible = pixels[:, :, 3] != 0
    red, green, blue = pixels[visible, :3].astype(np.float32).T
    tone = blue + 0.35 * (green - 0.5 * blue)
    stops, colors = zip(*PALETTE)
    target = np.stack([np.interp(tone, stops, channel) for channel in zip(*colors)], axis=1)

    # Treat pale neutral glints as dark eye details, matching the white reference.
    # Transparent highlights in the source keep their original alpha.
    glint = np.clip((np.minimum(red, green) - 88) / 75, 0, 1)
    glint *= np.clip((red + 46 - blue) / 30, 0, 1)
    target += (np.array([37, 29, 41]) - target) * glint[:, None]
    pixels[visible, :3] = np.rint(target).astype(np.uint8)
    return Image.fromarray(pixels)


def frame_box(index):
    row, column = divmod(index, COLUMNS)
    return tuple(value * FRAME_SIZE for value in (column, row, column + 1, row + 1))


def export_sheet(path, output):
    with Image.open(path) as image:
        source = image.convert('RGBA')
    if source.size != (COLUMNS * FRAME_SIZE,) * 2:
        raise ValueError(f'{path.name}: expected a 1536×1536 atlas')

    alpha = source.getchannel('A')
    for index in range(COLUMNS ** 2):
        if bool(alpha.crop(frame_box(index)).getbbox()) != (index < FRAME_COUNT):
            raise ValueError(f'{path.name}: unexpected content in cell {index + 1}')

    white = recolor(source)
    white.save(output / path.name)
    frame_dir = output / '序列帧' / path.stem
    frame_dir.mkdir(parents=True)
    for index in range(FRAME_COUNT):
        white.crop(frame_box(index)).save(frame_dir / f'{index + 1:02d}.png')
    print(f'{path.name}: {FRAME_COUNT} frames at {FRAME_SIZE}×{FRAME_SIZE}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ART / '白鱼',
                        help='New output directory. Defaults to 双子/白鱼.')
    output = parser.parse_args().output.resolve()
    if output.exists():
        parser.error(f'Choose a new output directory: {output} already exists.')
    sheets = sorted((ART / '黑鱼').glob('*.png'))
    if not sheets:
        parser.error(f'No black fish sheets found under {ART / "黑鱼"}.')

    output.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix='.white-fish-', dir=output.parent) as staging:
        generated = Path(staging) / 'frames'
        generated.mkdir()
        for sheet in sheets:
            export_sheet(sheet, generated)
        generated.rename(output)
    print(f'Exported {len(sheets) * FRAME_COUNT} frames to {output}')


if __name__ == '__main__':
    main()
