"""Export Lan's authored sword-wave body, preserving pixels and native timing."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw
from aseprite_rgba_reader import read, layer_frame

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'homeing-star-temp-assert/PendingArt/character/主角-岚/手动作业区/Sprite-0003.aseprite'
TARGET = ROOT / 'homeing-star-game/assets/characters/lan/body/attack/sword_wave'
PREVIEW = ROOT / 'homeing-star-test/artifacts/lan-sword-wave-source.png'

def main():
    before = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    document = read(SOURCE)
    assert document['canvas'] == (140, 60)
    assert len(document['frames']) == 24
    assert all(frame['duration_ms'] == 100 for frame in document['frames']), 'Update runtime timing if native timing changes'
    assert len(document['layers']) == 1 and document['layers'][0]['visible']
    sheet = Image.new('RGBA', (140 * 6, 60 * 4))
    preview = Image.new('RGBA', (140 * 6, 80 * 4), (45, 50, 60, 255))
    draw = ImageDraw.Draw(preview)
    for index, frame in enumerate(document['frames']):
        image, opacity = layer_frame(document, index, 0)
        assert opacity == 1.0, 'Do not silently alter authored opacity'
        sheet.paste(image, ((index % 6) * 140, (index // 6) * 60))
        point = ((index % 6) * 140, (index // 6) * 80)
        preview.alpha_composite(image, point)
        draw.text((point[0] + 3, point[1] + 61), str(index + 1), fill='white')
    TARGET.mkdir(parents=True, exist_ok=True)
    sheet.save(TARGET / 'sword_wave_body_140x60_24f.png')
    (TARGET / 'manifest.json').write_text(json.dumps({
        'source': str(SOURCE.relative_to(ROOT)), 'source_sha256': before,
        'frame_size': [140, 60], 'frame_count': 24, 'columns': 6,
        'durations_ms': [f['duration_ms'] for f in document['frames']],
        'effects': None, 'hitboxes': None,
    }, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    preview.resize((1680, 640), Image.Resampling.NEAREST).save(PREVIEW)
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == before
    print('Exported 24 native frames; source unchanged:', before)

if __name__ == '__main__':
    main()
