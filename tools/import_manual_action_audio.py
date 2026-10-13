"""Prepare user action sounds without changing the original WAVs."""
from pathlib import Path
import hashlib,json,wave
import numpy as np

SOURCE=Path(r"D:\音效包\提取音轨用\手动")
STAGING=Path(r"D:\HomingStar\Art\manual-action-audio-20261011")
TARGET=Path(r"D:\HomingStar\homing-star-godot\assets\sideview\audio\actions")
CLIPS=[
 ("主角起跳.wav","player_jump",None,-3),
 ("主角二段跳.wav","player_double_jump",None,-3),
 ("森林奔跑.wav","forest_run_01",(.28,.59),-3),
 ("森林奔跑.wav","forest_run_02",(.77,1.01),-3),
 ("森林跳跃落地.wav","forest_land",None,-3),
 ("鹿冲刺预警.wav","deer_charge_warning",None,-3),
 ("鹿奔跑.wav","deer_run",None,-3),
 ("鹿鸣-近.wav","deer_call_near",None,-6),
 ("鹿鸣-远.wav","deer_call_far",None,-6),
]

def main():
 STAGING.mkdir(parents=True,exist_ok=True); TARGET.mkdir(parents=True,exist_ok=True)
 rows=[]
 for filename,key,cut,peak_db in CLIPS:
  path=SOURCE/filename
  with wave.open(str(path),"rb") as w:
   assert w.getsampwidth()==2
   rate=w.getframerate()
   a=np.frombuffer(w.readframes(w.getnframes()),dtype="<i2").reshape(-1,w.getnchannels()).astype(float).mean(axis=1)/32768
  if cut:
   a=a[int(cut[0]*rate):int(cut[1]*rate) if cut[1] else len(a)]
  window=max(1,int(.01*rate))
  levels=np.array([np.sqrt(np.mean(a[i:i+window]**2)) for i in range(0,len(a),window)])
  active=np.flatnonzero(levels>levels.max()*.04)
  start=max(0,int(active[0]*window-.015*rate)); end=min(len(a),int((active[-1]+1)*window+.03*rate))
  a=a[start:end]; gain=10**(peak_db/20)/max(np.max(np.abs(a)),1e-9)
  a*=gain
  fade=min(len(a)//2,int(.006*rate)); a[:fade]*=np.linspace(0,1,fade); a[-fade:]*=np.linspace(1,0,fade)
  with wave.open(str(STAGING/(key+".wav")),"wb") as w:
   w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(np.round(a*32767).astype("<i2").tobytes())
  rows.append({"key":key,"source":filename,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"duration":len(a)/rate,"gain_db":float(20*np.log10(gain)),"segment":cut,"trim_seconds":start/rate,"peak_db":peak_db})
  print(key,round(len(a)/rate,3),"seconds")
 (STAGING/"manifest.json").write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding="utf-8")
 return rows

if __name__=="__main__": main()
