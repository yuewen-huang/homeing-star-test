"""Validate the whole-level proposal and build its review diagram (no game writes)."""
from __future__ import annotations

import argparse
import json
import math
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PLAN = ROOT / "homeing-star-doc/docs/design/sunken_cavern/plan.json"
TEMPLATE = Path(__file__).with_name("sunken_cavern_plan_inline.html")


def contains(rect, point, strict=False):
    x, y, w, h = rect
    px, py = point
    margin = 1e-7 if strict else -1e-7
    return x + margin < px < x + w - margin and y + margin < py < y + h - margin


def length(points, screen):
    return sum(math.hypot((b[0] - a[0]) * screen[0], (b[1] - a[1]) * screen[1])
               for a, b in zip(points, points[1:]))


def reachable(plan, unlocked=()):
    graph = {r["id"]: [] for r in plan["regions"]}
    for edge in plan["connections"]:
        if edge["kind"] == "shortcut" and edge["id"] not in unlocked:
            continue
        graph[edge["a"]].append(edge["b"])
        graph[edge["b"]].append(edge["a"])
    seen, queue = {plan["entry"]}, deque([plan["entry"]])
    while queue:
        for neighbor in graph[queue.popleft()]:
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append(neighbor)
    return seen


def validate(plan):
    regions = {r["id"]: r for r in plan["regions"]}
    assert len(regions) == len(plan["regions"]), "Duplicate region ID"
    world = [0, 0, *plan["world_screens"]]
    for room in regions.values():
        x, y, w, h = room["rect"]
        assert contains(world, [x, y]) and contains(world, [x+w, y+h]), room["id"]
        assert 1 <= w <= 2 and h <= (2.5 if room["type"] == "tower" else 2), room["id"]
    rooms = list(regions.values())
    for i, a in enumerate(rooms):
        ax, ay, aw, ah = a["rect"]
        for b in rooms[i+1:]:
            bx, by, bw, bh = b["rect"]
            assert min(ax+aw, bx+bw) <= max(ax, bx) or min(ay+ah, by+bh) <= max(ay, by), (a["id"], b["id"])

    ids, all_segments = set(), []
    for edge in plan["connections"]:
        assert edge["id"] not in ids
        ids.add(edge["id"])
        assert edge["a"] in regions and edge["b"] in regions
        for room_id, point in [(edge["a"], edge["points"][0]), (edge["b"], edge["points"][-1])]:
            rect = regions[room_id]["rect"]
            assert contains(rect, point) and not contains(rect, point, strict=True), (edge["id"], "port off boundary")
        for a, b in zip(edge["points"], edge["points"][1:]):
            assert a[0] == b[0] or a[1] == b[1], "Only orthogonal connector budgets"
            all_segments.append((edge["id"], a, b))
            # Sample the real connector width, not only its centre line.
            half_x = edge["clearance_px"] / (2 * plan["screen_px"][0]) if a[0] == b[0] else 0
            half_y = edge["clearance_px"] / (2 * plan["screen_px"][1]) if a[1] == b[1] else 0
            for step in range(101):
                t = step / 100
                point = [a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t]
                for offset in [-1, 0, 1]:
                    probe = [point[0] + half_x*offset, point[1] + half_y*offset]
                    assert contains(world, probe), (edge["id"], "outside world")
                    for room in rooms:
                        if room["id"] not in [edge["a"], edge["b"]]:
                            assert not contains(room["rect"], probe, strict=True), (edge["id"], "hits unrelated room", room["id"])

    # There are no intended crossovers: reject centreline crossings/overlaps.
    for i, (aid, a, b) in enumerate(all_segments):
        for bid, c, d in all_segments[i+1:]:
            if aid == bid:
                continue
            if a[0] == b[0] and c[1] == d[1]:
                assert not (min(c[0], d[0]) <= a[0] <= max(c[0], d[0]) and min(a[1], b[1]) <= c[1] <= max(a[1], b[1])), (aid, bid, "crossing")
            elif a[1] == b[1] and c[0] == d[0]:
                assert not (min(a[0], b[0]) <= c[0] <= max(a[0], b[0]) and min(c[1], d[1]) <= a[1] <= max(c[1], d[1])), (aid, bid, "crossing")
            elif a[0] == b[0] == c[0] == d[0]:
                assert min(max(a[1], b[1]), max(c[1], d[1])) < max(min(a[1], b[1]), min(c[1], d[1])), (aid, bid, "overlap")
            elif a[1] == b[1] == c[1] == d[1]:
                assert min(max(a[0], b[0]), max(c[0], d[0])) < max(min(a[0], b[0]), min(c[0], d[0])), (aid, bid, "overlap")

    initial = reachable(plan)
    assert initial == set(regions), ("unreachable with shortcuts shut", set(regions) - initial)
    for edge in plan["connections"]:
        if edge["kind"] == "shortcut":
            assert edge["unlock_from"] in initial
            assert edge["unlock_from"] in [edge["a"], edge["b"]]
    for route in [plan["initial_route"], plan["upper_loop"], plan["lower_loop"]]:
        for a, b in zip(route, route[1:]):
            matches = [e for e in plan["connections"] if {a,b} == {e["a"],e["b"]}]
            assert matches, (a,b,"missing edge")
            if route is plan["initial_route"]:
                assert any(e["kind"] == "open" for e in matches), "Initial route depends on unopened door"

    water_report = []
    budget = plan["movement_budget"]
    for water in plan["water_routes"]:
        room = regions[water["region"]]
        x, y, w, h = water["rect"]
        assert contains(room["rect"], [x,y]) and contains(room["rect"], [x+w,y+h])
        assert all(contains(water["rect"], p) for p in water["points"])
        assert water["points"][0][1] == water["points"][-1][1] == y, "Missing surface exit"
        distance = length(water["points"], plan["screen_px"])
        seconds = math.ceil(distance/budget["swim_speed_px_s"]*budget["turn_margin"]*2)/2
        assert seconds <= budget["planned_continuous_swim_cap_s"] < budget["oxygen_seconds"]
        water_report.append({"id":water["id"],"length_px":round(distance,1),"budget_s":seconds,"required":water["required"]})
    area = sum(r["rect"][2]*r["rect"][3] for r in rooms)
    report = {"scope":"design data only; no runtime playtest", "regions":len(regions),
              "connections":len(plan["connections"]),"initial_reachable":sorted(initial),
              "open_cycle_rank":len([e for e in plan["connections"] if e["kind"] == "open"])-len(regions)+1,
              "all_open_cycle_rank":len(plan["connections"])-len(regions)+1,
              "room_area_screens":round(area,4),"world_px":[round(a*b) for a,b in zip(plan["world_screens"],plan["screen_px"])],
              "water":water_report}
    assert report["all_open_cycle_rank"] == 2
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, default=DEFAULT_PLAN)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--historical", action="store_true", help="Explicitly render the rejected box proposal for history only")
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text(encoding="utf-8-sig"))
    if plan.get("status") == "rejected_by_user" and not args.historical:
        parser.error("The box proposal was rejected. Use build_sunken_cavern_outline.py for the current review proposal.")
    report = validate(plan)
    args.output.mkdir(parents=True, exist_ok=True)
    fragment = TEMPLATE.read_text(encoding="utf-8-sig").replace("__PLAN_JSON__", json.dumps(plan, ensure_ascii=False)).replace("__REPORT_JSON__",json.dumps(report,ensure_ascii=False))
    assert "__PLAN_JSON__" not in fragment and "__REPORT_JSON__" not in fragment
    (args.output / "sunken-cavern-layout.html").write_text(fragment,encoding="utf-8")
    (args.output / "validation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(report,ensure_ascii=False,indent=2))


if __name__ == "__main__":
    main()
