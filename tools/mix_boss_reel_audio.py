"""Postproduction-only soundtrack. Dry captures have the native Music bus muted."""
from pathlib import Path
import json
import subprocess

FF = Path('D:/MiniMax/com.minimax.hub/MiniMax Design/current/resources/ffmpeg/ffmpeg.exe')
FP = FF.with_name('ffprobe.exe')
BGM = Path('D:/HomingStar/homeing-star-game/assets/levels/town/audio/town_disorder_night.mp3')

def duration(path):
    return float(json.loads(subprocess.check_output([
        str(FP), '-v', 'error', '-show_entries', 'format=duration', '-of', 'json', str(path)
    ]))['format']['duration'])

def mix(dry, target, log):
    seconds = duration(dry)
    graph = (
        f'[0:a]volume=0.075,afade=t=in:d=0.25,'
        f'afade=t=out:st={max(0, seconds-0.7):.5f}:d=0.7[bed];'
        '[1:a]asplit=2[sfx][key];'
        '[bed][key]sidechaincompress=threshold=0.025:ratio=6:attack=3:release=220[ducked];'
        '[sfx][ducked]amix=inputs=2:normalize=0,alimiter=limit=0.89:level=0[a]'
    )
    with open(log, 'w', encoding='utf8') as stream:
        subprocess.run([
            str(FF), '-hide_banner', '-y', '-stream_loop', '-1', '-i', str(BGM),
            '-i', str(dry), '-filter_complex', graph, '-map', '1:v:0', '-map', '[a]',
            '-c:v', 'copy', '-c:a', 'aac', '-b:a', '256k', '-t', f'{seconds:.6f}',
            '-movflags', '+faststart', str(target)
        ], stdout=stream, stderr=stream, check=True)
