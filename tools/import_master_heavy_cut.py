"""Append the new master cut without regenerating existing approved action atlases."""
from pathlib import Path
import json,hashlib,subprocess
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'homeing-star-temp-assert/PendingArt/character/师傅优化计划/new-attack.aseprite'
DEST=ROOT/'homeing-star-game/assets/bosses/master/body/boss/phase1'
AUDIT=ROOT/'.artifacts/master-phase1-plan-20261020'
def main():
    AUDIT.mkdir(parents=True,exist_ok=True)
    subprocess.run(['D:/Aseprite/Aseprite.exe','-b',str(SOURCE),'--format','json-array','--data',str(AUDIT/'new_attack.json'),'--sheet',str(AUDIT/'new_attack.png'),'--sheet-type','horizontal'],capture_output=True,timeout=45,creationflags=subprocess.CREATE_NO_WINDOW)
    meta=json.loads((AUDIT/'new_attack.json').read_text(encoding='utf-8')); records=meta['frames']
    image=Image.open(AUDIT/'new_attack.png').convert('RGBA');w,h=records[0]['sourceSize'].values()
    parts={'START':[0,1],'ING':[2,23],'END':[24,27]};ext=[];sub=[];animations=[];whole=[]
    for part,(a,b) in parts.items():
        clip='heavy_cut_'+part;columns=min(4,b-a+1);atlas=Image.new('RGBA',(w*columns,h*((b-a+columns)//columns)));entries=[]
        for local,i in enumerate(range(a,b+1)):
            rect=records[i]['frame'];native=image.crop((rect['x'],rect['y'],rect['x']+w,rect['y']+h));x,y=local%columns*w,local//columns*h
            atlas.paste(native,(x,y));ident=f'{clip}_{local}'
            sub.append(f'[sub_resource type="AtlasTexture" id="{ident}"]\natlas = ExtResource("{clip}")\nregion = Rect2({x}, {y}, {w}, {h})\n')
            entries.append('{"duration": %s, "texture": SubResource("%s")}'%(records[i]['duration']/1000,ident))
        path=DEST/'actions'/f'{clip}.png';atlas.save(path)
        check=Image.open(path).convert('RGBA')
        for local,i in enumerate(range(a,b+1)):
            r=records[i]['frame'];x,y=local%columns*w,local//columns*h
            assert check.crop((x,y,x+w,y+h)).tobytes()==image.crop((r['x'],r['y'],r['x']+w,r['y']+h)).tobytes()
        ext.append(f'[ext_resource type="Texture2D" path="res://assets/bosses/master/body/boss/phase1/actions/{clip}.png" id="{clip}"]\n')
        animations.append('{"frames": [%s], "loop": false, "name": &"%s", "speed": 1.0}'%(', '.join(entries),clip));whole+=entries
    animations.append('{"frames": [%s], "loop": false, "name": &"heavy_cut", "speed": 1.0}'%', '.join(whole))
    frames=DEST/'frames.tres';text=frames.read_text(encoding='utf-8')
    if 'id="heavy_cut_START"' not in text:
        import re
        text=re.sub(r'load_steps=(\d+)',lambda m:'load_steps='+str(int(m[1])+len(ext)+len(sub)),text,count=1)
        at=text.index('[sub_resource');text=text[:at]+'\n'.join(ext)+'\n'+text[at:]
        at=text.index('[resource]');text=text[:at]+'\n'.join(sub)+'\n'+text[at:]
        text=text.rstrip();assert text.endswith(']');text=text[:-1]+',\n'+',\n'.join(animations)+']\n';frames.write_text(text,encoding='utf-8')
    manifest=DEST/'manifest.json';data=json.loads(manifest.read_text(encoding='utf-8'))
    data['actions']['heavy_cut']={'source':SOURCE.name,'sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'frame_size':[w,h],'frame_count':28,'durations_ms':[r['duration'] for r in records],'tags':[],'slices':[],'parts':parts,'body_scale_compensation':1.28}
    manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    seg=ROOT/'homeing-star-game/scripts/bosses/master/master_phase1_segments.gd';s=seg.read_text(encoding='utf-8');s=s.replace('const PARTS := {','const PARTS := {"heavy_cut": '+json.dumps(parts)+', ',1) if '"heavy_cut"' not in s else s;seg.write_text(s,encoding='utf-8')
    print('Verified all 28 native pixels/frames; appended START / ING / END.')
if __name__=='__main__':main()
