"""Prepare pose references and package imagegen-painted HD vine animation assets.

Painting is performed by imagegen. This tool only lays out references, splits cells,
aligns the common root, packages Aseprite, and measures the painted collision body.
"""
from pathlib import Path
import argparse
import json
import shutil
import hashlib
from PIL import Image, ImageDraw
import build_vine_ground_slam as native
from build_vine_ground_slam_v2 import DURATIONS, STAGES
from import_deer_ground_lash import body_capsules

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'homeing-star-temp-assert/PendingArt/character/朽角巡林者/藤鞭地底重拍_高清双藤_v3_20261013'
GAME = ROOT / 'homeing-star-game/assets/bosses/deer/body/human/vfx'
SIZE = (512, 512)
PIVOT = (110, 448)
GROUPS = ['01_F00-F05', '02_F06-F11', '03_F12-F17', '04_F18-F23', '05_F24-F29']


def prepare():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / '参考').mkdir(exist_ok=True)
    (OUT / '生图原始输出').mkdir(exist_ok=True)
    old = Image.open(GAME / 'vine_ground_lash.png').convert('RGBA')
    for group in range(5):
        image = Image.new('RGBA', (224*3, 224*2))
        for slot in range(6):
            index = group*6+slot
            x, y = index % 6*224, index//6*224
            image.paste(old.crop((x,y,x+224,y+224)), (slot%3*224, slot//3*224))
        image.save(OUT / '参考' / f'{group+1:02d}_F{group*6:02d}-F{group*6+5:02d}.png')


def opaque_bbox(image):
    return image.getchannel('A').point(lambda a: 255 if a > 16 else 0).getbbox()


def soil_pivot(image):
    """Align on the little brown root clod, never on the moving tip/content bbox."""
    pixels = image.load()
    soil = [(x,y) for y in range(330,512) for x in range(10,220)
            if pixels[x,y][3] > 128 and pixels[x,y][0] > pixels[x,y][1] * 1.12
            and pixels[x,y][1] > pixels[x,y][2] * 1.05 and pixels[x,y][0] > 35]
    if not soil:
        raise ValueError('No authored root clod found; refuse content-centering')
    foot = max(y for x,y in soil)
    xs = [x for x,y in soil if y >= foot-9]
    return ((min(xs)+max(xs))/2, foot-9)


def package():
    (OUT / '序列帧').mkdir(exist_ok=True)
    (OUT / '预览').mkdir(exist_ok=True)
    source = ROOT / 'homeing-star-temp-assert/PendingArt/character/朽角巡林者/藤鞭地底重拍_三变体_v2_20261013/03_双藤重拍.aseprite'
    original_bytes = source.read_bytes()
    frames, anchors, bounds = [], [], []
    for group in GROUPS:
        atlas = Image.open(OUT / '生图原始输出' / (group+'.png')).convert('RGBA')
        assert atlas.size == (1536,1024), (group, atlas.size)
        for slot in range(6):
            x, y = slot % 3*512, slot//3*512
            frame = atlas.crop((x,y,x+512,y+512))
            box = opaque_bbox(frame)
            if box:
                anchor = soil_pivot(frame)
            else:
                anchor = PIVOT
            frames.append(frame)
            anchors.append(anchor)
            bounds.append(box)
    assert len(frames) == 30 and opaque_bbox(frames[29]) is None
    # One common scale for ALL frames. Translation only aligns the planted root.
    common_scale = 1.0
    for box, anchor in zip(bounds, anchors):
        if not box:
            continue
        for extent, available in ((anchor[0]-box[0], PIVOT[0]-8),
                                  (box[2]-anchor[0], 504-PIVOT[0]),
                                  (anchor[1]-box[1], PIVOT[1]-8),
                                  (box[3]-anchor[1], 504-PIVOT[1])):
            if extent > 0:
                common_scale = min(common_scale, available/extent)
    normalized = []
    shifts = []
    sheet = Image.new('RGBA', (3072,2560))
    for index, (frame, anchor) in enumerate(zip(frames, anchors)):
        resized = frame.resize((round(512*common_scale),)*2, Image.Resampling.LANCZOS)
        dx = round(PIVOT[0]-anchor[0]*common_scale)
        dy = round(PIVOT[1]-anchor[1]*common_scale)
        image = Image.new('RGBA', SIZE)
        image.alpha_composite(resized, (dx,dy))
        normalized.append(image)
        shifts.append([dx,dy])
        image.save(OUT / '序列帧' / f'F{index:02d}.png')
        sheet.paste(image, (index % 6*512, index//6*512))
    sheet.save(OUT / '03_双藤重拍_高清.png')
    # Keep the original 30-frame physics/timing as a hidden, locked reference layer.
    document = native.read(source)
    references = []
    for i in range(30):
        old, _ = native.layer_frame(document, i, 1)
        reference = old.resize(SIZE, Image.Resampling.NEAREST)
        references.append(reference)
    native.SIZE, native.ROOT = SIZE, PIVOT
    native.aseprite(OUT / '03_双藤重拍_高清.aseprite', normalized, references,
                    plan=[(0,0,DURATIONS[i],STAGES[i]) for i in range(30)])
    capsules = [body_capsules(frame, PIVOT) for frame in normalized]
    assert all(capsules[i] for i in range(11,21)), 'Missing solid body on an active frame'
    data = dict(canvas=list(SIZE), pivot=list(PIVOT), columns=6, rows=5,
                duration_ms=DURATIONS, active_frames=[11,20], slam_frames=[11,18],
                impact_frames=[16,18], capsules=capsules,
                bounds=[opaque_bbox(im) for im in normalized], texture_filter='linear',
                source_sha256=hashlib.sha256(original_bytes).hexdigest(),
                hd_source='03_双藤重拍_高清.aseprite', common_scale=common_scale)
    (OUT / '时间轴.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    (OUT / '枢轴归一记录.json').write_text(json.dumps(dict(native_cell=512, canvas=SIZE,pivot=PIVOT,
        common_scale=common_scale, measured_roots=anchors, translations=shifts),indent=2),encoding='utf-8')
    shutil.copy2(OUT / '03_双藤重拍_高清.png', GAME / 'vine_ground_lash_hd.png')
    encoded = json.dumps(json.dumps(data, separators=(',', ':')))
    (GAME / 'vine_ground_lash_hd.tres').write_text('[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/animation = '+encoded+'\n',encoding='utf-8')
    # Preview preserves the generated alpha via composition, not a background-removal edit.
    previews = []
    for image in normalized:
        bg = Image.new('RGBA', SIZE, (28,36,33,255))
        bg.alpha_composite(image)
        previews.append(bg.convert('RGB'))
    previews[0].save(OUT / '预览' / '03_双藤重拍_高清.gif', save_all=True,
                     append_images=previews[1:], duration=DURATIONS, loop=0, disposal=2)
    check_sheet = Image.new('RGB',(512*5,512*2),(28,36,33))
    for slot, index in enumerate([7,10,11,12,13,14,15,16,18,23]):
        check_sheet.paste(previews[index],(slot%5*512,slot//5*512))
        ImageDraw.Draw(check_sheet).text((slot%5*512+8,slot//5*512+8),f'F{index:02d}',fill='white')
    check_sheet.save(OUT / '预览' / '传力关键帧.png')
    assert source.read_bytes() == original_bytes
    print('PASS: 30 generated 512px frames, common scale',common_scale,'pivot',PIVOT,
          '2.14s; native two-layer RGBA round-trip verified; original untouched')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--package', action='store_true')
    args = parser.parse_args()
    if args.prepare:
        prepare()
        print('Prepared five six-frame pose reference strips')
    if args.package:
        package()
