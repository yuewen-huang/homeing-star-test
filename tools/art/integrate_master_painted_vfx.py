"""Sprite-pipeline full-strip normalization using the shipped VFX pivot, not feet.

The plugin's default character normalizer crops and bottom-centers every pose;
for sword wind that would move the attack. Reuse its strip splitter, apply ONE
scale to each complete strip, register to the authored pose trace, and preserve
the original cell, world pivot and timing. Never independently resize a pose.
"""
import importlib.util
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw

WORK = Path(__file__).resolve().parents[3]
ARCHIVE = WORK/'homeing-star-temp-assert/Art/master_painted_vfx/20261021'
REFERENCE = ARCHIVE/'reference'
OUTPUT = WORK/'homeing-star-game/assets/generated/combat_vfx/master/heavy_skills'
REVIEW = WORK/'homeing-star-test/artifacts/master_painted_vfx/normalized'
PLUGIN = Path.home()/'.codex/plugins/cache/openai-curated-remote/game-studio/0.1.2/scripts'
CHOICES = {
    'inertia_combo/cut_1_left': 'inertia_combo_cut_1_left.png',
    'inertia_combo/cut_2_left': 'inertia_combo_cut_2_left.png',
    'inertia_combo/cut_3_left': 'inertia_combo_cut_3_left_v2.png',
    'lunge_combo/cut_1_left': 'lunge_combo_cut_1_left.png',
    'lunge_combo/cut_2_left': 'lunge_combo_cut_2_left_v2.png',
    'air_qi_combo/cut_1_left': 'air_qi_combo_cut_1_left.png',
    'air_qi_combo/takeoff_halo': 'air_qi_combo_takeoff_halo_refined.png',
    'air_qi_combo/landing_gold': 'air_qi_combo_landing_gold.png',
    'air_qi_combo/release_glint': 'air_qi_combo_release_glint.png',
}


def threshold(image, cutoff=64):
    a = np.array(image.convert('RGBA'))
    a[a[:,:,3] < cutoff] = 0
    return Image.fromarray(a)


