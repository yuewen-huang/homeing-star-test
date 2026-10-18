"""Inventory local audio without moving assets; build a searchable local audition page."""
from pathlib import Path
from collections import Counter, defaultdict
import argparse, csv, hashlib, html, json, mimetypes, re, struct
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

WORKSPACE = Path(__file__).resolve().parents[2]
GAME = WORKSPACE / 'homeing-star-game'
OUT = WORKSPACE / 'homeing-star-test' / 'audio-preview'
LIBRARY = Path('D:/音效包')
SKIP = {'.git', '.godot', 'node_modules', '__pycache__', 'tools_deps'}
MANUAL = {'主角起跳': ['player_jump'], '主角二段跳': ['player_double_jump'],
          '森林奔跑': ['forest_run_01', 'forest_run_02'], '森林跳跃落地': ['forest_land'],
          '鹿冲刺预警': ['deer_charge_warning'], '鹿奔跑': ['deer_run'],
          '鹿鸣-近': ['deer_call_near'], '鹿鸣-远': ['deer_call_far']}

def metadata(path):
    result = {'duration': None, 'rate': None, 'channels': None, 'bits': None}
    if path.suffix.lower() != '.wav': return result
    try:
        with path.open('rb') as f:
            header = f.read(12)
            if header[:4] != b'RIFF' or header[8:] != b'WAVE': return result
            byte_rate = data_bytes = None
            while chunk := f.read(8):
                if len(chunk) != 8: break
                kind, size = struct.unpack('<4sI', chunk)
                if kind == b'fmt ':
                    raw = f.read(min(size, 40))
                    if len(raw) >= 16:
                        _, channels, rate, byte_rate, _, bits = struct.unpack('<HHIIHH', raw[:16])
                        result.update(rate=rate, channels=channels, bits=bits)
                    f.seek(size-len(raw), 1)
                else:
                    if kind == b'data': data_bytes = size
                    f.seek(size, 1)
                if size % 2: f.seek(1, 1)
                if byte_rate and data_bytes is not None:
                    result['duration'] = round(data_bytes/byte_rate, 4)
                    break
    except (OSError, ValueError, struct.error): pass
    return result

def code_references():
    lines = []
    for folder in [GAME/'scripts', GAME/'scenes', GAME/'assets']:
        for path in folder.rglob('*'):
            if path.suffix not in {'.gd', '.tscn', '.tres'}: continue
            if path.name == 'mix_profile.gd': continue # Calibration inventory is not a playback reference.
            try:
                for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
                    if 'audio/' in line or '.wav' in line or '.res' in line or '.mp3' in line:
                        lines.append((path, number, line))
            except (UnicodeError, OSError): pass
    return lines

def references(path, lines):
    try: uri = 'res://' + path.relative_to(GAME).as_posix()
    except ValueError: return []
    return [f'{p.relative_to(GAME).as_posix()}:{n}' for p, n, line in lines if uri in line]

