"""Package ImageGen art using sprite-pipeline; no procedural character drawing.

All operations are deterministic layout, uniform scaling and anchor alignment.
The supplied skill normalizer and contact-sheet renderer are used directly.
"""
from pathlib import Path
import json
import subprocess
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'homeing-star-temp-assert/PendingArt/forest_npcs/20261015-production'
GAME = ROOT / 'homeing-star-game'
SKILL = Path('C:/Users/P6063166/.codex/plugins/cache/openai-curated-remote/game-studio/0.1.2/scripts')
CHARS = [('yupo', '榆婆', 'red_squirrel'), ('ali', '阿砾', 'beaver'),
         ('lingwei', '铃尾', 'rabbit'), ('xiaosui', '小穗', 'red_squirrel')]
EMOTIONS = ['normal', 'concerned', 'relieved']
DURATIONS = [6.0, 1.0, 0.35, 1.0]


def bbox(im, threshold=8):
    return im.getchannel('A').point(lambda a: 255 if a > threshold else 0).getbbox()


def split(im, count):
    return [im.crop((round(i * im.width / count), 0, round((i + 1) * im.width / count), im.height)) for i in range(count)]


def feet_center(im):
    box = bbox(im, 100)
    foot = im.crop((0, box[3] - 10, im.width, box[3]))
    fb = bbox(foot, 100)
    return (fb[0] + fb[2]) // 2, box[3]


def frames_resource(id):
    out = ['[gd_resource type="SpriteFrames" load_steps=6 format=3]', '',
           f'[ext_resource type="Texture2D" path="res://assets/characters/forest_npcs/{id}/idle_128x160_4f.png" id="1"]', '']
    for i in range(4):
        out += [f'[sub_resource type="AtlasTexture" id="Atlas_{i}"]', 'atlas = ExtResource("1")',
                f'region = Rect2({i * 128}, 0, 128, 160)', '']
    out += ['[resource]', 'animations = [{', '"frames": [']
    out += [f'{{"duration": {DURATIONS[i]}, "texture": SubResource("Atlas_{i}")}}' + (',' if i < 3 else '') for i in range(4)]
    out += ['],', '"loop": true,', '"name": &"idle",', '"speed": 3.0', '}]', '']
    return '\n'.join(out)


