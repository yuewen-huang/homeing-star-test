"""Build the sunken-tower design review and lossless concept crops.

Design topology and provisional travel budgets only. This does not modify the
Godot project or certify physics, water/air behaviour, camera or gameplay.
"""
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
import math
from pathlib import Path
import shutil

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
PLAN = ROOT / "homeing-star-doc/docs/design/chapter_2_underwater_tower/plan.json"
OUTPUT = ROOT / "homeing-star-temp-assert/PendingArt/chapter_2_underwater_tower/20261031"
FONT = Path("C:/Windows/Fonts/msyh.ttc")
COLORS = {"bg":"#081c25", "text":"#e6ecea", "muted":"#a8bac0", "wall":"#71848b", "air":"#554b37", "flooded":"#123f55", "mixed":"#244953", "swim":"#78d6df", "walk":"#e0ded2", "shortcut":"#edb773", "investigation":"#f4d77d"}


def adjacency(plan, shortcuts=False):
    result = {r["id"]: [] for r in plan["rooms"]}
    result[plan["entry"]["id"]] = []
    for edge in plan["edges"]:
        if shortcuts or edge["kind"] != "shortcut":
            result[edge["a"]].append((edge["b"], edge))
            result[edge["b"]].append((edge["a"], edge))
    return result


def distances(graph, start):
    dist, queue = {start: 0}, deque([start])
    while queue:
        node = queue.popleft()
        for nxt, _ in graph[node]:
            if nxt not in dist:
                dist[nxt] = dist[node] + 1
                queue.append(nxt)
    return dist


def route_length(edge):
    return sum(math.dist(a, b) for a, b in zip(edge["route"], edge["route"][1:]))


def verify(plan):
    rooms = {r["id"]: r for r in plan["rooms"]}
    points = {key: r["point"] for key, r in rooms.items()}
    points["OUT"] = plan["entry"]["point"]
    assert len(rooms) == len(plan["rooms"]) == 12
    edge_ids = {e["id"]: e for e in plan["edges"]}
    assert len(edge_ids) == len(plan["edges"])
    for edge in plan["edges"]:
        assert edge["a"] in points and edge["b"] in points
        assert edge["route"][0] == points[edge["a"]], edge["id"]
        assert edge["route"][-1] == points[edge["b"]], edge["id"]
        if edge["kind"] == "swim":
            minimum = route_length(edge) / plan["oxygen"]["swim_speed_reference"] * plan["oxygen"]["travel_length_factor"]
            assert edge["swim_seconds"] >= minimum, (edge["id"], minimum)
    base, full = adjacency(plan), adjacency(plan, True)
    assert len(distances(base, "OUT")) == len(points), "Room unreachable without shortcuts"
    shortcuts = []
    for edge in plan["edges"]:
        if edge["kind"] == "shortcut":
            assert edge["open_from"] == edge["a"]
            hops = distances(base, edge["a"])[edge["b"]]
            assert hops >= 2
            shortcuts.append({"id":edge["id"], "open_from":edge["open_from"], "base_minimum_connections":hops, "opened_connections":1})
    for loop in plan["loops"]:
        assert loop["rooms"][0] == loop["rooms"][-1]
        assert len(set(loop["rooms"][:-1])) == len(loop["rooms"]) - 1
        assert len(loop["edges"]) == len(loop["rooms"]) - 1
        for eid, a, b in zip(loop["edges"], loop["rooms"], loop["rooms"][1:]):
            assert {edge_ids[eid]["a"],edge_ids[eid]["b"]} == {a,b}
        assert sum(edge_ids[e]["kind"] == "shortcut" for e in loop["edges"]) == 1
    air = {key for key, room in rooms.items() if room["air_refill"]} | {"OUT"}
    swim_segments = []

    def follow_swim(start, here, visited, total, eids):
        if here != start and here in air:
            swim_segments.append({"from":start,"to":here,"edges":eids,"budget_seconds":total})
            return
        for nxt, edge in base[here]:
            if edge["kind"] == "swim" and nxt not in visited:
                follow_swim(start, nxt, visited | {nxt}, total + edge["swim_seconds"], eids + [edge["id"]])

    for start in air:
        follow_swim(start, start, {start}, 0, [])
    longest = max(s["budget_seconds"] for s in swim_segments)
    assert longest <= plan["oxygen"]["planning_target_max_unbroken_swim_seconds"]
    for room in rooms.values():
        x,y,w,h = room["rect"]
        assert 0 <= x < x+w <= plan["world_size"][0]
        assert 0 <= y < y+h <= plan["world_size"][1]
    cycle_base = sum(len(v) for v in base.values()) // 2 - len(base) + 1
    cycle_full = sum(len(v) for v in full.values()) // 2 - len(full) + 1
    assert cycle_base == 2 and cycle_full == 5
    return {"scope":"design_graph_and_image_crops_only", "all_12_rooms_reachable_without_shortcuts":True,
            "initial_independent_cycles":cycle_base, "all_shortcuts_open_independent_cycles":cycle_full,
            "three_named_loops_closed":True, "shortcuts":shortcuts,
            "swim_budget_basis":"polyline / 180 px per second * 1.2, rounded up; not measured gameplay",
            "longest_unbroken_swim_budget_seconds":longest,
            "current_full_bar_seconds":plan["oxygen"]["current_full_bar_seconds"],
            "oxygen_budget_remaining_seconds":plan["oxygen"]["current_full_bar_seconds"]-longest,
            "swim_segments": sorted(swim_segments,key=lambda s:(s["from"],s["to"])),
            "not_verified":["Godot physical traversal", "actual swim times", "water/air compartment sealing", "collision", "facade registration and reveal", "camera framing", "boss room integration"]}


