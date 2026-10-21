"""Prepare transparent whole-animation edit targets without changing frame pivots.

Extends sprite-pipeline's build_sprite_edit_canvas recipe: that helper scales and
centres one seed in one slot. VFX need every authored frame and the original shared
clip origin, including pivots outside the visible image, so neither bbox trimming
nor per-frame anchor normalization is allowed here.
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
GAME = ROOT / 'homeing-star-game'
OUT = ROOT / 'homeing-star-test/artifacts/master_painted_vfx/reference'
ATLAS = GAME / 'assets/generated/combat_vfx/master/heavy_skills'


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source = json.loads((ATLAS / 'manifest.json').read_text(encoding='utf-8'))
    shutil.copy2(ATLAS / 'manifest.json', OUT / 'source_manifest.json')
    metadata = {'invariants': ['native pixel size', 'no per-frame crop or centering',
                              'original per-clip pivot', 'original order and times'],
                'clips': {}, 'boards': {}}
    by_move = {}
    for name, spec in source['clips'].items():
        if not (('/cut_' in name and name.endswith('_left')) or name in {
                'air_qi_combo/takeoff_halo', 'air_qi_combo/landing_gold', 'air_qi_combo/release_glint'}):
            continue
        move, cut = name.split('/')
        width, height = spec['cell']
        frames = []
        source_slots = []
        for index in range(spec['frames']):
            page_index = index // spec['capacity']
            page_frame = index % spec['capacity']
            x = (page_frame % spec['columns']) * width
            y = (page_frame // spec['columns']) * height
            page = Image.open(ATLAS / spec['pages'][page_index]).convert('RGBA')
            frames.append(page.crop((x, y, x + width, y + height)))
            source_slots.append({'page': spec['pages'][page_index], 'rect': [x, y, width, height]})
        clip = {'name': name, 'spec': spec, 'frames': frames, 'source_slots': source_slots}
        if '/cut_' in name:
            by_move.setdefault(move, []).append(clip)
        # Eight timeline slots, 4 columns x 2 rows, rendered 1:1 with fixed margins.
        rows = (len(frames) + 3) // 4
        canvas = Image.new('RGBA', (1536, 512 * max(2, rows)))
        slot_w, slot_h = 384, 512
        # One fixed transparent source canvas per clip, never frame-specific.
        source_side = max(320, width, height)
        scale = min(1.0, 352 / source_side, 480 / source_side)
        source_left = (source_side - width) // 2
        source_top = (source_side - height) // 2
        target_side = round(source_side * scale)
        left, top = (slot_w - target_side) // 2, (slot_h - target_side) // 2
        slots = []
        for index, frame in enumerate(frames):
            x = left + index % 4 * slot_w
            y = top + index // 4 * slot_h
            source_canvas = Image.new('RGBA', (source_side, source_side))
            source_canvas.alpha_composite(frame, (source_left, source_top))
            canvas.alpha_composite(source_canvas.resize((target_side, target_side), Image.Resampling.NEAREST), (x, y))
            fx, fy = x + source_left * scale, y + source_top * scale
            slots.append({'index': index, 'time': spec['times'][index],
                          'rect': [fx, fy, width * scale, height * scale],
                          'source_canvas_rect': [x, y, target_side, target_side],
                          'pivot': [fx + spec['pivot'][0] * scale, fy + spec['pivot'][1] * scale],
                          'empty': frame.getbbox() is None,
                          'alpha_bbox': frame.getbbox(), 'source': source_slots[index]})
        filename = f'{move}_{cut}_edit.png'
        canvas.save(OUT / filename)
        metadata['clips'][name] = {'canvas': filename, 'canvas_size': list(canvas.size),
                                  'layout': f'4 columns x {max(2, rows)} rows; left to right, top to bottom',
                                  'slot_size': [slot_w, slot_h], 'slots': slots,
                                  'source_canvas_size': [source_side, source_side],
                                  'source_canvas_frame_offset': [source_left, source_top],
                                  'scale': scale, 'unused_slots': list(range(len(frames), max(2, rows) * 4)),
                                  'original': spec}
    for move, clips in by_move.items():
        clips.sort(key=lambda item: item['name'])
        board = Image.new('RGBA', (1536, 1536))
        row_heights = [(max(c['spec']['cell'][1] + 24, 128) * 2) for c in clips]
        top = (1536 - sum(row_heights) - 32 * (len(clips) - 1)) // 2
        board_slots = []
        for row, clip in enumerate(clips):
            spec = clip['spec']
            width, height = spec['cell']
            sw, sh = max(width + 24, 256), max(height + 24, 128)
            left = (1536 - sw * 4) // 2
            for index, frame in enumerate(clip['frames']):
                x = left + index % 4 * sw + 12
                y = top + index // 4 * sh + 12
                board.alpha_composite(frame, (x, y))
                board_slots.append({'clip': clip['name'], 'index': index,
                                    'rect': [x, y, width, height],
                                    'pivot': [x + spec['pivot'][0], y + spec['pivot'][1]]})
            top += row_heights[row] + 32
        filename = f'{move}_whole_animation.png'
        board.save(OUT / filename)
        metadata['boards'][move] = {'canvas': filename, 'canvas_size': [1536, 1536],
                                   'layout': 'each cut occupies two rows of four timeline slots',
                                   'slots': board_slots}
    # The actual painted source is effect-only, not a gameplay screenshot.
    style_source = GAME / 'assets/bosses/master/fx/wind/phase1_attack2_fx_750x384_25f.png'
    sheet = Image.open(style_source).convert('RGBA')
    style = Image.new('RGBA', (1536, 1024))
    style_slots = []
    # Per-sequence union crop is for style study only, never target normalization.
    for row, indices in enumerate(([8, 9, 10], [15, 16, 17])):
        group = [sheet.crop(((i % 5) * 750, (i // 5) * 384,
                             (i % 5 + 1) * 750, (i // 5 + 1) * 384)) for i in indices]
        boxes = [f.getbbox() for f in group if f.getbbox()]
        union = (min(b[0] for b in boxes), min(b[1] for b in boxes),
                 max(b[2] for b in boxes), max(b[3] for b in boxes))
        scale = min(1, 480 / (union[2] - union[0]), 460 / (union[3] - union[1]))
        for col, frame in enumerate(group):
            frame = frame.crop(union)
            if scale < 1:
                frame = frame.resize((round(frame.width * scale), round(frame.height * scale)), Image.Resampling.NEAREST)
            x, y = col * 512 + 16, row * 512 + 16
            style.alpha_composite(frame, (x, y))
            style_slots.append({'source_frame': indices[col], 'rect': [x, y, *frame.size],
                                'group_crop': union, 'shared_group_scale': scale})
    style.save(OUT / 'return_chain_painted_style.png')
    metadata['style'] = {'source': str(style_source), 'canvas': 'return_chain_painted_style.png',
                         'frames_zero_based': [8, 9, 10, 15, 16, 17], 'slots': style_slots,
                         'note': 'First two hits are painted source. Third flip_chop is baked procedural, not painted style seed.'}
    dump(OUT / 'frame_mapping.json', metadata)
    print(OUT)
    print('prepared', len(metadata['clips']), 'complete cut canvases and', len(metadata['boards']), 'whole-move boards')


if __name__ == '__main__':
    main()
