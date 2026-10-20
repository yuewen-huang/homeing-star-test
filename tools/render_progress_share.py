from pathlib import Path
import subprocess,json,math,wave,sys,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFont

B=Path('D:/HomingStar/homeing-star-temp-assert/Recordings/20261019_boss_real_maps')
P=B/'short_video_release'; NEURAL='--xiaoxiao' in sys.argv
O=B/('progress_share_xiaoxiao' if NEURAL else 'progress_share_release');O.mkdir(exist_ok=True)
RAW=Path('D:/HomingStar/homeing-star-test/artifacts/录屏/movie3.avi')
FF=Path('D:/MiniMax/com.minimax.hub/MiniMax Design/current/resources/ffmpeg/ffmpeg.exe');FP=FF.with_name('ffprobe.exe')
MUSIC=Path('D:/HomingStar/homeing-star-game/assets/levels/town/audio/town_disorder_night.mp3')
FONT='C:/Windows/Fonts/msyhbd.ttc'; REG='C:/Windows/Fonts/msyh.ttc'
CUES=json.loads((O/'narration_timeline.json').read_text(encoding='utf8'))
END=max(83.2,CUES[-1]['start']+CUES[-1]['duration']+1.5)
if NEURAL:
 # Reuse the reviewed visual edit; regenerate the tail only if its duration changes.
 for name in ['00_battle.mp4']+[f'scene_{i:02d}.mp4' for i in range(13)]:
  target=O/name
  if not target.exists():shutil.copyfile(B/'progress_share_release'/name,target)

def run(args,name):
 with open(O/(name+'.log'),'w',encoding='utf8') as f:
  subprocess.run([str(FF),'-hide_banner','-nostdin','-y',*map(str,args)],stdout=f,stderr=f,check=True)
def probe(p):
 return json.loads(subprocess.check_output([str(FP),'-v','quiet','-show_streams','-show_format','-of','json',str(p)]))
def f(n,reg=False):return ImageFont.truetype(REG if reg else FONT,n)
def put(d,xy,t,n=36,c='#e9eee3'):d.text(xy,t,font=f(n),fill=c)

# Keep the approved battle edit, cutting its old final hold before the exploration bridge.
if not (O/'00_battle.mp4').exists():
 run(['-i',P/'vertical_dry.mp4','-t','29.2','-c','copy',O/'00_battle.mp4'],'00_battle')

# Output start / source start / duration / presentation / title / caption / source.
# Minigames total 9.2 seconds. No repeated scoring or results screens.
SHOTS=[
 (29.2,49.5,2.8,'map','走进四境','雾 · 巨木迷境',RAW),
 (32.0,106.2,2.8,'map','云海与浮台','风 · 林海之上',RAW),
 (34.8,142.0,3.0,'game','乘风远航','避障与乱流',RAW),
 (37.8,210.0,3.4,'game','藤间飞渡','松手，再接住',RAW),
 (41.2,34.8,2.8,'game','符文轮盘','看准时机，连续命中',RAW),
 (44.0,8.12,4.0,'combat','聊聊制作','震刀反馈',B/'stems'/'01_master.mp4'),
 (48.0,9.36,3.5,'combat','聊聊制作','闪避与追击',B/'stems'/'02_deer_mist.mp4'),
 (51.5,175.5,4.5,'map','一起交流','藤 · 枝间穿行',RAW),
 (56.0,252.0,4.0,'map','继续打磨','根 · 幽蓝水光',RAW),
 (60.0,98.0,4.0,'map','听听你的想法','雾 · 林间探索',RAW),
 (64.0,116.0,4.5,'map','评论区见','风 · 借势跃起',RAW),
 (68.5,176.0,4.5,'map','想试玩，留个言','藤 · 密林深处',RAW),
 (73.0,255.0,3.5,'map','再细修一轮','根 · 林中居民',RAW),
 (76.5,117.0,END-76.5,'end','归航星','试玩版正在准备中',RAW),
]

def art(i,title,caption,py,ph,end=False):
 im=Image.new('RGBA',(1080,1920));d=ImageDraw.Draw(im)
 d.rectangle((0,0,1080,445),fill=(5,16,18,225))
 put(d,(78,100),'归 航 星',35)
 put(d,(78,162),'一个月的开发进度',29,'#75d3c4')
 put(d,(78,240),title,72)
 put(d,(82,353),caption,32,'#b3c5be')
 d.line((80,433,1000,433),fill='#65b8aa',width=2)
 d.line((0,py,1080,py),fill='#cbb579',width=3)
 d.line((0,py+ph,1080,py+ph),fill='#cbb579',width=3)
 if end:
  d.rounded_rectangle((110,1165,970,1325),radius=16,fill=(5,18,20,240),outline='#b0b89a',width=2)
  put(d,(160,1190),'一起讨论 · 一起打磨',51)
 p=O/f'art_{i:02d}.png';im.save(p);return p

