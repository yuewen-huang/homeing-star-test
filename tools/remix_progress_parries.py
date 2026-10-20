from pathlib import Path
import subprocess,json
import numpy as np

B=Path('D:/HomingStar/homeing-star-temp-assert/Recordings/20261019_boss_real_maps')
O=B/'progress_share_xiaoxiao';W=O/'parry_mix';W.mkdir(exist_ok=True)
FF=Path('D:/MiniMax/com.minimax.hub/MiniMax Design/current/resources/ffmpeg/ffmpeg.exe');FP=FF.with_name('ffprobe.exe')
OLD=O/'归航星_开发进度分享_晓晓版.mp4'
OUT=O/'归航星_开发进度分享_晓晓_震刀强化版.mp4'
MUSIC=Path('D:/HomingStar/homeing-star-game/assets/levels/town/audio/town_disorder_night.mp3')
SR=48000
duration=float(subprocess.check_output([str(FP),'-v','quiet','-show_entries','format=duration','-of','csv=p=0',str(OLD)]))
N=round(duration*SR)
def decode(path,filters=None,seek=None):
 args=[str(FF),'-v','error']
 if seek is not None:args+=['-ss',str(seek)]
 args+=['-i',str(path),'-t',str(duration)]
 if filters:args+=['-af',filters]
 args+=['-f','f32le','-ar',str(SR),'-ac','2','pipe:1']
 a=np.frombuffer(subprocess.check_output(args),np.float32).reshape(-1,2).copy()
 if len(a)<N:a=np.pad(a,((0,N-len(a)),(0,0)))
 return a[:N]

shots=json.loads((B/'short_video_release/edit_timeline.json').read_text(encoding='utf8'))
shots.extend([dict(source='master_1',source_start=8.12,source_seconds=4.,start=44.,speed=1),dict(source='deer_1',source_start=9.36,source_seconds=3.5,start=48.,speed=1)])
events=[]
for shot in shots:
 for e in json.loads((B/shot['source']/'events.json').read_text(encoding='utf8')):
  event=e.get('event')
  if event not in ['parry','red_parry','contact']:continue
  if event=='contact' and e.get('result')!='PARRY_SUCCESS':continue
  t=e.get('frame',-999)/60
  if shot['source_start']<=t<shot['source_start']+shot['source_seconds']:
   at=shot['start']+(t-shot['source_start'])/shot['speed']
   if at<29.2 or at>=44:events.append(dict(time=round(at,5),kind=event,source=shot['source']))
events=sorted({round(e['time'],4):e for e in events}.values(),key=lambda e:e['time'])

# Raised-cosine windows avoid clicks. Accents are existing recorded contacts only.
def envelope(pre,hold,release):
 env=np.zeros(N,np.float32)
 for e in events:
  a=max(0,round((e['time']-pre)*SR));b=round(e['time']*SR);c=round((e['time']+hold)*SR);d=min(N,round((e['time']+hold+release)*SR))
  x=np.ones(d-a,np.float32)
  if b>a:x[:b-a]=.5-.5*np.cos(np.linspace(0,np.pi,b-a))
  if d>c:x[c-a:]=.5+.5*np.cos(np.linspace(0,np.pi,d-c))
  env[a:d]=np.maximum(env[a:d],x)
 return env
accent=envelope(.018,.12,.23)
duck=envelope(.045,.17,.22)
native=decode(O/'picture_dry.mp4')
brighter=decode(O/'picture_dry.mp4','highpass=f=70,equalizer=f=2800:t=q:w=0.8:g=2.8')
native+=accent[:,None]*(brighter-native)
native*=1+accent[:,None]*.8
voice=decode(O/'narration.wav')
voice*=1-duck[:,None]*.35
music=decode(MUSIC,seek=64.056)
# A smooth speech activity envelope keeps the music out of narration's way.
hop=480
rms=np.sqrt(np.mean(voice[:N//hop*hop].reshape(-1,hop,2)**2,axis=(1,2)))
activity=np.minimum(1,rms/.025)
smooth=np.zeros_like(activity)
level=0.
for i,v in enumerate(activity):
 level+=(v-level)*(.65 if v>level else .045);smooth[i]=level
speech=np.repeat(smooth,hop)
speech=np.pad(speech,(0,N-len(speech)),mode='edge')
gain=.11*(1-.67*speech)*(1-.78*duck)
fade=np.minimum(1,np.arange(N)/(SR*.3))*np.minimum(1,(N-1-np.arange(N))/(SR*2))
music*=gain[:,None]*fade[:,None]
for name,a in [('native',native),('voice',voice),('music',music)]:a.astype('<f4').tofile(W/(name+'.f32'))
args=[str(FF),'-hide_banner','-nostdin','-y','-i',str(OLD)]
for name in ['native','voice','music']:args+=['-f','f32le','-ar',str(SR),'-ac','2','-i',str(W/(name+'.f32'))]
args+=['-filter_complex','[1:a][2:a][3:a]amix=inputs=3:normalize=0,aresample=192000,alimiter=limit=0.86:attack=2:release=65:level=0,aresample=48000[a]','-map','0:v:0','-map','[a]','-c:v','copy','-c:a','aac','-b:a','256k','-t',str(duration),'-movflags','+faststart',str(OUT)]
with open(W/'encode.log','w') as f:subprocess.run(args,stdout=f,stderr=f,check=True)
report=dict(contacts=len(events),contact_events=events,native_contact_gain_db=5.1,contact_presence_eq_db=2.8,voice_duck_at_contact_db=3.74,music_duck_at_contact_db=13.15,game_modified=False)
(W/'mix_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('CONTACTS',len(events),'FINAL',OUT,flush=True)
