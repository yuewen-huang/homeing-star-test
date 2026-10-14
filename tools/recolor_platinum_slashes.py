"""Recolor native RGBA slash cels while preserving every structural chunk.

No generated art, resizing, alpha changes, flattened layers or source overwrites.
Exports and verifies every frame with the installed native Aseprite renderer.
"""
from pathlib import Path
import argparse
import colorsys
from functools import lru_cache
import hashlib
import json
import struct
import subprocess
import zlib

from PIL import Image, ImageDraw, ImageFont, ImageChops
from aseprite_rgba_reader import read

VARIANTS = {
    "1_红白": (0.0, 1.1, 0.0),
    "2_蓝白": (212 / 360, 1.1, 0.0),
    "3_橄榄绿白": (65 / 360, 1.0, 0.48),
    "4_黑白": None,
}


@lru_cache(maxsize=None)
def recolor_rgb(rgb, variant):
    _, saturation, value = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))
    # Neutralize the original cream tint in white highlights, then preserve
    # the continuous painted gold ramp as a continuous new color ramp.
    strength = max(0.0, (saturation - 0.08) / 0.92)
    tuning = VARIANTS[variant]
    if tuning is None:
        grey = round(255 * value * (1 - strength) ** 1.8)
        return (grey, grey, grey)
    hue, gain, darken = tuning
    rgb_out = colorsys.hsv_to_rgb(hue, min(1.0, strength * gain), value * (1 - darken * strength))
    return tuple(round(255 * c) for c in rgb_out)


def recolor_pixels(pixels, variant):
    result = bytearray(pixels)
    for offset in range(0, len(pixels), 4):
        if pixels[offset + 3] == 0:
            continue
        rgb = tuple(pixels[offset:offset + 3])
        result[offset:offset + 3] = bytes(recolor_rgb(rgb, variant))
    assert result[3::4] == pixels[3::4]
    return bytes(result)


def chunks(raw):
    assert struct.unpack_from('<I', raw)[0] == len(raw)
    assert struct.unpack_from('<H', raw, 4)[0] == 0xA5E0
    assert struct.unpack_from('<H', raw, 12)[0] == 32
    position = 128
    result = []
    for _ in range(struct.unpack_from('<H', raw, 6)[0]):
        size, magic, short_count = struct.unpack_from('<IHH', raw, position)
        assert magic == 0xF1FA
        count = struct.unpack_from('<I', raw, position + 12)[0] or short_count
        cursor = position + 16
        frame_chunks = []
        for _ in range(count):
            length, kind = struct.unpack_from('<IH', raw, cursor)
            frame_chunks.append((kind, raw[cursor + 6:cursor + length]))
            cursor += length
        assert cursor == position + size
        result.append((raw[position:position + 16], frame_chunks))
        position += size
    assert position == len(raw)
    return result


def transform(raw, variant, editable):
    blocks = []
    for frame_header, frame_chunks in chunks(raw):
        packed_chunks = []
        for kind, body in frame_chunks:
            if kind == 0x2005 and struct.unpack_from('<H', body)[0] in editable:
                cel_type = struct.unpack_from('<H', body, 7)[0]
                if cel_type in (0, 2):
                    width, height = struct.unpack_from('<HH', body, 16)
                    pixels = zlib.decompress(body[20:]) if cel_type == 2 else body[20:]
                    assert len(pixels) == width * height * 4
                    changed = recolor_pixels(pixels, variant)
                    body = body[:20] + (zlib.compress(changed, 9) if cel_type == 2 else changed)
                else:
                    assert cel_type == 1, 'Tilemap cels are unsupported'
            packed_chunks.append(struct.pack('<IH', len(body) + 6, kind) + body)
        content = b''.join(packed_chunks)
        header = bytearray(frame_header)
        struct.pack_into('<I', header, 0, len(content) + 16)
        blocks.append(bytes(header) + content)
    content = b''.join(blocks)
    header = bytearray(raw[:128])
    struct.pack_into('<I', header, 0, 128 + len(content))
    result = bytes(header) + content
    verify_structure(raw, result, variant, editable)
    return result


