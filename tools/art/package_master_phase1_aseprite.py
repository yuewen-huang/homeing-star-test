"""Join the current production master's full phase-one actions into editable files."""
from pathlib import Path
import hashlib
import json
import re
import struct
import subprocess
import sys
import zlib

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from aseprite_rgba_reader import read, layer_frame
from package_deer_vfx_aseprite import chunk, string

ROOT = Path(__file__).resolve().parents[3]
GAME = ROOT / 'homeing-star-game'
ART = GAME / 'assets/bosses/master/body/boss/phase1'
LABELS = ['待机', '行走起步', '行走循环', '喝酒', '虚弱', '攻击一', '攻击二',
          '旋风连击', '瞬移', '特殊攻击', '起跳空中旋斩下劈', '叠势单斩']


def write_document(path, images, durations, action):
    width, height = images[0].size
    initial = [chunk(0x2004, struct.pack('<6HB3x', 3, 0, 0, 0, 0, 0, 255) + string('角色'))]
    initial.append(chunk(0x2018, struct.pack('<H8x', 1) +
                         struct.pack('<HHB8x3BB', 0, len(images)-1, 0, 120, 180, 210, 0) + string(action)))
    blocks = []
    for index, (image, duration) in enumerate(zip(images, durations)):
        chunks = initial.copy() if index == 0 else []
        # Independent editable cels; keep the full canvas including transparent pixels.
        cel = struct.pack('<HhhBHh5xHH', 0, 0, 0, 255, 2, 0, width, height)
        chunks.append(chunk(0x2005, cel + zlib.compress(image.tobytes(), 6)))
        payload = b''.join(chunks)
        blocks.append(struct.pack('<IHHH2xI', len(payload)+16, 0xF1FA, len(chunks), duration, len(chunks)) + payload)
    header = bytearray(128)
    struct.pack_into('<I5HIH', header, 0, 128+sum(map(len, blocks)), 0xA5E0,
                     len(images), width, height, 32, 1, durations[0])
    header[34:36] = bytes((1, 1))
    struct.pack_into('<HH', header, 40, 16, 16)
    path.write_bytes(bytes(header) + b''.join(blocks))


def main():
    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    audit = ROOT / '.artifacts/master-phase1-aseprite-package'
    audit.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((ART / 'manifest.json').read_text(encoding='utf-8'))
    source = (ART / 'frames.tres').read_text(encoding='utf-8')
    ext = dict((ident, GAME / path.removeprefix('res://')) for path, ident in
               re.findall(r'\[ext_resource[^\n]*path="([^"]+)" id="([^"]+)"\]', source))
    regions = {}
    for ident, atlas, coords in re.findall(
            r'\[sub_resource type="AtlasTexture" id="([^"]+)"\]\s*atlas = ExtResource\("([^"]+)"\)\s*region = Rect2\(([^)]+)\)', source):
        regions[ident] = (ext[atlas], tuple(int(float(n)) for n in coords.split(',')))
    animations = {}
    for frames, loop, name, speed in re.findall(
            r'"frames": \[(.*?)\],\s*"loop": (true|false|0|1),\s*"name": &"([^"]+)",\s*"speed": ([\d.]+)', source, re.S):
        entries = re.findall(r'"duration": ([\d.]+),\s*"texture": SubResource\("([^"]+)"\)', frames)
        animations[name] = (entries, float(speed), loop in ('true', '1'))
    report = []
    for index, ((action, spec), label) in enumerate(zip(manifest['actions'].items(), LABELS), 1):
        path = output / f'{index:02d}_{label}_{action}.aseprite'
        if path.exists():
            raise FileExistsError(f'Refusing to replace an existing editable file: {path}')
        entries, speed, loop = animations[action]
        images, durations = [], []
        for duration, ident in entries:
            atlas, (x, y, width, height) = regions[ident]
            with Image.open(atlas) as sheet:
                images.append(sheet.convert('RGBA').crop((x, y, x+width, y+height)))
            durations.append(round(float(duration) / speed * 1000))
        assert len(images) == spec['frame_count'], action
        assert list(images[0].size) == spec['frame_size'], action
        assert durations == spec['durations_ms'], action
        write_document(path, images, durations, action)
        document = read(path)
        assert len(document['frames']) == len(images)
        for n, image in enumerate(images):
            rendered, opacity = layer_frame(document, n, 0)
            assert opacity == 1 and rendered.tobytes() == image.tobytes(), (action, n)
            assert document['frames'][n]['duration_ms'] == durations[n]
        # Verify that the installed Aseprite can open and render every delivered frame.
        png, metadata = audit / f'{action}.png', audit / f'{action}.json'
        png.unlink(missing_ok=True)
        metadata.unlink(missing_ok=True)
        process = subprocess.run(['D:/Aseprite/Aseprite.exe', '-b', str(path),
                                  '--format', 'json-array', '--data', str(metadata),
                                  '--sheet', str(png), '--sheet-type', 'horizontal'],
                                 capture_output=True, timeout=45, creationflags=subprocess.CREATE_NO_WINDOW)
        if not png.exists() or not metadata.exists():
            raise RuntimeError(process.stderr.decode(errors='replace'))
        exported = json.loads(metadata.read_text(encoding='utf-8'))
        assert len(exported['frames']) == len(images), action
        with Image.open(png) as sheet:
            sheet = sheet.convert('RGBA')
            for n, frame in enumerate(exported['frames']):
                r = frame['frame']
                actual = sheet.crop((r['x'], r['y'], r['x']+r['w'], r['y']+r['h']))
                assert actual.tobytes() == images[n].tobytes(), (action, n, 'native pixels')
                assert frame['duration'] == durations[n], (action, n, 'native timing')
        report.append(dict(action=action, label=label, file=path.name, canvas=spec['frame_size'],
                           frames=len(images), durations_ms=durations, loop=loop,
                           sha256=hashlib.sha256(path.read_bytes()).hexdigest(), verified=True))
        print(f'VERIFIED {path.name}: {len(images)} frames, {images[0].size}', flush=True)
    (output / '动作清单.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    lines = ['# 师傅一阶段动作工程', '',
             '每个文件是一套完整基础动作，START → ING → END 已按正式资源的源帧顺序合并为连续时间轴。',
             '保留正式资源画布、透明像素与逐帧时长，不缩放、不裁边、不增删帧。每份只有一个可编辑的“角色”层，帧互相独立。',
             '原来的 8 个子动作均包含在对应完整动作中，见下方帧范围（Aseprite 从第 1 帧计数）。',
             '这是角色原画动作集合；运行时动态刀光、残影与招式组合不烘焙到角色层。', '',
             '| 文件 | 帧数 | 画布 |', '| --- | ---: | --- |']
    lines.extend(f"| {r['file']} | {r['frames']} | {r['canvas'][0]}×{r['canvas'][1]} |" for r in report)
    lines.extend(['', '## 已包含的子动作', ''])
    for sub, spec in manifest['submoves'].items():
        ranges = list(spec['parts'].values())
        lines.append(f"- {spec['label']}（{sub}）：{spec['source']} 第 {ranges[0][0]+1}–{ranges[-1][1]+1} 帧。")
    lines.extend(['', '全部文件已用本机 Aseprite 批处理重新打开并导出，逐帧像素、帧数和时长与正式 SpriteFrames 资源核对通过。', ''])
    (output / '说明.md').write_text('\n'.join(lines), encoding='utf-8')
    print(f'TOTAL: {len(report)} actions, {sum(r["frames"] for r in report)} frames')


if __name__ == '__main__':
    main()
