"""Import the user's standalone root variants through native Aseprite, without modifying sources."""
from pathlib import Path
import argparse, hashlib, json, shutil, struct, subprocess
from PIL import Image


def import_roots(source, project, work, executable):
    work.mkdir(parents=True, exist_ok=True)
    clips = {}
    for kind in ('short', 'medium', 'high', 'nodule'):
        count = 1 if kind == 'nodule' else 3
        for variant in range(count):
            key = 'nodule' if kind == 'nodule' else f'{kind}{variant+1}'
            path = source / ('树根结节.aseprite' if kind == 'nodule' else key+'.aseprite')
            blob = path.read_bytes()
            _, magic, n, w, h, depth = struct.unpack_from('<I5H', blob)
            assert magic == 0xA5E0 and depth == 32
            durations=[]; pos=128
            for _ in range(n):
                length, magic, _, duration = struct.unpack_from('<I3H',blob,pos)
                assert magic == 0xF1FA and duration > 0
                durations.append(duration); pos += length
            stem = work/key
            subprocess.run([str(executable),'-b','--list-layers',str(path),'--trim','--format','json-array','--data',str(stem.with_suffix('.json')),'--sheet',str(stem.with_suffix('.png')),'--sheet-type','packed','--sheet-width','2048'],check=True,capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW)
            native = json.loads(stem.with_suffix('.json').read_text(encoding='utf-8'))
            assert len(native['frames']) == n
            atlas = Image.open(stem.with_suffix('.png')).convert('RGBA')
            frames=[]
            for i,row in enumerate(native['frames']):
                r=row['frame']; im=atlas.crop((r['x'],r['y'],r['x']+r['w'],r['y']+r['h']))
                # Very faint leftover brush pixels are retained in art but do not define grounding/hit shape.
                mask=im.getchannel('A').point(lambda a:255 if a>=96 else 0)
                box=mask.getbbox(); assert box
                band=mask.crop((0,max(box[1],box[3]-6),im.width,box[3]))
                xs=[x for y in range(band.height) for x in range(band.width) if band.getpixel((x,y))]
                anchor_x=sum(xs)/len(xs); anchor_y=box[3]
                frames.append({'duration_ms':durations[i],'region':[r[k] for k in ('x','y','w','h')], 'offset':[-anchor_x,-anchor_y], 'hit_rect':[box[0]-anchor_x,box[1]-anchor_y,box[2]-box[0],box[3]-box[1]], 'source_position':[row['spriteSourceSize']['x'],row['spriteSourceSize']['y']]})
            clips[key]={'kind':kind,'variant':variant,'canvas':[w,h],'duration_ms':sum(durations),'frames':frames,'source_file':path.name,'source_sha256':hashlib.sha256(blob).hexdigest(),'idle_frame':n-1,'destroy_frames':[1,0] if kind=='nodule' else []}
            print(key,n,'frames',sum(durations),'ms',flush=True)
    dest=project/'assets/bosses/deer/fx/root_painted';dest.mkdir(parents=True,exist_ok=True)
    for key in clips: shutil.copy2(work/(key+'.png'),dest/(key+'.png'))
    payload=json.dumps({'world_scale':1.4,'clips':clips,'source_folder':str(source)},ensure_ascii=False,separators=(',',':'))
    (dest/'timelines.tres').write_text('[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/timelines = '+json.dumps(payload,ensure_ascii=False)+'\n',encoding='utf-8')
    (work/'source_hashes.json').write_text(json.dumps({c['source_file']:c['source_sha256'] for c in clips.values()},ensure_ascii=False,indent=2),encoding='utf-8')
    print('IMPORTED',len(clips),'root/nodule clips; originals untouched')

if __name__ == '__main__':
    p=argparse.ArgumentParser()
    for name in ('source','project','work','aseprite'):p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();import_roots(a.source,a.project,a.work,a.aseprite)
