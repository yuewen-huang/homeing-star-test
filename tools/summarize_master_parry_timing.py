"""Summarize audit output and sample actual first-clip rectangles, without game writes."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
log = ROOT / "homeing-star-test/artifacts/master_timing_audit.log"
for line in log.read_text(encoding="utf-8").splitlines():
    if line.startswith("AUDIT_PHASE1 "):
        d = json.loads(line.split(" ", 1)[1])
        t = [c["contact"] for c in d["cuts"]]
        print(d["label"], "contacts_ms", [round(x*1000, 2) for x in t],
              "gaps_ms", [round((b-a)*1000, 2) for a,b in zip(t,t[1:])])
    elif line.startswith("AUDIT_PHASE2 "):
        d = json.loads(line.split(" ", 1)[1])
        g = d["groups"]
        for speed in [1,1.4]:
            print(d["id"], speed, "contacts_ms", [round(x["contact"]/speed*1000,2) for x in g],
                  "gaps_ms", [round((b["contact"]-a["contact"])/speed*1000,2) for a,b in zip(g,g[1:])])

# First-clip only: ground-level stationary Lan, same root scale, 28x58 hurtbox.
# These are geometric samples, not an end-to-end physics or player-input replay.
p = ROOT / "homeing-star-game/assets/bosses/master/body/boss/phase2/arrangements.json"
data = json.loads(p.read_text(encoding="utf-8"))
for mid in ["master_phase2_pressure_five", "master_phase2_rising_quake"]:
    move = data["moves"][mid]
    c = dict(move["clips"][0])
    # Production restores the first clip's authored windup at runtime.
    c["start_time"] = 0.0
    scene = (ROOT / "homeing-star-game/scenes/bosses/master/master_boss.tscn").read_text(encoding="utf-8")
    root_scale = float(re.search(r'\[node name="MasterBoss"[^\n]*\]\s*scale = Vector2\(([^,]+),',scene)[1])
    scale = move["scale"] * root_scale
    art = c.get("pixel_scale", 1)
    ox,oy = c.get("geometry_offset", [0,0])
    rows = []
    for gap in range(0,201,5):
        hits = []
        for member in c["groups"][0]["members"]:
            for sample in member["samples"]:
                t,x,y,w = sample
                x,y = (x*art+ox)*scale, (y*art+oy)*scale
                half = max(4,w*scale*art)/2
                if x+half>gap-14 and x-half<gap+14 and y+half>-58 and y-half<0:
                    hits.append(t-c["start_time"])
        if hits:
            t = min(hits)
            rows.append({"gap":gap,"unbuffed_ms":round(t*1000,2),"buffed_ms":round(t/1.4*1000,2),
                         "latest_neutral_K_buffed_ms":round((t/1.4-.12)*1000,2)})
    print("FIRST_CONTACT_GEOMETRY", mid, json.dumps(rows))
