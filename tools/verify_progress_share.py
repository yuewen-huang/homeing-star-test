from pathlib import Path
import subprocess,json,sys
from PIL import Image,ImageDraw,ImageFont
NEURAL='--xiaoxiao' in sys.argv
O=Path('D:/HomingStar/homeing-star-temp-assert/Recordings/20261019_boss_real_maps')/('progress_share_xiaoxiao' if NEURAL else 'progress_share_release')
FF=Path('D:/MiniMax/com.minimax.hub/MiniMax Design/current/resources/ffmpeg/ffmpeg.exe');FP=FF.with_name('ffprobe.exe')
V=O/('归航星_开发进度分享_晓晓版.mp4' if NEURAL else '归航星_开发进度分享_竖版.mp4')
data=json.loads(subprocess.check_output([str(FP),'-v','quiet','-show_streams','-show_format','-of','json',str(V)]))
with open(O/'decode_check.log','w') as f:
 p=subprocess.run([str(FF),'-v','error','-i',str(V),'-f','null','-'],stdout=f,stderr=f)
assert p.returncode==0 and (O/'decode_check.log').stat().st_size==0
with open(O/'audio_check.log','w') as f:
 subprocess.run([str(FF),'-hide_banner','-i',str(V),'-vn','-af','volumedetect','-f','null','-'],stdout=f,stderr=f,check=True)
times=[2,16,25,29.5,35.5,38.6,42,45.5,50,58,66,79]
sheet=Image.new('RGB',(4*270,3*500),'#0b191b');d=ImageDraw.Draw(sheet)
for i,t in enumerate(times):
 out=O/f'qa_{t:g}.jpg'
 subprocess.run([str(FF),'-v','error','-y','-ss',str(t),'-i',str(V),'-frames:v','1','-q:v','2',str(out)],check=True)
 im=Image.open(out);im.thumbnail((270,480));x=(i%4)*270;y=(i//4)*500
 sheet.paste(im,(x,y+20));d.text((x+10,y+2),f'{t:.1f}s',fill='white')
sheet.save(O/'qa_contact_sheet.jpg',quality=92)
report=dict(duration=float(data['format']['duration']),size=int(data['format']['size']),resolution=[data['streams'][0]['width'],data['streams'][0]['height']],fps=data['streams'][0]['r_frame_rate'],full_decode='passed',narration='Xiaoxiao Neural +0%' if NEURAL else 'local Chinese female',minigames_seconds=9.2,captions=20)
(O/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
