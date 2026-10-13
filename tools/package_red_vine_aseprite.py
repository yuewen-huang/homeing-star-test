"""Split the four supplied red-vine sheets without repainting or resampling.

Keep the original RGBA crops in a hidden reference and an independent editable
effect layer. Validate the documents with the installed native Aseprite.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import subprocess
import sys
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from package_deer_vfx_aseprite import chunk, string, user_data
from aseprite_rgba_reader import read, layer_frame

CANVAS = (104, 544)
PIVOT = (52, 40)
CONFIGS = [
    ('01_红藤', '像素红色藤蔓生长与消散序列 spritesheet.png',
     [31,84,136,189,244,299,355,407,462,519,575,631,685,738], 9),
    ('02_红藤', '像素红藤蔓生长与消散序列.png',
     [31,83,137,190,245,299,354,410,471,535,598,662,728], 9),
    ('03_红藤', '红色藤蔓生长消散像素动画序列.png',
     [28,76,123,174,223,272,324,379,435,492,551,615,672,733], 10),
    ('04_红藤', '红色藤蔓生长动画精灵表.png',
     [28,77,126,176,229,285,337,389,453,515,583,651,717], 9),
]


def write_document(path, frames, tags, source_name, duration):
    initial = []
    for name, flags in [('原图参考_隐藏锁定', 0), ('红藤特效_可编辑', 3)]:
        initial.append(chunk(0x2004, struct.pack('<6HB3x', flags, 0, 0, 0, 0, 0, 255) + string(name)))
        initial.append(user_data('原始 RGBA 切帧，未改颜色、透明度或比例。来源：' + source_name))
    data = struct.pack('<H8x', len(tags))
    for tag in tags:
        data += struct.pack('<HHB8x3BB', tag['from'], tag['to'], 0, 220, 70, 70, 0) + string(tag['name'])
    initial.append(chunk(0x2018, data))
    initial.append(chunk(0x2022, struct.pack('<III', 1, 2, 0) + string('vine_origin') +
                         struct.pack('<IiiIIii', 0, 0, 0, *CANVAS, *PIVOT)))
    blocks = []
    for index, frame in enumerate(frames):
        chunks = list(initial) if index == 0 else []
        for layer in range(2):
            # Full independent cels also preserve RGB beneath zero-alpha pixels.
            cel = struct.pack('<HhhBHh5xHH', layer, 0, 0, 255, 2, 0, *CANVAS)
            chunks.append(chunk(0x2005, cel + zlib.compress(frame.tobytes(), 9)))
        payload = b''.join(chunks)
        blocks.append(struct.pack('<IHHH2xI', len(payload)+16, 0xF1FA, len(chunks), duration, len(chunks)) + payload)
    header = bytearray(128)
    struct.pack_into('<I5HIH', header, 0, 128 + sum(map(len, blocks)), 0xA5E0,
                     len(frames), *CANVAS, 32, 1, duration)
    header[34:36] = bytes((1, 1))
    struct.pack_into('<HH', header, 40, 16, 16)
    path.write_bytes(bytes(header) + b''.join(blocks))


def split(source, roots):
    image = Image.open(source).convert('RGBA')
    pixels = np.asarray(image)
    # Find paths through transparent gaps rather than cutting curved leaves on
    # a rigid grid. Every source pixel belongs to exactly one frame region.
    boundaries = [np.zeros(image.height, dtype=int)]
    for a, b in zip(roots, roots[1:]):
        lo, hi = a+12, b-12
        xs = np.arange(lo, hi+1)
        alpha = pixels[:, xs, 3].astype(float)
        cost = (np.maximum(alpha-4, 0)**2) + abs(xs-(a+b)/2)*0.015
        scores = cost[0].copy()
        parents = []
        for y in range(1, image.height):
            options = np.stack((np.r_[np.inf,scores[:-1]]+0.05,
                                scores, np.r_[scores[1:],np.inf]+0.05))
            choices = options.argmin(axis=0)
            parents.append(np.arange(len(xs)) + choices-1)
            scores = cost[y] + options.min(axis=0)
        seam = np.empty(image.height, dtype=int)
        index = int(scores.argmin())
        for y in range(image.height-1, -1, -1):
            seam[y] = xs[index]
            if y:
                index = int(parents[y-1][index])
        boundaries.append(seam)
    boundaries.append(np.full(image.height, image.width, dtype=int))
    frames, records = [], []
    for i, root in enumerate(roots):
        # Top of the hanging attachment, ignoring faint alpha noise.
        occupied = (pixels[:80, root-4:root+5, 3] > 200).any(axis=1)
        root_y = int(np.flatnonzero(occupied)[0])
        left_rows, right_rows = boundaries[i:i+2]
        left, right = int(left_rows.min()), int(right_rows.max())
        dx, dy = PIVOT[0]-root, PIVOT[1]-root_y
        frame = Image.new('RGBA', CANVAS)
        assert left+dx >= 0 and right+dx <= CANVAS[0]
        assert dy >= 0 and image.height+dy <= CANVAS[1]
        canvas = np.asarray(frame).copy()
        for y, (l, r) in enumerate(zip(left_rows, right_rows)):
            canvas[y+dy, l+dx:r+dx] = pixels[y,l:r]
            assert np.array_equal(canvas[y+dy,l+dx:r+dx], pixels[y,l:r])
        frame = Image.fromarray(canvas)
        frames.append(frame)
        records.append({'frame': i, 'source_rect': [left, 0, right-left, image.height],
                        'source_root': [root, root_y], 'canvas_offset': [left+dx, dy],
                        'source_row_spans': np.stack((left_rows,right_rows),axis=1).tolist()})
    return frames, records


def background(size):
    image = Image.new('RGBA', size, (160, 164, 171, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], 12):
        for x in range(0, size[0], 12):
            if (x//12+y//12)%2 == 0:
                draw.rectangle((x,y,x+11,y+11), fill=(195,199,205,255))
    return image


def verify(path, frames, tags, duration, native_dir, aseprite):
    doc = read(path)
    assert doc['canvas'] == CANVAS and len(doc['frames']) == len(frames)
    assert len(doc['layers']) == 2 and not doc['layers'][0]['visible'] and doc['layers'][1]['visible']
    for i, frame in enumerate(frames):
        for layer in range(2):
            actual, opacity = layer_frame(doc, i, layer)
            assert opacity == 1 and actual.tobytes() == frame.tobytes()
    data, sheet = native_dir/(path.stem+'.json'), native_dir/(path.stem+'.png')
    data.unlink(missing_ok=True)
    sheet.unlink(missing_ok=True)
    result = subprocess.run([str(aseprite), '-b', '--list-layers', '--list-tags', '--list-slices', str(path),
                    '--format', 'json-array', '--data', str(data), '--sheet', str(sheet),
                    '--sheet-type', 'horizontal'], capture_output=True,
                   creationflags=subprocess.CREATE_NO_WINDOW, timeout=45)
    # This installed build also crashes on --version and on known-good documents
    # after producing complete exports. Retain that limitation in the report;
    # validation below still requires every freshly exported frame to be exact.
    if result.returncode not in (0, 0xC0000409):
        raise RuntimeError(f'Aseprite failed: {result.returncode}: {result.stderr!r}')
    meta = json.loads(data.read_text(encoding='utf-8'))
    assert len(meta['frames']) == len(frames)
    assert [t['name'] for t in meta['meta']['frameTags']] == [t['name'] for t in tags]
    assert meta['meta']['slices'][0]['keys'][0]['pivot'] == dict(zip(('x','y'), PIVOT))
    exported = Image.open(sheet).convert('RGBA')
    for i, record in enumerate(meta['frames']):
        assert record['duration'] == duration
        r = record['frame']
        actual = np.asarray(exported.crop((r['x'],r['y'],r['x']+r['w'],r['y']+r['h'])))
        expected = np.asarray(frames[i])
        assert np.array_equal(actual[:,:,3], expected[:,:,3]), (path.name, i, 'alpha')
        visible = expected[:,:,3] > 0
        assert np.array_equal(actual[:,:,:3][visible], expected[:,:,:3][visible]), (path.name, i, 'RGB')
    return {'file': path.name, 'frames': len(frames), 'two_layers': True,
            'source_rgba_exact_in_both_layers': True, 'native_visible_pixels_and_alpha_exact': True,
            'duration_ms': duration, 'pivot': list(PIVOT), 'native_aseprite': str(aseprite),
            'native_process_exit_code': result.returncode,
            'native_process_note': '导出完整且逐帧一致；本机版本在导出后异常退出（--version 与既有工程亦如此）。' if result.returncode else '正常退出'}


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--duration', type=int, default=100)
    parser.add_argument('--aseprite', type=Path, default=Path('E:/Aseprite/Aseprite.exe'))
    args = parser.parse_args()
    out = args.output or args.source/'Aseprite_20261013'
    preview = out/'预览'
    native = out/'校验'
    for directory in (out, preview, native):
        directory.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 18)
    overview = Image.new('RGB', (CANVAS[0]*14, (CANVAS[1]+32)*4), (28,31,36))
    overview_draw = ImageDraw.Draw(overview)
    manifest = {'canvas': list(CANVAS), 'pivot': list(PIVOT), 'timing': 'PNG 无原始时长；检查暂用每帧 100ms。', 'clips': []}
    reports = []
    for row, (name, filename, roots, last_growth) in enumerate(CONFIGS):
        frames, mapping = split(args.source/filename, roots)
        tags = [{'name': '全序列', 'from': 0, 'to': len(frames)-1},
                {'name': '生长', 'from': 0, 'to': last_growth},
                {'name': '消散', 'from': last_growth+1, 'to': len(frames)-1}]
        path = out/(name+'.aseprite')
        if path.exists():
            raise FileExistsError(f'Refuse to overwrite an artist document: {path}')
        write_document(path, frames, tags, filename, args.duration)
        sequence = out/'序列帧'/name
        sequence.mkdir(parents=True, exist_ok=True)
        animation = []
        for i, frame in enumerate(frames):
            frame.save(sequence/f'{i:02d}.png')
            bg = background(CANVAS)
            bg.alpha_composite(frame)
            animation.append(bg.convert('RGB'))
            y = row*(CANVAS[1]+32)
            overview.paste(bg.convert('RGB'), (i*CANVAS[0],y+32))
            overview_draw.text((i*CANVAS[0]+4,y+6), f'{row+1:02d} / F{i:02d}', font=font, fill='white')
        animation[0].save(preview/(name+'.gif'), save_all=True, append_images=animation[1:],
                          duration=args.duration, loop=0, disposal=2)
        animation[0].save(preview/(name+'_慢放.gif'), save_all=True, append_images=animation[1:],
                          duration=args.duration*3, loop=0, disposal=2)
        reports.append(verify(path, frames, tags, args.duration, native, args.aseprite))
        manifest['clips'].append({'file': path.name, 'source': filename,
                                  'source_sha256': hashlib.sha256((args.source/filename).read_bytes()).hexdigest(),
                                  'frames': len(frames), 'duration_ms_per_frame': args.duration,
                                  'tags': tags, 'mapping': mapping})
        print('PASS', path.name, len(frames), 'frames: native Aseprite, pixels, alpha, timing, pivot')
    overview.save(preview/'全部帧总览.png')
    (out/'时间轴.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    (out/'Aseprite校验.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding='utf-8')
    table = '\n'.join(f"| {c['file']} | {c['frames']} | {c['source']} |" for c in manifest['clips'])
    (out/'检查说明.md').write_text('''# 红藤序列 Aseprite 检查稿

用途：候选 BOSS 第四阶段「落幕」特效。**等待用户检查通过后接入游戏。**

| 工程 | 帧数 | 原图 |
| --- | ---: | --- |
''' + table + '''

- 从左到右拆帧，共 54 帧；没有补画、删帧、改色或缩放。每份工程独立。
- 两层：`原图参考_隐藏锁定`（原始切帧备份）和 `红藤特效_可编辑`（默认显示）。修改特效层即可，各帧没有链接。
- 原图已有透明通道；透明像素内的红黑背景 RGB 和少量弱透明边缘保留原样。预览棋盘格不属于工程。
- 统一透明画布 104×544，悬挂点 `vine_origin` pivot=(52,40)。逐帧仅整数平移，将顶部悬挂点对齐；生长长度、叶片和比例保持原图。
- 每帧暂定 100ms（10 FPS）。PNG 没有原始时间信息，后续技能时序以确认后的稿件为准。`生长` / `消散` 标签仅便于检查。
- 原图少数最长帧已经触及图片下边缘，保持原样，没有补绘缺失部分。
- `预览/` 有正常速度、三倍慢放 GIF 和全部帧总览；`序列帧/` 为透明切帧。
- 已用本机 Aseprite 批量打开并导出全部帧，核对颜色、透明度、帧时长、标签和枢轴；`Aseprite校验.json` 记录结果。
- 本机 Aseprite 1.2.15 在完成导出后异常退出（--version 与既有工程也有同样问题）；全部新导出帧仍已逐像素核对。此环境问题记录在校验报告中。
- 只修改待定素材与测试仓库中的转换工具，尚未导入游戏。原 PNG 未修改。
''', encoding='utf-8')


if __name__ == '__main__':
    main()
