"""Build a continuous passage outline; validate dry routes, gates and local basins."""
from __future__ import annotations

import argparse
import json
import math
from collections import defaultdict, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "homeing-star-doc/docs/design/sunken_cavern/outline.json"
TEMPLATE = Path(__file__).with_name("sunken_cavern_outline_inline.html")


def rect_cells(rects):
    return {(x,y) for rx,ry,w,h in rects for x in range(rx,rx+w) for y in range(ry,ry+h)}


def contours(cells):
    """Clockwise exposed grid edges, including counterclockwise rock islands."""
    edges = set()
    for x,y in cells:
        if (x,y-1) not in cells: edges.add(((x,y),(x+1,y)))
        if (x+1,y) not in cells: edges.add(((x+1,y),(x+1,y+1)))
        if (x,y+1) not in cells: edges.add(((x+1,y+1),(x,y+1)))
        if (x-1,y) not in cells: edges.add(((x,y+1),(x,y)))
    adjacency = defaultdict(set)
    for a,b in edges: adjacency[a].add(b)
    result = []
    while edges:
        start, following = min(edges)
        loop, current = [start], start
        while True:
            edge = (current,following)
            edges.remove(edge); adjacency[current].remove(following)
            previous, current = current, following
            if current == start: break
            loop.append(current)
            options = list(adjacency[current])
            assert options, "Open outline edge"
            # Prefer a clockwise turn at a diagonal touch.
            dx,dy = current[0]-previous[0],current[1]-previous[1]
            priorities = [(current[0]-dy,current[1]+dx),(current[0]+dx,current[1]+dy),
                          (current[0]+dy,current[1]-dx),(current[0]-dx,current[1]-dy)]
            following = min(options,key=priorities.index)
        simplified=[]
        for i,p in enumerate(loop):
            before,after=loop[i-1],loop[(i+1)%len(loop)]
            if (p[0]-before[0])*(after[1]-p[1]) != (p[1]-before[1])*(after[0]-p[0]):
                simplified.append(list(p))
        result.append(simplified)
    return result


def flood(cells, origin):
    if origin not in cells: return set()
    seen,queue={origin},deque([origin])
    while queue:
        x,y=queue.popleft()
        for p in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
            if p in cells and p not in seen:
                seen.add(p);queue.append(p)
    return seen


def graph_reachable(data, opened=(), dry=False):
    graph=defaultdict(set)
    for route in data["routes"]:
        if route.get("door") and route["door"] not in opened: continue
        if dry and route.get("water"): continue
        graph[route["a"]].add(route["b"]);graph[route["b"]].add(route["a"])
    seen,queue={data["entry"]},deque([data["entry"]])
    while queue:
        for node in graph[queue.popleft()] - seen:
            seen.add(node);queue.append(node)
    return seen


def distance(points,cell_px):
    return sum(math.dist(a,b)*cell_px for a,b in zip(points,points[1:]))


