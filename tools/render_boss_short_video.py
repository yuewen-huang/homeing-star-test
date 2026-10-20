from pathlib import Path
import subprocess, json, math, random, wave
import numpy as np
from PIL import Image,ImageDraw,ImageFont,ImageFilter

BASE=Path('D:/HomingStar/homeing-star-temp-assert/Recordings/20261019_boss_real_maps')
OUT=BASE/'short_video_release';OUT.mkdir(exist_ok=True)
FF=Path('D:/MiniMax/com.minimax.hub/MiniMax Design/current/resources/ffmpeg/ffmpeg.exe');FP=FF.with_name('ffprobe.exe')
MUSIC=Path('D:/HomingStar/homeing-star-game/assets/levels/town/audio/town_disorder_night.mp3')
FONT='C:/Windows/Fonts/msyhbd.ttc'; REG='C:/Windows/Fonts/msyh.ttc'; LAT='C:/Windows/Fonts/bahnschrift.ttf'
FILES={x['folder']:BASE/'stems'/x['file'] for x in json.loads((BASE/'manifest.json').read_text(encoding='utf8'))}
# start, native duration, output speed. No speed changes inside continuous parry runs.
SHOTS=[
 ('master_1',37.05,.75,.75,'一闪。','先看这一刀','震刀 × 连招 × 子弹时间',800,'red'),
 ('master_1',8.12,2.50,1,'叮。叮。叮。','师傅 · 回身三连','听清这三拍。',740,'cyan'),
 ('deer_3',6.18,2.75,1,'五连，全接。','朽角巡林者 · 风','节奏，越来越快。',730,'cyan'),
 ('crab_1',5.95,2.0,1,'三拍全接','晶蟹 · 盐田实战','近身，接刀。',640,'gold'),
 ('core_0',.78,.90,1,'四核 · 接刀','风区核心','01 / 风',1000,'cyan'),
 ('core_1',.78,.90,1,'四核 · 接刀','藤区核心','02 / 藤',280,'cyan'),
 ('core_2',.78,.90,1,'四核 · 接刀','雾区核心','03 / 雾',1000,'cyan'),
 ('core_3',.78,.90,1,'四核 · 接刀','根区核心','04 / 根',280,'cyan'),
 ('deer_1',3.58,2.0,1,'红刀 · 一闪','朽角巡林者 · 雾','这一刀，接住了。',700,'red'),
 ('deer_2',3.58,2.0,1,'红刀 · 一闪','朽角巡林者 · 根','接住，再反击。',700,'red'),
 ('master_1',38.86,3.0,1,'闪避 · 追击','师傅 · 子弹时间','慢下来，连上去。',920,'cyan'),
 ('deer_1',9.36,2.50,1,'闪避 · 追击','朽角巡林者 · 雾','把空隙，变成连招。',800,'cyan'),
 ('deer_4',5.55,3.40,1,'连刺 · 反震','朽角巡林者 · 藤','三连瞬刺，逐刀接住。',640,'gold'),
 ('deer_3',14.95,2.60,1,'红刀 · 终结','朽角巡林者 · 风','一闪，穿过去。',640,'red'),
 ('master_1',36.55,1.85,1,'最后一刀。','师傅 · 二阶段','下一刀，你来接。',800,'gold'),
]
COLORS={'cyan':(84,240,215),'gold':(244,196,110),'red':(255,112,88)}
TOTAL=sum(s[2]/s[3] for s in SHOTS)+1.15

def run(args,log):
 with open(OUT/log,'w',encoding='utf8') as f:
  subprocess.run([str(FF),'-hide_banner','-y',*map(str,args)],stdout=f,stderr=f,check=True)

def font(n,latin=False,regular=False):return ImageFont.truetype(LAT if latin else REG if regular else FONT,n)
def text(d,xy,s,size,color,latin=False,regular=False):d.text(xy,s,font=font(size,latin,regular),fill=color,stroke_width=0)
def spaced(d,xy,s,size,color,gap=4):
 x,y=xy
 for c in s:
  d.text((x,y),c,font=font(size),fill=color);x+=d.textlength(c,font=font(size))+gap

