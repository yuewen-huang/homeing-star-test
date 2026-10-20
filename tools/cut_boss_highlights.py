from pathlib import Path
import subprocess, json
from mix_boss_reel_audio import mix
BASE=Path('D:/HomingStar/homeing-star-temp-assert/Recordings/20261019_boss_real_maps')
FF=Path('D:/MiniMax/com.minimax.hub/MiniMax Design/current/resources/ffmpeg/ffmpeg.exe')
PARTS=BASE/'highlights_parts';PARTS.mkdir(exist_ok=True)
manifest=json.loads((BASE/'manifest.json').read_text(encoding='utf8'))
files={r['folder']:BASE/'stems'/r['file'] for r in manifest}

def run(args,log):
 with open(BASE/log,'w',encoding='utf8') as f:subprocess.run([str(FF),'-hide_banner','-y',*map(str,args)],stdout=f,stderr=f,check=True)

def start(folder,take):
 ev=json.loads((BASE/folder/'events.json').read_text(encoding='utf8'))
 return next(e['frame']/60 for e in ev if e.get('take')==take and e['event']=='take_start')

segments=[
 ('master_1',start('master_1','return_chain')+.4,3.65,'师傅 · 三连震刀'),
 ('deer_3',start('deer_3','accel_five')+.4,4.7,'风 · 加速五连'),
 ('master_1',next(e['frame']/60 for e in json.loads((BASE/'master_1/events.json').read_text()) if e['event']=='evade' and e['take']=='bullet_time_attack_0')-.25,3.9,'师傅 · 闪避追击'),
 ('deer_1',.45,5.8,'雾 · 接刀反击'),
 ('deer_2',.45,5.8,'根 · 接刀反击'),
 ('deer_3',start('deer_3','red_finale')+.4,5.4,'风 · 红刀终结'),
 ('deer_3',start('deer_3','three_ding_dodge')+.6,4.0,'风 · 子弹时间'),
 ('deer_4',start('deer_4','pierce_triple')+.4,5.7,'藤 · 三连瞬刺'),
 ('crab_1',next(e['frame']/60 for e in json.loads((BASE/'crab_1/events.json').read_text()) if e['event']=='start' and e['combo']=='triple')+.1,8.0,'盐田晶蟹 · 连续接刀'),
 ('master_1',start('master_1','phase_2_dash')+.35,2.35,'师傅 · 二阶段红刀'),
]
for folder in ['core_0','core_1','core_2','core_3']:
 segments.append((folder,.35,1.4,folder+' · 光圈接刀'))
 if folder=='core_0': segments.append((folder,start(folder,'ring_dodge')+.45,3.7,'风区核心 · 闪避追击'))
chapters=[]; timeline=0; parts=[]
for i,(folder,at,duration,title) in enumerate(segments):
 target=PARTS/f'{i:02d}.mp4'
 run(['-ss',f'{at:.4f}','-i',files[folder],'-t',duration,'-c:v','libx264','-crf','18','-preset','fast','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-af',f'afade=t=in:d=0.025,afade=t=out:st={duration-.04}:d=0.04','-video_track_timescale','15360',target],f'highlights_{i:02d}.log')
 parts.append(target)
 chapters.append({'t':round(timeline,2),'title':title,'source':folder,'source_start':at,'duration':duration})
 timeline+=duration
 print('CUT',i,title,flush=True)
(PARTS/'concat.txt').write_text('\n'.join("file '%s'" % x.as_posix() for x in parts),encoding='utf8')
run(['-f','concat','-safe','0','-i',PARTS/'concat.txt','-c','copy','-movflags','+faststart',BASE/'stems/boss_highlights.mp4'],'highlights_encode.log')
mix(BASE/'stems/boss_highlights.mp4',BASE/'boss_highlights.mp4',BASE/'highlights_mix.log')
(BASE/'highlights_chapters.json').write_text(json.dumps(chapters,ensure_ascii=False,indent=2),encoding='utf8')
print('HIGHLIGHTS COMPLETE',timeline,flush=True)
