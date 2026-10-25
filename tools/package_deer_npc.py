"""Package ImageGen's male stag idle strip; only crop, uniform scale and alignment.

Usage: python package_deer_npc.py <raw-strip.png>
"""
from pathlib import Path
import json
import shutil
import subprocess
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'homeing-star-temp-assert/PendingArt/deer_npc/20261025'
BODY = ROOT / 'homeing-star-game/assets/characters/deer/body/npc'
PORTRAIT = ROOT / 'homeing-star-game/assets/shared/ui/portraits/dialogue_fit/deer'
SKILL = Path('D:/CodexData/.codex/plugins/cache/openai-curated-remote/game-studio/0.1.2/scripts')


def main():
    SOURCE.mkdir(parents=True, exist_ok=True)
    BODY.mkdir(parents=True, exist_ok=True)
    PORTRAIT.mkdir(parents=True, exist_ok=True)
    raw = SOURCE / 'idle_raw.png'
    if Path(sys.argv[1]).resolve() != raw.resolve():
        shutil.copyfile(sys.argv[1], raw)
    subprocess.run([sys.executable, str(SKILL / 'normalize_sprite_strip.py'),
                    '--input', str(raw), '--out-dir', str(SOURCE / 'normalized'),
                    '--frames', '4', '--frame-size', '144'], check=True)
    sheet = Image.new('RGBA', (512, 160))
    checks = []
    for i in range(4):
        square = Image.open(SOURCE / f'normalized/{i+1:02d}.png').convert('RGBA')
        box = square.getbbox()
        assert box and box[0] >= 8 and box[2] <= 136, ('Frame too wide', i, box)
        frame = Image.new('RGBA', (128, 160))
        frame.alpha_composite(square.crop((8, 0, 136, 144)), (0, 8))
        frame.save(BODY / f'idle_{i:02d}.png')
        (SOURCE / 'frames').mkdir(exist_ok=True)
        frame.save(SOURCE / f'frames/idle_{i:02d}.png')
        sheet.alpha_composite(frame, (128*i, 0))
        checks.append({'bbox': frame.getbbox(), 'anchor': [64, 152]})
    sheet.save(BODY / 'idle_128x160_4f.png')
    resources = ['[gd_resource type="SpriteFrames" load_steps=6 format=3]', '',
                 '[ext_resource type="Texture2D" path="res://assets/characters/deer/body/npc/idle_128x160_4f.png" id="1"]', '']
    for i in range(4):
        resources += [f'[sub_resource type="AtlasTexture" id="Atlas_{i}"]',
                      'atlas = ExtResource("1")', f'region = Rect2({i*128}, 0, 128, 160)', '']
    resources += ['[resource]', 'animations = [{', '"frames": [']
    durations = [6.0, 1.0, 0.35, 1.0]
    resources += [f'{{"duration": {duration}, "texture": SubResource("Atlas_{i}")}}' + (',' if i < 3 else '')
                  for i, duration in enumerate(durations)]
    resources += ['],', '"loop": true,', '"name": &"idle",', '"speed": 3.0', '}]']
    (BODY / 'idle_frames.tres').write_text('\n'.join(resources)+'\n', encoding='utf-8')
    # User requested the existing HD portrait with a tighter face crop (2026-10-25).
    hd_source = ROOT / 'homeing-star-temp-assert/Art/头像/净化的翡翠之心森林鹿灵.png'
    hd = Image.open(hd_source).convert('RGBA')
    face_crop = (610, 330, 1120, 785)
    bust = hd.crop(face_crop)
    original = ROOT / 'homeing-star-game/assets/shared/ui/portraits/deer/normal.png'
    original.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(hd_source, original)
    bust.thumbnail((120, 107), Image.Resampling.LANCZOS)
    portrait = Image.new('RGBA', (120, 107))
    portrait.alpha_composite(bust, ((120-bust.width)//2, 107-bust.height))
    portrait.save(PORTRAIT / 'normal.png')
    (BODY / 'art_metadata.json').write_text(json.dumps({
        'id': 'deer', 'role': 'purified_resident', 'sex': 'male',
        'frame_size': [128, 160], 'frame_count': 4, 'feet_anchor': [64, 152],
        'default_draw_scale': .777778, 'frame_durations': durations,
        'pose_checks': checks, 'portrait_canvas': [120, 107],
        'portrait_source': '净化的翡翠之心森林鹿灵.png', 'portrait_crop': face_crop,
        'source': 'ImageGen male stag seed and whole-strip edit; user review pending'
    }, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    subprocess.run([sys.executable, str(SKILL / 'render_sprite_preview_sheet.py'),
                    '--frames-dir', str(SOURCE / 'frames'), '--out', str(SOURCE / 'idle_preview.png'),
                    '--columns', '4'], check=True)
    print(json.dumps(checks))


if __name__ == '__main__':
    main()