parts=[O/'00_battle.mp4']
for i,(start,at,dur,kind,title,cap,src) in enumerate(SHOTS):
 target=O/f'scene_{i:02d}.mp4';parts.append(target)
 if target.exists():continue
 wide=kind=='game'; combat=kind=='combat'
 crop='crop=1160:630:60:45' if wide else 'crop=1280:440:0:160' if combat else 'crop=864:600:208:72'
 ph=586 if wide else 370 if combat else 750
 py=(1920-ph)//2
 overlay=art(i,title,cap,py,ph,kind=='end')
 graph=f'[0:v]trim=duration={dur},setpts=PTS-STARTPTS,fps=60,split=2[b][r];[b]scale=270:480:force_original_aspect_ratio=increase,crop=270:480,gblur=sigma=17,eq=brightness=-0.24:saturation=0.5,scale=1080:1920[bg];[r]{crop},scale=1080:{ph}:flags=lanczos,setsar=1[fg];[bg][fg]overlay=0:{py}:shortest=1[s];[s][1:v]overlay=0:0:shortest=1'
 # Gentle dark dip at the beginning of a section; no bright flash or fake hit.
 if i in [0,5,9,13]:graph+=',fade=t=in:d=0.16'
 if kind=='end':graph+=f',fade=t=out:st={dur-.6}:d=0.6'
 graph+='[v];'
 if combat:graph+=f'[0:a]atrim=duration={dur},asetpts=PTS-STARTPTS,afade=t=in:d=0.025,afade=t=out:st={dur-.04}:d=0.04[a]'
 else:graph+=f'anullsrc=r=48000:cl=stereo,atrim=duration={dur}[a]'
 run(['-ss',at,'-i',src,'-loop','1','-i',overlay,'-filter_complex',graph,'-map','[v]','-map','[a]','-t',dur,'-r','60','-c:v','libx264','-crf','20','-preset','veryfast','-threads','6','-pix_fmt','yuv420p','-c:a','aac','-ar','48000','-ac','2','-b:a','192k','-video_track_timescale','15360',target],f'scene_{i:02d}')
 print('SCENE',i,start,dur,flush=True)

(O/'concat.txt').write_text('\n'.join("file '%s'"%p.as_posix() for p in parts),encoding='utf8')
if not (O/'picture_dry.mp4').exists():run(['-f','concat','-safe','0','-i',O/'concat.txt','-c','copy',O/'picture_dry.mp4'],'concat')

# Offline narration: trim only engine padding; maintain each sentence's approved wording.
voice=np.zeros((int((END+1)*48000),2),dtype=np.float32)
for cue in CUES:
 wav=Path(cue['file']) if NEURAL else O/f"voice_{cue['index']:02d}.wav"
 pcm=subprocess.check_output([str(FF),'-v','error','-i',str(wav),'-f','f32le','-ar','48000','-ac','2','pipe:1'])
 x=np.frombuffer(pcm,np.float32).reshape(-1,2).copy()
 # Consistent speech loudness while retaining cadence; no change to the game audio.
 rms=np.sqrt(np.mean(x*x)); x*=min(5.,.105/max(rms,1e-6))
 ix=int(cue['start']*48000);voice[ix:ix+len(x)]+=x
voice=np.clip(voice,-.88,.88)
with wave.open(str(O/'narration.wav'),'wb') as w:
 w.setparams((2,2,48000,0,'NONE','not compressed'));w.writeframes((voice*32767).astype('<i2').tobytes())

base=Image.new('RGBA',(1080,1920));d=ImageDraw.Draw(base)
d.rectangle((0,1420,1080,1920),fill=(5,16,18,255))
put(d,(80,1715),'HOMING STAR  /  开发记录',27,'#87aea3')
d.line((80,1790,1000,1790),fill='#31534e',width=2)
d.rectangle((70,35,1010,84),fill=(5,16,18,240))
put(d,(82,39),'开发近况  ·  实机记录',25,'#b7c6b7')
base.save(O/'subtitle_base.png')

def ts(t):
 cs=round(t*100);return f'{cs//360000}:{cs//6000%60:02d}:{cs//100%60:02d}.{cs%100:02d}'
