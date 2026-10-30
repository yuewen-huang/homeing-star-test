from pathlib import Path
import subprocess, json, time
from mix_boss_reel_audio import mix
BASE=Path('D:/HomingStar/homeing-star-temp-assert/Recordings/20261019_boss_real_maps')
FF=Path('D:/MiniMax/com.minimax.hub/MiniMax Design/current/resources/ffmpeg/ffmpeg.exe')
FP=FF.with_name('ffprobe.exe')
JOBS=[('master_1','01_master','师傅 · 一、二阶段'),('deer_1','02_deer_mist','朽角巡林者 · 雾'),('deer_2','03_deer_root','朽角巡林者 · 根'),('deer_3','04_deer_wind','朽角巡林者 · 风'),('deer_4','05_deer_vine','朽角巡林者 · 藤'),('crab_1','06_crystal_crab','晶蟹'),('core_0','07_core_wind','风区核心'),('core_1','08_core_vine','藤区核心'),('core_2','09_core_mist','雾区核心'),('core_3','10_core_root','根区核心')]

def call(args,log):
    with open(BASE/log,'w',encoding='utf8') as f:
        subprocess.run([str(FF),'-hide_banner','-y',*map(str,args)],stdout=f,stderr=f,check=True)

def probe(path):
    return json.loads(subprocess.check_output([str(FP),'-v','error','-show_streams','-show_format','-of','json',str(path)]))

(BASE/'stems').mkdir(exist_ok=True)
start=time.monotonic(); results=[]
for folder,stem,title in JOBS:
    src=BASE/folder/'raw.avi'; log=BASE/folder/'record.log'
    while not log.exists() or 'Done recording movie' not in log.read_text(encoding='utf8',errors='replace'):
        if time.monotonic()-start>1500: raise TimeoutError(folder)
        time.sleep(2)
    target=BASE/'stems'/(stem+'.mp4')
    if not target.exists() or src.stat().st_mtime > target.stat().st_mtime or (folder=='deer_4' and float(probe(target)['format']['duration'])>12.1):
        call(['-i',src,*(['-t','12.0'] if folder=='deer_4' else []),'-c:v','libx264','-crf','18','-preset','fast','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-movflags','+faststart',target],stem+'_encode.log')
    mixed=BASE/target.name
    if not mixed.exists() or mixed.stat().st_mtime < target.stat().st_mtime:
        mix(target,mixed,BASE/(stem+'_mix.log'))
    info=probe(mixed)
    assert any(s['codec_type']=='audio' for s in info['streams'])
    video=next(s for s in info['streams'] if s['codec_type']=='video')
    assert (video['width'],video['height'],video['r_frame_rate'])==(1280,720,'60/1')
    dur=float(info['format']['duration'])
    results.append({'folder':folder,'file':target.name,'title':title,'duration':dur})
    print('ENCODED',stem,round(dur,2),flush=True)
    # Decode complete streams as an integrity check and measure native audio.
    call(['-i',target,'-af','volumedetect','-f','null','-'],stem+'_verify.log')
    assert 'mean_volume: -inf' not in (BASE/(stem+'_verify.log')).read_text(encoding='utf8',errors='replace')

(BASE/'manifest.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
# The full chronological collection uses the same codec, format and original audio.
(BASE/'concat.txt').write_text('\n'.join("file '%s'" % (BASE/'stems'/r['file']).as_posix() for r in results),encoding='utf8')
call(['-f','concat','-safe','0','-i',BASE/'concat.txt','-c','copy','-movflags','+faststart',BASE/'stems/boss_collection.mp4'],'collection_encode.log')
mix(BASE/'stems/boss_collection.mp4',BASE/'boss_collection.mp4',BASE/'collection_mix.log')
lines=['# BOSS 震刀与闪避追击录制','', '720p / 60 FPS。正式地图实机录屏，脚本输入、真实碰撞判定，无敌关闭。原 BGM 在录制进程中静音，后期统一配师傅一阶段音乐；震刀相对其它音效突出 6 dB，配乐低音量铺底并在打击时自动避让。未修改游戏代码、参数或已保存的音频设置。','', '覆盖师傅一、二阶段；朽角巡林者雾、根、风、藤四阶段；晶蟹，以及风、藤、雾、根四个区域核心。','', '蛤蟆按要求排除；双鱼尚无战斗招式，未收录。','', '| 视频 | 时长 |','|---|---|']
for r in results: lines.append(f"| [{r['title']}]({(BASE/r['file']).as_posix()}) | {r['duration']:.1f} 秒 |")
lines += ['', '真实地图：师傅为教程战斗场；朽角四阶段为第一章鹿 BOSS 房；晶蟹为第二章盐田的原生遭遇；四核心分别为风、藤、雾、根的正式核心房。', '', f'[完整合集]({(BASE/"boss_collection.mp4").as_posix()})', f'[精华剪辑]({(BASE/"boss_highlights.mp4").as_posix()})', '', '区域核心展示正式战斗的光圈接刀；没有额外阶段。各片段开始时重置位置及状态，交锋过程由游戏判定。普通难度沿用正式连续震刀辅助；晶蟹沿用困难难度逐刀输入。','', '闪避追击段由真实闪避触发游戏子弹时间，之后通过 J 输入连击。录像脚本使用内存进度，不更改玩家存档。','', '每段目录保留原始 AVI、判定 events.json、日志和关键帧。']
(BASE/'观看说明.md').write_text('\n'.join(lines),encoding='utf8')
print('PACKAGE COMPLETE',flush=True)
