"""Physically split reviewed deer actions. Never ship the original complete strips."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
from PIL import Image

BASE = Path(__file__).resolve().parents[1]
SEGMENTS = {
    'idle': {'ING': (0,31)}, 'walk': {'ING': (0,15)},
    'light': {'START':(0,5),'ING':(6,8),'END':(9,15)},
    'heavy': {'START':(0,17),'ING':(18,26),'END':(27,31)},
    'charge': {'START':(0,11),'ING':(12,24),'END':(25,31)},
    'roar': {'START':(0,3),'ING':(4,11),'END':(12,15)},
    'hurt': {'START':(0,3),'ING':(4,11),'END':(12,15)},
    'death': {'START':(0,2),'ING':(3,7),'END':(8,11)},
    'thrust': {'START':(0,5),'ING':(6,10),'END':(11,15)},
    'rear_gore': {'START':(0,10),'ING':(11,13),'END':(14,15)},
    'flick': {'START':(0,9),'ING':(10,21),'END':(22,31)},
    'bind_push': {'START':(0,5),'ING':(6,31)},
    'leap_turn': {'START':(0,4),'ING':(5,10),'END':(11,15)},
    'getup': {'START':(0,0),'ING':(1,2),'END':(3,3)},
}
EXTRA = {
    'charge_run_ING':('charge',12,17),
    'uppercut_START':('charge',18,19), 'uppercut_ING':('charge',20,24), 'uppercut_END':('charge',25,31),
    'flick_sweep_ING':('flick',10,14),
    'flick_lift_START':('flick',15,17), 'flick_lift_ING':('flick',18,21), 'flick_lift_END':('flick',22,31),
}
FINAL = {'thrust':('前刺.png',16),'rear_gore':('直立角击.png',16),
         'flick':('甩头挑击.png',32),'bind_push':('角力前进.png',32),'leap_turn':('跳跃转身.png',16)}
OLD_COUNTS = {'idle':32,'walk':16,'light':16,'heavy':32,'charge':32,'roar':16,'hurt':16,'death':12}
LOOPS = {'idle_ING','walk_ING','hurt_ING','roar_ING','charge_run_ING','bind_push_ING'}


def weighted_core(frame):
    pts=[]
    for y in range(60,250):
        for x in range(35,235):
            r,g,b,a=frame.getpixel((x,y))
            weight=max(g-max(r,b)-23,0)*(g/255)**8*a/255
            if weight: pts.append((x,y,weight))
    total=sum(p[2] for p in pts)
    return [sum(p[d]*p[2] for p in pts)/total for d in (0,1)] if total>0.001 else [138.0,198.0]


def read_resource_json(path,key):
    value=path.read_text(encoding='utf-8-sig').split('metadata/'+key+' = ',1)[1].strip()
    parsed=json.loads(value)
    return json.loads(parsed) if isinstance(parsed,str) else parsed


def old_frame_clip(family,frame):
    if family=='charge':
        if 12<=frame<=17:return 'charge_run_ING',frame-12
        if 18<=frame<=19:return 'uppercut_START',frame-18
        if 20<=frame<=24:return 'uppercut_ING',frame-20
        if frame>=25:return 'uppercut_END',frame-25
    for part,(first,last) in SEGMENTS[family].items():
        if first<=frame<=last:return family+'_'+part,frame-first
    raise ValueError((family,frame))


def migrate_painted(project):
    path=project/'assets/bosses/deer/fx/painted/timelines.tres'
    data=read_resource_json(path,'timelines')
    for kind,clip in data['clips'].items():
        for sample in clip.get('body_offsets',[]):
            family=sample['animation'];frame=sample['body_frame']
            if family in SEGMENTS:
                sample['animation'],sample['body_frame']=old_frame_clip(family,frame)
        if kind=='mist_dash':
            for frame in clip['frames']:
                if 'body_clip' not in frame:
                    frame['body_clip'],frame['body_frame']=old_frame_clip('charge',frame['body_frame'])
    text='[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/timelines = '+json.dumps(json.dumps(data,ensure_ascii=False),ensure_ascii=False)+'\n'
    path.write_text(text,encoding='utf-8')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--project',type=Path,default=BASE.parent/'homeing-star-game')
    parser.add_argument('--source',type=Path,default=BASE.parent/'homeing-star-temp-assert/PendingArt/workspace_art/动作补充/Final')
    parser.add_argument('--output',type=Path,default=BASE/'artifacts/deer-action-split-20261012')
    parser.add_argument('--bindings-only',action='store_true')
    args=parser.parse_args();project=args.project
    if args.bindings_only:
        migrate_painted(project);return
    art=project/'assets/bosses/deer/body/boss'
    snapshot=BASE.parent/'homeing-star-temp-assert/PendingArt/workspace_art/deer-action-split-20261012/source_full'
    snapshot.mkdir(parents=True,exist_ok=True)
    for name,count in OLD_COUNTS.items():
        filename=f'{name}_256x256_{count}f.png'
        if not (snapshot/filename).exists():shutil.copy2(art/filename,snapshot/filename)
    for filename in ['core_positions.tres','clash_core_positions.tres']:
        if not (snapshot/filename).exists() and (art/filename).exists():shutil.copy2(art/filename,snapshot/filename)
    anchors_path=snapshot/'anchors.json'
    if not anchors_path.exists():
        anchors={}
        for filename,function,key in [('deer_boss.gd','light_hoof_offset','light'),('deer_boss.gd','heavy_hoof_offset','heavy'),
                                      ('deer_boss.gd','charge_antler_offset','charge'),('deer_clash_phase.gd','warning_offset','rear_gore')]:
            text=(project/'scripts/sideview'/filename).read_text(encoding='utf-8')
            body=text.split('func '+function+'(',1)[1].split('\nfunc ',1)[0]
            array=re.search(r'var (?:anchors|points) := \[(.*?)\]',body,re.S).group(1)
            anchors[key]=[[float(x),float(y)] for x,y in re.findall(r'Vector2\(([-\d.]+),\s*([-\d.]+)\)',array)]
        anchors_path.write_text(json.dumps(anchors),encoding='utf-8')
    anchors=json.loads(anchors_path.read_text(encoding='utf-8'))
    cores=read_resource_json(snapshot/'core_positions.tres','core_positions')
    if (snapshot/'clash_core_positions.tres').exists():cores.update(read_resource_json(snapshot/'clash_core_positions.tres','core_positions_json'))
    sources={};cells={};pivots={}
    for name,count in OLD_COUNTS.items():
        path=snapshot/f'{name}_256x256_{count}f.png';im=Image.open(path).convert('RGBA')
        cells[name]=[im.crop((i*256,0,(i+1)*256,256)) for i in range(count)]
        sources[name]=path;pivots[name]=[128,252]
    for name,(filename,count) in FINAL.items():
        path=args.source/filename;im=Image.open(path).convert('RGBA');columns=im.width//256
        cells[name]=[im.crop((i%columns*256,i//columns*256,(i%columns+1)*256,(i//columns+1)*256)) for i in range(count)]
        sources[name]=path;pivots[name]=[128,256] if name=='leap_turn' else [82,256]
        if name not in cores:cores[name]=[weighted_core(f) for f in cells[name]]
    path=BASE.parent/'homeing-star-temp-assert/PendingArt/character/朽角巡林者/死亡/image-2-godot4 (9)/image-2/textures/image-2_spritesheet.png'
    im=Image.open(path).convert('RGBA');columns=im.width//256
    cells['getup']=[im.crop((i%columns*256,i//columns*256,(i%columns+1)*256,(i//columns+1)*256)) for i in range(12,16)]
    sources['getup']=path;pivots['getup']=[128,256];cores['getup']=[weighted_core(f) for f in cells['getup']]
    target=art/'actions';target.mkdir(exist_ok=True);args.output.mkdir(parents=True,exist_ok=True)
    clips={};coverage={name:set() for name in cells}
    definitions={name+'_'+part:(name,first,last) for name,parts in SEGMENTS.items() for part,(first,last) in parts.items()}
    definitions.update(EXTRA)
    for name,(family,first,last) in definitions.items():
        frames=cells[family][first:last+1];assert len(frames)==last-first+1
        strip=Image.new('RGBA',(256*len(frames),256))
        for i,frame in enumerate(frames):
            assert frame.getbbox(),(name,i)
            strip.paste(frame,(i*256,0))
        strip.save(target/(name+'.png'))
        # Exact pixel identity is checked against each approved source cell.
        check=Image.open(target/(name+'.png')).convert('RGBA')
        assert all(check.crop((i*256,0,(i+1)*256,256)).tobytes()==frame.tobytes() for i,frame in enumerate(frames))
        coverage[family].update(range(first,last+1))
        points={'core':cores[family][first:last+1]}
        if family in anchors:
            key='antler' if family in ['charge','rear_gore'] else 'hoof'
            points[key]=[anchors[family][min(i,len(anchors[family])-1)] for i in range(first,last+1)]
        clips[name]={'file':name+'.png','count':len(frames),'pivot':pivots[family],
                     'fps':12,'loop':name in LOOPS,'anchors':points,
                     'source':family,'source_first':first,'source_last':last}
    assert all(coverage[name]==set(range(len(frames))) for name,frames in cells.items())
    families={name:{part:name+'_'+part for part in parts} for name,parts in SEGMENTS.items()}
    families.update({'charge_run':{'ING':'charge_run_ING'},
                     'uppercut':{'START':'uppercut_START','ING':'uppercut_ING','END':'uppercut_END'},
                     'flick_sweep':{'ING':'flick_sweep_ING'},
                     'flick_lift':{'START':'flick_lift_START','ING':'flick_lift_ING','END':'flick_lift_END'}})
    data={'version':1,'clips':clips,'families':families,'exceptions':{
        'idle':'Pure breathing loop; only ING.', 'walk':'Pure walking loop; only ING.',
        'bind_push':'Source F06-F31 stays low. No authored END; explicitly reuse thrust_END when releasing.',
        'death':'F00-F11 ends lying down. Original F12-F15 are separate getup, not death recovery.'}}
    (target/'library.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    # Explicit resource dependencies also include every physical PNG in scene-only exports.
    resource=f'[gd_resource type="Resource" load_steps={len(clips)+1} format=3]\n\n'
    for i,(name,clip) in enumerate(clips.items()):
        resource+=f'[ext_resource type="Texture2D" path="res://assets/bosses/deer/body/boss/actions/{clip["file"]}" id="{i+1}"]\n'
    resource+='\n[resource]\nmetadata/library_json = '+json.dumps(json.dumps(data,ensure_ascii=False),ensure_ascii=False)+'\n'
    resource+='metadata/textures = {\n'+',\n'.join(json.dumps(name)+f': ExtResource("{i+1}")' for i,name in enumerate(clips))+'\n}\n'
    (target/'library.tres').write_text(resource,encoding='utf-8')
    audit={'sources':{name:{'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'frames':len(cells[name])} for name,path in sources.items()},
           'clips':{name:{k:v for k,v in clip.items() if k!='anchors'} for name,clip in clips.items()},'exceptions':data['exceptions']}
    (args.output/'audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
    migrate_painted(project)
    print(f'PASS: {len(cells)} action sources, {sum(len(f) for f in cells.values())} frames reviewed/covered, {len(clips)} independent PNG clips; source pixels unchanged')


if __name__=='__main__':main()
