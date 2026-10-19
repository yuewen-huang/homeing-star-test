"""Check native source preservation, runtime export identity and logical bounds."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'homeing-star-game/assets/bosses/deer/body/boss/actions'
OUT=ROOT/'homeing-star-test/artifacts/deer-edited-aseprite-20261016'


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    report=json.loads((OUT/'import_report.json').read_text())
    library=json.loads((ART/'library.json').read_text())
    before=json.loads((OUT/'before/library.json').read_text())
    verification={};maximum=0.0
    for name,record in report['clips'].items():
        assert sha(ART/(name+'.aseprite'))==record['source_sha256'],(name,'Authored file changed')
        assert sha(ART/(name+'.png'))==record['exported_sha256'],(name,'Runtime differs from native export')
        entry=dict(library['clips'][name])
        for key in ('frame_size','source_aseprite','texture_to_logical_scale'):entry.pop(key)
        assert entry==before['clips'][name],(name,'Original pivot/anchor/timing changed')
        new=Image.open(ART/(name+'.png')).convert('RGBA')
        old=Image.open(OUT/'before'/(name+'.png')).convert('RGBA')
        w,h=record['cell'];density=256/w
        deltas=[]
        for frame in range(record['count']):
            bbox=new.crop((frame*w,0,(frame+1)*w,h)).getbbox()
            oldbox=old.crop((frame*256,0,(frame+1)*256,256)).getbbox()
            if bbox and oldbox:deltas.append(max(abs(a*density-b) for a,b in zip(bbox,oldbox)))
        maximum=max(maximum,max(deltas))
        verification[name]=dict(source_unchanged=True,native_png_bytes_exact=True,logical_anchors_and_timing_unchanged=True,
            native_cell=[w,h],density_compensation=density,max_authored_bbox_edge_delta_logical=max(deltas))
    result=dict(clips=verification,count=len(verification),stored_frames=report['stored_frames'],
        max_authored_bbox_edge_delta_logical=maximum,
        note='Bounding differences measure changed authored silhouettes/quantization; no per-frame rescaling or recentering is performed.')
    (OUT/'verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(f'PASS: {len(verification)} source hashes; {report["stored_frames"]} frames; exact native PNGs; original anchors/timing unchanged')
    print('Maximum authored bbox edge difference after logical compensation:',maximum)


if __name__=='__main__':main()
