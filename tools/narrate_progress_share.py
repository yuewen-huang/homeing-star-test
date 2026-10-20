from pathlib import Path
import sys, asyncio, json, subprocess
sys.path.insert(0, str(Path('D:/HomingStar/homeing-star-test/artifacts/video_python')))
import edge_tts

OUT=Path('D:/HomingStar/homeing-star-temp-assert/Recordings/20261019_boss_real_maps/progress_share_xiaoxiao')
OUT.mkdir(exist_ok=True)
LINES=[
 '同学们好呀，好久没来更新了。',
 '距离上次分享，差不多已经过去一个月，',
 '今天带大家看看《归航星》最近的进度。',
 '这段时间，我们主要在打磨战斗。',
 '从连续震刀、闪避后的追击，',
 '到不同BOSS的招式和阶段变化，',
 '前面这些就是目前的实机效果。',
 '战斗之外，四境的探索和几个小游戏也在继续完善，',
 '这里挑了几段给大家看看。',
 '后面也想穿插着分享一些制作过程，',
 '比如震刀的反馈怎么做、小游戏的手感怎么调。',
 '大家对哪些实现感兴趣，',
 '或者自己做的时候遇到了问题，都可以来问我，',
 '咱们一起交流，我也顺便整理一下这一路踩过的坑。',
 '现在还有不少细节要慢慢磨。',
 '哪里看着不太顺，或者有什么想玩的内容，',
 '都欢迎在评论区聊聊。',
 '想亲自上手的同学，也可以留个言，',
 '我会结合大家的反馈再细修一轮，',
 '争取尽快把试玩版放到Steam，让大家实际玩玩看。',
]
FP='D:/MiniMax/com.minimax.hub/MiniMax Design/current/resources/ffmpeg/ffprobe.exe'
async def main():
 data=[]
 for i,line in enumerate(LINES):
  p=OUT/f'voice_{i:02d}.mp3'
  if not p.exists() or p.stat().st_size<1000:
   spoken=line.replace('BOSS','Boss').replace('《','').replace('》','')
   await edge_tts.Communicate(spoken,voice='zh-CN-XiaoxiaoNeural',rate='+0%',pitch='+0Hz').save(str(p))
  dur=float(subprocess.check_output([FP,'-v','quiet','-show_entries','format=duration','-of','csv=p=0',str(p)]))
  data.append(dict(index=i,text=line,duration=dur,file=p.as_posix()))
  print(i,round(dur,2),line,flush=True)
 (OUT/'narration.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf8')
 (OUT/'口播文案.txt').write_text('\n'.join(LINES),encoding='utf8')
asyncio.run(main())