def checker(size):
    im = Image.new('RGBA', size, '#d7d6cf')
    d = ImageDraw.Draw(im)
    for y in range(0, size[1], 16):
        for x in range(0, size[0], 16):
            if (x // 16 + y // 16) % 2:
                d.rectangle((x, y, x + 15, y + 15), fill='#bdbeb6')
    return im


def main():
    source = json.loads((ART / 'source_manifest.json').read_text(encoding='utf-8'))
    max_height = max(v['body_source_size'][1] for v in source['characters'].values())
    records = {}
    all_idle, all_portraits = {}, {}
    for id, name, species in CHARS:
        work = ART / id
        body_dest = GAME / 'assets/characters/forest_npcs' / id
        face_dest = GAME / 'assets/shared/ui/portraits/dialogue_fit' / id
        original_dest = GAME / 'assets/shared/ui/portraits/forest_npcs' / id
        for folder in [body_dest, face_dest, original_dest, work / 'idle_normalized']:
            folder.mkdir(parents=True, exist_ok=True)
        raw = Image.open(work / 'idle_raw.png').convert('RGBA')
        slots = split(raw, 4)
        boxes = [bbox(s) for s in slots]
        assert all(boxes), (id, boxes)
        contents = [s.crop(b) for s, b in zip(slots, boxes)]
        # Generator can return a different canvas size: one scale restores the
        # whole strip to the approved seed's pixel resolution before normalizing.
        shared_scale = min(224 / max(c.width for c in contents), 224 / max(c.height for c in contents))
        aligned = Image.new('RGBA', (1024, 256))
        for i, c in enumerate(contents):
            c = c.resize((round(c.width * shared_scale), round(c.height * shared_scale)), Image.Resampling.NEAREST)
            aligned.alpha_composite(c, (i * 256 + (256 - c.width) // 2, 240 - c.height))
        aligned.save(work / 'idle_aligned_source.png')
        subprocess.run([sys.executable, str(SKILL / 'normalize_sprite_strip.py'),
                        '--input', str(work / 'idle_aligned_source.png'), '--out-dir', str(work / 'idle_normalized'),
                        '--frames', '4', '--frame-size', '144', '--anchor', str(work / 'approved_seed_256.png')], check=True)
        frames, checks = [], []
        for i in range(4):
            small = Image.open(work / 'idle_normalized' / f'{i + 1:02}.png').convert('RGBA')
            cx, bottom = feet_center(small)
            placed = Image.new('RGBA', (128, 160))
            dx, dy = 64 - cx, 152 - bottom
            placed.alpha_composite(small, (dx, dy))
            # Every final content pixel must have survived the canvas placement.
            assert sum(placed.getchannel('A').tobytes()) == sum(small.getchannel('A').tobytes()), (id, 'clipped')
            assert feet_center(placed) == (64, 152), (id, feet_center(placed))
            placed.save(body_dest / f'idle_{i:02}.png')
            frames.append(placed)
            checks.append({'bbox': bbox(placed), 'feet': feet_center(placed)})
        sheet = Image.new('RGBA', (512, 160))
        for i, frame in enumerate(frames):
            sheet.alpha_composite(frame, (i * 128, 0))
        sheet.save(body_dest / 'idle_128x160_4f.png')
        (body_dest / 'idle_frames.tres').write_text(frames_resource(id), encoding='utf-8')
        stage = work / 'frames_preview_input'
        stage.mkdir(exist_ok=True)
        for i, frame in enumerate(frames):
            frame.save(stage / f'{i:02}.png')
        subprocess.run([sys.executable, str(SKILL / 'render_sprite_preview_sheet.py'), '--frames-dir', str(stage),
                        '--out', str(work / 'idle_contact_sheet.png'), '--columns', '4'], check=True)
        assert ImageChops.difference(frames[0], frames[2]).convert('RGB').getbbox(), (id, 'missing blink change')
        all_idle[id] = frames

        p_raw = Image.open(work / 'portrait_raw.png').convert('RGBA')
        # The rabbit generation placed its busts unevenly. Equal thirds cut
        # ear tips and carried them into the next slot. These measured empty
        # gutters split all three complete silhouettes without retouching pixels.
        if id == 'lingwei':
            assert p_raw.size == (2172, 724)
            cuts = [0, 754, 1432, 2172]
            p_slots = [p_raw.crop((cuts[i], 0, cuts[i + 1], p_raw.height)) for i in range(3)]
        else:
            p_slots = split(p_raw, 3)
        p_boxes = [bbox(p) for p in p_slots]
        p_contents = [p.crop(b) for p, b in zip(p_slots, p_boxes)]
        w = max(p.width for p in p_contents)
        h = max(p.height for p in p_contents)
        face_scale = min(1, 120 / w, 107 / h)
        size = round(w * face_scale), round(h * face_scale)
        faces = []
        for expression, p in zip(EMOTIONS, p_contents):
            aligned_portrait = Image.new('RGBA', (w, h))
            aligned_portrait.alpha_composite(p, ((w - p.width) // 2, h - p.height))
            aligned_portrait.save(original_dest / f'{expression}.png')
            sized = aligned_portrait.resize(size, Image.Resampling.NEAREST)
            face = Image.new('RGBA', (120, 107))
            face.alpha_composite(sized, ((120 - size[0]) // 2, 107 - size[1]))
            assert face.size == (120, 107) and face.getchannel('A').getextrema()[0] == 0
            face.save(face_dest / f'{expression}.png')
            faces.append(face)
        assert ImageChops.difference(faces[0], faces[1]).convert('RGB').getbbox(), (id, 'identical expressions')
        all_portraits[id] = faces
        height = max(bbox(f)[3] - bbox(f)[1] for f in frames)
        draw_scale = round(source['characters'][id]['body_source_size'][1] / max_height * 112 / height, 6)
        metadata = {'id': id, 'name': name, 'species': species, 'frame_size': [128, 160],
                    'frame_count': 4, 'feet_anchor': [64, 152], 'default_draw_scale': draw_scale,
                    'animation_fps': 3.0, 'frame_durations': DURATIONS, 'loop_seconds': sum(DURATIONS) / 3,
                    'expressions': EMOTIONS, 'portrait_canvas': [120, 107], 'pose_checks': checks,
                    'idle_source_scale': shared_scale, 'portrait_scale': face_scale}
        (body_dest / 'art_metadata.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
        records[id] = metadata

    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 22)
    smallfont = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 16)
    overview = checker((1280, 730))
    d = ImageDraw.Draw(overview)
    for index, (id, name, _) in enumerate(CHARS):
        x = index * 320
        d.text((x + 22, 12), name, font=font, fill='#1a2821')
        sprite = all_idle[id][0].resize((256, 320), Image.Resampling.NEAREST)
        overview.alpha_composite(sprite, (x + 32, 50))
        for e, expression in enumerate(['常态', '担忧', '放松']):
            face = all_portraits[id][e]
            overview.alpha_composite(face, (x + 16 + (e % 2) * 150, 400 + (e // 2) * 155))
            d.text((x + 16 + (e % 2) * 150, 510 + (e // 2) * 155), expression, font=smallfont, fill='#1a2821')
    overview.convert('RGB').save(ART / 'forest_npcs_overview.png')
    gif_frames = []
    for i in range(4):
        canvas = checker((1280, 390))
        d = ImageDraw.Draw(canvas)
        for index, (id, name, _) in enumerate(CHARS):
            d.text((index * 320 + 22, 12), name, font=font, fill='#1a2821')
            canvas.alpha_composite(all_idle[id][i].resize((256, 320), Image.Resampling.NEAREST), (index * 320 + 32, 45))
        gif_frames.append(canvas.convert('RGB'))
    gif_frames[0].save(ART / 'forest_npcs_idle_preview.gif', save_all=True, append_images=gif_frames[1:],
                       duration=[2000, 333, 117, 333], loop=0, disposal=2)
    (ART / 'package_report.json').write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({id: {'world_height': round(max(b['bbox'][3] - b['bbox'][1] for b in m['pose_checks']) * m['default_draw_scale'], 2),
                           'feet': [b['feet'] for b in m['pose_checks']], 'portrait_scale': m['portrait_scale']}
                      for id, m in records.items()}, ensure_ascii=False))


if __name__ == '__main__':
    main()
