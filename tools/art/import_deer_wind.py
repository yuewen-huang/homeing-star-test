"""Native Aseprite export + isolated, traceable Studio wind renderer import."""
from pathlib import Path
import hashlib, json, re, shutil, subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
GAME = ROOT / 'homeing-star-game'
STUDIO = ROOT / 'combat-vfx-studio'
ARCHIVE = ROOT / 'homeing-star-temp-assert/ProductionArt/deer/wind_human_20261106'
BODY = GAME / 'assets/bosses/deer/body/wind_human'
FX = GAME / 'scripts/bosses/deer/wind_studio'
ART = GAME / 'assets/bosses/deer/fx/wind_studio'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()

def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def bodies():
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    BODY.mkdir(parents=True, exist_ok=True)
    clips, audit = {}, []
    for source, action, segments in [('atak1','cast',[6,3,7]), ('atak2','core',[7,16,9]), ('change','change',[14,8,10])]:
        original = Path('D:/DownLoad/人形态') / (source+'.aseprite')
        archived = ARCHIVE / original.name
        shutil.copy2(original, archived)
        sheet, meta = ARCHIVE/(source+'.png'), ARCHIVE/(source+'.json')
        subprocess.run(['D:/Aseprite/Aseprite.exe','-b',str(original),'--sheet-type','horizontal','--sheet',str(sheet),'--format','json-array','--data',str(meta)], check=True)
        frames = json.loads(meta.read_text())['frames']
        img = Image.open(sheet).convert('RGBA')
        assert len(frames)==sum(segments)
        offset = 0
        for name, count in zip(['START','ING','END'], segments):
            key = action+'_'+name
            out = Image.new('RGBA',(256*count,256))
            for i in range(count):
                rect = frames[offset+i]['frame']
                cell = img.crop((rect['x'],rect['y'],rect['x']+256,rect['y']+256))
                out.paste(cell,(i*256,0))
                assert out.crop((i*256,0,(i+1)*256,256)).tobytes()==cell.tobytes()
            out.save(BODY/(key+'.png'))
            clips[key]={'file':key+'.png','count':count,'source_first':offset,'durations':[f['duration']/1000 for f in frames[offset:offset+count]]}
            offset += count
        assert sha(original)==sha(archived)
        audit.append({'source':str(original),'sha256':sha(original),'frames':len(frames),'pixel_preserving':True})
    write_json(BODY/'clips.json',{'root':[112,256],'scale':1.5,'clips':clips})
    write_json(ARCHIVE/'audit.json',audit)

def renderers():
    queue = ['magic/wind/puff.gd','magic/wind/tornado.gd','magic/wind/gust.gd','render_caps.gd']
    found = {}
    pattern = re.compile(r'res://vfx/([\w./-]+\.(?:gdshaderinc|gdshader|gd|png))')
    while queue:
        rel = queue.pop()
        if rel in found: continue
        p = STUDIO/'vfx'/rel
        data = p.read_text(encoding='utf-8')
        found[rel] = data
        queue.extend(pattern.findall(data))
    # MagicArt loads shader names dynamically, including includes.
    for p in (STUDIO/'vfx/magic/shaders').iterdir():
        if p.suffix in ('.gdshader','.gdshaderinc'):
            found['magic/shaders/'+p.name]=p.read_text(encoding='utf-8')
    audit=[]
    for rel, data in found.items():
        dest=(FX if rel.endswith('.gd') else ART)/rel
        data=re.sub(r'^class_name .*\n','',data,flags=re.M)
        data=data.replace('var stage: ComboStage','var stage: Node2D')
        data=data.replace('const GROUND_Y := 520.0','const GROUND_Y := 555.0')
        if 'RenderCaps.' in data and rel!='render_caps.gd':
            data += '\nconst RenderCaps = preload("res://scripts/bosses/deer/wind_studio/render_caps.gd")\n'
        if rel=='magic/wind/tornado.gd':
            data=re.sub(r'\tif age < stop and age > charge \* 0.6:.*?(?=\t_debris)', '', data, flags=re.S)
        data=pattern.sub(lambda m:'res://'+str((FX if m[1].endswith('.gd') else ART).relative_to(GAME)).replace('\\','/')+'/'+m[1],data)
        data=data.replace('res://vfx/magic/shaders/%s.gdshader','res://assets/bosses/deer/fx/wind_studio/magic/shaders/%s.gdshader')
        dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_text(data,encoding='utf-8')
        audit.append({'source':'vfx/'+rel,'source_sha256':sha(STUDIO/'vfx'/rel),'runtime':str(dest.relative_to(GAME)).replace('\\','/'),'runtime_sha256':sha(dest)})
    write_json(ART/'import_manifest.json',{'adaptations':['namespaced resource paths','remove global class names','stage uses Node2D proxy','floor 555','remove Studio dummy tornado control; gameplay owns capture'],'files':audit})

