"""Import approved master VFX cels and match remaining phase-one colours.

Preserve the artist's changed cels exactly. Only RGB changes on other cels;
keep all native document chunks, references, timing, position and alpha.
Fit edited active-frame rectangles to their new artwork without changing
segment IDs, damage cadence, warnings, reactions, body placement or facing.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import zlib

import numpy as np
from PIL import Image, ImageFont

from aseprite_rgba_reader import read, layer_frame
from recolor_platinum_slashes import chunks
from package_master_effects_aseprite import (
    CONFIGS, GAME, FX, BODY, OUT, split_sheet, durations_and_hits,
    make_preview, checker, data_url, HTML, runs,
)

EDIT_LAYER = '技能特效_可编辑'
REPORT_DIR = OUT/'接入检查_20261014'
NATIVE = Path('D:/Aseprite/Aseprite.exe')
# Sampled from the two approved edits: shadows, blue body, cyan, mint, white.
RAMP_POS = np.array([0,.25,.45,.65,.78,.86,.925],dtype=float)
RAMP_RGB = np.array([(1,60,106),(1,113,182),(1,124,198),(1,151,236),
                     (0,242,253),(105,240,199),(255,255,255)],dtype=float)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def recolor(pixels, width, height):
    rgba = np.frombuffer(pixels,dtype=np.uint8).reshape(height,width,4).copy()
    rgb = rgba[:,:,:3].astype(float)/255
    energy = .52*rgb.max(axis=2)+.48*(rgb@np.array([.2126,.7152,.0722]))
    mapped = np.stack([np.interp(energy,RAMP_POS,RAMP_RGB[:,c]) for c in range(3)],axis=2)
    visible = rgba[:,:,3]>0
    rgba[visible,:3] = np.rint(mapped[visible]).astype(np.uint8)
    assert rgba[:,:,3].tobytes() == pixels[3::4]
    return rgba.tobytes()


def recolor_document(raw, layer, keep_frames):
    blocks = []
    for index,(frame_header,frame_chunks) in enumerate(chunks(raw)):
        packed = []
        for kind,body in frame_chunks:
            if kind == 0x2005 and struct.unpack_from('<H',body)[0] == layer and index not in keep_frames:
                cel_type = struct.unpack_from('<H',body,7)[0]
                if cel_type in (0,2):
                    w,h = struct.unpack_from('<HH',body,16)
                    pixels = zlib.decompress(body[20:]) if cel_type == 2 else body[20:]
                    changed = recolor(pixels,w,h)
                    body = body[:20]+(zlib.compress(changed,9) if cel_type == 2 else changed)
                elif cel_type == 1:
                    linked = struct.unpack_from('<H',body,16)[0]
                    assert (linked in keep_frames) == (index in keep_frames), 'Cannot recolor a link to an artist-edited frame'
                else:
                    raise ValueError('Unsupported tilemap')
            packed.append(struct.pack('<IH',len(body)+6,kind)+body)
        payload = b''.join(packed)
        header = bytearray(frame_header)
        struct.pack_into('<I',header,0,len(payload)+16)
        blocks.append(bytes(header)+payload)
    header = bytearray(raw[:128])
    payload = b''.join(blocks)
    struct.pack_into('<I',header,0,128+len(payload))
    return bytes(header)+payload


def export_and_check(path,expected,durations,folder):
    sheet,data = folder/(path.stem+'.png'),folder/(path.stem+'.json')
    result = subprocess.run([str(NATIVE),'-b','--layer',EDIT_LAYER,str(path),
                             '--format','json-array','--data',str(data),'--sheet',str(sheet),
                             '--sheet-type','rows','--sheet-columns','4'],
                            capture_output=True,timeout=45,creationflags=subprocess.CREATE_NO_WINDOW)
    assert data.exists() and sheet.exists(), f'Native export missing: {path.name}, {result.returncode}'
    meta = json.loads(data.read_text(encoding='utf-8'))
    assert len(meta['frames']) == len(expected)
    atlas = Image.open(sheet).convert('RGBA')
    for i,record in enumerate(meta['frames']):
        assert record['duration'] == durations[i]
        rect = record['frame']
        actual = np.asarray(atlas.crop((rect['x'],rect['y'],rect['x']+rect['w'],rect['y']+rect['h'])))
        reference = np.asarray(expected[i])
        assert actual.shape == reference.shape
        assert np.array_equal(actual[:,:,3],reference[:,:,3])
        visible = reference[:,:,3]>0
        assert np.array_equal(actual[visible,:3],reference[visible,:3]), (path.name,i+1)
    return result.returncode


def format_number(value):
    return f'{value:g}'


def patch_timeline(raw,prepared):
    replacements = {}
    for name,action,frames,edited in prepared[:2]:
        ident = re.search(r'&"'+re.escape(action)+r'": SubResource\("([^"]+)"\)',raw)[1]
        pattern = r'(\[sub_resource type="Animation" id="'+re.escape(ident)+r'"\]\n)(.*?)(?=\n\[|\Z)'
        match = re.search(pattern,raw,re.S)
        block = match[2]
        track_pattern = r'tracks/2/keys = \{(.*?)\n\}(?:\n|$)'
        track = re.search(track_pattern,block,re.S)
        times = [float(t) for t in re.search(r'"times": PackedFloat32Array\((.*?)\)',track[1])[1].split(',')]
        entries = re.findall(r'\{\n"args": \[(.*?)\],\n"method": &"([^"]+)"\n\}',track[1],re.S)
        assert len(entries) == len(times)
        # Attack 1 previously used one rectangle for all three active frames.
        if action == 'attack_1':
            args,method = entries[0]
            assert times == [.8,1.1]
            times = [.8,.9,1,1.1]
            entries = [(args,method)]*3+[entries[1]]
        rendered = []
        boxes = []
        for t,(args,method) in zip(times,entries):
            i = round(t*10)
            if method == '_timeline_attack_frame' and i in edited:
                bounds = frames[i].getchannel('A').getbbox()
                assert bounds is not None
                x,y,right,bottom = bounds
                w,h = frames[i].size
                at = ((x+right-w)/2,(y+bottom-h)/2)
                size = (right-x,bottom-y)
                replacement = f'Vector2({format_number(at[0])}, {format_number(at[1])}), Vector2({size[0]}, {size[1]})'
                args,n = re.subn(r'Vector2\([^)]*\), Vector2\([^)]*\)',replacement,args,count=1)
                assert n == 1
                boxes.append({'frame':i+1,'position':at,'size':size})
            rendered.append('{\n"args": ['+args+'],\n"method": &"'+method+'"\n}')
        new_track = 'tracks/2/keys = {\n"times": PackedFloat32Array('+', '.join(format_number(t) for t in times)+'),\n"transitions": PackedFloat32Array('+', '.join(['1']*len(times))+'),\n"values": ['+', '.join(rendered)+']\n}\n'
        new_block = block[:track.start()]+new_track+block[track.end():]
        raw = raw[:match.start(2)]+new_block+raw[match.end(2):]
        replacements[action] = boxes
    return raw,replacements


def refresh_handoff():
    """Keep the frame finder consistent with the artwork now used by the game."""
    from PIL import ImageDraw
    manifest_path = OUT/'时间轴与来源.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    clips = []
    overview = Image.new('RGB',(4*304,4*238),(25,28,34))
    draw = ImageDraw.Draw(overview)
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',16)
    preview = OUT/'预览'
    for index,conf in enumerate(CONFIGS):
        name,action,filename,body,size,count,position,scale = conf
        source = GAME/FX/filename
        document = read(OUT/(name+'.aseprite'))
        sheet,game_frames = split_sheet(source,size,count)
        frames = [layer_frame(document,i,1)[0] for i in range(count)]
        references = [layer_frame(document,i,0)[0] for i in range(count)]
        assert all(a.tobytes()==b.tobytes() for a,b in zip(frames,game_frames))
        durations = [f['duration_ms'] for f in document['frames']]
        visible = [i+1 for i,f in enumerate(frames) if f.getchannel('A').getbbox()]
        item = manifest[index]
        item['visible_effect_frames'] = visible
        if index < 5:
            item.setdefault('previous_runtime_sha256',item['source_sha256'])
            item['source_sha256'] = sha(source)
            item['imported'] = '2026-10-14'
            animation = make_preview(preview,name,frames,references,durations,item['hit_windows_one_based'],font)
        else:
            animation = []
            for effect,reference in zip(frames,references):
                bg = checker(size)
                if body:
                    faded = reference.copy()
                    faded.putalpha(reference.getchannel('A').point(lambda a:round(a*.45)))
                    bg.alpha_composite(faded)
                bg.alpha_composite(effect)
                factor = min(208/size[0],160/size[1],1)
                animation.append(bg.resize((round(size[0]*factor),round(size[1]*factor)),Image.Resampling.NEAREST).convert('RGB'))
        hero = max(range(count),key=lambda i:sum(frames[i].getchannel('A').histogram()[1:]))
        x,y = (index%4)*304,(index//4)*238
        draw.text((x+8,y+7),name,font=font,fill='white')
        draw.text((x+8,y+31),f'{count} 帧 | 有特效：'+','.join(f'{a}-{b}' for a,b in runs(visible)),font=font,fill=(145,200,220))
        thumb = animation[hero]
        overview.paste(thumb,(x+(304-thumb.width)//2,y+64))
        clips.append({**item,'name':name,'fx':data_url(source),'ref':data_url(GAME/BODY/body) if body else None,'columns':sheet.width//size[0]})
    overview.save(preview/'师傅技能特效索引.png')
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'师傅特效逐帧查看.html').write_text(HTML.replace('__DATA__',json.dumps(clips,ensure_ascii=False).replace('</','<\\/')),encoding='utf-8')
    notes_path = OUT/'如何找到要修改的帧.md'
    notes = notes_path.read_text(encoding='utf-8')
    notes = notes.replace('本次没有接入或改变游戏。','2026-10-14：一阶段五个技能已接入游戏；手工改动帧原样保留，其余按新配色改色。接入前原稿及运行图保存在 `接入检查_20261014/接入前备份`。')
    notes = notes.replace('没有裁边、缩放或重绘。','导出没有裁边或缩放；手工重绘帧直接保留，其余帧只改色。')
    notes_path.write_text(notes,encoding='utf-8')


def import_additional_document():
    """Import the user's subsequent attack-3 edits on frames 6, 7 and 8."""
    name,action,filename,body,size,count,position,scale = CONFIGS[2]
    source,target = OUT/(name+'.aseprite'),GAME/FX/filename
    timeline_path = GAME/BODY/'master_combat_timelines.tres'
    addendum = REPORT_DIR/'攻击3补充_678'
    assert not addendum.exists(), 'An additional import already exists; review before replacing it'
    addendum.mkdir()
    fingerprints = {p:sha(p) for p in (source,target,timeline_path)}
    for p in (source,target,timeline_path):
        shutil.copy2(p,addendum/p.name)
    doc = read(source)
    assert doc['canvas'] == size and len(doc['frames']) == count
    layer = next(i for i,l in enumerate(doc['layers']) if l['name']==EDIT_LAYER)
    assert layer == 1 and len(doc['layers']) == 2
    frames = [layer_frame(doc,i,layer)[0] for i in range(count)]
    assert all(layer_frame(doc,i,layer)[1] == 1 for i in range(count))
    sheet,previous = split_sheet(target,size,count)
    edited = {i for i,(a,b) in enumerate(zip(previous,frames)) if a.tobytes()!=b.tobytes()}
    assert edited == {5,6,7}, f'Unexpected additional changed frames: {sorted(edited)}'
    durations = [f['duration_ms'] for f in doc['frames']]
    assert durations == durations_and_hits()[action][0]
    export_folder = addendum/'特效层导出'
    export_folder.mkdir()
    native_exit = export_and_check(source,frames,durations,export_folder)
    columns = sheet.width//size[0]
    for i,frame in enumerate(frames):
        sheet.paste(frame,((i%columns)*size[0],(i//columns)*size[1]))
    runtime = export_folder/target.name
    sheet.save(runtime)
    assert all(a.tobytes()==b.tobytes() for a,b in zip(frames,split_sheet(runtime,size,count)[1]))
    new_timeline,boxes = patch_timeline(timeline_path.read_text(encoding='utf-8'),[(name,action,frames,edited)])
    staged_timeline = export_folder/timeline_path.name
    staged_timeline.write_text(new_timeline,encoding='utf-8')
    assert all(sha(p)==value for p,value in fingerprints.items()), 'A source changed during preparation'
    shutil.copy2(runtime,target)
    shutil.copy2(staged_timeline,timeline_path)
    staging = REPORT_DIR/'已接入原稿'
    shutil.copy2(source,staging/source.name)
    shutil.copy2(runtime,staging/target.name)
    shutil.copy2(staged_timeline,staging/timeline_path.name)
    audit_path = REPORT_DIR/'接入校验.json'
    audit = json.loads(audit_path.read_text(encoding='utf-8'))
    audit['hitboxes'][action] = boxes[action]
    audit['clips'][2]['artist_frames_preserved'] = [6,7,8]
    audit['clips'][2]['recolored_frames'] = [f for f in audit['clips'][2]['recolored_frames'] if f not in [6,7,8]]
    audit['clips'][2]['native_export_exit'] = native_exit
    audit['clips'][2]['additional_import'] = '攻击3补充_678'
    audit_path.write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
    report = {'file':source.name,'artist_frames_preserved':[6,7,8],'other_frames_identical_to_previous_runtime':True,
              'effect_layer_native_rgba_exact':True,'duration_exact':True,'source_sha256':fingerprints[source],
              'native_exit_code':native_exit,'hitboxes':boxes[action]}
    (addendum/'补充接入校验.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    refresh_handoff()
    print('IMPORTED additional attack-3 frames 6, 7, 8 exactly; remaining frames preserved.',flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rebuild-from-backup',action='store_true',help='Rebuild the published import from its untouched original backup')
    parser.add_argument('--additional-attack3-edits',action='store_true',help='Import subsequent artist edits on attack-3 frames 6, 7 and 8')
    args = parser.parse_args()
    if args.additional_attack3_edits:
        import_additional_document()
        return
    assert not (REPORT_DIR/'攻击3补充_678').exists(), 'Later artist edits exist; do not rebuild from the initial backup'
    REPORT_DIR.mkdir(exist_ok=True)
    backup = REPORT_DIR/'接入前备份'
    staging = REPORT_DIR/'已接入原稿'
    native = REPORT_DIR/'原生导出校验'
    for p in (backup,staging,native):
        p.mkdir(exist_ok=True)
    timeline = durations_and_hits()
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',16)
    report,prepared,changes = [],[],[]
    original_hashes = {}
    for conf in CONFIGS[:5]:
        name,action,filename,body,size,count,position,scale = conf
        source,target = OUT/(name+'.aseprite'),GAME/FX/filename
        original_hashes[source] = sha(source)
        original_hashes[target] = sha(target)
        for p in (source,target):
            saved = backup/p.name
            if args.rebuild_from_backup:
                assert saved.exists() and sha(p)==sha(staging/p.name), 'Published file changed; refuse rebuilding'
            else:
                assert not saved.exists(), 'An earlier import backup exists; review before importing again'
                shutil.copy2(p,saved)
        document_source = backup/source.name
        document = read(document_source)
        assert document['canvas'] == size and len(document['frames']) == count
        assert len(document['layers']) == 2
        layer = next(i for i,l in enumerate(document['layers']) if l['name'] == EDIT_LAYER)
        assert layer == 1
        durations = [f['duration_ms'] for f in document['frames']]
        assert durations == timeline[action][0], 'Artist frame timing differs from combat timeline'
        original_sheet,old_frames = split_sheet(backup/target.name,size,count)
        frames = [layer_frame(document,i,layer)[0] for i in range(count)]
        assert all(layer_frame(document,i,layer)[1] == 1 for i in range(count)), 'Do not bake opacity changes silently'
        edited = {i for i,(old,new) in enumerate(zip(old_frames,frames)) if old.tobytes() != new.tobytes()}
        if conf in CONFIGS[2:5]:
            assert not edited, 'Unexpected artist edits in another source document'
        converted = staging/source.name
        raw = document_source.read_bytes()
        converted.write_bytes(recolor_document(raw,layer,edited))
        new_document = read(converted)
        new_frames = [layer_frame(new_document,i,layer)[0] for i in range(count)]
        assert new_document['canvas'] == document['canvas']
        assert new_document['layers'] == document['layers']
        for i in range(count):
            assert new_document['frames'][i]['duration_ms'] == durations[i]
            assert layer_frame(new_document,i,0)[0].tobytes() == layer_frame(document,i,0)[0].tobytes()
            assert new_frames[i].getchannel('A').tobytes() == frames[i].getchannel('A').tobytes()
            if i in edited:
                assert new_frames[i].tobytes() == frames[i].tobytes(), 'Artist edit was changed'
        exit_code = export_and_check(converted,new_frames,durations,native)
        packed = original_sheet.copy()
        columns = original_sheet.width//size[0]
        for i,frame in enumerate(new_frames):
            packed.paste(frame,((i%columns)*size[0],(i//columns)*size[1]))
        runtime = staging/target.name
        packed.save(runtime)
        assert all(a.tobytes()==b.tobytes() for a,b in zip(split_sheet(runtime,size,count)[1],new_frames))
        references = [layer_frame(new_document,i,0)[0] for i in range(count)]
        make_preview(staging,name,new_frames,references,durations,timeline[action][1],font)
        prepared.append((name,action,new_frames,edited))
        changes += [(converted,source),(runtime,target)]
        recolored = [i+1 for i in range(count) if i not in edited and new_frames[i].tobytes()!=frames[i].tobytes()]
        report.append({'file':source.name,'artist_frames_preserved':[i+1 for i in sorted(edited)],
                       'recolored_frames':recolored,'reference_exact':True,'alpha_and_timing_exact':True,
                       'runtime':str(target),'native_export_exit':exit_code,'native_visible_rgba_exact':True})
        print('VERIFIED',name,'artist frames',[i+1 for i in sorted(edited)],'recolored',recolored,flush=True)
    timeline_path = GAME/BODY/'master_combat_timelines.tres'
    original_hashes[timeline_path] = sha(timeline_path)
    if args.rebuild_from_backup:
        assert sha(timeline_path)==sha(staging/timeline_path.name), 'Timeline changed; refuse rebuilding'
    else:
        shutil.copy2(timeline_path,backup/timeline_path.name)
    updated,boxes = patch_timeline((backup/timeline_path.name).read_text(encoding='utf-8'),prepared)
    staged_timeline = staging/timeline_path.name
    staged_timeline.write_text(updated,encoding='utf-8')
    changes.append((staged_timeline,timeline_path))
    # Only replace files after every source document and runtime sheet passed.
    assert all(sha(p)==fingerprint for p,fingerprint in original_hashes.items()), 'A source changed during preparation'
    for source,target in changes:
        shutil.copy2(source,target)
    (REPORT_DIR/'接入校验.json').write_text(json.dumps({'clips':report,'hitboxes':boxes,'palette':RAMP_RGB.astype(int).tolist()},ensure_ascii=False,indent=2),encoding='utf-8')
    refresh_handoff()
    print('IMPORTED 5 phase-one skills; preserved artist cels, alpha, timing and reference layers.',flush=True)


if __name__ == '__main__':
    import sys
    sys.stdout.reconfigure(encoding='utf-8')
    main()
