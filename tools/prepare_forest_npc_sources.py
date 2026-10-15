"""Slice the approved, ImageGen-matted board; package seeds for sprite-pipeline.

Only layout/cropping/uniform resampling happens here. Character drawing and
background extraction are performed by ImageGen, never synthesized in this script.
"""
from pathlib import Path
import argparse
import json
import subprocess
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'homeing-star-temp-assert/PendingArt/forest_npcs/20261015-production'
SKILL = Path('C:/Users/P6063166/.codex/plugins/cache/openai-curated-remote/game-studio/0.1.2')
CHARACTERS = [('yupo', 0, 384), ('ali', 384, 800), ('lingwei', 800, 1184), ('xiaosui', 1184, 1536)]


def content(im):
    box = im.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()
    if box is None:
        raise ValueError('Empty source crop')
    return im.crop(box)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('matted_board', type=Path)
    args = parser.parse_args()
    im = Image.open(args.matted_board).convert('RGBA')
    assert im.size == (1536, 1024), im.size
    OUT.mkdir(parents=True, exist_ok=True)
    im.save(OUT / 'approved_cast_matted.png')
    manifest = {'approval': 'User approved all four designs on 2026-10-15', 'characters': {}}
    for name, left, right in CHARACTERS:
        dest = OUT / name
        dest.mkdir(exist_ok=True)
        body = content(im.crop((left, 60, right, 624)))
        portrait = content(im.crop((left, 624, right, 1024)))
        body.save(dest / 'approved_body_source.png')
        portrait.save(dest / 'approved_portrait_source.png')
        ratio = min(224 / body.height, 224 / body.width)
        sized = body.resize((round(body.width * ratio), round(body.height * ratio)), Image.Resampling.NEAREST)
        seed = Image.new('RGBA', (256, 256))
        seed.alpha_composite(sized, ((256 - sized.width) // 2, 240 - sized.height))
        seed.save(dest / 'approved_seed_256.png')
        subprocess.run([sys.executable, str(SKILL / 'scripts/build_sprite_edit_canvas.py'),
                        '--seed', str(dest / 'approved_seed_256.png'),
                        '--out', str(dest / 'idle_reference_canvas.png'),
                        '--frames', '4', '--slot-size', '256', '--canvas-size', '1024'], check=True)
        manifest['characters'][name] = {'body_source_size': body.size, 'portrait_source_size': portrait.size,
                                        'reference_canvas': '1024x1024; strip x=0..1024,y=384..640; four 256x256 slots'}
    (OUT / 'source_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print(OUT)


if __name__ == '__main__':
    main()