def verify_structure(source, output, variant, editable):
    assert source[4:128] == output[4:128], 'Canvas and document metadata changed'
    for (sh, sc), (oh, oc) in zip(chunks(source), chunks(output)):
        assert sh[4:] == oh[4:], 'Frame timing or chunk counts changed'
        assert len(sc) == len(oc)
        for (sk, sb), (ok, ob) in zip(sc, oc):
            assert sk == ok
            if sk != 0x2005 or struct.unpack_from('<H', sb)[0] not in editable:
                assert sb == ob, 'Non-art chunk or hidden guide changed'
                continue
            cel_type = struct.unpack_from('<H', sb, 7)[0]
            if cel_type not in (0, 2):
                assert sb == ob
                continue
            assert sb[:20] == ob[:20], 'Cel placement, opacity or size changed'
            before = zlib.decompress(sb[20:]) if cel_type == 2 else sb[20:]
            after = zlib.decompress(ob[20:]) if cel_type == 2 else ob[20:]
            assert after == recolor_pixels(before, variant)


def composite(document, frame):
    canvas = Image.new('RGBA', document['canvas'])
    for index, layer in enumerate(document['layers']):
        if not layer['visible']:
            continue
        cel = document['frames'][frame]['cels'].get(index)
        if cel is None:
            continue
        pixels = cel['image'].copy()
        opacity = layer['opacity'] / 255 * cel['opacity'] / 255
        if opacity != 1:
            pixels.putalpha(pixels.getchannel('A').point(lambda a: round(a * opacity)))
        at = Image.new('RGBA', document['canvas'])
        at.paste(pixels, cel['position'])
        canvas = Image.alpha_composite(canvas, at)
    return canvas


