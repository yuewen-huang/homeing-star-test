"""Issue ordinary keyboard batches; no game state is used to choose inputs."""
import json,sys,time
from pathlib import Path
out=Path(__file__).resolve().parents[1]/'artifacts/journey-review-20261109'
cmd=json.loads(sys.argv[1])
old=json.loads((out/'status.json').read_text())
cmd['seq']=old['seq']+1
tmp=out/'command.tmp'
tmp.write_text(json.dumps(cmd),encoding='utf-8')
tmp.replace(out/'command.json')
deadline=time.time()+100
while time.time()<deadline:
    try:
        status=json.loads((out/'status.json').read_text())
        if status['seq']==cmd['seq']:
            print(json.dumps(status));break
    except (FileNotFoundError,json.JSONDecodeError):pass
    time.sleep(.1)
else:raise SystemExit('Timed out; inspect native log before sending another batch')