def profiles():
    recipes={
      'leaves':dict(name='鹿四阶段 · 三叶',events=[dict(t=i*.21,do='cast',element='wind',path='wave',wave=[65,-90,38][i],turns=1,charge=.16,travel=[1.25,1.65,.95][i],size=1.65,radius=42,start=[340,330],end=[1020,480]) for i in range(3)],gameplay=dict(damage=[18,18,26],flight=[1.25,1.65,.95],interval=.21,reach=1050,leaf_size=82,return_time=1.1)),
      'tornado':dict(name='鹿四阶段 · 合风根林',events=[dict(t=0,do='cast',element='wind',path='stay',start=[x,555],charge=.8,travel=6.8,size=1.0,radius=100) for x in [95,1085]],gameplay=dict(duration=7.6,damage=24,root_damage=28,throw_speed=620,throw_lift=620)),
      'meteors':dict(name='鹿四阶段 · 风陨',events=[dict(t=i*.38,do='cast',element='wind',start=[340+i*85,-30],end=[340+i*85,530],path='straight',charge=.48,travel=.34,size=1.4,radius=78) for i in range(7)],gameplay=dict(count=7,interval=.38,storm_life=4.5,storm_radius=64,damage=22)),
      'phantom':dict(name='鹿四阶段 · 鹿闪',events=[dict(t=0,do='cast',element='wind',start=[120,460],end=[1080,460],path='straight',charge=.65,travel=.46,size=2.0,radius=70)],gameplay=dict(damage=24,tail_damage=20,tail_life=2.5,tail_spacing=125)),
      'core':dict(name='鹿四阶段 · 九叠风核',events=[dict(t=0,do='cast',element='wind',start=[380,300],end=[710,450],path='arc',arc=70,charge=1.7,travel=.36,size=4.6,radius=145)],gameplay=dict(contacts=9,interval=.22,damage=16,explosion_damage=24,explosion_interval=.24,radius=135))
    }
    for key, recipe in recipes.items():
        folder=STUDIO/'combos'/('deer_wind_'+key)
        # Once seeded, the editor is authoritative. Reimport must preserve later edits.
        if (folder/'combo.json').exists():
            recipe=json.loads((folder/'combo.json').read_text(encoding='utf-8'))
        else:
            write_json(folder/'combo.json',recipe)
        if not (folder/'style.json').exists():
            write_json(folder/'style.json',dict(title=recipe['name'],language='zh',renderer='magic',magic_quality='ultimate',pixel=2,thickness=1))
        scene=(STUDIO/"combos/wind_blade/wind_blade.tscn").read_text(encoding="utf-8").replace("wind_blade","deer_wind_"+key)
        (folder/('deer_wind_'+key+'.tscn')).write_text(scene, encoding='utf-8')
        write_json(ART/(key+'.json'),recipe)
    write_json(ART/'profiles_manifest.json',{'profiles':[{'key':k,'source':'combos/deer_wind_'+k+'/combo.json','sha256':sha(STUDIO/'combos'/('deer_wind_'+k)/'combo.json')} for k in recipes]})

if __name__=='__main__':
    bodies(); renderers(); profiles()
    print('Imported 80 original cells, 9 physical segments, Studio wind renderer and 5 editable recipes.')
