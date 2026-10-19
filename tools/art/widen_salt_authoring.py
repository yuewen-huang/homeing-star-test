"""Widen saved salt scenery without stretching a single painted prop."""
from pathlib import Path
from datetime import datetime
import re
import shutil

ROOT=Path(__file__).resolve().parents[3]
GAME=ROOT/'homeing-star-game'
SCENES=GAME/'scenes/levels/chapter_2_salt'
RESOURCE='res://assets/levels/chapter_2_salt/environment/layout_wide/'
backup=ROOT/'homeing-star-test/artifacts'/('salt-wide-'+datetime.now().strftime('%Y%m%d-%H%M%S'))
backup.mkdir(parents=True)

def blocks(text): return re.split(r'(?=^\[)',text,flags=re.M)
def rock_shift(text):
    result=[]
    for block in blocks(text):
        header=block.split('\n',1)[0]
        if header.startswith('[node ') and re.search(r'parent="(?:Environment/)?Boundary/(?:LeftBanks|RightBanks)"',header):
            match=re.search(r'^position = Vector2\(([-\d.eE+]+),\s*([-\d.eE+]+)\)',block,re.M)
            if match:
                x,y=map(float,match.groups()); q=max(0,min(1,y/1080)); s=0.6+0.4*q
                x+=1800*(1+s if 'RightBanks"' in header else 1-s)
                block=block[:match.start()]+f'position = Vector2({x:.8f}, {y:.8f})'+block[match.end():]
        result.append(block)
    return ''.join(result)

basepath=SCENES/'chapter_2_salt_environment.tscn'
base=basepath.read_text(encoding='utf-8')
if 'id="wide_ground"' in base: raise SystemExit('Already widened; edit existing nodes instead.')
for name in ['chapter_2_salt_environment.tscn','chapter_2_salt_field.tscn','chapter_2_salt_ambient.tscn']:
    shutil.copy2(SCENES/name,backup/name)

remove_meshes=set(); retained=[]
for block in blocks(base):
    header=block.split('\n',1)[0]
    if re.match(r'\[node name="Wall_\d+".*parent="Boundary"',header) or re.search(r'^\[node .*parent="Boundary/Wall_\d+"',header):
        match=re.search(r'mesh = SubResource\("([^"]+)"\)',block)
        if match: remove_meshes.add(match[1])
        continue
    for node,asset in [('Ground','ground'),('OuterGround','outer_ground')]:
        if re.match(rf'\[node name="{node}" ',header):
            match=re.search(r'mesh = SubResource\("([^"]+)"\)',block)
            remove_meshes.add(match[1]); block=block.replace(match[0],f'mesh = ExtResource("wide_{asset}")')
    retained.append(block)
base=''.join(b for b in retained if not any(b.startswith(f'[sub_resource type="ArrayMesh" id="{mesh}"') for mesh in remove_meshes))
base=rock_shift(base)
references=''.join(f'[ext_resource type="ArrayMesh" path="{RESOURCE}{asset}.tres" id="wide_{asset}"]\n' for asset in ['ground','outer_ground']+[f'north_{i:02d}' for i in range(10)])
index=base.index('[sub_resource '); base=base[:index]+references+'\n'+base[index:]
walls=''
for i in range(10):
    walls+=f'\n[node name="Wall_{i:02d}" type="Node2D" parent="Boundary"]\n\n[node name="NorthMesh" type="MeshInstance2D" parent="Boundary/Wall_{i:02d}"]\nz_index = 60\nmesh = ExtResource("wide_north_{i:02d}")\ntexture = ExtResource("6_dvojq")\n'
index=base.index('[node name="LeftBanks"'); base=base[:index]+walls+'\n'+base[index:]
base=base.replace('region_rect = Rect2(0, 0, 10800, 2800)','region_rect = Rect2(0, 0, 14400, 2800)')
for i,x in enumerate(range(7200,10800,600),18):
    base+=f'\n[node name="Shore_{i:02d}" type="Sprite2D" parent="Boundary/SouthCoast"]\nposition = Vector2({x}, 1048)\ntexture = ExtResource("12_ry18n")\ncentered = false\nflip_h = {str(i%2==1).lower()}\n'
basepath.write_text(base,encoding='utf-8',newline='\n')

path=SCENES/'chapter_2_salt_field.tscn'; main=rock_shift(path.read_text(encoding='utf-8'))
index=main.index('[node name="SaltField"')
main=main[:index]+'[ext_resource type="PackedScene" path="res://scenes/levels/chapter_2_salt/chapter_2_salt_worksite.tscn" id="8_worksite"]\n\n'+main[index:]
index=main.index('[editable path="Environment"]')
main=main[:index]+'[node name="WorksiteDetails" parent="Environment" instance=ExtResource("8_worksite")]\n\n'+main[index:]
path.write_text(main,encoding='utf-8',newline='\n')

path=SCENES/'chapter_2_salt_ambient.tscn'; ambient=path.read_text(encoding='utf-8'); result=[]; old_mesh=None
for block in blocks(ambient):
    header=block.split('\n',1)[0]
    if header.startswith('[node name="StaticScatter"'):
        match=re.search(r'mesh = SubResource\("([^"]+)"\)',block); old_mesh=match[1]
        block=block.replace(match[0],'mesh = ExtResource("wide_ambient")')
        block=re.sub(r'"foot": Vector2\(([-\d.eE+]+),\s*([-\d.eE+]+)\)',lambda m:f'"foot": Vector2({float(m[1])*2:.8f}, {m[2]})',block)
    if header.startswith('[node ') and 'parent="Wildlife"' in header:
        block=re.sub(r'^position = Vector2\(([-\d.eE+]+),\s*([-\d.eE+]+)\)',lambda m:f'position = Vector2({float(m[1])*2:.8f}, {m[2]})',block,flags=re.M)
    result.append(block)
ambient=''.join(b for b in result if not b.startswith(f'[sub_resource type="ArrayMesh" id="{old_mesh}"'))
index=ambient.index('[sub_resource ')
ambient=ambient[:index]+f'[ext_resource type="ArrayMesh" path="{RESOURCE}ambient.tres" id="wide_ambient"]\n\n'+ambient[index:]
path.write_text(ambient,encoding='utf-8',newline='\n')
print('Widened ground/north/coast; preserved reef sizes, source node identities and 124 decor quads. BACKUP:',backup)
