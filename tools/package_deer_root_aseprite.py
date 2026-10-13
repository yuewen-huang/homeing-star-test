"""Root concept art handoff, separate from implemented mist combat."""
from pathlib import Path
import json,sys,zipfile
from PIL import Image,ImageDraw,ImageFont
from package_deer_vfx_aseprite import write_aseprite,composite,LAYERS
out=Path(sys.argv[1])
manifest=json.loads((out/'capture_manifest.json').read_text(encoding='utf-8'))
def normalize(value):
    if isinstance(value,dict):return {k:normalize(v) for k,v in value.items()}
    if isinstance(value,list):return [normalize(v) for v in value]
    if isinstance(value,float) and value.is_integer():return int(value)
    return value
manifest=normalize(manifest)
manifest["clips"].sort(key=lambda c:c["name"])
(out/'capture_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
preview=out/'预览';preview.mkdir(exist_ok=True)
notes=[]
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',19)
overview=Image.new('RGB',(1040,1260),(32,36,39));draw=ImageDraw.Draw(overview)
for idx,clip in enumerate(manifest['clips']):
    raw=Path(clip['folder']);canvas=tuple(map(int,clip['canvas']));name=clip['name']
    assert any(Image.open(raw/f"{f['index']:04d}_front.png").getbbox() for f in clip['frames']), (clip['id'],'missing concept effects')
    tags=write_aseprite(out/(name+'.aseprite'),clip['frames'],raw,canvas,clip['anchor'])
    notes.append(dict(id=clip['id'],file=name+'.aseprite',canvas=list(canvas),anchor=clip['anchor'],frame_count=len(clip['frames']),duration_ms=sum(f['duration_ms'] for f in clip['frames']),tags=tags,frames=clip['frames']))
    images=[]
    scale=min(1,1024/canvas[0]);size=(round(canvas[0]*scale),round(canvas[1]*scale))
    for frame in clip['frames'][::2]:
        bg=Image.new('RGBA',canvas,(32,36,39,255));bg.alpha_composite(composite(raw,frame,canvas))
        images.append(bg.resize(size,Image.Resampling.NEAREST).convert('RGB'))
    durations=[100]*len(images)
    if len(clip['frames'])%2:durations[-1]=50
    images[0].save(preview/(name+'.gif'),save_all=True,append_images=images[1:],duration=durations,loop=0,disposal=2)
    chosen={'light_nodule':18,'heavy_wave':40,'root_combo':72,'tracking_module':16,'root_ultimate':167,'decoy_counter':167}[clip['id']]
    still=composite(raw,clip['frames'][chosen],canvas)
    still.save(preview/(name+'.png'))
    thumbsize=(480,round(480*canvas[1]/canvas[0]));thumb=still.resize(thumbsize,Image.Resampling.NEAREST)
    x=(idx%2)*520+20;y=(idx//2)*420+34
    overview.paste(thumb,(x,y),thumb);draw.text((x,y-29),name,font=font,fill=(235,235,235))
    print('PACKAGED',clip['id'],len(clip['frames']),canvas,flush=True)
overview.save(preview/'总览.png')
(out/'时间轴.json').write_text(json.dumps(dict(status=manifest['status'],fps=20,world_units_per_pixel=1.4,layers=[l[0] for l in LAYERS],clips=notes),ensure_ascii=False,indent=2),encoding='utf-8')
(out/'开始画特效.md').write_text("""# 鹿 BOSS 根阶段绘制工程

这批是根阶段设计动画参考，尚未接入正式战斗。轻跺、重踩、快→快→慢使用专用 BOSS 调试房间中的真实鹿动作；根刺、大招及破解是提案时间轴的概念特效。先看 GIF，再打开 Aseprite 画即可。

- 01 轻跺与根瘤：真实 F07 落蹄后 0.12 秒拱出；根瘤保持约 6 秒，随后下沉。保持段可以只画少量循环帧。
- 02 重踩连续根浪：真实 F18 落蹄后，前方八根从近到远破土。每根预警 0.42 秒、相邻间隔 0.09 秒；整波与重踩共用一次命中预算。
- 03 根阶段快快慢：真实连击参考；两次根瘤、一次重踩根浪。01/02 的特效可以复用。
- 04 追踪破土模块：0.60 秒预警后，三根向上爆发、保持、碎裂退回；位置在预警时锁定，不追着玩家走。
- 05 全场根潮大招：吟唱→六轮追踪破土→汇集→整地预警→一次根潮上冲→喘息。全场构图用于看范围；正式素材可拆成重复的地面模块。
- 06 雾分身破解与反噬：演示大招 2.35 秒按 Q，未结算预警和后续根刺改追分身，终击汇到分身；力量沿地下抽回鹿蹄，鹿失衡 4.5 秒。分身持续到大招结束，不随 5 秒隐身到期消失。这是根阶段的雾分身破解，没有藤蔓牢笼。

## 怎么画

在 `绘制_前景`、`绘制_后景` 画；每一帧独立，空白帧没有链接。概念前后景、动作、预警均可隐藏。`动作参考_锁定` 包含鹿和破解时的分身参考；正式导出只取你的两个绘制层。

画布脚底原点保存在 `boss_origin` 切片：01/04 为 512×384、(256,332)；02/03 为 1024×384、(768,332)；05/06 为 2048×384、(1740,332)。画布变宽用于容纳连续根浪和整场范围，角色像素尺度不变。每个画布像素对应 1.4 个游戏世界单位。

全部工程 20 FPS、50 ms/帧；GIF 为便于浏览降采样至 10 FPS，原时长保留。深色背景只在 GIF 中，工程透明。允许减少绘制帧、重复保持帧和改时长；无需逐帧照抄。

范围、形状最终以你画的为准。现有根刺的细枝和宽度只是占位；提案判定矩形与美术几何待正式绘制后对齐。`时间轴.json` 保留真实动作帧、世界位置与提案阶段；暂不当作已实现伤害或道具逻辑。

工程、GIF、原始分层和校验结果均位于游戏仓库外，生成工具放在独立测试仓库。
""",encoding='utf-8')
archive=out.parent/'鹿BOSS_根阶段特效绘制工程.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in sorted(out.glob('*.aseprite')):z.write(p,p.name)
    for name in ['开始画特效.md','时间轴.json']:z.write(out/name,name)
    for p in sorted(preview.iterdir()):z.write(p,'预览/'+p.name)
print('ZIP',round(archive.stat().st_size/1024**2,2),'MiB',flush=True)