def font(size):
    return ImageFont.truetype(str(FONT), size)


def fit(image, size):
    result = image.copy()
    result.thumbnail(size, Image.Resampling.LANCZOS)
    return result


def paste_center(canvas, image, box):
    image = fit(image, (box[2]-box[0],box[3]-box[1]))
    canvas.paste(image,(int((box[0]+box[2]-image.width)/2), int((box[1]+box[3]-image.height)/2)))


def dash(draw, points, fill, width=4, dash_length=14):
    for a,b in zip(points,points[1:]):
        length = math.dist(a,b)
        for start in range(0,math.ceil(length),dash_length*2):
            lo, hi = start/length, min(1,(start+dash_length)/length)
            draw.line([(a[0]+(b[0]-a[0])*lo,a[1]+(b[1]-a[1])*lo),(a[0]+(b[0]-a[0])*hi,a[1]+(b[1]-a[1])*hi)],fill=fill,width=width)


def blueprint(plan):
    canvas = Image.new("RGB",(1200,1700),COLORS["bg"])
    draw = ImageDraw.Draw(canvas)
    draw.text((50,26),"沉塔 · 探索结构图",font=font(34),fill=COLORS["text"])
    draw.text((50,80),"世界坐标草案；连线是通路关系，非已验收碰撞",font=font(22),fill=COLORS["muted"])
    scale, ox, oy = .32, 55, 140
    p = lambda point: (ox+point[0]*scale,oy+point[1]*scale)
    outline = [[420,4360],[420,3000],[460,3000],[460,1780],[780,1780],[780,1140],[1080,1140],[1080,460],[2240,460],[2240,1140],[2800,1140],[2800,1780],[2840,1780],[2840,4360],[420,4360]]
    draw.line([p(q) for q in outline],fill=COLORS["wall"],width=4)
    # The thick internal spine and disconnected slabs prevent a single open shaft.
    for rect in [(1940,1100,180,740),(1280,2450,50,650),(1660,3220,220,500)]:
        x,y,w,h = rect
        draw.rectangle([p((x,y)),p((x+w,y+h))],fill="#33444a")
    for room in plan["rooms"]:
        x,y,w,h = room["rect"]
        a,b=p((x,y)),p((x+w,y+h))
        draw.rectangle([a,b],fill=COLORS.get(room["water"],COLORS["air"]),outline=COLORS["wall"],width=2)
        draw.line([p((x,y+h)),p((x+w,y+h))],fill=COLORS["wall"],width=5)
        name = room["name"].replace("上层浸水廊","浸水廊").replace("塔顶观星室","观星室")
        draw.text((a[0]+10,a[1]+8),room["id"],font=font(21),fill=COLORS["text"])
        draw.text((a[0]+10,a[1]+36),name,font=font(23),fill=COLORS["text"])
    for edge in plan["edges"]:
        pts=[p(q) for q in edge["route"]]
        if edge["kind"] == "shortcut":
            dash(draw,pts,COLORS["shortcut"],5)
            at=pts[1]
            draw.text((at[0]+7,at[1]-28),edge["id"],font=font(24),fill=COLORS["shortcut"])
        else:
            draw.line(pts,fill=COLORS["swim"] if edge["kind"] == "swim" else COLORS["walk"],width=5,joint="curve")
    for room in plan["rooms"]:
        x,y=p(room["point"])
        if room.get("investigation"):
            draw.polygon([(x,y-10),(x+10,y),(x,y+10),(x-10,y)],fill=COLORS["investigation"])
        else:
            draw.ellipse((x-7,y-7,x+7,y+7),fill=COLORS["text"])
        if room["air_refill"] and room["water"] != "air":
            draw.text((x-35,y+16),"换气",font=font(20),fill=COLORS["text"])
    draw.text(p((15,3290)),"入口",font=font(21),fill=COLORS["text"])
    for y,label in [(450,"塔顶"),(1170,"上层"),(1810,"中上"),(2470,"中下"),(3210,"下层"),(3810,"塔基")]:
        at=p((2860,y))
        draw.text(at,label,font=font(20),fill=COLORS["muted"])
    draw.text((50,1580),"青线：潜水　浅线：步行／石阶　虚线：远端开栓近路",font=font(22),fill=COLORS["text"])
    draw.text((50,1620),"菱形：调查位置　气龛／高台：换气落点",font=font(22),fill=COLORS["muted"])
    return canvas


