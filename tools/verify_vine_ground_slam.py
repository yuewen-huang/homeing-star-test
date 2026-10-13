"""Round-trip every offline vine-slam frame through the installed Aseprite."""
from pathlib import Path
import argparse
import json
import subprocess
import sys

from PIL import Image


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--aseprite',type=Path,default=Path('E:/Aseprite/Aseprite.exe'))
    args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    meta=json.loads((args.source/'时间轴.json').read_text(encoding='utf-8'))
    report=[]
    for variant in meta['variants']:
        name=Path(variant['file']).stem
        jsonfile=args.output/(name+'.json')
        sheetfile=args.output/(name+'.png')
        result=subprocess.run([str(args.aseprite),'-b','--list-layers','--list-tags','--list-slices',
            str(args.source/variant['file']),'--format','json-array','--data',str(jsonfile),
            '--sheet',str(sheetfile),'--sheet-type','horizontal'],
            capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW,timeout=40)
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors='replace'))
        if not jsonfile.exists():
            raise RuntimeError('Native Aseprite did not create its export')
        native=json.loads(jsonfile.read_text(encoding='utf-8'))
        assert len(native['frames'])==variant['frames']
        assert all(f['duration']==variant['frame_plan'][i]['duration_ms'] for i,f in enumerate(native['frames']))
        assert [t['name'] for t in native['meta']['frameTags']]==[t['name'] for t in variant['tags']]
        slices=native['meta']['slices']
        assert slices[0]['keys'][0]['pivot']=={'x':48,'y':196}
        with Image.open(sheetfile) as image:
            sheet=image.convert('RGBA')
        for i,f in enumerate(native['frames']):
            rect=f['frame']
            actual=sheet.crop((rect['x'],rect['y'],rect['x']+rect['w'],rect['y']+rect['h']))
            expected=Image.open(args.source/'序列帧'/name/f'{i:02d}.png').convert('RGBA')
            assert actual.size==expected.size and actual.tobytes()==expected.tobytes(),(name,i)
        report.append({'file':variant['file'],'native_frames':len(native['frames']),
                       'all_pixels_exact':True,'duration_ms':sum(f['duration'] for f in native['frames']),
                       'pivot':slices[0]['keys'][0]['pivot'],'tags':[t['name'] for t in native['meta']['frameTags']]})
        print('PASS',name,len(native['frames']),'frames: native Aseprite pixels, durations, tags, pivot exact')
    (args.output/'native-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')


if __name__=='__main__':main()
