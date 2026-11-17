"""Local native-frame viewer: every captured frame, with source-pose stepping."""
import argparse
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--before', type=Path, required=True)
p.add_argument('--before-trace', type=Path, required=True)
p.add_argument('--after', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
versions = []
for label, directory, trace in [('修改后', a.after, a.after/'fish_frames.json'),
                                 ('修改前', a.before, a.before_trace)]:
    records = json.loads(trace.read_text(encoding='utf-8'))['frames']
    records = [r for r in records if (directory / f'movie_{r["index"]:03}.png').exists()]
    versions.append({'label': label, 'base': directory.resolve().as_uri(), 'frames': records})
html = r'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>双鱼逐帧检查</title>
<style>body{margin:20px auto;max-width:1280px;padding:0 20px;background:#161d21;color:#dce9ec;font:16px/1.65 system-ui}h1{font-size:24px}button,select{background:#263741;color:inherit;border:1px solid #526873;border-radius:5px;padding:7px 12px;cursor:pointer}button:hover{background:#365562}#screen{width:100%;display:block;background:#111}#seek{width:100%;accent-color:#8ed2d6}#bar,#marks{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}#readout{white-space:pre-wrap;font-family:monospace;font-size:14px}p{color:#aabfc5}#marks button{font-size:12px}strong{color:#8ed2d6}</style>
<h1>双鱼逐帧检查</h1><p>游戏原生截图。← → 前后一步为 1/60 秒；Shift + ← → 跳到任一鱼的下一张原画。可切换修改前后，暂停对照接缝。</p>
<div id="bar"><select id="version"></select><button id="back">← 上一帧</button><button id="play">播放</button><button id="next">下一帧 →</button><button id="pose">下一张原画</button><select id="speed"><option value="1">原速 1×</option><option value=".5">慢放 0.5×</option><option value=".25">慢放 0.25×</option></select></div>
<img id="screen" alt="双鱼游戏原生帧"><input id="seek" type="range" min="0" value="0"><div id="readout"></div><div id="marks"></div>
<p>本轮核对：上转长尾接缝、下转反向帧、行进方向骤变、双鱼迎面避让。截图保留原画轮廓；方向数字是行进方向，不能替代对鱼身和尾鳍的观察。</p>
<script>const versions=__DATA__;
const $=id=>document.getElementById(id);let v=0,n=0,playing=false,last=0,acc=0;
const clips=[['横游',0,16],['低头回旋',16,32],['展鳍扫摆',48,32],['仰头压潜',80,32],['双回旋',112,32],['蜷身前探',144,32],['抬头回旋',176,32],['摆尾',208,32]];
function fish(f){const c=clips.find(c=>f.frame>=c[1]&&f.frame<c[1]+c[2]);return `${c[0]} 第 ${f.frame-c[1]+1} 帧${f.mirror?' · 镜像':''}｜${f.action}｜行进 ${((f.heading*180/Math.PI%360+360)%360).toFixed(1)}°`;}
function show(){const ver=versions[v];n=Math.max(0,Math.min(n,ver.frames.length-1));const r=ver.frames[n];$('screen').src=ver.base+'/movie_'+String(r.index).padStart(3,'0')+'.png';$('seek').value=n;$('readout').textContent=`${ver.label}  ${r.time.toFixed(3)} 秒 · 实机帧 ${r.index} / ${ver.frames.length-1}\n昭：${fish(r.white)}\n玄：${fish(r.black)}`;}
function key(r){return [r.white.frame,r.white.mirror,r.black.frame,r.black.mirror].join('/');}
function step(d,pose=false){playing=false;$('play').textContent='播放';const rows=versions[v].frames;const old=key(rows[n]);do{n+=d;}while(pose&&n>0&&n<rows.length-1&&key(rows[n])===old);show();}
function change(){v=Number($('version').value);$('seek').max=versions[v].frames.length-1;const marks=$('marks');marks.replaceChildren();function mark(i,label){let b=document.createElement('button');b.textContent=label;b.onclick=()=>{playing=false;n=i;show();};marks.append(b);}mark(150,'2.50s 汇合前');versions[v].frames.forEach((r,i,rows)=>{if(!i)return;for(const c of ['white','black']){if(r[c].turning&&!rows[i-1][c].turning)mark(i,`${r.time.toFixed(2)}s ${c==='white'?'昭':'玄'}${r[c].action==='turn_up'?'上转':'下转'}`);if(r[c].mirror!==rows[i-1][c].mirror)mark(Math.max(0,i-2),`${r.time.toFixed(2)}s ${c==='white'?'昭':'玄'}接缝`);}});show();}
versions.forEach((v,i)=>$('version').add(new Option(v.label,i)));$('version').onchange=change;$('seek').oninput=()=>{playing=false;n=Number($('seek').value);show();};$('back').onclick=()=>step(-1);$('next').onclick=()=>step(1);$('pose').onclick=()=>step(1,true);$('play').onclick=()=>{playing=!playing;acc=0;$('play').textContent=playing?'暂停':'播放';};document.onkeydown=e=>{if(e.key==='ArrowRight'||e.key==='ArrowLeft'){e.preventDefault();step(e.key==='ArrowRight'?1:-1,e.shiftKey);}if(e.code==='Space'){e.preventDefault();$('play').click();}};
function tick(t){if(playing){acc+=(t-last)/1000*60*Number($('speed').value);const d=Math.floor(acc);if(d){acc-=d;n+=d;if(n>=versions[v].frames.length){n=0;}show();}}last=t;requestAnimationFrame(tick);}change();requestAnimationFrame(tick);
</script></html>'''
a.out.parent.mkdir(parents=True, exist_ok=True)
a.out.write_text(html.replace('__DATA__', json.dumps(versions, ensure_ascii=False)), encoding='utf-8')
print(a.out)
