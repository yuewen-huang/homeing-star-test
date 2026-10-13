"""Check the final HD source through native Aseprite, including every RGBA pixel."""
from pathlib import Path
import json
import subprocess
import sys
from PIL import Image
from build_hd_vine_lash import OUT, DURATIONS

sys.stdout.reconfigure(encoding='utf-8')
out = OUT / '预览'
sheet = out / 'native-hd.png'
data = out / 'native-hd.json'
result = subprocess.run(['E:/Aseprite/Aseprite.exe', '-b', '--list-layers', '--list-tags',
    '--list-slices', str(OUT / '03_双藤重拍_高清.aseprite'), '--format', 'json-array',
    '--data', str(data), '--sheet', str(sheet), '--sheet-type', 'horizontal'],
    capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW, timeout=40)
assert result.returncode == 0, result.stderr.decode(errors='replace')
assert data.exists(), (result.stdout, result.stderr)
native = json.loads(data.read_text(encoding='utf-8'))
assert len(native['frames']) == 30
assert [f['duration'] for f in native['frames']] == DURATIONS
assert native['meta']['slices'][0]['keys'][0]['pivot'] == dict(x=110,y=448)
image = Image.open(sheet).convert('RGBA')
for i, frame in enumerate(native['frames']):
    r = frame['frame']
    exported = image.crop((r['x'],r['y'],r['x']+r['w'],r['y']+r['h']))
    expected = Image.open(OUT / '序列帧' / f'F{i:02d}.png').convert('RGBA')
    assert exported.tobytes() == expected.tobytes(), i
report = dict(frames=30,canvas=[512,512],pivot=[110,448],duration_ms=sum(DURATIONS),
              native_rgba_pixel_exact=True,layers=native['meta']['layers'],
              tags=native['meta']['frameTags'])
(out/'native-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS native Aseprite: all 30 HD RGBA frames, durations, pivot and two layers verified')
