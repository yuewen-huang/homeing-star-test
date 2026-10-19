"""Import only the user's wind-pressure layer; verify every deer reference frame."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image
from aseprite_rgba_reader import read, layer_frame

BASE = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=BASE.parent/'homeing-star-temp-assert/Art/bind_push_ING.aseprite')
    parser.add_argument('--project', type=Path, default=BASE.parent/'homeing-star-game')
    parser.add_argument('--output', type=Path, default=BASE/'artifacts/deer-wind-combo-20261012')
    args = parser.parse_args()
    before = hashlib.sha256(args.source.read_bytes()).hexdigest()
    doc = read(args.source)
    assert doc['canvas'] == (330, 256) and len(doc['frames']) == 26
    assert [layer['name'] for layer in doc['layers']] == ['Sprite Sheet', '图层 2']
    assert all(frame['duration_ms'] == 100 for frame in doc['frames'])
    body = Image.open(args.project/'assets/bosses/deer/body/boss/actions/bind_push_ING.png').convert('RGBA')
    assert body.size == (256*26, 256)
    atlas = Image.new('RGBA', (330*8, 256*4))
    frames = []
    for index in range(26):
        reference, alpha = layer_frame(doc, index, 0)
        expected = Image.new('RGBA', doc['canvas'])
        expected.paste(body.crop((256*index, 0, 256*(index+1), 256)), (0, 0))
        assert alpha == 1 and reference.tobytes() == expected.tobytes(), ('Body reference changed', index)
        effect, opacity = layer_frame(doc, index, 1)
        x, y = index%8*330, index//8*256
        atlas.paste(effect, (x, y))
        frames.append({'region': [x,y,330,256], 'opacity': opacity, 'duration_ms': 100})
    target = args.project/'assets/bosses/deer/fx/painted'
    target.mkdir(parents=True, exist_ok=True)
    texture = target/'wind_pressure.png'
    atlas.save(texture)
    check = Image.open(texture).convert('RGBA')
    for index, frame in enumerate(frames):
        x,y,w,h = frame['region']
        assert check.crop((x,y,x+w,y+h)).tobytes() == layer_frame(doc,index,1)[0].tobytes()
    data = {'canvas': [330,256], 'pivot': [82,256], 'world_scale': 1.4, 'frames': frames,
            'body_clip': 'bind_push_ING', 'contact_frames': [3,10,17], 'tail_first':21,
            'source_sha256': before}
    resource = '[gd_resource type="Resource" load_steps=2 format=3]\n\n[ext_resource type="Texture2D" path="res://assets/bosses/deer/fx/painted/wind_pressure.png" id="1"]\n\n[resource]\nmetadata/texture = ExtResource("1")\nmetadata/animation = '+json.dumps(json.dumps(data,ensure_ascii=False),ensure_ascii=False)+'\n'
    (target/'wind_pressure.tres').write_text(resource,encoding='utf-8')
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'painted-import.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    assert hashlib.sha256(args.source.read_bytes()).hexdigest() == before
    print('PASS: 26 unchanged body references; 26 exact effect cels; original opacity, canvas and pivot retained; source unchanged')

if __name__ == '__main__': main()
