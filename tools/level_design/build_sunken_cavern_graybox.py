"""Compile the accepted outline and traversal realization to a standalone Godot layout."""
from __future__ import annotations

import json
import math
from collections import defaultdict
from pathlib import Path
from build_sunken_cavern_outline import contours

ROOT=Path(__file__).resolve().parents[3]
DESIGN=ROOT/"homeing-star-doc/docs/design/sunken_cavern"
OUTPUT=ROOT/"homeing-star-game/assets/levels/chapter_2_underwater/cavern/layout.json"


def rect_cells(rects):
    return {(x,y) for a,b,w,h in rects for x in range(a,a+w) for y in range(b,b+h)}


def merged_rects(cells):
    active,result={},[]
    ys=range(min(y for _,y in cells),max(y for _,y in cells)+1)
    for y in ys:
        row=sorted(x for x,py in cells if py==y)
        runs=[]
        for x in row:
            if runs and x==runs[-1][1]: runs[-1][1]+=1
            else: runs.append([x,x+1])
        current={}
        for start,end in runs:
            key=(start,end)
            current[key]=active.get(key,[start,y,end-start,0])
            current[key][3]+=1
        result.extend(value for key,value in active.items() if key not in current)
        active=current
    return result+list(active.values())


def main():
    source=json.loads((DESIGN/"outline.json").read_text(encoding="utf-8-sig"))
    config=json.loads((DESIGN/"graybox.json").read_text(encoding="utf-8-sig"))
    cell=source["cell_px"]
    free=rect_cells([r for s in source["spaces"] for r in s["rects"]])
    wall_cells={(x,y) for x in range(-1,156) for y in range(-1,89)}-free
    walls=[[n*cell for n in r] for r in merged_rects(wall_cells)]
    floors=[]
    by_y=defaultdict(list)
    for x,y in free:
        if (x,y+1) not in free: by_y[y+1].append(x)
    for y,xs in by_y.items():
        for x in sorted(xs):
            if floors and floors[-1][1]==y*cell and floors[-1][0]+floors[-1][2]==x*cell:
                floors[-1][2]+=cell
            else: floors.append([x*cell,y*cell,cell])

    anchors={n["id"]:[config["feet_x_cells"].get(n["id"],n["p"][0])*cell,config["feet_y_cells"][n["id"]]*cell] for n in source["nodes"]}
    nav={};links=[];platforms=[];ladders=[];ramps=[]
    apertures=[[h["x"][0]*cell,h["x"][1]*cell,h["y"]*cell] for h in config["apertures"]]

    def point(name,p):
        if name in nav: assert math.dist(nav[name],p)<.1,(name,nav[name],p)
        nav[name]=list(p)
        return name

    def link(a,b,mode="walk",door=None,one_way=False):
        if a==b:return
        item={"a":a,"b":b,"mode":mode}
        if door:item["door"]=door
        if one_way:item["one_way"]=True
        links.append(item)

    def platform(x0,x1,y):
        if x0>x1:x0,x1=x1,x0
        # Guard real overhead clearance at every visible landing/run.
        for x in range(math.ceil(x0+14),math.floor(x1-14)+1,16):
            for dy in [6,32,62]:
                assert (math.floor(x/cell),math.floor((y-dy)/cell)) in free,("platform in rock",x,y,dy)
        spans=[(x0,x1)]
        for left,right,height in apertures:
            if height!=y:continue
            spans=[part for a,b in spans for part in ((a,min(b,left)),(max(a,right),b)) if part[1]>part[0]]
        platforms.extend([a,y,b-a] for a,b in spans if b-a>0.1)

    for name,p in anchors.items():point(name,p)
    for left,right,y in config["balconies"]:platform(left*cell,right*cell,y*cell)

    def landing(p, width):
        # A short local rest instead of a deck spanning the entire shaft.
        left,right=p[0]-width/2,p[0]+width/2
        def clear(x):
            return all((math.floor(x/cell),math.floor((p[1]-dy)/cell)) in free for dy in (6,32,62))
        while not clear(left) and left<p[0]:left+=8
        while not clear(right) and right>p[0]:right-=8
        platform(left,right,p[1])

    for x,y,width in config["rests"]:landing([x*cell,y*cell],width*cell)

    for index,path in enumerate(config["traversals"]):
        points=[anchors[path["a"]]]+[[x*cell,y*cell] for x,y in path["via"]]+[anchors[path["b"]]]
        names=[path["a"]]+[f"route_{index}_{i}" for i in range(len(path["via"]))]+[path["b"]]
        for i,(name,p) in enumerate(zip(names,points)):
            point(name,p)
            adjacent=path["modes"][max(0,i-1):min(len(path["modes"]),i+1)]
            landing(p,128 if any(m in ("jump","drop") for m in adjacent) else 64)
        for i,(a,b,mode) in enumerate(zip(points,points[1:],path["modes"])):
            if mode=="walk":
                assert a[1]==b[1],("walk changes height",path["theme"],a,b)
                platform(a[0],b[0],a[1])
            elif mode=="ramp":
                assert abs((b[1]-a[1])/(b[0]-a[0]))<=.4,("steep ramp",path["theme"],a,b)
                for j in range(33):
                    t=j/32
                    x,y=a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t
                    assert all((math.floor(x/cell),math.floor((y-dy)/cell)) in free for dy in (6,32,62)),("ramp in rock",a,b,x,y)
                ramps.append([list(a),list(b)])
            elif mode in ("climb", "service_climb"):
                limit = 1536 if mode == "service_climb" else 320
                assert a[0]==b[0] and abs(a[1]-b[1])<=limit
                ladders.append([a[0]-18,min(a[1],b[1]),36,abs(a[1]-b[1])])
            elif mode=="jump":
                assert abs(a[1]-b[1])<=80 and abs(a[0]-b[0])<=144,("jump budget",a,b)
            elif mode=="drop":
                assert b[1]>a[1] and b[1]-a[1]<=1536,("drop budget",a,b)
            elif mode=="lift":
                assert b[1]<a[1] and path.get("one_way"),("lift must ascend",a,b)
            else:raise ValueError(mode)
            link(names[i],names[i+1],"climb" if mode=="service_climb" else mode,one_way=path.get("one_way",False))
            if mode=="drop" and "chute_x" in path:links[-1]["chute_x"]=path["chute_x"]*cell

    for run in config["horizontal_runs"]:
        a,b=run["a"],run["b"]
        assert anchors[a][1]==anchors[b][1]==run["y"]*cell,(a,b)
        platform(anchors[a][0],anchors[b][0],run["y"]*cell)
        link(a,b,door=run.get("door"))

    entry_ramp=[[x*cell,y*cell] for x,y in config["entry_ramp_cells"]]
    for a,b in zip(entry_ramp,entry_ramp[1:]):
        if a[1]==b[1]:platform(a[0],b[0],a[1])
        else:ramps.append([a,b])
    point("entry_ramp_top",entry_ramp[0]);point("entry_ramp_low",entry_ramp[-1])
    link("entry","entry_ramp_top");link("entry_ramp_top","entry_ramp_low");link("entry_ramp_low","gate")
    # The ramp's upper deck meets the real lip before the player's body reaches it.
    platform(anchors["entry"][0],entry_ramp[0][0],anchors["entry"][1])
    platform(entry_ramp[-1][0],anchors["gate"][0],anchors["gate"][1])

    # Pool approaches end at real banks, never at invisible water-spanning decks.
    point("w1_bank",[53*cell,62*cell]);link("w60","w1_bank");platform(anchors["w60"][0],53*cell,62*cell)
    water=[]
    for w in source["water"]:
        water.append({"id":w["id"],"rects":[[v*cell for v in r] for r in w["rects"]],"surfaces":[[v*cell for v in r] for r in w["surface_segments"]]})
    gates=[]
    for door in source["doors"]:
        rect=[v*cell for v in door["rect"]]
        left=door["id"]=="S1"
        gates.append({"id":door["id"],"rect":rect,"latch":[rect[0]-64 if left else rect[0]+rect[2]+64,rect[1]+rect[3]-36],"side":-1 if left else 1})
    # Coalesce overlapping authored rests and street pieces; preserve apertures.
    platform_rows=defaultdict(list)
    for x,y,w in platforms:platform_rows[y].append((x,x+w))
    platforms=[]
    for y,spans in platform_rows.items():
        merged=[]
        for a,b in sorted(spans):
            if merged and a<=merged[-1][1]+.01:merged[-1][1]=max(merged[-1][1],b)
            else:merged.append([a,b])
        platforms.extend([a,y,b-a] for a,b in merged)

    # Virtual support sits 2 px above real rock. This prevents the physics body
    # catching a rock's vertical corner when leaving a one-way landing.
    for floor in floors+platforms:floor[1]-=2
    for p in anchors.values():p[1]-=2
    for p in nav.values():p[1]-=2
    for ladder in ladders:ladder[1]-=2
    for ramp in ramps:
        for p in ramp:p[1]-=2
    bounds=[0,0,156*cell,89*cell]
    result={"source":"Accepted sunken_cavern/outline.json + graybox.json; generated by build_sunken_cavern_graybox.py",
            "cell_px":cell,"bounds":bounds,"start":anchors["entry"],"walls":walls,"floors":floors,"platforms":platforms,"ramps":ramps,"ladders":ladders,
            "water":water,"doors":gates,"markers":anchors,"well_east_scarp":config.get("well_east_scarp",[]),
            "mechanisms":config["mechanisms"],
            "visual_contours":[[[x*cell,y*cell] for x,y in loop] for loop in contours(free)],
            "apertures":[[a,b,y-2] for a,b,y in apertures],
            "spaces":[{"id":s["id"],"rects":[[v*cell for v in r] for r in s["rects"]]} for s in source["spaces"]],
            "navigation":{"points":nav,"links":links},
            "water_itineraries":{name:[[x*cell,y*cell,mode] for x,y,mode in route] for name,route in config["water_itineraries"].items()}}
    # Verify the compiled dry graph, without either gate, still reaches the arena.
    graph=defaultdict(set)
    for e in links:
        if e.get("door"):continue
        graph[e["a"]].add(e["b"])
        if not e.get("one_way"):graph[e["b"]].add(e["a"])
    seen={"entry"};todo=["entry"]
    while todo:
        for q in graph[todo.pop()]-seen:seen.add(q);todo.append(q)
    dry_expected=set(anchors)-{"wet_start","vault","pool_recess"}
    assert dry_expected<=seen,("Unconnected compiled dry anchors",dry_expected-seen)
    assert "vault" not in seen
    # A one-way drop must always have another dry route back to the entrance.
    reverse=defaultdict(set)
    for a,neighbors in graph.items():
        for b in neighbors:reverse[b].add(a)
    back={"entry"};todo=["entry"]
    while todo:
        for q in reverse[todo.pop()]-back:back.add(q);todo.append(q)
    assert dry_expected<=back,("No dry return",dry_expected-back)
    OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    OUTPUT.write_text(json.dumps(result,ensure_ascii=False,separators=(",",":"))+"\n",encoding="utf-8")
    print(json.dumps({"wall_rects":len(walls),"floor_runs":len(floors),"landings_and_decks":len(platforms),"short_ladders":len(ladders),"dry_anchor_count":len(dry_expected),"output":str(OUTPUT)},ensure_ascii=False))


if __name__=="__main__":main()