def layout(ori,shot,index,pane_y,pane_h):
 W,H=(1080,1920) if ori=='vertical' else (1920,1080)
 im=Image.new('RGBA',(W,H));d=ImageDraw.Draw(im)
 a=COLORS[shot[8]];cream=(240,243,231,255);muted=(155,180,174,255)
 if ori=='vertical':
  # Deliberate typography and generous safe margins for phone app controls.
  d.rectangle((0,0,W,430),fill=(5,16,18,188));d.rectangle((0,1415,W,H),fill=(5,16,18,210))
  text(d,(76,100),'归 航 星',35,cream);text(d,(76,158),'BLADE  /  RHYTHM',27,(*a,255),True)
  text(d,(76,235),shot[4],88,cream);text(d,(80,360),shot[5],31,muted)
  d.line((78,434,1000,434),fill=(*a,130),width=2)
  for x in (0,W-1):d.line((x,pane_y,x,pane_y+pane_h),fill=(*a,210),width=3)
  d.line((0,pane_y,W,pane_y),fill=(*a,220),width=3);d.line((0,pane_y+pane_h,W,pane_y+pane_h),fill=(*a,220),width=3)
  text(d,(78,1473),shot[6],48,cream)
  text(d,(80,1584),'连续震刀  /  红刀反击  /  闪避追击',27,muted)
  text(d,(80,1710),'HOMING STAR',29,(*a,255),True)
  text(d,(820,1710),f'{index+1:02d} / {len(SHOTS):02d}',29,muted,True)
  for j in range(len(SHOTS)):
   x=80+j*61;d.rectangle((x,1790,x+45,1794),fill=(*a,255) if j<=index else (89,117,113,120))
  # Corner cuts and fine circuit-like strokes stay outside the playfield.
  d.line((80,1680,80,1650,110,1650),fill=(*a,150),width=2)
  d.line((1000,190,1000,100,910,100),fill=(*a,110),width=2)
 else:
  d.rectangle((0,0,W,190),fill=(5,14,17,255));d.rectangle((0,890,W,H),fill=(5,14,17,255))
  text(d,(84,44),'归航星',32,cream);text(d,(235,51),'BLADE / RHYTHM',23,(*a,255),True)
  text(d,(84,96),shot[4],48,cream);text(d,(1200,108),shot[5],27,muted)
  text(d,(84,948),shot[6],37,cream);text(d,(1460,962),f'{index+1:02d}  /  {len(SHOTS):02d}',25,muted,True)
  d.line((84,1025,1836,1025),fill=(46,76,73,180),width=2)
  d.line((84,1025,84+(1836-84)*(index+1)/len(SHOTS),1025),fill=(*a,255),width=3)
  d.line((0,pane_y,W,pane_y),fill=(*a,170),width=2);d.line((0,pane_y+pane_h,W,pane_y+pane_h),fill=(*a,170),width=2)
 p=OUT/f'{ori}_layout_{index:02d}.png';im.save(p);return p

def wipe(ori,shot,pane_y,pane_h):
 W,H=(1080,1920) if ori=='vertical' else (1920,1080)
 layer=Image.new('RGBA',(W,H));d=ImageDraw.Draw(layer);a=COLORS[shot[8]]
 # Dark brush blade + two thin luminous edges, never a full-screen white flash.
 cx=W*.5;shift=pane_h*.38
 poly=[(cx-W*.24,pane_y),(cx+W*.06,pane_y),(cx+W*.06+shift,pane_y+pane_h),(cx-W*.24+shift,pane_y+pane_h)]
 d.polygon(poly,fill=(4,17,21,245))
 d.line((cx-W*.24-12,pane_y,cx-W*.24+shift-12,pane_y+pane_h),fill=(*a,210),width=8)
 d.line((cx+W*.06+10,pane_y,cx+W*.06+shift+10,pane_y+pane_h),fill=(229,255,240,180),width=3)
 random.seed(14)
 for i in range(32):
  y=pane_y+random.random()*pane_h;x=cx-W*.24+(y-pane_y)*.38-random.uniform(15,160)
  d.line((x,y,x-random.uniform(15,75),y-random.uniform(8,35)),fill=(*a,random.randint(60,160)),width=random.randint(1,3))
 p=OUT/f'{ori}_wipe_{shot[8]}.png';layer.save(p);return p

def parry_times(name,start,seconds,speed):
 ev=json.loads((BASE/name/'events.json').read_text(encoding='utf8'))
 arr=[]
 for e in ev:
  if e.get('event') in ['parry','red_parry','contact'] and e.get('result','PARRY_SUCCESS')=='PARRY_SUCCESS':
   t=e.get('frame',-999)/60
   if start<=t<start+seconds:arr.append((t-start)/speed)
 return arr

