"""Bake phase-two body proportions into RGBA sheets; never fit individual action poses.

The ordinary phase-two stance is the reference. Uppercut uses one uniform transform
for all frames. The two existing transformation-form scales are baked into their art.
Default writes a review sheet; --apply backs up current working images before replacing.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[3]
BODY=ROOT/'homeing-star-game/assets/bosses/master/body/boss/phase2'
OUT=ROOT/'homeing-star-test/artifacts/master_phase2_body_size'
BACKUP=ROOT/'homeing-star-temp-assert/Archive/master-phase2-size-normalization-20261026'
SCALE=1.7

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def apply_metadata(body,effects,report):
    for name,move in body['moves'].items():
        move['scale']=report['world_scale']
        effects['moves'][name]['world_scale']=report['world_scale']
        for ci,clip in enumerate(move['clips']):
            normalization=report['actions'][clip['animation']]
            clip.update(normalization)
            for event in effects['moves'][name]['events']:
                if event['node']==f'body_{ci+1}': event.update(normalization)

def prepare(apply=False):
    OUT.mkdir(parents=True,exist_ok=True)
    manifest_path=BODY/'normalization.json'
    if manifest_path.exists():
        raise SystemExit('Normalization already exists. Do not resample normalized assets twice.')
    report={'version':1,'world_scale':SCALE,'reference':'idle_256x256_24f.png','actions':{},'sources':{}}
    rows=[]
    staged={}
    for path in sorted(BODY.glob('*.png')):
        stem,cell,number=path.stem.rsplit('_',2)
        w,h=map(int,cell.split('x')); count=int(number[:-1])
        sheet=Image.open(path).convert('RGBA')
        columns=sheet.width//w
        report['sources'][path.name]={'sha256':sha(path),'backup':str(BACKUP/path.name)}
        output=Image.new('RGBA',sheet.size)
        scale=110/131 if stem=='uppercut' else 1.0
        pivot=(101.5,345.0) if stem=='uppercut' else (128.0,228.0)
        offset=[(pivot[0]-65)*(1-scale),(pivot[1]-346)*(1-scale)] if stem=='uppercut' else [0,0]
        report['actions']['phase_2_'+stem]={'pixel_scale':scale,'geometry_offset':offset}
        for i in range(count):
            x,y=(i%columns)*w,(i//columns)*h
            frame=sheet.crop((x,y,x+w,y+h))
            factor=scale
            if stem=='transform': factor=(1.25 if i<7 else 1.44)/SCALE
            if factor!=1:
                # Nearest-neighbour RGBA sampling: no palette conversion or interpolation.
                px,py=pivot
                transformed=frame.transform((w,h),Image.Transform.AFFINE,
                    (1/factor,0,px*(1-1/factor),0,1/factor,py*(1-1/factor)),Image.Resampling.NEAREST)
                bounds=frame.getbbox()
                if bounds:
                    box=[px+(bounds[0]-px)*factor,py+(bounds[1]-py)*factor,
                         px+(bounds[2]-px)*factor,py+(bounds[3]-py)*factor]
                    assert min(box[:2])>=-.01 and box[2]<=w+.01 and box[3]<=h+.01,(path,i,box)
            else: transformed=frame
            output.paste(transformed,(x,y))
            if i==(15 if stem=='transform' else 0):
                old_scale=(1.44 if stem=='transform' else 1.7 if stem in ['idle','walk','howl'] else 2.0)
                rows.append((stem,frame.copy(),old_scale,transformed.copy(),SCALE))
        if stem in ['uppercut','transform']:
            dest=OUT/path.name
            output.save(dest)
            staged[path]=dest
            report['sources'][path.name]['normalized_sha256']=sha(dest)
    canvas=Image.new('RGB',(2100,1140),'#17212c')
    draw=ImageDraw.Draw(canvas)
    for index,(name,before,before_scale,after,after_scale) in enumerate(rows):
        x,y=(index%3)*700,(index//3)*380
        draw.text((x+12,y+8),name,fill='white')
        for col,frame,factor,label in [(0,before,before_scale,'BEFORE'),(1,after,after_scale,'STATIC / FIXED 1.7')]:
            bounds=frame.getbbox()
            body=frame.crop(bounds)
            body=body.resize((round(body.width*factor),round(body.height*factor)),Image.Resampling.NEAREST)
            at=(x+col*350+(350-body.width)//2,y+315-body.height)
            canvas.paste(body,at,body)
            draw.line((x+col*350,y+315,x+(col+1)*350-2,y+315),fill='#7496a3',width=1)
            draw.text((x+col*350+5,y+329),label,fill='#d0e0ed')
            draw.text((x+col*350+5,y+347),str(body.height)+' px',fill='#d0e0ed')
    canvas.save(OUT/'comparison.png')
    report['transform_bake']={'boundary_frame':7,'first_pixel_scale':1.25/SCALE,'second_pixel_scale':1.44/SCALE,'pivot':[128,228]}
    (OUT/'normalization.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
    if apply:
        BACKUP.mkdir(parents=True,exist_ok=True)
        for name,record in report['sources'].items():
            path=BODY/name
            assert sha(path)==record['sha256'],'Source changed during review'
            backup=BACKUP/name
            if backup.exists(): assert sha(backup)==record['sha256'],'Existing backup differs; do not overwrite'
            else: shutil.copyfile(path,backup)
        for path,stage in staged.items(): shutil.copyfile(stage,path)
        shutil.copyfile(OUT/'normalization.json',manifest_path)
        # Keep the original Studio-tuned coordinates and express only the asset transform.
        body_path=BODY/'arrangements.json'
        effects_path=ROOT/'homeing-star-game/assets/bosses/master/fx/phase2/arrangements.json'
        body=json.loads(body_path.read_text(encoding='utf8'))
        effects=json.loads(effects_path.read_text(encoding='utf8'))
        apply_metadata(body,effects,report)
        for path,data in [(body_path,body),(effects_path,effects)]:
            path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print('Applied' if apply else 'Preview ready',OUT/'comparison.png')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--apply',action='store_true')
    prepare(parser.parse_args().apply)