def main():
    module_spec = importlib.util.spec_from_file_location('sprite_normalizer',PLUGIN/'normalize_sprite_strip.py')
    helper = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(helper)
    mapping = json.loads((REFERENCE/'frame_mapping.json').read_text(encoding='utf-8'))
    manifest = json.loads((REFERENCE/'source_manifest.json').read_text(encoding='utf-8'))
    report = {}
    REVIEW.mkdir(parents=True,exist_ok=True)
    for name, source_file in CHOICES.items():
        meta = mapping['clips'][name]
        original = meta['original']
        source = Image.open(ARCHIVE/'generated'/source_file).convert('RGBA')
        # One whole-canvas resize, including the square gold strip's different
        # returned resolution. Never resize or center a single generated pose.
        expected = tuple(meta['canvas_size'])
        assert abs(source.width/source.height-expected[0]/expected[1]) < .015,source_file
        source = source.resize(expected,Image.Resampling.NEAREST)
        reference = Image.open(REFERENCE/meta['canvas']).convert('RGBA')
        sw,sh = meta['slot_size']
        slots=[]; refs=[]
        for row in range(expected[1]//sh):
            slots.extend(helper.split_strip(source.crop((0,row*sh,expected[0],(row+1)*sh)),4))
            refs.extend(helper.split_strip(reference.crop((0,row*sh,expected[0],(row+1)*sh)),4))
        visible = [s['index'] for s in meta['slots'] if not s['empty']]
        for i in visible: slots[i] = threshold(slots[i])
        anchor = 5 if name=='inertia_combo/cut_3_left' else max(visible,key=lambda i:np.count_nonzero(np.array(refs[i].getchannel('A'))))
        src_box = refs[anchor].getchannel('A').getbbox()
        gen_boxes=[slots[i].getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox() for i in visible]
        for i,box in zip(visible,gen_boxes):
            # A terminal 1-3 pixel remnant may reasonably disappear in the
            # painted fade; a substantive missing pose is a failed generation.
            if box is None:
                assert np.count_nonzero(np.array(refs[i].getchannel('A')))>0
                assert np.count_nonzero(np.array(refs[i].getchannel('A'))) <= 8,f'Missing generated frame: {name}/{i}'
        # Use the approved strongest pose as the registration seed. Stray pixels
        # from a neighboring generated slot must not shrink the entire animation.
        gen_box=gen_boxes[visible.index(anchor)]
        scale=max((src_box[2]-src_box[0])/(gen_box[2]-gen_box[0]),
                  (src_box[3]-src_box[1])/(gen_box[3]-gen_box[1]))
        if name.endswith('release_glint'):
            scale=(src_box[2]-src_box[0])/(gen_box[2]-gen_box[0])
        dx=(src_box[0]+src_box[2])/2-(gen_box[0]+gen_box[2])*scale/2
        dy=(src_box[1]+src_box[3])/2-(gen_box[1]+gen_box[3])*scale/2
        if '/cut_' in name:
            # Resampling can drop isolated tip pixels used by the input bbox.
            # Calibrate the one strip-wide scale against the actually visible
            # seed, so an airy painted tail does not shorten a heavy sword cut.
            seed=slots[anchor].transform((sw,sh),Image.Transform.AFFINE,
                (1/scale,0,-dx/scale,0,1/scale,-dy/scale),Image.Resampling.NEAREST)
            actual=seed.getchannel('A').getbbox()
            if actual:
                gain=min(1.25,max((src_box[2]-src_box[0])/(actual[2]-actual[0]),
                                  (src_box[3]-src_box[1])/(actual[3]-actual[1])))
                scale*=gain
                dx=(src_box[0]+src_box[2])/2-(gen_box[0]+gen_box[2])*scale/2
                dy=(src_box[1]+src_box[3])/2-(gen_box[1]+gen_box[3])*scale/2
        normalized=[]
        removed=0
        for item in meta['slots']:
            i=item['index']; col=i%4; row=i//4
            if item['empty']:
                frame=Image.new('RGBA',tuple(original['cell']))
            else:
                registered=slots[i].transform((sw,sh),Image.Transform.AFFINE,
                    (1/scale,0,-dx/scale,0,1/scale,-dy/scale),Image.Resampling.NEAREST)
                # Register each painted pose to its authored trace anchor. The
                # model can move a cap inside its slot even with fixed layout;
                # translation repairs that drift without per-pose rescaling.
                bounds=refs[i].getchannel('A').getbbox()
                painted=registered.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
                if painted:
                    tx=round((bounds[0]+bounds[2]-painted[0]-painted[2])/2)
                    ty=round((bounds[1]+bounds[3]-painted[1]-painted[3])/2)
                    registered=registered.transform((sw,sh),Image.Transform.AFFINE,(1,0,-tx,0,1,-ty),Image.Resampling.NEAREST)
                # Bounded extraction permits broken brush tips but prevents a
                # model-invented plume from expanding the authored attack reach.
                allowed=Image.new('L',(sw,sh))
                ImageDraw.Draw(allowed).rectangle((bounds[0]-8,bounds[1]-8,bounds[2]+7,bounds[3]+7),fill=255)
                prior=registered.getchannel('A')
                registered.putalpha(ImageChops.multiply(prior,allowed))
                removed+=int(np.count_nonzero(np.array(prior)))-int(np.count_nonzero(np.array(registered.getchannel('A'))))
                x,y,w,h=item['rect']; x-=col*sw; y-=row*sh
                frame=registered.crop((round(x),round(y),round(x+w),round(y+h)))
                assert frame.size==tuple(original['cell'])
            normalized.append(frame)
        def ship(clip_name, images):
            spec=manifest['clips'][clip_name]
            w,h=spec['cell']; columns=int(spec['columns'])
            page=Image.new('RGBA',(w*columns,h*((len(images)+columns-1)//columns)))
            for i,frame in enumerate(images): page.paste(frame,((i%columns)*w,(i//columns)*h))
            assert len(spec['pages'])==1
            page.save(OUTPUT/spec['pages'][0])
            spec['art']='imagegen_hand_painted'
            spec['source_strip']=source_file
        ship(name,normalized)
        if name.endswith('_left'):
            ship(name[:-5]+'_right',[im.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for im in normalized])
        preview=Image.new('RGBA',(original['cell'][0]*4,original['cell'][1]*((len(normalized)+3)//4)),(35,40,42,255))
        for i,frame in enumerate(normalized): preview.alpha_composite(frame,((i%4)*frame.width,(i//4)*frame.height))
        preview.convert('RGB').save(REVIEW/(name.replace('/','_')+'.png'))
        report[name]={'source':source_file,'registration_seed':anchor,'shared_scale':scale,'shared_offset':[dx,dy],
                      'frames':len(normalized),'removed_outside_envelope':removed}
        print(name, 'shared scale',round(scale,3),'frames',len(normalized))
    manifest['art_pipeline']='sprite-pipeline/imagegen/full-strip/shared-pivot'
    (OUTPUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    pages=[p for c in manifest['clips'].values() for p in c['pages']]
    lines=[f'[gd_resource type="Resource" load_steps={len(pages)+1} format=3]','']
    for i,page in enumerate(pages):
        lines.append(f'[ext_resource type="Texture2D" path="res://assets/generated/combat_vfx/master/heavy_skills/{page}" id="{i+1}"]')
    lines+=['','[resource]','metadata/manifest = '+json.dumps(json.dumps(manifest,separators=(',',':'))),'metadata/textures = {']
    lines += [json.dumps(p)+f': ExtResource("{i+1}")'+(',' if i+1<len(pages) else '') for i,p in enumerate(pages)]
    lines+=['}','']
    (OUTPUT/'library.tres').write_text('\n'.join(lines),encoding='utf-8')
    (REVIEW/'normalization_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')


if __name__=='__main__': main()