def checker(size, light=False):
    image = Image.new('RGBA', size)
    draw = ImageDraw.Draw(image)
    colors = [(232, 234, 237), (209, 213, 219)] if light else [(24, 32, 42), (33, 43, 56)]
    for y in range(0, size[1], 8):
        for x in range(0, size[0], 8):
            draw.rectangle((x, y, x + 7, y + 7), fill=colors[(x // 8 + y // 8) % 2])
    return image


def font(size):
    return ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', size)


def native_export(exe, path, sheet, metadata):
    run = subprocess.run([str(exe), '-b', '--list-layers', '--list-tags', str(path),
                          '--format', 'json-array', '--data', str(metadata),
                          '--sheet', str(sheet), '--sheet-type', 'horizontal'],
                         capture_output=True, timeout=45,
                         creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    if run.returncode:
        raise RuntimeError(run.stderr.decode('utf-8', errors='replace'))
    native = json.loads(metadata.read_text(encoding='utf-8'))
    atlas = Image.open(sheet).convert('RGBA')
    result = []
    for frame in native['frames']:
        box = frame['frame']
        cropped = atlas.crop((box['x'], box['y'], box['x'] + box['w'], box['y'] + box['h']))
        full = Image.new('RGBA', (frame['sourceSize']['w'], frame['sourceSize']['h']))
        at = frame['spriteSourceSize']
        full.paste(cropped, (at['x'], at['y']))
        result.append(full)
    return result, native


def save_gif(frames, durations, path, scale=3, light=False):
    backgrounds = []
    for frame in frames:
        background = checker(frame.size, light)
        background.alpha_composite(frame)
        backgrounds.append(background.convert('RGB').resize((frame.width * scale, frame.height * scale), Image.Resampling.NEAREST))
    # Loop pause is preview-only; native frame durations remain unchanged.
    backgrounds.append(checker(frames[0].size, light).convert('RGB').resize(backgrounds[0].size, Image.Resampling.NEAREST))
    backgrounds[0].save(path, save_all=True, append_images=backgrounds[1:], duration=durations + [220], loop=0, disposal=2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--aseprite', type=Path, default=Path('E:/Aseprite/Aseprite.exe'))
    args = parser.parse_args()
    sources = sorted(args.source.glob('*.aseprite'))
    assert len(sources) == 18, 'Expected all 18 approved slash animations'
    assert args.output.resolve() != args.source.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    documents = {p.name: read(p) for p in sources}
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    report, palettes, previews = [], {}, {}
    for variant in VARIANTS:
        directory = args.output / variant
        preview_dir = directory / '预览'
        verify_dir = directory / '校验'
        preview_dir.mkdir(parents=True, exist_ok=True)
        verify_dir.mkdir(parents=True, exist_ok=True)
        all_frames = {}
        timeline = []
        for source in sources:
            original = documents[source.name]
            editable = {i for i, layer in enumerate(original['layers']) if layer['visible']}
            target = directory / source.name
            target.write_bytes(transform(source.read_bytes(), variant, editable))
            document = read(target)
            assert document['layers'] == original['layers']
            assert document['canvas'] == original['canvas'] == (128, 128)
            durations = [f['duration_ms'] for f in document['frames']]
            assert durations == [f['duration_ms'] for f in original['frames']]
            sheet_path = preview_dir / (source.stem + '-图集.png')
            frames, native = native_export(args.aseprite, target, sheet_path, verify_dir / (source.stem + '.json'))
            assert len(frames) == len(original['frames']) == 6
            maxima = []
            for index, actual in enumerate(frames):
                expected = composite(document, index)
                diff = ImageChops.difference(actual.convert('RGBa'), expected.convert('RGBa'))
                maximum = max(high for low, high in diff.getextrema())
                assert maximum == 0, (target.name, index, maximum)
                assert actual.getchannel('A').tobytes() == composite(original, index).getchannel('A').tobytes()
                assert native['frames'][index]['duration'] == durations[index]
                maxima.append(maximum)
            save_gif(frames, durations, preview_dir / (source.stem + '.gif'), light=variant == '4_黑白')
            all_frames[source.name] = frames
            timeline.append({'file': source.name, 'frames': 6, 'canvas': [128, 128], 'timings_ms': durations,
                             'layers': original['layers'], 'native_aseprite_verified': True, 'max_pixel_difference': max(maxima)})
            report.append({'variant': variant, 'source': source.name, 'source_sha256': hashes[source.name],
                           'output_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                           'frames_verified': 6, 'all_alpha_unchanged': True, 'non_art_chunks_byte_identical': True,
                           'native_pixel_difference': max(maxima)})
        (directory / '时间轴.json').write_text(json.dumps(timeline, ensure_ascii=False, indent=2), encoding='utf-8')
        # All 18 motions in each color, with both dark/light backgrounds for black.
        overview = Image.new('RGBA', (6 * 196 + 24, 3 * 220 + 80), (15, 22, 32))
        draw = ImageDraw.Draw(overview)
        draw.text((22, 18), variant.replace('_', ' · ') + '  |  6 方向 × 3 变体', font=font(24), fill='white')
        for column in range(6):
            for row in range(3):
                source = sources[column * 3 + row]
                peak = max(all_frames[source.name], key=lambda f: sum(f.getchannel('A').get_flattened_data()))
                tile = checker((128, 128), variant == '4_黑白')
                tile.alpha_composite(peak)
                tile = tile.resize((176, 176), Image.Resampling.NEAREST)
                x, y = 22 + column * 196, 68 + row * 220
                overview.alpha_composite(tile, (x, y))
                draw.text((x, y + 182), source.stem[:4] + ' ' + ['薄刃', '宽弧', '多刃'][row], font=font(16), fill='#d2d9e3')
        overview.convert('RGB').save(preview_dir / '总览.png')
        previews[variant] = all_frames
        palettes[variant] = {'hsv_tuning': VARIANTS[variant], 'white_cutoff_saturation': 0.08}
        print(f'VERIFIED {variant}: 18 files, 108 frames', flush=True)

    # Compact side-by-side color comparison, three representative styles.
    samples = sources[:3]
    comparison = Image.new('RGBA', (1060, 4 * 306 + 100), (15, 22, 32))
    draw = ImageDraw.Draw(comparison)
    draw.text((24, 18), '白金斩击 · 脚本换色', font=font(28), fill='white')
    draw.text((190, 63), 'A 薄刃快斩               B 宽弧重斩               C 碎风多刃', font=font(20), fill='#bcc8d7')
    for row, variant in enumerate(VARIANTS):
        y = 100 + row * 306
        draw.text((24, y + 105), variant.replace('_', '\n'), font=font(23), fill='white', spacing=10)
        for column, source in enumerate(samples):
            frames = previews[variant][source.name]
            peak_index = max(range(6), key=lambda i: sum(frames[i].getchannel('A').get_flattened_data()))
            tile = checker((128, 128), variant == '4_黑白')
            tile.alpha_composite(frames[peak_index])
            comparison.alpha_composite(tile.resize((256, 256), Image.Resampling.NEAREST), (172 + column * 294, y))
    comparison.convert('RGB').save(args.output / '四种配色对比.png')
    # Exact common source timing for a four-color animated B comparison.
    source = samples[1]
    durations = [f['duration_ms'] for f in documents[source.name]['frames']]
    animated = []
    for index in range(6):
        frame = Image.new('RGB', (1024, 300), (15, 22, 32))
        draw = ImageDraw.Draw(frame)
        for column, variant in enumerate(VARIANTS):
            tile = checker((128, 128), variant == '4_黑白')
            tile.alpha_composite(previews[variant][source.name][index])
            frame.paste(tile.convert('RGB').resize((256, 256), Image.Resampling.NEAREST), (column * 256, 40))
            draw.text((column * 256 + 14, 8), variant.replace('_', ' · '), font=font(22), fill='white')
        animated.append(frame)
    animated[0].save(args.output / '四种配色动画对比.gif', save_all=True, append_images=animated[1:],
                     duration=durations, loop=0, disposal=2)
    assert hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}, 'Source modified'
    (args.output / '校验结果.json').write_text(json.dumps({'files': 72, 'frames': 432, 'palettes': palettes,
        'source_unchanged': True, 'results': report}, ensure_ascii=False, indent=2), encoding='utf-8')
    (args.output / '先看这里.md').write_text(
        '# 白金斩击四套变色\n\n'
        '用 Python 脚本替换原金色，保留白色核心：1 红白、2 蓝白、3 橄榄绿白、4 黑白。\n\n'
        '每套 18 个原生 Aseprite 动画，每个 6 帧，共 72 文件 / 432 帧。128×128 画布、'
        '像素位置、Alpha、独立 cel、图层名称/可见性/透明度、定位点、标签和帧时长均保留。'
        '没有新增图层。原白金文件未修改。\n\n'
        '每套预览目录有全部动画 GIF、透明横向图集和 18 动作总览；黑白预览用浅色棋盘方便看黑色轮廓。'
        '根目录提供四配色静态/动画对比。GIF 调色板仅用于预览，原生 Aseprite 与 PNG 保留完整 RGBA。\n\n'
        '本机 E:/Aseprite/Aseprite.exe 已批量打开全部 72 文件并导出；432 帧与脚本预期逐像素一致，'
        '所有 Alpha 与原动画一致。校验结果.json 保存源/输出 SHA256 与核验结果。\n\n'
        '换色脚本位于 homeing-star-test/tools/recolor_platinum_slashes.py。\n', encoding='utf-8')
    print(f'COMPLETE: {args.output}', flush=True)


if __name__ == '__main__':
    main()