def build(plan, output, inline):
    output.mkdir(parents=True,exist_ok=True)
    concepts, crops = output/"concepts", output/"crops"
    concepts.mkdir(exist_ok=True)
    crops.mkdir(exist_ok=True)
    source = concepts/"tower_facade_cutaway.png"
    with Image.open(source) as original:
        original.load()
        assert original.size == (1536,1024), original.size
        halves = {key: original.crop(rect) for key,rect in plan["source_pair_regions"].items()}
    for key,image in halves.items():
        image.save(concepts/f"tower_{key}.png")
    manifest = {"source":"concepts/tower_facade_cutaway.png", "source_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),
                "source_size":[1536,1024], "halves":plan["source_pair_regions"],
                "purpose":"lossless overlapping reference crops; facade and cutaway are not registered final layers", "crops":[]}
    for crop in plan["crops"]:
        x0,y0,x1,y1 = crop["rect"]
        assert 0<=x0<x1<=768 and 0<=y0<y1<=1024
        files={}
        for key,image in halves.items():
            path=crops/f"{crop['id']}_{key}.png"
            clipped=image.crop(crop["rect"])
            clipped.save(path)
            with Image.open(path) as saved:
                assert saved.size == clipped.size
                assert saved.tobytes() == clipped.tobytes()
            files[key]=path.relative_to(output).as_posix()
        manifest["crops"].append({**crop,"files":files,"native_size":[x1-x0,y1-y0]})
    assert set().union(*(set(c["rooms"]) for c in plan["crops"])) == {r["id"] for r in plan["rooms"]}
    sheet=Image.new("RGB",(2080,1490),COLORS["bg"])
    draw=ImageDraw.Draw(sheet)
    draw.text((40,20),"沉塔 · 六组局部参考（每组左外观、右内部）",font=font(34),fill=COLORS["text"])
    draw.text((40,75),"相邻切片保留重叠；均为原尺寸裁切参考，需按路线补绘和统一对齐。",font=font(23),fill=COLORS["muted"])
    for i,crop in enumerate(plan["crops"]):
        x,y=40+(i%2)*1030,135+(i//2)*440
        draw.text((x,y),f"{chr(65+i)}  {crop['name']}",font=font(28),fill=COLORS["text"])
        for j,key in enumerate(("facade","cutaway")):
            with Image.open(crops/f"{crop['id']}_{key}.png") as image:
                paste_center(sheet,image,(x+j*490,y+50,x+j*490+475,y+345))
        draw.text((x,y+353)," / ".join(crop["rooms"]),font=font(22),fill=COLORS["muted"])
    sheet.save(output/"crop_contact_sheet.png")
    diagram=blueprint(plan)
    diagram.save(output/"tower_route_plan.png")
    overview=Image.new("RGB",(2200,1740),COLORS["bg"])
    draw=ImageDraw.Draw(overview)
    draw.text((50,30),"沉没古城 · 从整塔概念到探索路线",font=font(42),fill=COLORS["text"])
    draw.text((50,95),"六层／十二处空间／两处初探分岔／三条远端开栓近路",font=font(27),fill=COLORS["muted"])
    paste_center(overview,halves["cutaway"],(30,200,990,1550))
    paste_center(overview,diagram,(1000,160,2190,1690))
    draw.text((60,1590),"左：美术氛围参考　右：待灰盒验证的空间设计",font=font(25),fill=COLORS["text"])
    draw.text((60,1640),"两者尚未按像素对齐；通路与干湿边界以设计稿补绘。",font=font(23),fill=COLORS["muted"])
    overview.save(output/"tower_design_overview.png")
    report=verify(plan)
    report["all_12_crop_files_pixel_identical_to_source_regions"]=True
    report["all_12_rooms_assigned_to_reference_crops"]=True
    for path,value in [(output/"crop_manifest.json",manifest),(output/"verification.json",report)]:
        path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    shutil.copyfile(PLAN,output/"plan_snapshot.json")
    if inline:
        template=Path(__file__).with_name("underwater_tower_inline.html").read_text(encoding="utf-8")
        inline.parent.mkdir(parents=True,exist_ok=True)
        inline.write_text(template.replace("__TOWER_PLAN_JSON__",json.dumps(plan,ensure_ascii=False)),encoding="utf-8")
        assert inline.stat().st_size<1_000_000
    print(json.dumps({"output":str(output),"rooms":12,"initial_cycles":report["initial_independent_cycles"],"opened_cycles":report["all_shortcuts_open_independent_cycles"],"max_swim_budget_seconds":report["longest_unbroken_swim_budget_seconds"],"reference_crop_files":12,"inline":str(inline) if inline else None},ensure_ascii=False))


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,default=OUTPUT)
    parser.add_argument("--inline",type=Path)
    parser.add_argument("--check-only",action="store_true")
    args=parser.parse_args()
    plan=json.loads(PLAN.read_text(encoding="utf-8"))
    if args.check_only:
        print(json.dumps(verify(plan),ensure_ascii=False,indent=2))
    else:
        build(plan,args.output,args.inline)
