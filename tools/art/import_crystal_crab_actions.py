"""Export native Aseprite body layers and authored ground guides."""
from pathlib import Path
import hashlib
import json
import sys
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from aseprite_rgba_reader import read, layer_frame

WORKSPACE = Path(__file__).resolve().parents[3]
DEST = WORKSPACE/'homeing-star-game/assets/sideview/characters/crystal_crab/boss/actions'
SPECS = {'idle':'待机','walk':'走路','left_slam':'左砸','right_slam':'右砸','double_slam':'双砸','burrow':'钻地-移动-出现'}

def main():
    manifest = {'version':2,'source_type':'native_aseprite','frame_size':[256,256],'pivot_x':128,'ground_reference':'authored horizontal guide layer','actions':{}}
    clips = []
    total = 0
    for action,label in SPECS.items():
        entry = {'label':label,'count':0,'segments':{}}
        for part in ['START','ING','END']:
            clip = action+'_'+part
            source = DEST/(clip+'.aseprite')
            source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
            document = read(source)
            assert document['canvas']==(256,256), (source,'unexpected canvas')
            names = [layer['name'] for layer in document['layers']]
            assert len(names)==2 and names.count('Sprite Sheet')==1, (source,names)
            body_index = names.index('Sprite Sheet')
            guide_index = 1-body_index
            frames,ground_y,durations = [],[],[]
            for index,frame in enumerate(document['frames']):
                body,opacity = layer_frame(document,index,body_index)
                guide,guide_opacity = layer_frame(document,index,guide_index)
                assert opacity==guide_opacity==1.0, (source,index,'unsupported opacity')
                bounds = guide.getbbox()
                assert bounds is not None and bounds[0]==0 and bounds[2]==256 and bounds[3]-bounds[1]==1, (source,index,'expected one horizontal ground line')
                assert body.getbbox() is not None, (source,index,'empty body frame')
                frames.append(body)
                ground_y.append(bounds[1])
                durations.append(frame['duration_ms'])
            count = len(frames)
            strip = Image.new('RGBA',(count*256,256))
            for index,frame in enumerate(frames): strip.paste(frame,(index*256,0))
            strip.save(DEST/(clip+'.png'))
            check = Image.open(DEST/(clip+'.png')).convert('RGBA')
            for index,frame in enumerate(frames):
                assert check.crop((index*256,0,(index+1)*256,256)).tobytes()==frame.tobytes()
            assert hashlib.sha256(source.read_bytes()).hexdigest()==source_hash
            ends,cumulative = [],0
            for duration in durations:
                cumulative += duration
                ends.append(cumulative/1000)
            spec = {'clip':clip,'source':source.name,'source_sha256':source_hash,'body_layer':names[body_index],'guide_layer':names[guide_index],'count':count,'source_start':entry['count'],'ground_y':ground_y,'durations_ms':durations,'frame_ends':ends,'duration':cumulative/1000,'fps':count*1000/cumulative}
            entry['segments'][part] = spec
            entry['count'] += count
            clips.append(spec)
            print(clip,count,'frames; authored ground',sorted(set(ground_y)),flush=True)
        total += entry['count']
        manifest['actions'][action] = entry
    (DEST/'library.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    script = ['class_name CrystalCrabActionLibrary','extends RefCounted','','## Generated from native Aseprite bodies. Ground guides never enter textures.','const FRAME_SIZE := Vector2(256,256)','const PIVOT := Vector2(128,192)','const ACTIONS: Array[StringName] = [&"idle", &"walk", &"left_slam", &"right_slam", &"double_slam", &"burrow"]','const LABELS := {']
    for action,label in SPECS.items(): script.append(f'\t&"{action}": "{label}",')
    script += ['}','const CLIPS := {']
    for spec in clips:
        clip = spec['clip']
        fields = [f'"texture": preload("res://assets/sideview/characters/crystal_crab/boss/actions/{clip}.png")']
        for key in ['count','source_start','fps','ground_y','durations_ms','frame_ends','duration']:
            fields.append(f'"{key}": {json.dumps(spec[key])}')
        script.append(f'\t&"{clip}": {{'+', '.join(fields)+'},')
    script += ['}','','static func parts(action: StringName) -> Array[StringName]:','\treturn [StringName(String(action)+"_START"), StringName(String(action)+"_ING"), StringName(String(action)+"_END")]','','static func duration(clip: StringName) -> float:','\treturn float(CLIPS[clip].duration)','','static func frame_at(clip: StringName, seconds: float) -> int:','\tvar ends: Array = CLIPS[clip].frame_ends','\tfor index in ends.size():','\t\tif seconds+0.00000001<float(ends[index]): return index','\treturn ends.size()-1','','static func build_frames() -> SpriteFrames:','\tvar frames := SpriteFrames.new()','\tframes.remove_animation(&"default")','\tfor clip: StringName in CLIPS:','\t\tvar spec: Dictionary = CLIPS[clip]','\t\tframes.add_animation(clip)','\t\tframes.set_animation_loop(clip,false)','\t\tframes.set_animation_speed(clip,spec.fps)','\t\tfor index in int(spec.count):','\t\t\tvar texture := AtlasTexture.new()','\t\t\ttexture.atlas = spec.texture','\t\t\ttexture.region = Rect2(Vector2(index*256,0),FRAME_SIZE)','\t\t\tframes.add_frame(clip,texture,float(spec.durations_ms[index])/1000*float(spec.fps))','\treturn frames','']
    (WORKSPACE/'homeing-star-game/scripts/sideview/crystal_crab_action_library.gd').write_text('\n'.join(script),encoding='utf-8')
    print(f'Verified {total} native body frames in {len(clips)} segments; guides excluded, authored timing/ground preserved.')

if __name__=='__main__': main()