def build(data):
    cells=rect_cells([r for space in data["spaces"] for r in space["rects"]])
    positions={n["id"]:n["p"] for n in data["nodes"]}
    assert len(positions)==len(data["nodes"]),"Duplicate node"
    origin=tuple(map(math.floor,positions[data["entry"]]))
    assert flood(cells,origin)==cells,"Disconnected passage geometry"
    water_cells=set()
    water_report=[]
    for water in data["water"]:
        basin=rect_cells(water["rects"])
        assert basin <= cells,(water["id"],"water outside passage")
        assert not basin & water_cells,"Overlapping water basins"
        assert flood(basin,next(iter(basin)))==basin,"Disconnected basin"
        level=water["surface_segments"][0][1]
        assert all(y1==y2==level for _,y1,_,y2 in water["surface_segments"]),"Unequal open water levels"
        for x,y in basin:
            for p in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                assert p not in cells or p in basin or p[1]<level,(water["id"],"uncontained water edge",p)
        for x1,y1,x2,y2 in water["surface_segments"]:
            assert all((x,y1-1) in cells and (x,y1-1) not in basin for x in range(x1,x2)),"No real air above pool"
        length=distance(water["trip"],data["cell_px"])
        seconds=math.ceil(length/data["budget"]["swim_px_s"]*data["budget"]["turn_margin"]*2)/2
        assert seconds<=data["budget"]["swim_review_cap_s"]<data["budget"]["oxygen_s"]
        for a,b in zip(water["trip"],water["trip"][1:]):
            for step in range(101):
                t=step/100
                x,y=a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t
                assert (math.floor(x),math.floor(y+.01)) in basin,(water["id"],"trip leaves water")
        water_report.append({"id":water["id"],"length_px":round(length,1),"budget_s":seconds,"return_included":water["requires_return_underwater"]})
        water_cells |= basin

    gates=set()
    for door in data["doors"]:
        gate=rect_cells([door["rect"]]);assert gate<=cells
        gates |= gate
    dry_cells=cells-water_cells-gates
    initial_dry_geometry=flood(dry_cells,origin)
    assert tuple(map(math.floor,positions["vault"])) not in initial_dry_geometry,"Vault has unintended dry bypass"
    assert tuple(map(math.floor,positions[data["boss"]])) in initial_dry_geometry,"Boss depends on swimming or shortcut"

    route_ids=set()
    for index,route in enumerate(data["routes"]):
        route["id"]=f"R{index+1:02d}"
        pair=frozenset([route["a"],route["b"]]);assert pair not in route_ids,"Duplicate route"
        route_ids.add(pair)
        points=[positions[route["a"]],*route["via"],positions[route["b"]]]
        route["points"]=points
        for a,b in zip(points,points[1:]):
            for step in range(max(2,math.ceil(math.dist(a,b)*10))+1):
                t=step/max(2,math.ceil(math.dist(a,b)*10))
                px,py=a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t
                # Approximate body-clearance envelope, not movement simulation.
                for ox,oy in [(0,0),(-.4,0),(.4,0),(0,-.65),(0,.65)]:
                    assert (math.floor(px+ox),math.floor(py+oy)) in cells,(route["id"],"route/body envelope hits rock",[px,py])

    initial=graph_reachable(data)
    assert initial==set(positions),("graph unreachable",set(positions)-initial)
    initial_dry=graph_reachable(data,dry=True)
    assert data["boss"] in initial_dry and "vault" not in initial_dry
    for door in data["doors"]:
        assert door["unlock_from"] in initial,"Cyclic gate dependency"
    assert "vault" in graph_reachable(data,opened=["S1"],dry=True)
    assert tuple(map(math.floor,positions["vault"])) in flood(cells-water_cells,origin),"S1 does not open dry access"
    assert not (water_cells & rect_cells(next(s["rects"] for s in data["spaces"] if s["id"]=="boss_room")))

    outlines=contours(cells)
    xs,ys=[x for x,_ in cells],[y for _,y in cells]
    bounds=[min(xs),min(ys),max(xs)+1,max(ys)+1]
    all_cycle=len(data["routes"])-len(positions)+1
    initial_cycle=len([r for r in data["routes"] if not r.get("door")])-len(positions)+1
    geometry={"bounds":bounds,"outline":outlines,
              "space_outlines":{s["id"]:contours(rect_cells(s["rects"])) for s in data["spaces"]},
              "water_outlines":{w["id"]:contours(rect_cells(w["rects"])) for w in data["water"]}}
    report={"status":"design geometry checked; no Godot movement playtest",
            "space_pieces":len(data["spaces"]),"route_nodes":len(positions),"routes":len(data["routes"]),
            "initial_cycle_rank":initial_cycle,"all_open_cycle_rank":all_cycle,
            "initial_dry_reachable_nodes":len(initial_dry),"all_nodes":len(positions),
            "boss_initially_dry_reachable":True,"vault_initially_requires_swim":True,
            "water_contained":True,"open_pool_surfaces_have_air":True,
            "passage_area_screen_equivalent":round(len(cells)*data["cell_px"]**2/math.prod(data["screen_px"]),2),
            "bounds_screens":[round((bounds[2]-bounds[0])*data["cell_px"]/data["screen_px"][0],2),round((bounds[3]-bounds[1])*data["cell_px"]/data["screen_px"][1],2)],
            "water":water_report}
    assert initial_cycle>=4,"Too few initial route choices"
    return geometry,report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    data=json.loads(SOURCE.read_text(encoding="utf-8-sig"))
    geometry,report=build(data)
    args.output.mkdir(parents=True,exist_ok=True)
    fragment=TEMPLATE.read_text(encoding="utf-8").replace("__OUTLINE_JSON__",json.dumps(data,ensure_ascii=False)).replace("__GEOMETRY_JSON__",json.dumps(geometry,ensure_ascii=False)).replace("__REPORT_JSON__",json.dumps(report,ensure_ascii=False))
    (args.output/"sunken-cavern-outline.html").write_text(fragment,encoding="utf-8")
    (args.output/"outline_validation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(report,ensure_ascii=False,indent=2))


if __name__=="__main__": main()