meta=[];cursor=0
for i,s in enumerate(SHOTS):
 dur=s[2]/s[3]
 meta.append({'clip':i,'source':s[0],'source_start':s[1],'source_seconds':s[2],'speed':s[3],'start':cursor,'duration':dur,'title':s[4],'map_caption':s[5]})
 cursor+=dur
(OUT/'edit_timeline.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
for ori in ['vertical','horizontal']:
 W,H=(1080,1920) if ori=='vertical' else (1920,1080)
 parts=[];previous=None
 for i,s in enumerate(SHOTS):
  name,start,seconds,speed,title,sub,footer,focus,tone=s;dur=seconds/speed
  wide=name.startswith('core_') or name=='deer_4' or i in [10,11]
  crop_w=1280 if (ori=='horizontal' or wide) else 720
  crop_x=max(0,min(1280-crop_w,int(focus-crop_w/2)))
  fg_h=round(W*440/crop_w)//2*2
  py=(H-fg_h)//2 if ori=='vertical' else (1080-fg_h)//2
  lay=layout(ori,s,i,py,fg_h);slash=wipe(ori,s,py,fg_h)
  times=parry_times(name,start,seconds,speed)
  z='1.012+0.00010*on'+''.join(f'+0.032*exp(-pow((on/60-{t:.5f})*17,2))' for t in times)
  # The background is the same native shot, heavily defocused and dimmed.
  timing=f'trim=duration={seconds:.6f},setpts=(PTS-STARTPTS)/{speed},fps=60'
  if ori=='vertical':
   graph=f'[0:v]{timing},split=2[raw][b];[b]scale=270:480:force_original_aspect_ratio=increase,crop=270:480,gblur=sigma=15,eq=brightness=-0.22:saturation=0.55,scale={W}:{H}[bg];'
  else:
   graph=f'[0:v]{timing}[raw];color=c=0x050e11:s={W}x{H}:r=60:d={dur:.6f}[bg];'
  graph+=f"[raw]crop={crop_w}:440:{crop_x}:160,zoompan=z='{z}':x='iw/2-iw/(2*zoom)':y='ih/2-ih/(2*zoom)':d=1:s={W}x{fg_h}:fps=60,setsar=1[fg];[bg][fg]overlay=0:{py}:shortest=1[scene];"
  graph+=f'[scene][1:v]overlay=0:0:shortest=1[art];'
  # A slash crosses each edit; a short outgoing ghost supplies the residual image.
  graph+=f"[art][2:v]overlay=x='if(lt(t,0.15),t/0.15*{W},-(1-(t-({dur:.6f}-0.15))/0.15)*{W})':y=0:enable='lt(t,0.15)+gt(t,{dur:.6f}-0.15)'[v];"
  graph+=f'[0:a]atrim=duration={seconds:.6f},asetpts=PTS-STARTPTS,atempo={speed},afade=t=in:d=0.008,afade=t=out:st={max(0,dur-.018):.5f}:d=0.018[a]'
  target=OUT/f'{ori}_{i:02d}.mp4'
  if not target.exists() or target.stat().st_size < 1000 or i==len(SHOTS)-1 or (ori=='vertical' and i in [10,11]):
   run(['-ss',f'{start:.6f}','-i',FILES[name],'-loop','1','-i',lay,'-loop','1','-i',slash,'-filter_complex',graph,'-map','[v]','-map','[a]','-t',f'{dur:.6f}','-r','60','-c:v','libx264','-crf','18','-preset','veryfast','-pix_fmt','yuv420p','-c:a','aac','-b:a','256k','-video_track_timescale','15360',target],f'{ori}_{i:02d}.log')
  parts.append(target);print('RENDERED',ori,i,flush=True)
 # Ending card holds a real final frame; it does not invent another hit.
 shot=OUT/f'{ori}_end_frame.png'
 run(['-ss',str(SHOTS[-1][2]/SHOTS[-1][3]-.17),'-i',parts[-1],'-frames:v','1',shot],f'{ori}_end_extract.log')
 endcard=Image.open(shot).convert('RGBA');d=ImageDraw.Draw(endcard)
 if ori=='vertical':
  d.rectangle((0,170,W,440),fill=(5,16,18,255));text(d,(76,205),'下一刀，',83,(242,245,233));text(d,(76,310),'你来接。',83,(244,196,110))
 else:
  d.rectangle((0,70,W,185),fill=(5,14,17,255));text(d,(84,89),'下一刀，你来接。',56,(244,196,110))
 endpng=OUT/f'{ori}_end.png';endcard.save(endpng)
 endmp4=OUT/f'{ori}_end.mp4'
 run(['-loop','1','-i',endpng,'-f','lavfi','-i','anullsrc=r=48000:cl=stereo','-t','1.15','-r','60','-c:v','libx264','-crf','18','-preset','veryfast','-pix_fmt','yuv420p','-c:a','aac','-b:a','256k','-video_track_timescale','15360',endmp4],f'{ori}_end.log')
 parts.append(endmp4)
 (OUT/f'{ori}_concat.txt').write_text('\n'.join("file '%s'"%p.as_posix() for p in parts),encoding='utf8')
 dry=OUT/f'{ori}_dry.mp4'
 run(['-f','concat','-safe','0','-i',OUT/f'{ori}_concat.txt','-c','copy',dry],f'{ori}_concat.log')
 # Custom soft air sweeps at selected cuts. Native parry contacts stay untouched.
 rate=48000;n=int(TOTAL*rate)+rate;who=np.zeros((n,2),np.float32);rng=np.random.default_rng(730)
 for e in meta[1:]:
  if e['clip'] in [5,6,7]:continue
  N=int(.20*rate);noise=rng.normal(0,1,N);spec=np.fft.rfft(noise);freq=np.fft.rfftfreq(N,1/rate);spec*=((freq>700)&(freq<5800));noise=np.fft.irfft(spec,n=N);noise/=max(abs(noise));noise*=np.sin(np.linspace(0,np.pi,N))**3*.035
  k=max(0,int((e['start']-.08)*rate));pan=np.linspace(.2,.8,N);who[k:k+N,0]+=noise*(1-pan);who[k:k+N,1]+=noise*pan
 sw=OUT/'transition_air.wav'
 with wave.open(str(sw),'wb') as w:w.setnchannels(2);w.setsampwidth(2);w.setframerate(rate);w.writeframes((np.clip(who,-1,1)*32767).astype('<i2').tobytes())
 target=OUT/('boss_short_vertical.mp4' if ori=='vertical' else 'boss_short_horizontal.mp4')
 # Use the energetic passage of the user's chosen phase-one soundtrack.
 graph=f'[1:a]atrim=duration={TOTAL:.6f},asetpts=PTS-STARTPTS,volume=0.105,afade=t=in:d=0.12,afade=t=out:st={TOTAL-.9:.6f}:d=0.9[bed];[0:a]asplit=2[native][key];[bed][key]sidechaincompress=threshold=0.023:ratio=7:attack=2:release=180[duck];[native][duck][2:a]amix=inputs=3:normalize=0,alimiter=limit=0.89:level=0[a]'
 run(['-i',dry,'-ss','64.056','-i',MUSIC,'-i',sw,'-filter_complex',graph,'-map','0:v:0','-map','[a]','-c:v','copy','-c:a','aac','-b:a','256k','-t',f'{TOTAL:.6f}','-movflags','+faststart',target],f'{ori}_final.log')
 print('FINAL',target,TOTAL,flush=True)
 # Clean cover from the cold-open composition, with a larger hook.
 run(['-ss','0.4','-i',target,'-frames:v','1',OUT/f'{ori}_cover_base.png'],f'{ori}_cover.log')
 cover=Image.open(OUT/f'{ori}_cover_base.png').convert('RGB');d=ImageDraw.Draw(cover)
 if ori=='vertical':
  d.rectangle((0,185,W,445),fill=(5,16,18));text(d,(76,204),'这一刀，',89,(242,245,233));text(d,(76,318),'我接住了。',89,(244,196,110))
 else:
  d.rectangle((0,70,W,185),fill=(5,14,17));text(d,(84,90),'这一刀，我接住了。',58,(244,196,110))
 cover.save(OUT/f'{ori}_cover.jpg',quality=95)

(OUT/'发布文案.txt').write_text('标题：把 BOSS 连招，打成一首歌\n\n文案：连续震刀、红刀一闪、闪避子弹时间追击。把音量打开，听这几声叮。\n\n#归航星 #独立游戏 #动作游戏 #震刀 #像素游戏\n\n竖屏：1080×1920 / 60 FPS\n横屏：1920×1080 / 60 FPS\n时长：约 30 秒\n全部来自真实地图实机录屏；无蛤蟆。录屏原 BGM 静音，后期配师傅一阶段现有音乐的强节奏段；原生震刀声保留。所有速度、构图、刀光转场、震动和混音均为后期处理，未修改游戏参数。',encoding='utf8')
print('SHORT VIDEO PACKAGE COMPLETE',flush=True)
