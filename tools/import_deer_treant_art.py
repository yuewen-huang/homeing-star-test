"""Import the user's small-treant sheets for the vine phase.

Source: PendingArt/character/朽角巡林者/小树人/{walk,idle}.png, each a 4×4 grid of 68×92
cells (16 frames, reading order), facing left, feet ending at cell y = 76. 'walk' is the walk
loop; 'idle' crouches and reaches both arms out, used as the spike-casting motion.
Sheets are copied pixel-exact (no scaling or recolour); the palette reference
small-treant-6colors.png is not a runtime asset. Sources are not modified.
"""
from pathlib import Path
import argparse
import hashlib
from PIL import Image

BASE = Path(__file__).resolve().parents[1]
SHEET = (272, 368)
CELL = (68, 92)
FEET_Y = 76


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=BASE.parent/'homeing-star-temp-assert/PendingArt/character/朽角巡林者/小树人')
    parser.add_argument('--project', type=Path, default=BASE.parent/'homeing-star-game')
    args = parser.parse_args()
    target = args.project/'assets/bosses/deer/body/treant'
    target.mkdir(parents=True, exist_ok=True)
    for source_name, target_name in (('walk.png', 'treant_walk.png'), ('idle.png', 'treant_cast.png')):
        source = args.source/source_name
        before = hashlib.sha256(source.read_bytes()).hexdigest()
        image = Image.open(source).convert('RGBA')
        assert image.size == SHEET, (source_name, image.size)
        for index in range(16):
            x, y = index % 4 * CELL[0], index // 4 * CELL[1]
            cell = image.crop((x, y, x + CELL[0], y + CELL[1]))
            box = cell.getbbox()
            assert box is not None and box[3] == FEET_Y, (source_name, index, box)
        image.save(target/target_name)
        assert Image.open(target/target_name).convert('RGBA').tobytes() == image.tobytes()
        assert hashlib.sha256(source.read_bytes()).hexdigest() == before
    print('PASS: walk and cast sheets copied exactly to %s; feet end at y=%d in all 32 cells; sources unchanged' % (target, FEET_Y))


if __name__ == '__main__':
    main()
