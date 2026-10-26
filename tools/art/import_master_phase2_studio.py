"""Install a saved Studio runtime snapshot and its exact renderer dependency closure.

godot --headless --path combat-vfx-studio --script res://tools/export_master_runtime.gd -- SNAPSHOT.json
python homeing-star-test/tools/art/import_master_phase2_studio.py SNAPSHOT.json
Studio documents are read-only inputs. The original game PixelSlash is never replaced.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
from normalize_master_phase2_body import apply_metadata

ROOT=Path(__file__).resolve().parents[3]
SCRIPT='scripts/bosses/master/studio_vfx/'
ART='assets/bosses/master/fx/phase2/studio/'

def main(snapshot):
    payload=json.loads(snapshot.read_text(encoding='utf-8-sig'))
    source=ROOT/'combat-vfx-studio'
    game=ROOT/'homeing-star-game'
    normalization=game/'assets/bosses/master/body/boss/phase2/normalization.json'
    if normalization.exists():
        apply_metadata(payload['body'],payload['effects'],json.loads(normalization.read_text(encoding='utf8')))
    for key,move in payload['effects']['moves'].items():
        for file,field in [('combo.json','studio_sha256'),('style.json','style_sha256')]:
            if hashlib.sha256((source/'combos'/key/file).read_bytes()).hexdigest()!=move[field]:
                raise SystemExit('Studio changed since export; export a fresh snapshot before importing.')
    pending=['authored_effect.gd','quake_effect.gd','pixel_slash.gd','combo_style.gd','render_caps.gd']
    seen=set()
    hashes={}
    pattern=re.compile(r'res://vfx/([\w./-]+\.(?:gdshaderinc|gdshader|gd|png))')
    def mapped(relative):
        return (ART if not relative.endswith('.gd') else SCRIPT)+relative
    while pending:
        relative=pending.pop()
        if relative in seen: continue
        seen.add(relative)
        path=source/'vfx'/relative
        original=path.read_bytes()
        hashes[relative]=hashlib.sha256(original).hexdigest()
        text=original.decode('utf-8-sig').replace('\r\n','\n').replace('\r','\n')
        pending.extend(pattern.findall(text))
        text=pattern.sub(lambda m:'res://'+mapped(m[1]),text)
        text=re.sub(r'^class_name \w+\s*\n','',text,flags=re.M)
        constants=[]
        if relative in ['authored_effect.gd','claw_rake.gd']:
            constants.append(f'const PixelSlash = preload("res://{SCRIPT}pixel_slash.gd")')
        if relative in ['pixel_slash.gd','quake_effect.gd']:
            constants.append(f'const ComboStyle = preload("res://{SCRIPT}combo_style.gd")')
        if relative=='quake_effect.gd':
            constants.append(f'const RenderCaps = preload("res://{SCRIPT}render_caps.gd")')
        if relative=='pixel_slash.gd': text=text.replace('-> PixelSlash:', '-> Node2D:')
        if relative=='pixel_slash.gd':
            # Claws use only these exact helpers, not the standalone sword demo renderer.
            palettes=re.search(r'^const PALETTES := \{[\s\S]*?^\}',text,re.M).group()
            helpers=text[text.index('static func ease_swing'):text.index('func configure')]
            text='extends RefCounted\n'+palettes+'\n'+helpers
        if relative=='claw_rake.gd': text=text.replace('not node is ComboStage','not node.has_meta("master_effect_root")')
        if constants:
            # Insert after extends or @tool (implicit RefCounted scripts need no extends).
            lines=text.splitlines()
            index=next((i+1 for i,line in enumerate(lines) if line.startswith('extends ')),1 if lines[0]=='@tool' else 0)
            lines[index:index]=constants
            text='\n'.join(lines)+'\n'
        dest=game/mapped(relative)
        dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_text(text.rstrip()+'\n',encoding='utf-8')
    for name,dest in [('body','assets/bosses/master/body/boss/phase2/arrangements.json'),('effects','assets/bosses/master/fx/phase2/arrangements.json')]:
        path=game/dest
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(json.dumps(payload[name],ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (game/'assets/bosses/master/fx/phase2/studio_sources.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
    print(f'Imported 3 saved Studio flows and {len(seen)} namespaced renderer dependencies; no Studio writes.')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('snapshot',type=Path)
    main(parser.parse_args().snapshot)