def build():
    OUT.mkdir(parents=True, exist_ok=True)
    refs = code_references()
    profile = json.loads((GAME/"assets/sideview/audio/sfx/mix_profile.json").read_text(encoding="utf-8"))["sounds"]
    files = set()
    for root in [WORKSPACE/'homeing-star-game', WORKSPACE/'homeing-star-temp-assert',
                 WORKSPACE/'homeing-star-test']:
        if not root.exists(): continue
        for p in root.rglob('*'):
            if any(part in SKIP for part in p.parts): continue
            if p.is_file() and p.suffix.lower() in {'.wav', '.mp3'}:
                if p.suffix.lower() == '.mp3' and not p.is_relative_to(GAME/'assets/sideview/audio'): continue
                files.add(p.resolve())
    items = []
    for path in sorted(files, key=lambda p: str(p).casefold()):
        runtime = path.is_relative_to(GAME/'assets')
        external = path.is_relative_to(LIBRARY)
        scope = '正式资源' if runtime else ('外部素材库' if external else '项目素材/测试产物')
        rel = path.relative_to(LIBRARY) if external else path.relative_to(WORKSPACE)
        group = rel.parts[0] if external else ('ui' if path.is_relative_to(GAME/'assets/ui') else path.parent.name if runtime else rel.parts[0])
        category = '/'.join(path.relative_to(GAME/'assets').parts[:-1]) if runtime else str(rel.parent)
        locations = references(path, refs) if runtime else []
        imported = []
        if external and path.parent.name == '手动':
            for key in MANUAL.get(path.stem, []):
                resource = GAME/'assets/sideview/audio/actions'/f'{key}.res'
                if resource.exists():
                    imported.append(resource.relative_to(GAME).as_posix())
                    locations += references(resource, refs)
        status = '有正式代码/场景引用' if locations and runtime else '已加工导入并有引用' if locations else '已加工导入，未检出引用' if imported else '未检出正式直接引用'
        with path.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        items.append(dict(id=len(items), name=path.name, path=str(path), uri=path.as_uri(),
                          scope=scope, group=group, category=category, status=status,
                          references=sorted(set(locations)), imported=imported,
                          format=path.suffix[1:].upper(), size=path.stat().st_size,
                          sha256=digest, **metadata(path)))
    duplicates = defaultdict(list)
    for row in items: duplicates[row['sha256']].append(row['id'])
    for row in items:
        row['copies'] = len(duplicates[row['sha256']])
        path = Path(row['path'])
        measurement = profile.get('res://'+path.relative_to(GAME).as_posix()) if path.is_relative_to(GAME) else None
        row['audition_gain_db'] = min(measurement['trim_db'], -3-measurement['peak_dbfs']) if measurement else None
    summary = {'total': len(items), 'wav': sum(r['format']=='WAV' for r in items),
               'scopes': dict(Counter(r['scope'] for r in items)),
               'runtime_wav': sum(r['scope']=='正式资源' and r['format']=='WAV' for r in items),
               'library_wav': sum(r['scope']=='外部素材库' and r['format']=='WAV' for r in items),
               'groups': dict(Counter(r['group'] for r in items)),
               'status': dict(Counter(r['status'] for r in items)),
               'duplicate_groups': sum(len(v)>1 for v in duplicates.values())}
    data = {'summary': summary, 'items': items}
    (OUT/'catalog.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    with (OUT/'catalog.csv').open('w', encoding='utf-8-sig', newline='') as f:
        keys = ['id','name','scope','group','category','format','duration','rate','channels','bits','size','status','references','imported','copies','sha256','path']
        writer = csv.DictWriter(f, fieldnames=keys, extrasaction='ignore')
        writer.writeheader()
        for row in items:
            writer.writerow({**row, 'references': '; '.join(row['references']), 'imported': '; '.join(row['imported'])})
    template = Path(__file__).with_name('audio_catalog_template.html').read_text(encoding='utf-8')
    (OUT/'index.html').write_text(template.replace('__CATALOG__',json.dumps(data, ensure_ascii=False).replace('<','\\u003c')), encoding='utf-8')
    readme = '# 项目内音效总目录\n\n打开 [试听页面](index.html)，或查看 [CSV 完整清单](catalog.csv) / [JSON 清单](catalog.json)。仅收录项目内文件，外部素材库不参与预览或服务路由。\n\n'
    readme += f'共 {summary["wav"]} 个 WAV，另列正式资源中的 MP3；正式 WAV {summary["runtime_wav"]} 个，外部素材库 WAV {summary["library_wav"]} 个。\n\n'
    readme += '“有引用”仅表示在正式脚本、场景或文本资源中发现直接资源路径，不等于每个游戏分支都会播放；“未检出”也不能排除动态加载。已加工的手动动作源轨通过既有 SOURCES.md 映射到九个 Godot .res 资源，试听的是原始 WAV。\n\n'
    readme += '试听默认将已测量的正式 WAV 对齐到基础响度（不含游戏中的前景/背景层级）；可切换原始音量，未测量的音频保持原始音量。\n\n'
    readme += '原始文件保持原位。用途分类取自现有文件夹，不代表音质或适用性已经试听确认。相同 SHA-256 的文件标记为重复副本，未删除。\n\n'
    readme += '本机双击 index.html 可以直接试听。若浏览器限制本地文件，运行 tools/build_audio_catalog.py --serve，再打开 http://127.0.0.1:8774/。服务只读取清单内音频，且仅监听本机。\n\n'
    readme += '| 来源分组 | 数量 |\n| --- | ---: |\n' + ''.join(f'| {k} | {v} |\n' for k,v in summary['groups'].items())
    (OUT/'README.md').write_text(readme, encoding='utf-8')
    print(json.dumps(summary, ensure_ascii=False))
    return data

def serve(data, port):
    allowed = {'/': OUT/'index.html', '/index.html': OUT/'index.html', '/catalog.json': OUT/'catalog.json', '/catalog.csv': OUT/'catalog.csv'}
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            route = urlparse(self.path).path
            if re.fullmatch(r'/audio/\d+', route):
                idx = int(route.rsplit('/',1)[1])
                if idx>=len(data['items']): self.send_error(404); return
                path = Path(data['items'][idx]['path'])
            else: path = allowed.get(route)
            if path is None or not path.is_file(): self.send_error(404); return
            size = path.stat().st_size
            start, end = 0, size-1
            ranged = re.fullmatch(r'bytes=(\d+)-(\d*)', self.headers.get('Range',''))
            if ranged:
                start = int(ranged[1]); end = min(int(ranged[2]), end) if ranged[2] else end
                if start>end: self.send_error(416); return
            self.send_response(206 if ranged else 200)
            self.send_header('Content-Type', mimetypes.guess_type(str(path))[0] or 'application/octet-stream')
            self.send_header('Content-Length',str(end-start+1)); self.send_header('Accept-Ranges','bytes')
            if ranged: self.send_header('Content-Range',f'bytes {start}-{end}/{size}')
            self.end_headers()
            try:
                with path.open('rb') as f:
                    f.seek(start); remaining = end-start+1
                    while remaining>0:
                        chunk = f.read(min(65536,remaining))
                        if not chunk: break
                        self.wfile.write(chunk); remaining -= len(chunk)
            except (BrokenPipeError, ConnectionResetError): pass
    print(f'Audio preview: http://127.0.0.1:{port}/', flush=True)
    ThreadingHTTPServer(('127.0.0.1',port),Handler).serve_forever()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--serve', action='store_true')
    parser.add_argument('--port', type=int, default=8774)
    args = parser.parse_args()
    if args.serve and (OUT/'catalog.json').exists():
        catalog = json.loads((OUT/'catalog.json').read_text(encoding='utf-8'))
    else:
        catalog = build()
    if args.serve: serve(catalog,args.port)
