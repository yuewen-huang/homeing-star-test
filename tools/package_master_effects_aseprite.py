"""Package the master's currently used painted VFX for frame-by-frame editing.

Runtime sheets remain untouched. Two independent raster layers per document:
locked hidden body/original reference, and editable effect. Native export and
RGBA readback verify the handoff. The offline viewer uses source-size crops.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import math
import re
import struct
import subprocess
import tempfile
import zlib

from PIL import Image, ImageDraw, ImageFont
from aseprite_rgba_reader import read, layer_frame
from package_deer_vfx_aseprite import chunk, string, user_data

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / 'homeing-star-game'
OUT = ROOT / 'homeing-star-temp-assert/PendingArt/Effects/Fw effects'
FX = 'assets/sideview/effects/'
BODY = 'assets/sideview/characters/master/boss/'
# Names and windows use Aseprite's one-based frame numbering.
CONFIGS = [
    ('01_一阶段_攻击1', 'attack_1', 'master_wind/phase1_optimized_atak1_fx_675x384_16f.png', 'phase1_optimized_atak1_body_675x384_16f.png', (675,384),16,(0,-192),1),
    ('02_一阶段_攻击2_三连', 'attack_2', 'master_wind/phase1_optimized_atak2_fx_750x384_25f.png', 'phase1_optimized_atak2_body_750x384_25f.png', (750,384),25,(37.5,-192),1),
    ('03_一阶段_攻击3_旋风', 'attack_3', 'master_wind/phase1_optimized_atak3_fx_600x350_32f.png', 'phase1_optimized_atak3_body_600x350_32f.png', (600,350),32,(122,-218.75),1.25),
    ('04_一阶段_瞬移突进', 'dash', 'master_wind/phase1_optimized_shunyi_fx_600x356_16f.png', 'phase1_optimized_shunyi_body_600x356_16f.png', (600,356),16,(0,-128),1),
    ('05_一阶段_特殊攻击', 'special_attack', 'master_wind/phase1_optimized_sp_atak_fx_500x500_16f.png', 'phase1_optimized_sp_atak_body_500x500_16f.png', (500,500),16,(-34.5,-162.5),1),
    ('06_二阶段_攻击1', 'phase_2_attack_1', 'master_wind/phase2/attack_1_fx_256x256_16f.png', 'phase2/attack_1_256x256_16f.png', (256,256),16,(0,-72),1.7),
    ('07_二阶段_攻击2_三连', 'phase_2_attack_2', 'master_wind/phase2/attack_2_fx_300x350_32f.png', 'phase2/attack_2_300x350_32f.png', (300,350),32,(22,-119),1.7),
    ('08_二阶段_金光特殊攻击', 'phase_2_special_attack', 'master_wind/phase2/special_attack_fx_380x300_24f.png', 'phase2/special_attack_380x300_24f.png', (380,300),24,(65,-95),1.7),
    ('09_二阶段_瞬移突进', 'phase_2_dash', 'master_wind/phase2/dash_fx_384x384_16f.png', 'phase2/dash_384x384_16f.png', (384,384),16,(2.5,-73),1.7),
    ('10_二阶段_上挑', 'phase_2_uppercut', 'master_wind/phase2/uppercut_fx_350x350_16f.png', 'phase2/uppercut_350x350_16f.png', (350,350),16,(73.5,-170),1.43),
    ('11_二阶段_上挑地面波', 'travel', 'master_wind/phase2/uppercut_ground_wave_266x116_4f.png', None, (266,116),4,(0,-54),1.2),
    ('12_二阶段_狼嚎魔法阵', 'howl_circle', 'lan_wind_magic/wind_magic_192x225_32f.png', None, (192,225),32,(0,-145),1.35),
    ('13_共用预警_红光', 'warning_red', 'combat_warning/red_counter_warning_625x87_5f.png', None, (125,87),5,None,1),
    ('14_共用预警_金光', 'warning_gold', 'combat_warning/gold_unparryable_warning_625x87_5f.png', None, (125,87),5,None,1),
]
HIT_WINDOWS = {
    'phase_2_attack_1': [(9,13)], 'phase_2_attack_2': [(7,8),(12,14),(25,27)],
    'phase_2_special_attack': [(7,9),(10,12),(16,17)],
    'phase_2_dash': [(7,9)], 'phase_2_uppercut': [(6,9)],
}


def durations_and_hits():
    """Read actual phase-one effect track, including blank and held frames."""
    raw = (GAME / BODY / 'master_combat_timelines.tres').read_text(encoding='utf-8')
    blocks = re.split(r'\[sub_resource type="Animation" id="([^"]+)"\]', raw)
    mapping = dict(re.findall(r'&"([^"]+)": SubResource\("([^"]+)"\)', raw))
    result = {}
    for animation, ident in mapping.items():
        block = blocks[blocks.index(ident)+1]
        length = float(re.search(r'^length = ([\d.]+)', block, re.M)[1])
        track = re.search(r'tracks/1/keys = \{(.*?)\n\}(?:\n|$)', block, re.S)[1]
        times = [float(v) for v in re.search(r'"times": PackedFloat32Array\((.*?)\)',track)[1].split(',')]
        indices = json.loads(re.search(r'"values": (\[.*?\])',track)[1])
        assert indices == list(range(len(indices)))
        durations = [round((b-a)*1000) for a,b in zip(times,times[1:]+[length])]
        events = re.search(r'tracks/2/keys = \{(.*?)\n\}(?:\n|$)', block, re.S)[1]
        event_times = [float(v) for v in re.search(r'"times": PackedFloat32Array\((.*?)\)',events)[1].split(',')]
        methods = re.findall(r'"method": &"([^"]+)"', events)
        windows, start = [], None
        for t, method in zip(event_times, methods):
            if method == '_timeline_attack_frame' and start is None:
                start = t
            elif method == '_timeline_close_hitbox' and start is not None:
                windows.append((round(start*10)+1, round(t*10)))
                start = None
        result[animation] = (durations,windows)
    return result


def split_sheet(path, size, count):
    sheet = Image.open(path).convert('RGBA')
    w,h = size
    assert sheet.width % w == 0 and sheet.height % h == 0
    columns = sheet.width//w
    assert columns*(sheet.height//h) >= count
    return sheet, [sheet.crop(((i%columns)*w,(i//columns)*h,(i%columns+1)*w,(i//columns+1)*h)) for i in range(count)]


def runs(indices):
    output = []
    for i in indices:
        if output and output[-1][1]+1 == i:
            output[-1][1] = i
        else:
            output.append([i,i])
    return output


def write_document(path, frames, references, durations, tags, metadata):
    canvas = frames[0].size
    initial = []
    for name, flags in [('动作或原图参考_隐藏锁定',0),('技能特效_可编辑',3)]:
        initial += [chunk(0x2004,struct.pack('<6HB3x',flags,0,0,0,0,0,255)+string(name)),
                    user_data(json.dumps(metadata,ensure_ascii=False))]
    tag_bytes = struct.pack('<H8x',len(tags))
    for name,a,b in tags:
        tag_bytes += struct.pack('<HHBH6x3BB',a-1,b-1,0,0,110,195,230,0)+string(name)
    initial.append(chunk(0x2018,tag_bytes))
    blocks = []
    for i,(effect,reference,duration) in enumerate(zip(frames,references,durations)):
        chunks = initial.copy() if i == 0 else []
        for layer,img in enumerate((reference,effect)):
            cel = struct.pack('<HhhBHh5xHH',layer,0,0,255,2,0,*canvas)
            chunks += [chunk(0x2005,cel+zlib.compress(img.tobytes(),9)),
                       user_data(f'Aseprite {i+1:02d}; Godot F{i:02d}; {duration}ms; 原图按行切帧')]
        payload = b''.join(chunks)
        blocks.append(struct.pack('<IHHH2xI',len(payload)+16,0xF1FA,len(chunks),duration,len(chunks))+payload)
    header = bytearray(128)
    struct.pack_into('<I5HIH',header,0,128+sum(map(len,blocks)),0xA5E0,len(frames),*canvas,32,1,durations[0])
    header[34:36] = bytes((1,1))
    struct.pack_into('<HH',header,40,16,16)
    path.write_bytes(bytes(header)+b''.join(blocks))


def verify(path, frames, references, durations, tags, native):
    doc = read(path)
    assert doc['canvas'] == frames[0].size and len(doc['frames']) == len(frames)
    assert len(doc['layers']) == 2 and not doc['layers'][0]['visible'] and doc['layers'][1]['visible']
    for i,(effect,reference,duration) in enumerate(zip(frames,references,durations)):
        assert doc['frames'][i]['duration_ms'] == duration
        for layer,expected in enumerate((reference,effect)):
            actual, opacity = layer_frame(doc,i,layer)
            assert opacity == 1 and actual.tobytes() == expected.tobytes(), (path.name,i,layer)
    report = {'file':path.name,'frames':len(frames),'rgba_exact_both_layers':True,'timing_exact':True}
    with tempfile.TemporaryDirectory(prefix='master_ase_verify_') as temporary:
        data, sheet = Path(temporary)/'export.json',Path(temporary)/'export.png'
        process = subprocess.run([str(native),'-b','--list-layers','--list-tags',str(path),
                                  '--format','json-array','--data',str(data),'--sheet',str(sheet),
                                  '--sheet-type','rows','--sheet-columns','4'],
                                 capture_output=True,timeout=45,creationflags=subprocess.CREATE_NO_WINDOW)
        report['native_exit_code'] = process.returncode
        if not data.exists() or not sheet.exists():
            raise RuntimeError(f'Native Aseprite did not export {path}: {process.returncode}')
        meta = json.loads(data.read_text(encoding='utf-8'))
        assert len(meta['frames']) == len(frames)
        # Aseprite sorts overlapping tags by timeline position when exporting.
        assert sorted((t['name'],t['from']+1,t['to']+1) for t in meta['meta']['frameTags']) == sorted(tags)
        export = Image.open(sheet).convert('RGBA')
        for i,record in enumerate(meta['frames']):
            assert record['duration'] == durations[i]
            r = record['frame']
            actual = export.crop((r['x'],r['y'],r['x']+r['w'],r['y']+r['h']))
            assert actual.size == frames[i].size
            assert actual.getchannel('A').tobytes() == frames[i].getchannel('A').tobytes()
            mask = frames[i].getchannel('A').point(lambda a:255 if a else 0)
            for channel in 'RGB':
                assert Image.composite(actual.getchannel(channel),Image.new('L',actual.size),mask).tobytes() == Image.composite(frames[i].getchannel(channel),Image.new('L',actual.size),mask).tobytes()
        report['native_visible_rgba_and_tags_exact'] = True
    return report


def checker(size):
    image = Image.new('RGBA',size,(43,47,55,255))
    draw = ImageDraw.Draw(image)
    for y in range(0,size[1],12):
        for x in range(0,size[0],12):
            if (x//12+y//12)%2:
                draw.rectangle((x,y,x+11,y+11),fill=(55,60,68,255))
    return image


def make_preview(out,name,frames,references,durations,hit_windows,font):
    w,h = frames[0].size
    factor = min(208/w,160/h,1)
    thumb = (round(w*factor),round(h*factor))
    cw,ch = 224,200
    columns = min(8,len(frames))
    contact = Image.new('RGB',(columns*cw,math.ceil(len(frames)/columns)*ch+42),(25,28,34))
    draw = ImageDraw.Draw(contact)
    draw.text((10,9),name+'   帧号从 1 开始 / F 为 Godot 索引',font=font,fill='white')
    animation = []
    for i,(effect,reference) in enumerate(zip(frames,references)):
        bg = checker((w,h))
        # The body appears only in previews; the editable effect keeps exact RGBA.
        if reference.tobytes() != effect.tobytes():
            faded = reference.copy()
            faded.putalpha(reference.getchannel('A').point(lambda a:round(a*.45)))
            bg.alpha_composite(faded)
        bg.alpha_composite(effect)
        view = bg.resize(thumb,Image.Resampling.NEAREST).convert('RGB')
        x,y = (i%columns)*cw,(i//columns)*ch+42
        active = any(a<=i+1<=b for a,b in hit_windows)
        label = f'{i+1:02d} / F{i:02d}  '+('打击' if active else ('空特效' if not effect.getchannel('A').getbbox() else ''))
        draw.text((x+8,y+5),label,font=font,fill=(255,205,103) if active else 'white')
        contact.paste(view,(x+(cw-thumb[0])//2,y+34+(160-thumb[1])//2))
        animation.append(view)
    contact.save(out/(name+'_帧号总览.png'))
    animation[0].save(out/(name+'_慢放.gif'),save_all=True,append_images=animation[1:],
                      duration=[d*3 for d in durations],loop=0,disposal=2)
    return animation


def data_url(path):
    return 'data:image/png;base64,'+base64.b64encode(path.read_bytes()).decode('ascii')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=OUT)
    parser.add_argument('--aseprite',type=Path,default=Path('D:/Aseprite/Aseprite.exe'))
    parser.add_argument('--resume',action='store_true',help='Reuse only byte-identical previously generated documents')
    args = parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    preview = args.output/'预览'
    preview.mkdir(exist_ok=True)
    paths = [args.output/(c[0]+'.aseprite') for c in CONFIGS]
    assert args.resume or not any(p.exists() for p in paths), 'Refuse to overwrite artist documents'
    timeline = durations_and_hits()
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',16)
    manifest, reports, viewer = [],[],[]
    overview = Image.new('RGB',(4*304,4*238),(25,28,34))
    overview_draw = ImageDraw.Draw(overview)
    for index,(name,action,filename,body,size,count,position,scale) in enumerate(CONFIGS):
        source = GAME/FX/filename
        sheet,frames = split_sheet(source,size,count)
        references = split_sheet(GAME/BODY/body,size,count)[1] if body else [f.copy() for f in frames]
        durations,hits = timeline.get(action,([100]*count,HIT_WINDOWS.get(action,[])))
        if action in ('howl_circle','warning_red','warning_gold'):
            durations = [round((i+1)*62.5)-round(i*62.5) for i in range(count)]
        assert len(durations) == count
        visible = [i+1 for i,f in enumerate(frames) if f.getchannel('A').getbbox()]
        tags = [('全序列',1,count)]
        tags += [(f'特效出现_{a:02d}-{b:02d}',a,b) for a,b in runs(visible)]
        tags += [(f'打击{j+1}_{a:02d}-{b:02d}',a,b) for j,(a,b) in enumerate(hits)]
        metadata = {'file':name+'.aseprite','action':action,'source':'res://'+FX+filename,
                    'body_reference':'res://'+BODY+body if body else None,'canvas':list(size),
                    'frame_count':count,'durations_ms':durations,'aseprite_frame_base':1,'godot_frame_base':0,
                    'visible_effect_frames':visible,'hit_windows_one_based':hits,'tags':tags,
                    'runtime_position_constant':position,'runtime_scale':scale,
                    'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                    'pivot_note':'PNG 没有切片 pivot；画布、像素位置不变。保留运行时位置/比例常量，未添加或取整半像素 pivot。'}
        path = args.output/(name+'.aseprite')
        if path.exists():
            with tempfile.TemporaryDirectory(prefix='master_ase_resume_') as temporary:
                candidate = Path(temporary)/path.name
                write_document(candidate,frames,references,durations,tags,metadata)
                assert path.read_bytes() == candidate.read_bytes(), f'Artist document changed; refuse overwrite: {path}'
        else:
            write_document(path,frames,references,durations,tags,metadata)
        reports.append(verify(path,frames,references,durations,tags,args.aseprite))
        animation = make_preview(preview,name,frames,references,durations,hits,font)
        hero = max(range(count),key=lambda i:sum(frames[i].getchannel('A').histogram()[1:]))
        x,y = (index%4)*304,(index//4)*238
        overview_draw.text((x+8,y+7),name,font=font,fill='white')
        overview_draw.text((x+8,y+31),f'{count} 帧 | 有特效：'+','.join(f'{a}-{b}' for a,b in runs(visible)),font=font,fill=(145,200,220))
        thumb = animation[hero]
        overview.paste(thumb,(x+(304-thumb.width)//2,y+64))
        body_data = None
        if body:
            body_data = data_url(GAME/BODY/body)
        viewer.append({**metadata,'name':name,'fx':data_url(source),'ref':body_data,'columns':sheet.width//size[0]})
        manifest.append(metadata)
        print(f'PASS {name}: {count} frames, exact RGBA/timing, native export',flush=True)
    overview.save(preview/'师傅技能特效索引.png')
    (args.output/'时间轴与来源.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    (args.output/'Aseprite校验.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2),encoding='utf-8')
    rows = ['| 工程 | 总帧数 | 出现特效的帧 | 打击帧 |','| --- | ---: | --- | --- |']
    for m in manifest:
        format_runs = lambda values:'、'.join(str(a) if a==b else f'{a}–{b}' for a,b in values) or '无'
        rows.append(f"| {m['file']} | {m['frame_count']} | {format_runs(runs(m['visible_effect_frames']))} | {format_runs(m['hit_windows_one_based'])} |")
    notes = '''# 师傅技能特效逐帧编辑稿

双击 `师傅特效逐帧查看.html`，选择技能，拖进度条；方向键逐帧，空格播放/暂停。可关闭动作参考，看纯特效。`预览` 内有帧号总览和三倍慢放 GIF。

帧号统一从 **1** 开始，与 Aseprite 默认时间轴一致。Godot F00 = Aseprite 第 1 帧，F08 = 第 9 帧。黄色“打击”来自当前碰撞时间窗；特效出现时间与伤害窗口可能不同。

每份工程只保留两层：隐藏锁定的“动作或原图参考”、可编辑的“技能特效”。需要看人物时打开参考层的小眼睛；魔法阵/地面波/预警的参考层为原图备份。每个 cel 独立，空白帧也保留，修改一帧不会联动其它帧。

直接改“技能特效_可编辑”层。画布、帧数、像素、透明度、坐标均与当前运行时 PNG 一致，没有裁边、缩放或重绘。PNG 不含 Aseprite pivot；运行时位置和比例常量在 `时间轴与来源.json`，半像素坐标未取整。保存时保留空白帧和原画布。

一阶段读取实际 AnimationLibrary 的 WindEffect 时间轴；二阶段技能基准 10 FPS，魔法阵/预警 16 FPS（62/63ms 量化）；二阶段增益、慢动作和命中停顿由游戏控制，不烘焙进原稿。上挑地面波在上挑第 10 帧发射。二阶段突进第 5 帧运行时隐藏，第 6 帧重新出现；参考图显示完整原稿像素。特殊攻击部分方向由游戏镜像，工程保持原图方向。

目录里原有 effect1–7.png 保留。旧版未被脚本使用的 master_wind 特效没有混入。红/金预警是共用素材，修改后接入会影响共享该素材的角色。狼嚎 HowlAura 的三圈扩散由代码绘制，并非 PNG 序列，未伪造为图稿。本次没有接入或改变游戏。

## 定位表（Aseprite 帧号）

'''+ '\n'.join(rows)
    native_exits = sorted({r['native_exit_code'] for r in reports})
    notes += '\n\n## 校验\n\n所有帧两个图层均逐字节回读一致；原生 Aseprite 批量导出的透明度、可见 RGB、帧数、时长和标签均通过校验。'
    if any(native_exits):
        notes += f'本机 Aseprite 在导出完成后异常退出（退出码 {native_exits}，--version 亦异常）；校验要求实际生成的导出逐帧一致，未以退出码推断成功。'
    (args.output/'如何找到要修改的帧.md').write_text(notes,encoding='utf-8')
    html = HTML.replace('__DATA__',json.dumps(viewer,ensure_ascii=False).replace('</','<\\/'))
    (args.output/'师傅特效逐帧查看.html').write_text(html,encoding='utf-8')


HTML = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>师傅特效 · 逐帧定位</title>
<style>body{margin:0;background:#171c24;color:#e6eef8;font:16px "Microsoft YaHei",sans-serif}main{max-width:1120px;margin:auto;padding:28px}h1{font-size:25px;margin:0 0 8px}.note{color:#aab8ca;line-height:1.7}select,button,input{font:inherit}select,button{background:#293448;color:white;border:1px solid #46556c;border-radius:6px;padding:8px;margin:4px}button{cursor:pointer}.tools{display:flex;align-items:center;gap:9px;flex-wrap:wrap;margin:16px 0}.stage{display:flex;justify-content:center;align-items:center;height:500px;background-color:#2b2f37;background-image:conic-gradient(#373c44 25%,transparent 0 50%,#373c44 0 75%,transparent 0);background-size:24px 24px;border:1px solid #445064;border-radius:10px}canvas{image-rendering:pixelated;max-width:100%;max-height:100%}#scrub{width:100%;margin:16px 0;accent-color:#60cbef}#status{font-size:20px;font-weight:bold}#frames{display:flex;gap:6px;flex-wrap:wrap;margin-top:18px}#frames button.active{background:#126c89}#frames button.hit{border-color:#f7c569;color:#f7c569}a{color:#7ed7f0}.meta{line-height:1.8;overflow-wrap:anywhere}</style>
<main><h1>师傅技能特效 · 逐帧定位</h1><div class="note">选技能 → 拖动时间轴 → 对照同号 Aseprite 帧修改。方向键逐帧，空格播放或暂停。</div>
<div class="tools"><select id="skill"></select><button id="play">播放</button><button id="previous">上一帧</button><button id="next">下一帧</button><label><input id="reference" type="checkbox" checked>动作参考</label><select id="speed"><option value="3">三倍慢放</option><option value="1">基准速度</option><option value="6">六倍慢放</option></select><a id="openDoc">打开 Aseprite 工程</a></div>
<div id="status"></div><input id="scrub" type="range" min="0" value="0"><div class="stage"><canvas id="canvas"></canvas></div><div id="frames"></div><p class="meta" id="meta"></p><p class="note">画面保持原稿方向；游戏可能镜像、移动或隐藏。黄色按钮代表当前伤害窗口。16 FPS 已量化为 62/63ms；动画按技能循环便于检查。参考层只用于定位。</p></main>
<script>const clips=__DATA__;
const $=id=>document.getElementById(id),ctx=$('canvas').getContext('2d');let current=0,frame=0,playing=false,timer=null,fxImage=null,refImage=null,revision=0;
clips.forEach((c,i)=>{let o=document.createElement('option');o.value=i;o.textContent=c.name;$('skill').append(o)});
function setFrame(n){frame=(n+clips[current].frame_count)%clips[current].frame_count;$('scrub').value=frame;draw()}
function draw(){const c=clips[current],[w,h]=c.canvas;ctx.clearRect(0,0,w,h);const x=frame%c.columns*w,y=Math.floor(frame/c.columns)*h;if(refImage&&$('reference').checked){ctx.globalAlpha=.45;ctx.drawImage(refImage,x,y,w,h,0,0,w,h)}ctx.globalAlpha=1;if(fxImage)ctx.drawImage(fxImage,x,y,w,h,0,0,w,h);let hit=c.hit_windows_one_based.some(([a,b])=>frame+1>=a&&frame+1<=b);$('status').textContent=`Aseprite 第 ${frame+1} / ${c.frame_count} 帧  ·  Godot F${String(frame).padStart(2,'0')}  ·  ${c.durations_ms[frame]}ms  ·  ${hit?'打击窗口':c.visible_effect_frames.includes(frame+1)?'有特效':'空特效帧'}`;Array.from($('frames').children).forEach((b,i)=>b.classList.toggle('active',i===frame))}
function stop(){playing=false;clearTimeout(timer);$('play').textContent='播放'}
function advance(){if(!playing)return;timer=setTimeout(()=>{setFrame(frame+1);advance()},clips[current].durations_ms[frame]*Number($('speed').value))}
function toggle(){if(playing)stop();else{playing=true;$('play').textContent='暂停';advance()}}
function load(url){return new Promise((resolve,reject)=>{const image=new Image();image.onload=()=>resolve(image);image.onerror=reject;image.src=url})}
async function choose(){stop();current=Number($('skill').value);frame=0;fxImage=refImage=null;const c=clips[current],token=++revision;[$('canvas').width,$('canvas').height]=c.canvas;$('scrub').max=c.frame_count-1;$('scrub').value=0;$('openDoc').href=c.file;$('meta').textContent=`画布 ${c.canvas.join(' × ')} ｜ 来源 ${c.source} ｜ 可见特效帧：${c.visible_effect_frames.join('、')} ｜ 参考层：${c.body_reference?'师傅同帧动作':'原图备份'}`;$('frames').replaceChildren();for(let i=0;i<c.frame_count;i++){const b=document.createElement('button');b.textContent=String(i+1).padStart(2,'0');b.className=c.hit_windows_one_based.some(([a,z])=>i+1>=a&&i+1<=z)?'hit':'';b.onclick=()=>{stop();setFrame(i)};$('frames').append(b)}draw();const images=await Promise.all([load(c.fx),c.ref?load(c.ref):Promise.resolve(null)]);if(token!==revision)return;[fxImage,refImage]=images;draw()}
$('skill').onchange=choose;$('play').onclick=toggle;$('previous').onclick=()=>{stop();setFrame(frame-1)};$('next').onclick=()=>{stop();setFrame(frame+1)};$('reference').onchange=draw;$('scrub').oninput=()=>{stop();setFrame(Number($('scrub').value))};document.addEventListener('keydown',e=>{if(e.target.tagName==='SELECT')return;if(['ArrowRight','ArrowLeft',' '].includes(e.key)){e.preventDefault();if(e.key===' ')toggle();else{stop();setFrame(frame+(e.key==='ArrowRight'?1:-1))}}});choose();</script></html>'''

if __name__ == '__main__':
    import sys
    sys.stdout.reconfigure(encoding='utf-8')
    main()
