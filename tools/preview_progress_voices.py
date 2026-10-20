from pathlib import Path
import sys,asyncio,json
sys.path.insert(0,'D:/HomingStar/homeing-star-test/artifacts/video_python')
import edge_tts

OUT=Path('D:/HomingStar/homeing-star-temp-assert/Recordings/20261019_boss_real_maps/progress_share_release/voice_previews')
OUT.mkdir(exist_ok=True)
TEXT='同学们好呀，好久没来更新了。距离上次分享，差不多已经过去一个月，今天带大家看看归航星最近的进度。'
async def main():
 for voice,name,rate in [('zh-CN-XiaoxiaoNeural','试听A_晓晓_自然聊天','+0%'),('zh-CN-XiaoyiNeural','试听B_晓伊_清亮利落','+5%')]:
  target=OUT/(name+'.mp3')
  if not target.exists() or target.stat().st_size<1000:
   await edge_tts.Communicate(TEXT,voice=voice,rate=rate,pitch='+0Hz').save(str(target))
  print(name,target.stat().st_size,flush=True)
 (OUT/'试听文字.txt').write_text(TEXT,encoding='utf8')
asyncio.run(main())
