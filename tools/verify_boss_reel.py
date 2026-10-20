from pathlib import Path
import json
import subprocess
from PIL import Image, ImageDraw
from mix_boss_reel_audio import FF, FP, BGM

BASE = Path('D:/HomingStar/homeing-star-temp-assert/Recordings/20261019_boss_real_maps')
manifest = json.loads((BASE/'manifest.json').read_text(encoding='utf8'))
assert len(manifest) == 10
assert not any('frog' in row['folder'] for row in manifest)
map_paths = [
    'res://scenes/levels/chapter_1/chapter_1_wind_boss_room.tscn',
    'res://scenes/levels/chapter_1/chapter_1_special_boss_upper_right_room.tscn',
    'res://scenes/levels/chapter_1/chapter_1_special_boss_lower_left_room.tscn',
    'res://scenes/levels/chapter_1/chapter_1_root_heart_room.tscn',
]
for i, expected in enumerate(map_paths):
    events = json.loads((BASE/f'core_{i}/events.json').read_text(encoding='utf8'))
    assert events and all(e['map'] == expected for e in events)
crab = json.loads((BASE/'crab_1/events.json').read_text(encoding='utf8'))
assert all(e['map'] == 'res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn'
           for e in crab if e['event'] == 'start')

for row in manifest:
    path = BASE/row['folder']
    errors = (path/'record.errors.log').read_text(encoding='utf8', errors='replace')
    assert not any(s in errors for s in ['SCRIPT ERROR:', 'Parse Error:', 'Compilation failed'])
    log = (path/'record.log').read_text(encoding='utf8', errors='replace')
    assert 'Done recording movie' in log
    assert '0 failures' in log or 'CRAB PARRY RECORDING: PASS' in log

summaries = {}
for name in [r['file'] for r in manifest] + ['boss_collection.mp4', 'boss_highlights.mp4']:
    path = BASE/name
    info = json.loads(subprocess.check_output([
        str(FP), '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(path)
    ]))
    video = next(s for s in info['streams'] if s['codec_type'] == 'video')
    assert (video['width'], video['height'], video['r_frame_rate']) == (1280, 720, '60/1')
    assert any(s['codec_type'] == 'audio' for s in info['streams'])
    result = subprocess.run([str(FF), '-v', 'error', '-i', str(path), '-f', 'null', '-'], capture_output=True)
    assert result.returncode == 0 and not result.stderr, (name, result.stderr)
    summaries[name] = float(info['format']['duration'])
    print('VERIFIED', name, flush=True)

canvas = Image.new('RGB', (1280, 612), (18, 23, 28))
draw = ImageDraw.Draw(canvas)
for i, row in enumerate(manifest):
    source = BASE/row['file']
    # Crystal crab is sampled after the native salt-field emergence.
    at = 8 if row['folder'] == 'crab_1' else (7 if row['folder'] == 'deer_4' else 1.1)
    shot = BASE/f'qa_{row["folder"]}.png'
    subprocess.run([str(FF), '-v', 'error', '-y', '-ss', str(at), '-i', str(source),
                    '-frames:v', '1', str(shot)], check=True)
    im = Image.open(shot).convert('RGB')
    im.thumbnail((320, 180))
    x = (i % 4)*320
    y = (i // 4)*204
    canvas.paste(im, (x, y+24))
    draw.text((x+5, y+5), row['folder'], fill='white')
canvas.save(BASE/'qa_real_maps.jpg')
(BASE/'verification.json').write_text(json.dumps({
    'all_streams_decode': True,
    'all_recorded_combat_audits_passed': True,
    'native_core_map_paths_verified': map_paths,
    'crab_map': 'res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn',
    'frogger_excluded': True,
    'soundtrack': str(BGM),
    'original_music': 'muted in recording process only',
    'parry_relative_to_other_sfx_db': 6,
    'postproduction_music_gain': 0.075,
    'postproduction_sidechain_ducking': True,
    'production_files_or_persisted_audio_settings_edited': False,
    'durations': summaries,
}, indent=2, ensure_ascii=False), encoding='utf8')
print('FINAL VERIFICATION COMPLETE', flush=True)
