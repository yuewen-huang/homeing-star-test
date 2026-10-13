"""Read-only analysis of the user's manually revised first run frame."""
from pathlib import Path
from collections import deque
from PIL import Image
import ast

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "PendingArt" / "character" / ("\u4e3b\u89d2-\u5c9a") / "palette-bases" / "run" / "sprite sheets"
USER = BASE / "run.png"
AUTO = BASE / "run-cat-ears-tail.png"
ORIGINAL = ROOT / "PendingArt" / "character" / ("\u4e3b\u89d2-\u5c9a") / "run" / "sprite sheets" / "run.png"
OUT = BASE / "run-user-analysis"
OUT.mkdir(exist_ok=True)

user = Image.open(USER).convert("RGBA").crop((0,0,65,60))
auto = Image.open(AUTO).convert("RGBA").crop((0,0,65,60))
original = Image.open(ORIGINAL).convert("RGBA").crop((0,0,65,60))
tree = ast.parse((ROOT / "tools/aseprite/lan_batch_palette_bases.py").read_text(encoding="utf-8"))
palette = next(ast.literal_eval(node.value) for node in tree.body if isinstance(node, ast.Assign) and any(isinstance(t,ast.Name) and t.id == "PALETTE" for t in node.targets))
clean = original.copy()
for y in range(60):
    for x in range(65):
        p=original.getpixel((x,y))
        if p[3] and (target := palette.get(f"{p[0]:02X}{p[1]:02X}{p[2]:02X}")):
            clean.putpixel((x,y),tuple(bytes.fromhex(target))+(p[3],))
clean.save(OUT/"frame01-clean-palette-base.png")
diff = [(x,y) for y in range(60) for x in range(65) if user.getpixel((x,y)) != clean.getpixel((x,y))]

# Connected edit regions help separate manual ear/tail work from unrelated pixels.
pending=set(diff); components=[]
while pending:
    start=pending.pop(); q=deque([start]); comp={start}
    while q:
        x,y=q.popleft()
        for n in ((x-1,y),(x+1,y),(x,y-1),(x,y+1),(x-1,y-1),(x+1,y+1),(x-1,y+1),(x+1,y-1)):
            if n in pending: pending.remove(n); comp.add(n); q.append(n)
    components.append(comp)

mask=Image.new("RGBA",(65,60))
for x,y in diff: mask.putpixel((x,y),(255,70,120,255))
def scale(im):
    bg=Image.new("RGBA",im.size)
    for y in range(60):
        for x in range(65):
            c=96 if (x//4+y//4)%2 else 116; bg.putpixel((x,y),(c,c,c,255))
    bg.alpha_composite(im)
    return bg.convert("RGB").resize((650,600),Image.Resampling.NEAREST)
canvas=Image.new("RGB",(1950,600),"#2F3036")
for i,im in enumerate((clean,user,mask)):canvas.paste(scale(im),(i*650,0))
canvas.save(OUT/"frame01-clean-user-diff-10x.png")
print(f"changed pixels against clean palette base: {len(diff)}")
for c in sorted(components,key=len,reverse=True):
    xs=[x for x,y in c];ys=[y for x,y in c]
    print(f"region pixels={len(c)} bbox=({min(xs)},{min(ys)})-({max(xs)},{max(ys)})")
