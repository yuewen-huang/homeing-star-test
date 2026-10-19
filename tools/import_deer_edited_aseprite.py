"""Export user-edited native deer segments, preserving originals and logical size.

The runtime keeps the original 256-unit pivot/anchor/hitbox coordinate contract;
each clip records its native texture cell and compensates density at draw time.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import struct
import subprocess
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[2]
GAME=ROOT/'homeing-star-game'
ART=GAME/'assets/bosses/deer/body/boss/actions'
OUT=ROOT/'homeing-star-test/artifacts/deer-edited-aseprite-20261016'


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--apply',action='store_true');args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'native').mkdir(exist_ok=True)
    (OUT/'before').mkdir(exist_ok=True)
    library=json.loads((ART/'library.json').read_text(encoding='utf-8-sig'))
    sources=sorted(ART.glob('*.aseprite'))
    assert {p.stem for p in sources}==set(library['clips']),'Authored clips must exactly match retained deer library'
    environment=dict(os.environ,APPDATA=str(OUT/'appdata'))
    records={};boards=[]
    for source in sources:
        name=source.stem;entry=library['clips'][name];count=int(entry['count'])
        source_hash=sha(source)
        header=struct.unpack_from('<I5H',source.read_bytes())
        _,magic,frames,w,h,depth=header
        assert magic==0xA5E0 and depth in (8,16,32)
        native=OUT/'native'/f'{name}.png';meta=OUT/'native'/f'{name}.json'
        result=subprocess.run(['E:/Aseprite/Aseprite.exe','-b',str(source),'--format','json-array',
            '--data',str(meta),'--sheet',str(native),'--sheet-type','horizontal'],
            capture_output=True,env=environment,timeout=40,creationflags=subprocess.CREATE_NO_WINDOW)
        assert result.returncode==0,(name,result.returncode,result.stderr)
        data=json.loads(meta.read_text(encoding='utf-8'));assert len(data['frames'])==frames
        image=Image.open(native);rgba=image.convert('RGBA')
        # Some user documents are a single flattened strip instead of a timeline.
        if frames==1 and count>1:
            assert w==256*count and h==256,(name,'Unexpected flattened strip')
            cell=(256,256);layout='authored_flat_strip';durations=[data['frames'][0]['duration']]*count
        else:
            assert frames==count,(name,frames,count)
            assert w==h and w in (200,256),(name,w,h)
            cell=(w,h);layout='authored_timeline';durations=[r['duration'] for r in data['frames']]
        assert image.size==(cell[0]*count,cell[1]),(name,image.size)
        before=ART/entry['file']
        backup=OUT/'before'/before.name
        if not backup.exists():backup.write_bytes(before.read_bytes())
        old=Image.open(backup).convert('RGBA')
        assert old.size==(256*count,256)
        first=rgba.crop((0,0,*cell));old_first=old.crop((0,0,256,256))
        tile=Image.new('RGBA',(540,310),'#242b33')
        tile.alpha_composite(old_first,(0,30))
        # Only this inspection copy is enlarged; native export is unchanged.
        restored=first.resize((256,256),Image.Resampling.NEAREST)
        tile.alpha_composite(restored,(280,30))
        d=ImageDraw.Draw(tile);d.text((4,5),name+' / OLD',fill='white');d.text((284,5),'EDIT / LOGICAL SIZE',fill='white')
        tile.save(OUT/f'{name}_compare.png')
        if name in ['idle_ING','light_ING','heavy_ING','charge_run_ING','thrust_ING','leap_turn_END','flick_START','getup_START','death_END']:boards.append((name,tile))
        records[name]=dict(source_sha256=source_hash,depth=depth,source_canvas=[w,h],source_frames=frames,
            count=count,cell=list(cell),layout=layout,authored_durations_ms=durations,
            runtime_fps=entry['fps'],old_first_bbox=old_first.getbbox(),new_first_bbox=first.getbbox(),
            exported_sha256=sha(native),old_png_sha256=sha(backup),palette_preserved=True)
        entry['frame_size']=list(cell)
        entry['source_aseprite']=source.name
        entry['texture_to_logical_scale']=256.0/cell[0]
        if args.apply:
            # Keep Aseprite's native exported PNG bytes, including its palette.
            before.write_bytes(native.read_bytes())
        assert sha(source)==source_hash,'Never rewrite user Aseprite files'
    board=Image.new('RGBA',(1620,310*((len(boards)+2)//3)),'#242b33')
    for i,(_,tile) in enumerate(boards):board.alpha_composite(tile,((i%3)*540,(i//3)*310))
    board.save(OUT/'size_comparison.png')
    library['native_texture_coordinates']='Pivots and anchors remain in original 256 logical units. Use frame_size and texture_to_logical_scale only for rendering.'
    if args.apply:
        for filename in ('library.json','library.tres'):
            backup=OUT/'before'/filename
            if not backup.exists():backup.write_bytes((ART/filename).read_bytes())
        (ART/'library.json').write_text(json.dumps(library,ensure_ascii=False,indent=2),encoding='utf-8')
        resource=(ART/'library.tres').read_text(encoding='utf-8-sig')
        start=resource.index('metadata/library_json = ');end=resource.index('\n',start)
        resource=resource[:start]+'metadata/library_json = '+json.dumps(json.dumps(library,ensure_ascii=False),ensure_ascii=False)+resource[end:]
        (ART/'library.tres').write_text(resource,encoding='utf-8')
    report=dict(applied=args.apply,clips=records,source_count=len(sources),stored_frames=sum(v['count'] for v in records.values()),
        policy='Native pixels and palette unchanged; original logical pivots, anchors, authored combat clocks and painted FX preserved')
    (OUT/'import_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(f'{len(sources)} files; {report["stored_frames"]} stored frames; native cells: '+str(sorted({tuple(v['cell']) for v in records.values()})))
    print('Applied' if args.apply else 'Audit only',OUT)


if __name__=='__main__':main()
