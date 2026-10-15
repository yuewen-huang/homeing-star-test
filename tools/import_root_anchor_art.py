"""Import six indexed Aseprite cels unchanged: four spawn frames, two idle frames."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image
from import_wind_thorn_wall import indexed_frames

BASE = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=BASE/'homeing-star-temp-assert/PendingArt/像素树桩魔法护盾动画帧.aseprite')
    parser.add_argument('--project', type=Path, default=BASE/'homeing-star-game')
    args = parser.parse_args()
    before = hashlib.sha256(args.source.read_bytes()).hexdigest()
    frames, durations = indexed_frames(args.source)
    assert len(frames) == 6 and frames[0].size == (132, 107)
    assert all(duration > 0 for duration in durations)
    width, height = frames[0].size
    sheet = Image.new('RGBA', (width*6, height))
    for i, frame in enumerate(frames):
        sheet.paste(frame, (i*width, 0))
    target = args.project/'assets/sideview/effects/root_anchor'
    target.mkdir(parents=True, exist_ok=True)
    sheet.save(target/'root_anchor.png')
    exported = Image.open(target/'root_anchor.png').convert('RGBA')
    for i, frame in enumerate(frames):
        assert exported.crop((i*width, 0, (i+1)*width, height)).tobytes() == frame.tobytes()
    # No authored slices. One fixed trunk-root baseline in the two idle cels;
    # the forward half of the magic ground ellipse extends below this baseline.
    data = {'canvas': [width, height], 'pivot': [66, 88], 'world_scale': 1.4,
            'pivot_source': 'shared trunk-root baseline in F04/F05; no source slice',
            'spawn_frames': 4, 'idle_frames': [4, 5], 'durations_ms': durations,
            'source_file': args.source.name, 'source_sha256': before}
    payload = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
    (target/'animation.tres').write_text('[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/animation = '+json.dumps(payload, ensure_ascii=False)+'\n', encoding='utf-8')
    assert hashlib.sha256(args.source.read_bytes()).hexdigest() == before
    print('PASS six exact source cels; timings %s; shared pivot (66,88); source unchanged' % durations)


if __name__ == '__main__':
    main()
