"""Send ordinary input batches to the visual review; only public health is returned."""
import argparse,json,time
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('seq',type=int)
p.add_argument('--frames',type=int,default=120)
p.add_argument('--walk',type=int,default=0)
p.add_argument('--out',type=Path)
for name in ['attack','parry','dodge','jump','patrol','stop']:p.add_argument('--'+name,action='store_true')
args=vars(p.parse_args())
out=args.pop('out') or Path(__file__).resolve().parents[1]/'artifacts/sandstorm-visual-review'
tmp=out/'command.tmp'
tmp.write_text(json.dumps(args),encoding='utf-8')
for attempt in range(50):
 try:
  tmp.replace(out/'command.json');break
 except PermissionError:
  if attempt==49:raise
  time.sleep(.02)
if not args['stop']:
 for _ in range(450):
  try:
   status=json.loads((out/'status.json').read_text(encoding='utf-8'))
   if status['seq']==args['seq']:print(json.dumps(status));break
  except (FileNotFoundError,json.JSONDecodeError):pass
  time.sleep(.1)
 else:raise SystemExit('Input batch timed out')
