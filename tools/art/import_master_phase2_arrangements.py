"""Import approved phase-two body arrangements and editable studio tracks.

First run smear-combo-demo/tools/export_phase2_bridge.gd with that Godot project.
The bridge is generated from the frozen, user-approved combo annotations.
"""
from pathlib import Path
import argparse
import json
import shutil

ROOT = Path(__file__).resolve().parents[3]
def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def build(bridge, force=False):
    source = json.loads(bridge.read_text(encoding='utf-8-sig'))
    game = ROOT / 'homeing-star-game'
    studio = ROOT / 'combat-vfx-studio'
    smear = ROOT / 'smear-combo-demo'
    if not force:
        for combo in source['combos']:
            if (studio/'combos'/combo['id']/'combo.json').exists():
                raise SystemExit('Refusing to overwrite Studio tuning; use --force only for an intentional re-import.')
    names = {'05_攻击一_attack_1_attack_1': ('attack_1',256,256,16),
             '06_攻击二_attack_2_attack_2': ('attack_2',300,350,32),
             '07_特殊攻击_special_attack_special_attack': ('special_attack',380,300,24),
             '08_冲刺_dash_dash': ('dash',384,384,16),
             '09_上挑_uppercut_uppercut': ('uppercut',350,350,16)}
    body = {'version':1, 'source_sha256':source['combos'][0]['source_sha256'], 'moves':{}}
    for combo in source['combos']:
        move = {'title':combo['title'],'scale':2.0,'duration':0,'clips':[]}
        graph = {'version':1,'name':'师傅二阶段 · '+combo['title'],'nodes':[],'edges':[]}
        for ci, clip in enumerate(combo['clips']):
            stem,w,h,n = names[clip['action']]
            image_name = f'{stem}_{w}x{h}_{n}f.png'
            asset = f'assets/characters/master_phase2/{image_name}'
            dest = studio/asset
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(game/'assets/bosses/master/body/boss/phase2'/image_name, dest)
            out = {k:clip[k] for k in ['label','start_time','duration','feet','cell']}
            out.update(animation='phase_2_'+stem,frames=n,groups=[])
            events = [{'t':0,'do':'body_reference','texture':'res://'+asset,'cell':[w,h],
                       'frames':n,'feet':clip['feet'],'scale':2.0,'source_from':clip['start_time'],
                       'duration':clip['duration'],'label':clip['label'],'origin':[430,520]}]
            group_indices = {}
            hit_owners = {}
            for ei, e in enumerate(clip['events']):
                t = round(e['release']-clip['start_time'],8)
                uid = f'track_{ci}_{ei}'
                if e['kind'] == 'quake':
                    px,py = [(p-f)*2+o for p,f,o in zip(e['point'],clip['feet'],[430,520])]
                    events.append({'t':t,'do':'quake','unit':'earth','mode':e['settings'].get('mode','radial'),
                                   'x':px,'y':py,'_annotation':e,'label':e['name'],'_authored_quake':True})
                    # Ground propagation is tuned in Studio, not an invisible ranged attack in game.
                    continue
                if e['group'] not in group_indices:
                    group_indices[e['group']] = len(out['groups'])
                    out['groups'].append({'id':str(e['group']),'members':[]})
                out['groups'][group_indices[e['group']]]['members'].append(
                    {'release':e['release'],'end':e['end'],'samples':e['collision_samples']})
                raw = {k:v for k,v in e.items() if k!='collision_samples'}
                raw.update(t=t,do='slash',duration=e['end']-e['release'],tail=e['fade_end']-e['end'],
                           contact=(e['contact']-e['release'])/(e['end']-e['release']),
                           fingers=e['settings'].get('fingers',3),palette='normal',
                           authored_curve=e['curve'],curve_feet=clip['feet'],curve_scale=2.0,curve_origin=[430,520],
                           _editor_id=uid,_editor_follow=True,label=e['name'])
                events.append(raw)
                current = hit_owners.get(e['group'])
                if current is None or e['contact']<current[0]: hit_owners[e['group']] = (e['contact'],uid)
            for contact,owner in hit_owners.values():
                events.append({'t':round(contact-clip['start_time'],8),'do':'hit','push':0,'stop':0.055,'shake':0,'spark':0,
                               '_editor_source':owner,'_authored_contact':True})
            owners = {owner for _, owner in hit_owners.values()}
            for event in events:
                if 'authored_curve' in event: event['_editor_follow'] = event['_editor_id'] in owners
            # Quake owns its actual arrival/hit in the native ground renderer.
            events.sort(key=lambda e:e['t'])
            node_id = f'body_{ci+1}'
            graph['nodes'].append({'id':node_id,'title':clip['label'],'category':'blade',
                                   'data':{'name':clip['label'],'events':events},'style':{'renderer':'claw','language':'zh'},
                                   'position':[80+ci*340,100],'delay':0,'join':'after','span':clip['duration']})
            if ci: graph['edges'].append({'from':f'body_{ci}','to':node_id})
            move['clips'].append(out)
            move['duration'] += clip['duration']
        body['moves'][combo['id']] = move
        folder = studio/'combos'/combo['id']
        style = json.loads((smear/'styles/default.json').read_text(encoding='utf-8-sig')) if (smear/'styles/default.json').exists() else {}
        style.update(title=graph['name'],language='zh',renderer='flow',flow_stage='melee')
        compiled = []
        elapsed = 0
        for node in graph['nodes']:
            for event in node['data']['events']:
                compiled.append(dict(event,t=elapsed+event['t'],_flow_node=node['id'],_flow_renderer='claw',_flow_style=node['style'],_flow_order=len(compiled)))
            elapsed += node['span']
        compiled.sort(key=lambda e:(e['t'],e['_flow_order']))
        write(folder/'combo.json',{'name':graph['name'],'source_sha256':combo['source_sha256'],'events':compiled,'_flow':graph})
        write(folder/'style.json',style)
        (folder/(combo['id']+'.tscn')).write_text('[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://vfx/combo_player.gd" id="1"]\n\n[node name="ComboPlayer" type="Node2D"]\nscript = ExtResource("1")\ncombo_file = "res://combos/'+combo['id']+'/combo.json"\nstyle_file = "res://combos/'+combo['id']+'/style.json"\n',encoding='utf-8')
        (folder/'prompt.md').write_text('师傅二阶段 · '+combo['title']+'。沿用已确认的身体切片、手绘曲线、时间标记及双爪命中分组；地震只导入触发点和传播方式。进入流程图，双击招式精调。身体仅作参考，不烘焙特效。\n',encoding='utf-8')
    write(game/'assets/bosses/master/body/boss/phase2/arrangements.json',body)
    print('Imported 3 AI body combos; 5 body references and exact editable curve tracks into Studio.')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--bridge',type=Path,default=ROOT/'smear-combo-demo/.local-data/phase2_bridge.json')
    parser.add_argument('--force',action='store_true')
    args=parser.parse_args()
    build(args.bridge,args.force)
