"""Cut authored frame ranges from production recordings into Godot Theora videos."""
import argparse
import json
import hashlib
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ffmpeg', required=True)
    parser.add_argument('--recording', type=Path, required=True)
    args = parser.parse_args()
    workspace = Path(__file__).resolve().parents[2]
    target = workspace / 'homeing-star-game/assets/shared/ui/tutorials'
    target.mkdir(parents=True, exist_ok=True)
    manifest_file = target / 'manifest.json'
    manifest = json.loads(manifest_file.read_text(encoding='utf-8')) if manifest_file.exists() else {}
    preview = args.recording / 'previews'
    preview.mkdir(exist_ok=True)
    clips = json.loads((args.recording / 'clips.json').read_text(encoding='utf-8'))
    events = json.loads((args.recording / 'events.json').read_text(encoding='utf-8'))
    alley_ids = {'normal_attack', 'instant_dash', 'jump_attack', 'dodge_combo', 'charged_attack', 'poise_throw'}
    for clip in clips:
        expected_scene = 'back_alley' if clip['id'] in alley_ids else 'tutorial'
        if clip.get('scene') != expected_scene:
            raise ValueError(f"Wrong scene for lesson {clip['id']}: {clip.get('scene')}")
        if clip['id'].startswith('master_') and clip['id'].endswith('_chain'):
            expected = 5 if clip['id'] == 'master_heavy_chain' else 6
            if clip.get('phase') != 1 or not clip.get('no_damage') or clip.get('parries') != expected or clip.get('difficulty') != 'hard':
                raise ValueError(f"Incomplete production long-chain evidence: {clip['id']}")
        if clip['id'].startswith('phase_2_') or clip['id'] == 'ultimate':
            if clip.get('phase') != 2:
                raise ValueError(f"Second-form lesson must use second-form footage: {clip['id']}")
        if clip['id'].startswith('phase_2_') and not clip.get('no_damage'):
            raise ValueError(f"Defense demonstration took damage: {clip['id']}")
        expected_parries = {'phase_2_slash': 1, 'phase_2_combo': 3}
        if clip['id'] in expected_parries and clip.get('parries') != expected_parries[clip['id']]:
            raise ValueError(f"Incomplete manual parry demonstration: {clip['id']}")
        if clip['id'] == 'phase_2_red_dash' and clip.get('red_parries', 0) < 1:
            raise ValueError('Second-form teleport must demonstrate a real red counter')
        if clip['id'] == 'phase_2_wave' and not clip.get('wave_jumped'):
            raise ValueError('Ground wave must demonstrate a real jump')
        if clip['id'] == 'phase_2_gold_chain' and clip.get('dodges', 0) < 2:
            raise ValueError('Gold pursuit must demonstrate repeated evasions')
        if expected_scene == 'back_alley':
            expected_enemies = {1: ['slime'], 2: ['slime'], 3: ['bat'], 4: ['slime', 'bat'], 5: ['frogger']}
            if clip['enemies'] != expected_enemies[clip['wave']] or not clip['hit_verified']:
                raise ValueError(f"Invalid current-wave evidence: {clip['id']}")
            if 'ultimate' in clip['unlocked'] or 'parry' in clip['unlocked']:
                raise ValueError(f"Future skill disclosed in {clip['id']}")
    clip_ids = {clip['id'] for clip in clips}
    for take, event, minimum in [('parry', 'parry', 1), ('parry_chain', 'parry', 3), ('red_parry', 'red_parry', 1), ('gold_dodge', 'gold_landing', 1)]:
        if take not in clip_ids:
            continue
        count = sum(e['take'] == take and e['event'] == event for e in events)
        if count < minimum:
            raise ValueError(f'Missing production contact evidence: {take}/{event}: {count}')
    if any(e['take'] == 'gold_dodge' and e['event'] == 'hurt' for e in events):
        raise ValueError('Gold dodge demonstration took damage')
    for clip in clips:
        start = clip['start_frame'] / clip['fps']
        duration = (clip['end_frame'] - clip['start_frame']) / clip['fps']
        if duration < 1.0:
            raise ValueError(f"Take too short: {clip['id']}: {duration}")
        output = target / f"{clip['id']}.ogv"
        subprocess.run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                        '-ss', str(start), '-i', str(args.recording / 'raw.avi'),
                        '-t', str(duration), '-vf', 'scale=640:360:flags=lanczos,fps=30',
                        '-c:v', 'libtheora', '-q:v', '7', '-pix_fmt', 'yuv420p', '-an', str(output)], check=True)
        subprocess.run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                        '-ss', str(duration * 0.5), '-i', str(output), '-frames:v', '1',
                        str(preview / f"{clip['id']}.png")], check=True)
        print(f"{clip['id']}: {duration:.2f}s, {output.stat().st_size // 1024} KiB", flush=True)
        manifest[output.name] = {**clip, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}
    manifest_file.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
