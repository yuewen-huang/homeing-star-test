"""Export the approved shared impact Aseprite clips into game SpriteFrames."""
from pathlib import Path
import argparse
import json
from PIL import Image
from aseprite_rgba_reader import read, layer_frame

ROOT=Path(__file__).resolve().parents[2]
MAPPING={
    '01_青白格反':'parry', '02_红反':'red_parry', '03_破韧':'poise_break',
    '04_失衡小红命中':'broken_hit', '05_普通命中小火花':'normal_hit',
}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--art',type=Path,default=ROOT/'homeing-star-temp-assert/Art/命中反馈_精修稿_20261012')
    parser.add_argument('--game',type=Path,default=ROOT/'homeing-star-game')
    args=parser.parse_args()
    output=args.game/'assets/sideview/effects/combat_feedback'
    output.mkdir(parents=True,exist_ok=True)
    records=[]
    for name,animation in MAPPING.items():
        document=read(args.art/f'{name}.aseprite')
        assert document['canvas']==(128,128)
        layers=[i for i,layer in enumerate(document['layers'])
                if layer['visible'] and layer['name'] in ('生成稿_可修改','精修补画')]
        assert layers, name
        frames=[];durations=[]
        for index,frame in enumerate(document['frames']):
            result=Image.new('RGBA',document['canvas'])
            for layer in layers:
                image,opacity=layer_frame(document,index,layer)
                if opacity!=1.0:
                    image.putalpha(image.getchannel('A').point(lambda a:round(a*opacity)))
                result.alpha_composite(image)
            frames.append(result);durations.append(frame['duration_ms'])
        strip=Image.new('RGBA',(128*len(frames),128))
        for index,frame in enumerate(frames):strip.paste(frame,(128*index,0))
        strip.save(output/f'{animation}.png')
        records.append({'animation':animation,'source':name+'.aseprite',
            'frame_count':len(frames),'frame_durations_ms':durations})
    lines=[f'[gd_resource type="SpriteFrames" load_steps={6+sum(r["frame_count"] for r in records)} format=3]','']
    for i,record in enumerate(records,1):
        lines += [f'[ext_resource type="Texture2D" path="res://assets/sideview/effects/combat_feedback/{record["animation"]}.png" id="{i}"]','']
    for i,record in enumerate(records,1):
        for frame in range(record['frame_count']):
            lines += [f'[sub_resource type="AtlasTexture" id="{record["animation"]}_{frame}"]',
                f'atlas = ExtResource("{i}")',f'region = Rect2({128*frame}, 0, 128, 128)','']
    animations=[]
    for record in records:
        frames=',\n'.join('{'+'\n"duration": '+str(ms)+'.0,\n"texture": SubResource("'+record['animation']+'_'+str(i)+'")\n}'
                           for i,ms in enumerate(record['frame_durations_ms']))
        animations.append('{\n"frames": ['+frames+'],\n"loop": false,\n"name": &"'+record['animation']+'",\n"speed": 1000.0\n}')
    lines += ['[resource]','animations = ['+',\n'.join(animations)+']','']
    (output/'impact_frames.tres').write_text('\n'.join(lines),encoding='utf-8')
    (output/'art_manifest.json').write_text(json.dumps({'canvas':[128,128],
        'pivot':[64,64],'world_scale':1.4,'clips':records},ensure_ascii=False,indent=2),encoding='utf-8')
    print('PASS Exported shared impact art: 5 animations, '+str(sum(r['frame_count'] for r in records))+' frames; source pivots and durations preserved.')

if __name__=='__main__':main()
