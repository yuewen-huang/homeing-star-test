"""Write the authored whole-map traversal overlay. Coordinates are in 64 px cells.

Each route has an explicit rhythm and connection to the accepted macro outline.
There is deliberately no universal shaft subdivision / automatic ladder fill.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TARGET = ROOT / 'homeing-star-doc/docs/design/sunken_cavern/graybox.json'


def main():
    config = json.loads(TARGET.read_text(encoding='utf-8-sig'))
    config['method'] = 'Authored roof returns, broken-floor jumps and directed drops; short ladders only in timber interiors. Existing Lan movement unchanged.'
    config.pop('shafts', None)
    config.pop('max_ladder_rise_px', None)
    config.pop('junction_runs', None)
    paths = []

    def route(a, b, theme, points, modes, one_way=False):
        assert len(points) + 1 == len(modes), (a, b)
        paths.append(dict(a=a, b=b, theme=theme, via=points, modes=modes, one_way=one_way))

    # West: a broken timber flight, long collapsed roof planes, then a second
    # ruined building with separated jump groups. No ladder in the main return.
    route('w28', 'w18', 'broken_beams',
          [[47,29],[49,28],[47,27],[45.5,26],[47.5,25],[49.5,24],[47.5,23]], ['jump']*7+['walk'], True)
    route('w36', 'w28', 'collapsed_roof',
          [[51,39],[53,38],[55,37],[60,37],[45,33.5],[47,32.5],[49,31.25],[51,30]],
          ['jump','jump','jump','walk','ramp','jump','jump','jump','walk'], True)
    route('w53', 'w36', 'lower_roofs_and_beams',
          [[52.5,56],[44.5,54],[52.5,52],[50.5,51],[48.5,50],[46.5,49],[44.5,49],
           [52.5,46.5],[44.5,44],[46.5,43],[48.5,42],[50.5,41],[52.5,40]],
          ['walk','ramp','ramp','jump','jump','jump','walk','ramp','ramp','jump','jump','jump','jump','walk'], True)
    route('w60', 'w53', 'foundation_roof',
          [[52.5,62],[44.5,60],[52.5,58],[44.5,56]], ['walk','ramp','ramp','ramp','walk'], True)
    route('w18','w28','west_upper_drop',[[44.5,27]],['drop','drop'],True)
    route('w28','w36','west_roof_drop',[[53.5,35]],['drop','drop'],True)
    route('w36','w53','west_lower_drop',[[44.5,46],[44.5,51]],['drop']*3,True)
    route('w53','w60','west_foundation_drop',[],['drop'],True)

    # Central: readable balconies and an open descent; the return uses streets
    # and the west building, rather than retracing a ladder in the same tube.
    route('c20', 'c12', 'upper_balcony', [[93,22],[91,21],[89,20]], ['jump']*3+['walk'], True)
    route('c12','c20','upper_balcony_drop',[[87,23]],['drop','walk'],True)
    route('c12', 'crown', 'observatory_timber',
          [[87.5,20],[87.5,15.5],[94.5,15.5],[94.5,11],[87.5,11],[87.5,6]],
          ['walk','climb','walk','climb','walk','climb','walk'])
    route('c20', 'c33', 'atrium_upper_drop', [[94,27],[90,31.5],[87,36]], ['drop']*3+['walk'], True)
    route('c33', 'c37', 'atrium_street_drop', [[85.5,40]], ['drop','walk'], True)
    route('c37', 'c41', 'atrium_arch_drop', [[94,44]], ['drop','walk'], True)
    route('c41', 'c53', 'atrium_lower_drop', [[88,49],[92,53],[90,56]], ['drop']*3+['walk'], True)
    route('c60', 'c53', 'lower_balcony_return',
          [[94.75,62],[87.25,60],[89.25,59],[91.25,58],[93.25,57],[94.75,56]],
          ['walk','ramp','jump','jump','jump','jump','walk'], True)
    route('c75', 'c60', 'crypt_talus_return',
          [[94.75,78],[87.25,75.5],[94.75,73],[92.75,72],[90.75,71],[88.75,70],[87.25,69],
           [94.75,66.5],[87.25,64],[89.25,63],[91.25,62]],
          ['walk','ramp','ramp','jump','jump','jump','jump','ramp','ramp','jump','jump','walk'], True)
    route('c53','c60','foundation_balcony_drop',[],['drop'],True)
    route('c60','c75','crypt_balcony_drop',[[86.5,70]],['drop','drop'],True)

    # East: offset building floors. Its lower end is a descent to the crypt;
    # the upper two storeys can be traversed in either direction.
    route('e41', 'e33', 'broken_storeys',
          [[132.5,44],[124.5,42],[132.5,40],[130.5,39],[128.5,38],[126.5,37],[124.5,36]],
          ['walk','ramp','ramp','jump','jump','jump','jump','walk'], True)
    route('e53', 'e41', 'east_roof_return',
          [[132.5,56],[107.5,50],[109.5,49],[111.5,49],[131.5,44]],
          ['walk','ramp','jump','walk','ramp','walk'])
    route('e33','e41','east_upper_floor_drop',[],['drop'],True)
    route('e53', 'e64', 'east_lower_drop', [[124.5,61],[129,66]], ['drop','drop','walk'], True)
    route('e64', 'ante', 'outer_sanctuary_drop',
          [[119,66],[117.5,71],[120.5,76],[117.5,80.5]], ['walk','drop','drop','drop','drop'], True)

    # A large lower loop: descend on the west, return via the central talus.
    route('dry_turn', 'dry_base', 'west_cave_drop',
          [[38,61],[42,67],[38,73]], ['drop']*4, True)
    route('c75', 'ante', 'crypt_broken_stair',
          [[108.5,78],[110.5,79],[112.5,80],[114.5,81],[116.5,82],[118.5,83]], ['walk']+['jump']*6)

    # Tower: the remaining long ascent has a reason to be a timber staircase.
    route('bell28', 'bell18', 'bell_lower_beams',
          [[31.5,30],[36.5,28.5],[34.5,27.5],[32.5,26.5],[36.5,25],[34.5,24],[32.5,23]],
          ['walk','ramp','jump','jump','ramp','jump','jump','walk'], True)
    route('bell18', 'bell_top', 'bell_timber',
          [[31.5,23],[31.5,19],[36.5,19],[36.5,15],[31.5,15],[31.5,12]],
          ['walk','climb','walk','climb','walk','climb','walk'])
    route('archive', 'archive_return', 'archive_broken_floors',
          [[109,25.5],[105.5,30]], ['drop']*3, True)
    route('gate_side', 'gate', 'shrine_service_ladder',
          [[23,50],[23,45],[25,45],[25,40]], ['walk','climb','walk','climb','walk'])
    route('street_side', 'street_split', 'shop_service_ladder',
          [[63,48],[63,44],[67,44],[67,40]], ['walk','climb','walk','climb','walk'])
    config['traversals'] = paths
    # Keep each sloping return suspended above the arriving street. A roof
    # starting flush with that street would scoop arriving feet onto itself.
    for path in paths:
        chutes={'west_upper_drop':44.5,'west_roof_drop':53.5,'west_lower_drop':44.5,'west_foundation_drop':53.5,
                'foundation_balcony_drop':95.5,'crypt_balcony_drop':86.5,
                'east_upper_floor_drop':133.5,'east_lower_drop':124.5,
                'atrium_upper_drop':94,'atrium_street_drop':85.5,'atrium_arch_drop':94,'atrium_lower_drop':88}
        if path['theme'] in chutes:path['chute_x']=chutes[path['theme']]
        if path['theme'] in ('lower_roofs_and_beams','foundation_roof'):
            for p in path['via']:
                if p[0] == 52.5: p[0] = 51.5
        if path['theme'] in ('lower_balcony_return','crypt_talus_return'):
            for p in path['via']:
                if p[0] == 94.75: p[0] = 93.75
        if path['theme'] in ('broken_storeys','east_roof_return'):
            for p in path['via']:
                if p[0] == 132.5: p[0] = 131.5
        if path['theme'] in ('lower_roofs_and_beams','foundation_roof',
                             'lower_balcony_return','crypt_talus_return','broken_storeys','east_roof_return'):
            x,y=path['via'][0]
            path['via'][0]=[x-1,y]
            path['via'].insert(1,[x,y-1])
            path['modes'].insert(1,'jump')
    config['apertures'] = [
        {'x':[44,45],'y':23},{'x':[53,54],'y':30},
        {'x':[44,45],'y':40},{'x':[53,54],'y':56},
        {'x':[95.25,96],'y':56},{'x':[86,87],'y':62},
        {'x':[133,134],'y':36},{'x':[123,124],'y':44},{'x':[124,125],'y':56}
    ]
    config['balconies'] = [[44,54,y] for y in [23,30,40,56]] + [[86,96,y] for y in [36,56,62]] + [[124,134,36],[122,134,44],[124,134,56]]
    # Catch shelves are optional rests, not mandatory navigation stops. A fall
    # can intercept a sloping roof before reaching one of these exact heights.
    config['rests'] = []
    for path in paths:
        if path['theme'] in ('atrium_upper_drop','atrium_street_drop','atrium_arch_drop','atrium_lower_drop'):
            config['rests'].extend([path['chute_x'],y,2] for x,y in path['via'])
            path['via']=[]
            path['modes']=['drop']
        if path['theme'] in ('west_upper_drop','west_roof_drop','west_lower_drop','crypt_balcony_drop','east_lower_drop'):
            config['rests'].extend([x,y,2] for x,y in path['via'])
            path['via']=[]
            path['modes']=['drop']
        if path['theme']=='outer_sanctuary_drop':
            config['rests'].extend([x,y,4] for x,y in path['via'][1:])
            path['via']=path['via'][:1]
            path['modes']=['walk','drop']
            path['chute_x']=119
        if path['theme']=='west_cave_drop':
            config['rests'].extend([[40,61,4],[40,67,4],[40,73,4]])
            path['via']=[]
            path['modes']=['drop']
            path['chute_x']=40
    for path in paths:
        if path['theme']=='foundation_roof':path['via'][-1][0]=45.5
    # Side catches must leave a real fall gap beside the return roof. A 128 px
    # catch nearly touches the roof turn and bridges the gap via ground snap.
    for rest in config['rests']:
        if rest[2]==2:rest[2]=0.75
    # The east return is a long ruined street, rather than another narrow
    # zigzag shaft. Carve its envelope into the shared whole-map source.
    outline_path=TARGET.with_name('outline.json')
    outline=json.loads(outline_path.read_text(encoding='utf-8-sig'))
    cells=set()
    for a,b in [([131.5,55],[107.5,50]),([107.5,50],[111.5,49]),([111.5,49],[131.5,44])]:
        for x in range(int(min(a[0],b[0])),int(max(a[0],b[0]))+1):
            t=max(0,min(1,(x+.5-a[0])/(b[0]-a[0])))
            y=a[1]+(b[1]-a[1])*t
            for cy in range(int(y)-4,int(y)+1):cells.add((x,cy))
    from build_sunken_cavern_graybox import merged_rects
    outline['spaces']=[s for s in outline['spaces'] if s['id'] not in ('east_terraces','west_loft')]
    outline['spaces'].append({'id':'east_terraces','name':'东街残坡','rects':merged_rects(cells),
                              'role':'东井向西展开的宽缓旧街，长斜面、折返平台与分层洞腔连接上下街，替代窄井里的重复折梯。'})
    loft=set()
    for x in range(45,61):
        y=33.5+(x+.5-45)*3.5/15
        for cy in range(int(y)-4,int(y)+1):loft.add((x,cy))
    outline['spaces'].append({'id':'west_loft','name':'商街残屋夹层','rects':merged_rects(loft),
                              'role':'从西井跳入商街上方的断楼板，经一段长斜屋面回到上街，打破窄井里的整排折线。'})
    outline_path.write_text(json.dumps(outline,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    TARGET.write_text(json.dumps(config, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f'Authored {len(paths)} traversal sections in {TARGET}')


if __name__ == '__main__':
    main()