def wrap(s,n=18):
 rows=[]
 while len(s)>n:
  pos=n
  for k in range(n,max(5,n-5),-1):
   if s[k-1] in '，、。！':pos=k;break
  rows.append(s[:pos]);s=s[pos:]
 rows.append(s);return r'\N'.join(rows)
ass='''[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 2
[V4+ Styles]
Format: Name,Fontname,Fontsize,PrimaryColour,SecondaryColour,OutlineColour,BackColour,Bold,Italic,Underline,StrikeOut,ScaleX,ScaleY,Spacing,Angle,BorderStyle,Outline,Shadow,Alignment,MarginL,MarginR,MarginV,Encoding
Style: Speech,Microsoft YaHei,48,&H00EEF3EA,&H00FFFFFF,&H00121008,&H80121008,0,0,0,0,100,100,1,0,1,1.2,0,5,70,110,0,1
Style: Chapter,Microsoft YaHei,28,&H00A3CDBB,&H00FFFFFF,&H00121008,&H00121008,0,0,0,0,100,100,1,0,1,0,0,7,80,110,0,1
[Events]
Format: Layer,Start,End,Style,Name,MarginL,MarginR,MarginV,Effect,Text
'''
srt=[]
for j,c in enumerate(CUES):
 end=c['start']+c['duration']
 ass+=f"Dialogue: 1,{ts(c['start'])},{ts(end)},Speech,,0,0,0,,{{\\pos(530,1560)\\fad(70,100)}}{wrap(c['text'])}\n"
 def st(t):
  ms=round(t*1000);return f'{ms//3600000:02d}:{ms//60000%60:02d}:{ms//1000%60:02d},{ms%1000:03d}'
 srt.append(f"{j+1}\n{st(c['start'])} --> {st(end)}\n{wrap(c['text']).replace(chr(92)+'N',chr(10))}\n")
for at,to,label in [(0,11.2,'01 / 一个月的进度'),(11.2,29.2,'02 / 战斗打磨'),(29.2,39.2,'03 / 四境与小游戏'),(39.2,60,'04 / 一起聊聊制作'),(60,END,'05 / 交流与试玩计划')]:
 ass+=f'Dialogue: 0,{ts(at)},{ts(to)},Chapter,,0,0,0,,{{\\pos(80,1460)}}{label}\n'
(O/'captions.ass').write_text(ass,encoding='utf-8-sig')
(O/'字幕.srt').write_text('\n'.join(srt),encoding='utf-8-sig')

# Native parries remain dry. Quiet master phase-one track ducks under both voice and SFX.
graph="[0:v][1:v]overlay=0:0:shortest=1,ass=filename='captions.ass'[v];"
graph+=f'[3:a]asplit=3[vox][vk][sk];[2:a]volume=0.16,afade=t=in:d=0.3,afade=t=out:st={END-2}:d=2[music];'
graph+='[0:a]asplit=2[native][nk];[music][nk]sidechaincompress=threshold=0.023:ratio=5:attack=2:release=170[m1];'
graph+='[m1][vk]sidechaincompress=threshold=0.014:ratio=9:attack=7:release=240[bed];'
graph+='[native][sk]sidechaincompress=threshold=0.028:ratio=1.7:attack=12:release=100[fx];'
graph+='[vox][fx][bed]amix=inputs=3:normalize=0,alimiter=limit=0.89:level=0[a]'
final=O/('归航星_开发进度分享_晓晓版.mp4' if NEURAL else '归航星_开发进度分享_竖版.mp4')
import os
os.chdir(O)
run(['-i',O/'picture_dry.mp4','-loop','1','-i',O/'subtitle_base.png','-ss','64.056','-stream_loop','-1','-i',MUSIC,'-i',O/'narration.wav','-filter_complex',graph,'-map','[v]','-map','[a]','-t',END,'-r','60','-c:v','libx264','-crf','19','-preset','veryfast','-threads','6','-pix_fmt','yuv420p','-c:a','aac','-b:a','256k','-ar','48000','-movflags','+faststart',final],'final')
(O/'edit_manifest.json').write_text(json.dumps(dict(duration=END,minigame_seconds=9.2,voice='zh-CN-XiaoxiaoNeural / rate +0%' if NEURAL else 'Microsoft Huihui Desktop / local offline female',narration=CUES,append_shots=[dict(start=s[0],source_start=s[1],duration=s[2],kind=s[3],title=s[4],source=str(s[6])) for s in SHOTS],game_modified=False),ensure_ascii=False,indent=2),encoding='utf8')
print('FINAL',final,flush=True)
