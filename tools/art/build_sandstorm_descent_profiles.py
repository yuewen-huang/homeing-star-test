"""Editable Studio quake recipes; production uses frames baked by Godot's renderer."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
STUDIO = ROOT / 'combat-vfx-studio'
GAME = ROOT / 'homeing-star-game'

def main():
    common = dict(t=0, do='quake', x=640, y=520, unit='earth', form='surge',
                  mode='radial', perspective=.16, travel=.065, ease=.8,
                  strength=1.1, body=False, flash=0, shake=0, wave=False,
                  dust=True, dust_color='c9ad79', seed=83,
                  ramp=['211b15', '4d3926', '87643e', 'c6a271', 'ead2a1'])
    recipes = {
        'descent_quake': dict(common, width=180, cracks=True, crack_amount=2,
                              crack_time=.45, crack_glow=0, debris='stone',
                              unit_size=.7, spacing=22, debris_density=.2, debris_height=24,
                              dust_height=18, dust_spread=48, dust_density=.75, dust_time=.30),
        'tiger_quake': dict(common, width=360, cracks=True, crack_amount=2.5,
                            crack_time=.50, crack_glow=0, debris='stone',
                            unit_size=.8, spacing=24, debris_density=.3, debris_height=30,
                            dust_height=25, dust_spread=35, dust_density=.9, dust_time=.34),
    }
    for key, event in recipes.items():
        name = 'sandstorm_' + key
        title = '蝎女·落地震沙' if key == 'descent_quake' else '蝎女·伏虎重震'
        folder = STUDIO / 'combos' / name
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'combo.json').write_text(json.dumps(dict(name=title, events=[event]), ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        (folder / 'style.json').write_text(json.dumps(dict(language='zh', renderer='quake', quake_style='cel', quake_detail='balanced', pixel=2, title=title), ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        (folder / 'prompt.md').write_text('蝎女技能1：连续5次垂直砸落，小范围地震；未命中后短暂停顿、原地化沙。使用特效编辑器地震模块，禁止额外自绘效果。\n', encoding='utf-8')
        (folder / (name+'.tscn')).write_text('[gd_scene format=3]\n\n[ext_resource type="Script" path="res://vfx/combo_player.gd" id="1"]\n\n[node name="ComboPlayer" type="Node2D"]\nscript = ExtResource("1")\ncombo_file = "res://combos/'+name+'/combo.json"\nstyle_file = "res://combos/'+name+'/style.json"\n', encoding='utf-8')
    build_sand()
    # Offline silhouette bottoms: only vertical foot registration, never centroid tracking.
    from PIL import Image
    bottoms = {}
    for action, file in [('跳跃落地', 'jump_land_256x256_14f.png'), ('伏虎霸王拳', 'tiger_punch_256x256_16f.png')]:
        image = Image.open(GAME / 'assets/bosses/sandstorm_fighter/body' / file)
        columns = image.width // 256
        count = 14 if action == '跳跃落地' else 16
        bottoms[action] = [image.crop(((i%columns)*256,(i//columns)*256,(i%columns+1)*256,(i//columns+1)*256)).getbbox()[3] for i in range(count)]
    target = GAME / 'assets/bosses/sandstorm_fighter/data/descent_skill.json'
    target.write_text(json.dumps(dict(drop_count=5, source_frame_numbers='one_based', charge_frames=[5,6,7], fall_frames=[8,9], landing_frame=10, frame_bottoms=bottoms), ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def build_sand():
    from PIL import Image
    import numpy as np
    ramp = ['35271d', '735737', 'ac8450', 'd4b57a', 'e0c794']
    grain = dict(t=0, do='swarm', material='sand', count=2800, size=.9, sand_grain=.65,
                 sand_dust=0, sand_settle=.2, look='mirror', ramp=ramp,
                 swirl=1.4, turbulence=8, tumble=0, fade_in=.025, fade_out=.24)
    pose_specs = [('idle','jump_land_256x256_14f.png',0,128),('land','jump_land_256x256_14f.png',9,128),('punch','tiger_punch_256x256_16f.png',10,50)]
    poses = {}
    for key, name, frame, foot_x in pose_specs:
        sheet = Image.open(GAME/'assets/bosses/sandstorm_fighter/body'/name)
        columns = sheet.width//256
        tile = sheet.crop(((frame%columns)*256,(frame//columns)*256,(frame%columns+1)*256,(frame//columns+1)*256))
        pixels = np.array(tile)
        ys,xs = np.nonzero(pixels[:,:,3]>128)
        rng = np.random.default_rng(83)
        samples = rng.choice(len(xs),64,replace=False)
        bottom = tile.getbbox()[3]
        poses[key] = [[round((int(xs[i])-foot_x)*1.1862,3),round((int(ys[i])-bottom)*1.1862,3),1,0,2.37,2.37] for i in samples]
        folder = ROOT/'homeing-star-test/artifacts/sandstorm-skill/erosion'/key
        folder.mkdir(parents=True,exist_ok=True)
        yy,xx = np.mgrid[:256,:256]
        # Small stable pixel clusters vanish across the body, exposing the sand particles.
        noise = ((xx//2*73856093) ^ (yy//2*19349663))%997/997
        threshold = .025 + .15*(.55*noise+.45*yy/256)
        for i in range(13):
            rgba=pixels.copy();rgba[:,:,3]=np.where(i/60>=threshold,0,pixels[:,:,3])
            rendered=Image.fromarray(rgba).resize((304,304),Image.Resampling.NEAREST)
            canvas=Image.new('RGBA',(512,384));canvas.paste(rendered,(round(256-foot_x*1.1862),round(300-bottom*1.1862)),rendered)
            canvas.save(folder/f'frame_{i:03d}.png')
    event=dict(grain,id='sandstorm_dissipate',form='peel',at=[640,520],time=.18,linger=.48,peel_segments=poses['land'])
    write_swarm('sandstorm_dissipate','蝎女·散沙消失',event,{'pose_segments':poses})
    # This path is the same accelerating vertical trajectory as the body, offset to its torso.
    path=[[640,520-420-80+420*(i/11)**2.6] for i in range(12)]
    event=dict(grain,id='sandstorm_drop_trail',form='stream',at=[640,520],count=4800,size=1.1,
               path=path,time=0,travel=.166,linger=.19,length=.72,width=21,
               turbulence=4,swirl=.5,hold_path_end=True,stream_taper=1,fade_in=.016,fade_out=.19)
    write_swarm('sandstorm_drop_trail','蝎女·下砸沙痕',event,{})

def write_swarm(name,title,event,extra):
    folder=STUDIO/'combos'/name;folder.mkdir(parents=True,exist_ok=True)
    (folder/'combo.json').write_text(json.dumps(dict(name=title,events=[event],**extra),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (folder/'style.json').write_text(json.dumps(dict(language='zh',renderer='quake',quake_style='pixel',quake_detail='fine',pixel=1,title=title),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (folder/'prompt.md').write_text('使用群体的砂砾材质，细尘比例为零。消散从原身体透明轮廓剥离小沙粒；下砸沿实际竖直加速轨迹留沙痕。不使用烟球或刀光。\n',encoding='utf-8')
    (folder/(name+'.tscn')).write_text('[gd_scene format=3]\n\n[ext_resource type="Script" path="res://vfx/combo_player.gd" id="1"]\n\n[node name="ComboPlayer" type="Node2D"]\nscript = ExtResource("1")\ncombo_file = "res://combos/'+name+'/combo.json"\nstyle_file = "res://combos/'+name+'/style.json"\n',encoding='utf-8')

if __name__ == '__main__':
    main()
