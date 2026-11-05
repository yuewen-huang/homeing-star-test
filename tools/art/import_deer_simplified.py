"""Split the authored deer into physical segments; never resize/repaint pixels."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'homeing-star-test/artifacts/deer-authored-20261105'
DEST = ROOT / 'homeing-star-game/assets/bosses/deer/body/authored'
# Frame ranges are inclusive, zero-based. Roots are deliberately measured body
# registration, not frame bounds: jump height and silhouette changes remain art.
CLIPS = {
    'idle_ING': ('idle', 0, 15),
    'rush_START': ('sprint', 0, 3), 'rush_ING': ('sprint', 4, 7), 'rush_END': ('sprint', 8, 15),
    'leap_START': ('Leap forward, land hard.', 0, 7),
    'leap_ING': ('Leap forward, land hard.', 8, 17),
    'leap_END': ('Leap forward, land hard.', 18, 31),
    'horn_START': ('shangtiao', 0, 4), 'horn_ING': ('shangtiao', 5, 7), 'horn_END': ('shangtiao', 8, 15),
    'roar_START': ('luming', 0, 3), 'roar_ING': ('luming', 4, 11), 'roar_END': ('luming', 12, 15),
    'hurt_START': ('hurt', 0, 3), 'hurt_ING': ('hurt', 4, 7), 'hurt_END': ('hurt', 8, 14),
    'walk_START': ('walk', 0, 3), 'walk_ING': ('walk', 4, 27), 'walk_END': ('walk', 28, 31),
    'stomp_START': ('atak', 0, 8), 'stomp_ING': ('atak', 9, 12), 'stomp_END': ('atak', 13, 15),
    'weak_START': ('week', 0, 4), 'weak_ING': ('week', 5, 9), 'weak_END': ('week', 10, 15),
}
RUSH_ROOT = [34,34,34,34,53,93,151,174,140,80,64,50,43,37,34,34]
LEAP_ROOT = [34,34,34,34,34,34,34,42,57,82,104,118,126,134,142,153,159,165,157,140,119,98,76,59,45,35,34,34,34,34,34,34]
# Chest points measured in the source canvas; airborne Y is intentionally kept.
CHEST = {
 'idle': [(143,207),(143,207),(141,208),(139,210),(137,211),(136,212),(136,212),(136,213),(137,212),(138,211),(139,210),(140,209),(142,207),(143,207),(143,207),(143,207)],
 'sprint': [(65,207),(66,211),(66,220),(65,222),(91,222),(132,218),(188,229),(215,241),(181,239),(122,240),(104,239),(88,240),(78,224),(69,212),(65,207),(65,207)],
 'Leap forward, land hard.': [(65,207),(65,207),(65,207),(65,214),(66,224),(67,231),(70,231),(76,228),(87,209),(119,153),(140,125),(156,116),(166,114),(174,113),(182,114),(190,120),(193,134),(193,169),(190,229),(170,229),(149,230),(127,230),(105,229),(88,225),(75,218),(65,211),(64,209),(65,207),(65,207),(65,207),(65,207),(65,207)],
 'shangtiao': [(143,207),(146,207),(154,215),(157,221),(158,226),(147,216),(131,207),(126,204),(125,204),(125,204),(125,204),(125,204),(126,205),(130,207),(137,208),(143,207)],
 'luming': [(143,207),(140,211),(136,214),(135,214),(134,214),(134,214),(134,214),(134,214),(134,214),(134,214),(134,214),(134,214),(135,214),(136,213),(140,210),(143,207)],
 'hurt': [(143,207),(132,209),(134,211),(166,224),(166,229),(166,230),(164,231),(163,230),(163,224),(160,217),(154,204),(147,201),(143,207),(143,207),(143,207)],
 'atak': [(143,207),(142,209),(143,211),(142,211),(139,193),(128,185),(126,186),(126,186),(127,187),(156,223),(156,223),(156,223),(156,223),(154,220),(149,212),(143,207)],
 'week': [(143,207),(143,207),(144,211),(144,214),(161,242),(159,242),(159,242),(159,242),(159,242),(159,242),(159,242),(158,240),(153,229),(149,225),(146,214),(143,207)],
 'walk': [(143,207),(143,207),(143,207),(145,207),(146,207),(147,208),(147,210),(147,210),(146,210),(145,210),(145,210),(145,210),(145,210),(145,209),(145,207),(145,207),(144,207),(144,207),(144,207),(144,208),(144,209),(144,210),(144,211),(144,211),(144,211),(144,211),(144,210),(144,210),(144,209),(144,208),(143,207),(143,207)],
}

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for name, (source, first, last) in CLIPS.items():
        atlas = Image.open(SOURCE / (source + '.png')).convert('RGBA')
        segment = atlas.crop((first*256, 0, (last+1)*256, 256))
        segment.save(DEST / (name + '.png'))
        roots = RUSH_ROOT if source == 'sprint' else LEAP_ROOT if source.startswith('Leap') else [112]*len(CHEST[source])
        manifest[name] = dict(file=name+'.png', count=last-first+1,
            source=source+'.aseprite', source_frames=list(range(first, last+1)),
            roots=[[roots[f],256] for f in range(first,last+1)],
            chest=[CHEST[source][f] for f in range(first,last+1)])
        for local,f in enumerate(range(first,last+1)):
            assert segment.crop((local*256,0,(local+1)*256,256)).tobytes() == atlas.crop((f*256,0,(f+1)*256,256)).tobytes()
    (DEST / 'clips.json').write_text(json.dumps(manifest, indent=2), encoding='utf8')
    print(f'{len(manifest)} physical clips; {sum(v["count"] for v in manifest.values())} frames preserved byte-for-byte as RGBA pixels')

if __name__ == '__main__': main()
