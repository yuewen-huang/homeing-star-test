"""Check the local planning diagram with Chrome's file-only headless interface."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path

CHROME = Path("C:/Program Files/Google/Chrome/Application/chrome.exe")
RENDER = Path("D:/CodexData/.codex/plugins/cache/openai-bundled/visualize/1.0.66/skills/visualize/scripts/render.py")
QA_SCRIPT = r"""
<script>
document.getElementById('__QA_ROOT_ID__').style.width='__QA_WIDTH__px';
requestAnimationFrame(() => requestAnimationFrame(() => {
  try {
    const root = document.getElementById('__QA_ROOT_ID__');
    const svg = root.querySelector('.cavern-svg');
    const bounds = svg.getBoundingClientRect();
    const labels = [...svg.querySelectorAll('text')].map(t => {
      const r=t.getBoundingClientRect();
      return {text:t.textContent,left:r.left,right:r.right,top:r.top,bottom:r.bottom};
    });
    const overlaps=[];
    for(let i=0;i<labels.length;i++) for(let j=i+1;j<labels.length;j++) {
      const a=labels[i],b=labels[j];
      if(Math.min(a.right,b.right)-Math.max(a.left,b.left)>1 && Math.min(a.bottom,b.bottom)-Math.max(a.top,b.top)>1) overlaps.push([a.text,b.text]);
    }
    __QA_SELECT_ACTION__
    const text = root.querySelector('__QA_DETAIL__').textContent;
    const result = {width:innerWidth,rootWidth:root.getBoundingClientRect().width,regions:__QA_REGION_COUNT__,
      water:svg.querySelectorAll('.water-fill').length,shortcuts:svg.querySelectorAll('.shortcut').length,
      overflow:document.documentElement.scrollWidth>innerWidth+1||root.scrollWidth>root.clientWidth+1,
      clipped:labels.filter(t=>t.left<bounds.left-1||t.right>bounds.right+1||t.top<bounds.top-1||t.bottom>bounds.bottom+1),
      overlaps,selection:__QA_SELECTION_CHECK__};
    parent.postMessage({cavernReview:result},'*');
  } catch(error) { parent.postMessage({cavernReview:{error:String(error)}},'*'); }
}));
</script>
"""
OUTER_LISTENER = """<script>
window.addEventListener('message',event=>{if(event.data?.cavernReview){
  let out=document.getElementById('cavern-qa-report');
  if(!out){out=document.createElement('pre');out.id='cavern-qa-report';out.hidden=true;document.body.append(out);}
  out.textContent=JSON.stringify(event.data.cavernReview);
}});
</script>"""


class ReportParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.reading = False
        self.value = ""

    def handle_starttag(self, tag, attrs):
        if tag == "pre" and dict(attrs).get("id") == "cavern-qa-report":
            self.reading = True

    def handle_endtag(self, tag):
        if tag == "pre":
            self.reading = False

    def handle_data(self, data):
        if self.reading:
            self.value += data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fragment", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--outline", action="store_true", help="Inspect the continuous outline instead of the retired box diagram")
    args = parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    qa_fragment = args.output/"qa_fragment.html"
    substitutions = {
        "__QA_ROOT_ID__":"sunken-cavern-outline" if args.outline else "sunken-cavern-plan",
        "__QA_SELECT_ACTION__":("const select=root.querySelector('#outline-select');select.value='vault';select.dispatchEvent(new Event('change',{bubbles:true}));" if args.outline else "root.querySelector('a[data-room=\"H\"]').dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true}));"),
        "__QA_DETAIL__":"#outline-detail" if args.outline else "#cavern-detail",
        "__QA_REGION_COUNT__":"root.querySelectorAll('option').length" if args.outline else "svg.querySelectorAll('a[data-room]').length",
        "__QA_SELECTION_CHECK__":"text.includes('沉封库室')&&text.includes('S1')&&text.includes('W1')" if args.outline else "text.includes('H · 淹没旧坊')&&text.includes('P05')&&text.includes('P06')",
    }
    qa_script=QA_SCRIPT
    for key,value in substitutions.items(): qa_script=qa_script.replace(key,value)
    qa_fragment.write_text(args.fragment.read_text(encoding="utf-8")+qa_script,encoding="utf-8")
    preview = args.output/"qa_preview.html"
    subprocess.run([sys.executable,str(RENDER),str(qa_fragment),str(preview),"--force"],check=True,capture_output=True,text=True)
    preview_template=preview.read_text(encoding="utf-8").replace("</head>",OUTER_LISTENER+"</head>")
    results=[]
    for width in [1000,736,360,320]:
        preview.write_text(preview_template.replace("__QA_WIDTH__",str(width)),encoding="utf-8")
        command=[str(CHROME),"--headless=new","--disable-gpu","--no-sandbox","--no-first-run","--no-default-browser-check",
                 "--allow-file-access-from-files", "--hide-scrollbars", "--virtual-time-budget=2000",
                 f"--user-data-dir={args.output/'chrome-qa-profile'}",f"--window-size={max(width+50,550)},960",
                 f"--screenshot={args.output/f'layout_{width}.png'}","--dump-dom",preview.as_uri()]
        result=subprocess.run(command,capture_output=True,timeout=30,creationflags=subprocess.CREATE_NO_WINDOW)
        (args.output/f"chrome_{width}.log").write_bytes(result.stderr)
        reader=ReportParser()
        reader.feed(result.stdout.decode("utf-8",errors="replace"))
        assert reader.value, "Browser did not return the local review report"
        report=json.loads(reader.value)
        assert "error" not in report,report
        assert report["rootWidth"] == width,report
        assert report["regions"]==(12 if args.outline else 9) and report["water"]==2 and report["shortcuts"]==2,report
        assert not report["overflow"] and not report["clipped"] and not report["overlaps"],report
        assert report["selection"],report
        results.append({"requested_width":width,**report})
    (args.output/"browser_validation.json").write_text(json.dumps(results,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(results,ensure_ascii=False,indent=2))


if __name__ == "__main__":
    main()
