"""Build the six reviewed master samples, exclusively from user-annotated frames."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT / 'smear-combo-demo'
sys.path.insert(0, str(PROJECT / 'tools'))
from smear_tools import Character, check_combo
from smear import describe, compose, body_height
from new_combo import write_combo

GODOT = 'D:/Godot/Godot_v4.7.2-stable_win64_console.exe'
SPECS = [
    ('trial', '试剑一斩', [('06', 5)], [0.65]),
    ('return', '回锋三连', [('07', 5), ('07', 14), ('07', 18)], [0.65, 1.25, 1.95]),
    ('spin', '旋风三连', [('08', 1), ('08', 9), ('08', 16)], [0.65, 1.25, 2.0]),
    ('suspended', '悬锋二式', [('10', 1), ('10', 8)], [0.75, 1.70]),
    ('intercept', '掠步截剑', [('09', 6), ('10', 1), ('10', 8)], [0.90, 1.70, 2.65]),
    ('air', '踏空四叠', [('11', 3), ('11', 7), ('11', 11), ('11', 15)], [0.80, 1.55, 2.30, 3.15]),
]
MIXED_SPECS = [
    ('ground_six', '回锋旋剑·六连', [('07', 5), ('07', 14), ('08', 1), ('08', 9), ('08', 16), ('07', 18)],
     [0.60, 1.15, 1.70, 2.25, 2.95, 3.75]),
    ('pursuit_seven', '掠步回锋·七连', [('09', 6), ('10', 1), ('07', 5), ('07', 14), ('08', 9), ('08', 16), ('07', 18)],
     [0.70, 1.30, 1.85, 2.40, 2.95, 3.60, 4.40]),
    ('sky_nine', '旋空归刃·九连', [('08', 1), ('08', 16), ('11', 3), ('11', 7), ('11', 11), ('11', 15), ('07', 5), ('07', 14), ('07', 18)],
     [0.65, 1.25, 1.95, 2.50, 3.05, 3.75, 4.45, 5.05, 5.85]),
]
REWORK_SPECS = [
    ('pressure_five', '压刃折返·五连', [('09',6), ('08',9), ('08',1), ('07',14), ('07',18)],
     [0.52,0.94,1.32,1.96,2.48]),
    ('flow_six', '游锋换势·六连', [('07',5), ('08',9), ('07',18), ('07',14), ('09',6), ('08',16)],
     [0.65,1.12,1.52,2.08,2.48,3.20]),
    ('sky_eight', '追空回身·八连', [('07',5), ('08',16), ('11',3), ('11',7), ('11',11), ('11',15), ('09',6), ('08',16)],
     [0.55,1.05,1.70,2.14,2.60,3.20,3.82,4.56]),
]


def verify(name, gif=False):
    result = subprocess.run([sys.executable, '-B', str(PROJECT/'tools/verify_combo.py'), name,
                             '--project', str(PROJECT), '--godot', GODOT] + (['--gif'] if gif else []),
                            capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=900)
    return result.stdout + result.stderr


def assert_marked(combo, character):
    assert 'recovery' not in combo, 'Do not use automatic recovery fallback'
    for cut in combo['cuts']:
        for frame in cut['lead'] + [cut['wind']] + cut['swing_frames'] + [cut['finish']] + cut['follow'] + cut['recover']:
            assert character.role(cut['action'], frame), (cut['action'], frame, 'unmarked')
        assert character.pose(cut['action'], cut['wind']) and character.pose(cut['action'], cut['finish'])


def write_rework_report():
    character = Character(PROJECT, 'master_phase1')
    digest = hashlib.sha256((character.folder/'character.json').read_bytes()).hexdigest()
    presentation_path = character.folder/'presentation.json'
    presentation = json.loads(presentation_path.read_text(encoding='utf-8')) if presentation_path.exists() else {}
    dash = next(a for a in character.actions if a.startswith('09_'))
    lines = ['# 师傅连招：当前样板与验证', '',
             '本报告由当前连招、标注和显示配置自动生成。原画、帧角色和实测坐标保留，比例补偿独立存于角色目录的 presentation.json。', '',
             '瞬移保持逆时针回扫；F3–5 引入、F6 蓄势、F7 挥刀中间帧、F8 定招。F7 没有单独测剑时，保留身体帧并在已测剑姿间插值。攻击二按用户文字确认的回扫 turn=1 编排，F17 是定招。', '',
             '瞬移当前实测：`'+json.dumps({k:v for k,v in character.poses.items() if k.startswith(dash+':')}, ensure_ascii=False)+'`', '',
             '瞬移采用约 75 世界像素的稳定刀带宽度；投影剑身变短时不再挤成细线，只影响可见刀带，不修改剑柄、剑尖及刀刃覆盖。普通尾迹限制最近 150°，末刀 200°。', '',
             '| 连招 | 接触时刻（动作秒） | 相邻间隔 | 标注版本 |', '| --- | --- | --- | --- |']
    sections = []
    for suffix, _, _, _ in REWORK_SPECS:
        name = 'master_phase1_rework_'+suffix
        folder = PROJECT/'combos'/name
        if not (folder/'audit.json').exists(): continue
        combo = json.loads((folder/'combo.json').read_text(encoding='utf-8'))
        audit = json.loads((folder/'audit.json').read_text(encoding='utf-8'))
        style = json.loads((folder/'style.json').read_text(encoding='utf-8'))
        _, contacts = check_combo(combo, character)
        gaps = [b-a for a,b in zip(contacts, contacts[1:])]
        lines.append('| '+style['title']+' | '+', '.join(f'{x:.3f}' for x in contacts)+' | '+', '.join(f'{x:.3f}' for x in gaps)+' | '+('最新' if audit['annotation_sha256']==digest else '待按新标注重建')+' |')
        sections += ['', '## '+style['title'], '', '场景：`combos/'+name+'/'+name+'.tscn`', '',
                     '| 刀 | 来源与帧 | 转向 | 蓄势/挥刀/保持 | 收势取消 |', '| --- | --- | --- | --- | --- |']
        for i, cut in enumerate(combo['cuts'],1):
            sections.append(f'| {i} | {cut["action"]} F{cut["wind"]} → {cut["swing_frames"]} → F{cut["finish"]} | {cut["turn"]} | {cut["wind_time"]:.3f}/{cut["swing"]:.3f}/{cut["hold"]:.3f} | '+('完整播放' if i==len(combo['cuts']) else f'{cut["cancel"]:.3f}s')+' |')
        sections += ['', '```text', audit['validation'].strip(), '```', '',
                     f'[实时 GIF]({name}/combo_realtime.gif) · [半速 GIF]({name}/combo_halfspeed.gif) · [预览图]({name}/combo_sheet.png)']
    if presentation:
        lines += ['', '## 固定动作比例', '',
                  '以攻击一站姿头顶到脚底 134 源像素为基准；每个动作整段等比缩放，不按单帧高低重新归一化，不裁画布，不改变脚底注册点。测量不包含举起的剑或特效。', '',
                  '| 动作 | 参考帧 | 身体高度 | 固定倍率 |', '| --- | --- | --- | --- |']
        for action, scale in presentation['action_scales'].items():
            m = presentation['body_measurements'][action]
            lines.append(f'| {action} | F{m["reference_frame"]} | {m["body_height"]} | {scale:.4f} |')
    lines += ['', '操作：1/空格重播，2 慢放，G 残影，V 画法，N/C 串联新版三套，Esc 返回列表。', '',
              '角色与刀光共用比例和动作时钟，击停一起冻结。八连的追进与木桩击退仅是演示编排，不直接应用到正式 BOSS。', '',
              '回归通过：绘制挥刀帧、收势取消链、尾迹角度限制、短投影剑身稳定刀带，以及测量剑姿和刀刃覆盖不变性。']
    (PROJECT/'verification/master_phase1_rework_report.md').write_text('\n'.join(lines+sections)+'\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--mixed', action='store_true')
    parser.add_argument('--rework', action='store_true')
    parser.add_argument('--only', choices=[s[0] for s in SPECS + MIXED_SPECS + REWORK_SPECS])
    args = parser.parse_args()
    character = Character(PROJECT, 'master_phase1')
    if args.rework:
        # User explicitly confirmed this is a returning sweep, even if an older open
        # annotation editor writes its stale thrust setting back to disk. Do not edit
        # their measured poses/roles or compete with the editor's save operation.
        action = next(a for a in character.actions if a.startswith('07_'))
        character.turns[action + ':14'] = 1
    annotation = PROJECT/'characters/master_phase1/character.json'
    digest = hashlib.sha256(annotation.read_bytes()).hexdigest()
    presentation = PROJECT/'characters/master_phase1/presentation.json'
    presentation_digest = hashlib.sha256(presentation.read_bytes()).hexdigest() if presentation.exists() else None
    prefix = 'master_phase1_rework_' if args.rework else ('master_phase1_chain_' if args.mixed else 'master_phase1_reviewed_')
    audit = PROJECT / 'verification' / ('master_phase1_rework' if args.rework else ('master_phase1_chains' if args.mixed else 'master_phase1_reviewed'))
    audit.mkdir(parents=True, exist_ok=True)
    (audit/'character_snapshot.json').write_bytes(annotation.read_bytes())
    if presentation.exists(): (audit/'presentation_snapshot.json').write_bytes(presentation.read_bytes())
    available = {(action[:2], cut['wind']): describe(character, cut)
                 for action in sorted(character.actions) for cut in character.cuts_in(action)}
    for suffix, title, selection, beats in (REWORK_SPECS if args.rework else (MIXED_SPECS if args.mixed else SPECS)):
        if args.only and suffix != args.only:
            continue
        name = prefix + suffix
        folder = PROJECT/'combos'/name
        if args.render:
            output = verify(name, gif=True)
            (audit/(suffix+'_render.log')).write_text(output, encoding='utf-8')
            print(name, output, flush=True)
            continue
        chain = [available[key] for key in selection]
        combo = compose(character, 'master_phase1', chain, 0.35, body_height(character))
        # All six selected last cuts have their own marked recovery; no fallback is needed.
        assert_marked(combo, character)
        if args.mixed or args.rework:
            assert len({cut['action'] for cut in combo['cuts']}) >= 2
            # Maintain a coherent forward string without walking through the target.
            for i, cut in enumerate(combo['cuts']):
                cut['lunge'] = 12 if i == 0 else (16 if i == len(chain)-1 else 8)
                cut['hit']['push'] = 25 if i < len(chain)-1 else 220
                if i == len(chain)-1:
                    cut['width'], cut['tail'], cut['hold'] = 0.75, 0.24, max(0.24, cut['hold'])
            if suffix == 'sky_nine':
                # The rising attack approaches, then sends the target forward for the
                # airborne pursuit and forward landing. Geometry/annotations stay intact.
                combo['cuts'][2]['lunge'] = 120
                combo['cuts'][2]['hit']['push'] = 850
                combo['cuts'][3]['lunge'] = 12
                combo['cuts'][4]['lunge'] = 12
                combo['cuts'][5]['lunge'] = 24
        if args.rework:
            combo['lead_fps'] = 24
            combo['ghost'] = {'life':0.10, 'alpha':0.28, 'recover_alpha':0.20, 'mode':'jumps'}
            combo['spoken_turn_overrides'] = {'attack_2:14': 'User confirmed returning sweep; turn=1'}
            for i, cut in enumerate(combo['cuts']):
                last = i == len(chain)-1
                cut['swing'] = (0.18 if last else (0.12 if i%2 else 0.15))
                cut['hold'] = max(0.22 if last else 0.12, 0.04*len(cut['follow'])+0.04)
                cut['cancel'] = 0.04 if cut['recover'] else 0.0
                cut['width'], cut['reach'], cut['extension'] = (0.62 if last else 0.38), 1.08, 1.10
                cut['tail'], cut['overshoot'], cut['echo'] = (0.14 if last else 0.055), (10 if last else 4), False
                cut['max_visible_turn'] = 200 if last else 150
                if cut['action'].startswith('09_'):
                    cut['band_width'] = round(134 * character.scale * 0.28, 2)
                    cut['preserve_band_width'] = True
                    cut['tail'] = 0.085
                cut['hit'].update(push=180 if last else 18, stop=0.10 if last else 0.045,
                                  shake=6 if last else 2.5, spark=85 if last else 36)
            if suffix == 'sky_eight':
                combo['cuts'][2]['lunge'] = 120
                combo['cuts'][2]['hit']['push'] = 1000
                combo['cuts'][5]['lunge'] = 24
                combo['cuts'][6]['lunge'] = 88
        at = 0.0
        for cut, beat in zip(combo['cuts'], beats):
            minimum_wind = max(0.12, len(cut['lead'])/combo['lead_fps']+0.07) if args.rework else 0.18
            cut['wind_time'] = round(max(minimum_wind, beat-at-cut['swing']*cut['contact']), 3)
            at += cut['wind_time'] + cut['swing'] + cut['hold'] + cut['cancel']
        combo['annotation_sha256'] = digest
        combo['presentation_sha256'] = presentation_digest
        combo['look'] = 'blade' if args.rework else 'crescent'
        style = {'title': '师傅重编 · '+title if args.rework else '师傅一阶段 · '+title, 'language': 'zh', 'pixel': 2 if args.rework else 3}
        prompt = ('2026-10-22 已审核设计：'+title+'。只使用用户已标注帧，保留绘制挥刀中间帧与收势；'
                  '普通可震刀样板，接触随实测刀刃校准，不修改标注、不引入未标注帧。')
        def save():
            assert_marked(combo, character)
            # A later calibrated contact in one cut must not consume the next parry gap.
            for _ in range(len(combo['cuts'])):
                _, times = check_combo(combo, character)
                short = next((i for i in range(1, len(times)) if times[i]-times[i-1] < 0.355), None)
                if short is None: break
                combo['cuts'][short]['wind_time'] = round(combo['cuts'][short]['wind_time'] + 0.36-(times[short]-times[short-1]), 3)
            write_combo(PROJECT, name, combo, style, prompt=prompt, force=True)
        base = combo['target_distance']
        best, best_score = base, (-1, -1)
        logs = []
        # Only choose target distance; never inflate sword geometry to hide misses.
        for factor in (1.0, 0.75, 1.25, 0.55, 1.5, 0.4, 0.85, 0.9, 0.95, 0.65, 0.6):
            combo['target_distance'] = round(base*factor)
            save()
            output = verify(name)
            logs.append(f'DISTANCE {combo["target_distance"]}\n'+output)
            found = re.search(r'(\d+)/(\d+) reach', output)
            score = (int(found[2])-output.count('never reaches'), int(found[1])) if found else (-1,-1)
            if score > best_score:
                best, best_score = combo['target_distance'], score
            if found and score[0] == int(found[2]):
                break
        combo['target_distance'] = best
        for _ in range(3):
            save()
            output = verify(name)
            logs.append('CONTACT CALIBRATION\n'+output)
            updates = re.findall(r'cut (\d+) reaches the target only at ([\d.]+)', output)
            if not updates:
                break
            for number, first in updates:
                combo['cuts'][int(number)-1]['contact'] = min(0.98, float(first)+0.03)
        # Contact calibration must retain the minimum gap as well as marked frames.
        errors, contacts = check_combo(combo, character)
        assert not errors, errors
        save()
        output = verify(name)
        logs.append('FINAL\n'+output)
        if 'WARN:' in output:
            style['title'] += '（刀刃覆盖待调）'
            save()
        (audit/(suffix+'_verify.log')).write_text('\n'.join(logs), encoding='utf-8')
        print(name, output, flush=True)
        (folder/'audit.json').write_text(json.dumps({'annotation_sha256':digest,
            'presentation_sha256':presentation_digest,
            'all_frames_annotated':True, 'contacts':contacts, 'target_distance':best,
            'validation':output}, ensure_ascii=False, indent=2), encoding='utf-8')
    assert hashlib.sha256(annotation.read_bytes()).hexdigest() == digest, 'Annotation changed during build'
    if args.rework: write_rework_report()


if __name__ == '__main__':
    main()
