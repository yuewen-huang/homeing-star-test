"""听音渠街美术排查。python homeing-star-test/tools/art/audit_listening_canal.py [--details]"""
import argparse
from collections import Counter
from pathlib import Path
import re
import time

GAME = Path(__file__).resolve().parents[3] / "homeing-star-game"
SCENES = GAME / "scenes/levels/chapter_2_underwater/cavern/bell_city"
HANDLE = "res://assets/levels/chapter_2_underwater/cavern/environment/listening_canal/trough_lever.png"
GEOMETRY = {"Polygon2D", "ColorRect", "Line2D", "MeshInstance2D", "MultiMeshInstance2D"}
LABELS = {
    "_draw_trough_support": "水槽支架", "_draw_leaf": "吊桥端面、箍带与铆钉",
    "_draw_striker": "钟槌与连杆", "_rope": "滑轮间的绳段", "draw_bank": "铺地与岸墙",
    "_draw_barricade": "泄洪挡板、木栓", "_draw_relics": "盐车及遗物",
    "_draw_gate": "门板、门闩与残旗", "_draw_spillway": "泄洪暗室与船骸",
    "_draw_details": "机关预警与水花", "_draw_foot_shadow": "脚下投影",
    "_draw_machinery": "水槽、水流", "_stream": "落水", "_chain": "锚链",
}


def resource(uri):
    return GAME / uri.removeprefix("res://")


def scripts_and_nodes(scene):
    refs, nodes = {}, {}
    node = None
    for number, line in enumerate(scene.read_text(encoding="utf-8-sig").splitlines(), 1):
        if line.startswith("["):
            node = None
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', line))
            if line.startswith("[ext_resource "):
                refs[attrs["id"]] = attrs["path"]
            elif line.startswith("[node "):
                parent = attrs.get("parent", ".")
                name = attrs["name"] if parent == "." else parent + "/" + attrs["name"]
                node = nodes[name] = {"type": attrs.get("type", ""), "line": number}
        elif node is not None and " = " in line:
            key, value = line.split(" = ", 1)
            ref = re.fullmatch(r'ExtResource\("([^"]+)"\)', value)
            node[key] = refs[ref[1]] if ref else value
    return refs, nodes


def art_inputs(source):
    """Resolve simple Godot preload expressions used by these two scenes."""
    dirs = dict(re.findall(r'const (\w+)\s*:?=\s*"(res://[^"]+/)"', source))
    for m in re.finditer(r'preload\(\s*(?:(\w+)\s*\+\s*)?"([^"]+)"\s*\)', source):
        uri = dirs.get(m[1], "") + m[2]
        if uri.endswith((".png", ".webp", ".svg")):
            yield uri, m.start()


# Gameplay objects that can disappear completely even when interactions still work.
# A live draw site must consume the declared texture, in addition to its existing file.
def check_mechanism(refs, required):
    missing = []
    for script, parts in required.items():
        source = resource(refs[script]).read_text(encoding="utf-8-sig") if script in refs else ""
        declared = {}
        for uri, index in art_inputs(source):
            line = source[source.rfind("\n", 0, index)+1:index].strip()
            binding = re.fullmatch(r"const (\w+)\s*:?=\s*", line)
            if binding and resource(uri).is_file():
                declared[binding[1]] = Path(uri).name
        used = set()
        for call in re.finditer(r"^[ \t]*(?:\w+\.)?(draw_texture_rect|draw_polygon|_draw_link)\(", source, re.M):
            args = arguments(source, call.end())
            slot = 3 if call[1] == "draw_polygon" else 0
            if len(args) > slot:
                used.add(args[slot])
        missing.extend(name for key, name in parts.items() if declared.get(key) != name or key not in used)
    return missing


def arguments(source, start):
    """Count only top-level arguments, including multiline UV and vertex arrays."""
    args, depth, first = [], 0, start
    for match in re.finditer(r'"(?:\\.|[^"\\])*"|#[^\n]*|[()\[\]{},]', source[start:]):
        token = match[0]
        end = start + match.start()
        if token in ("(", "[", "{"):
            depth += 1
        elif token == ")" and depth == 0:
            return args + [source[first:end].strip()]
        elif token in (")", "]", "}"):
            depth -= 1
        elif token == "," and depth == 0:
            args.append(source[first:end].strip())
            first = end + 1
    return []


def scan_script(path, details):
    source = path.read_text(encoding="utf-8-sig")
    vectors = []
    for uri, _ in art_inputs(source):
        status = "矢量图形" if uri.endswith(".svg") else "位图"
        if not resource(uri).is_file():
            status = "引用缺文件"
        if details or status != "位图":
            vectors.append(f"{status} {uri}")
    for item in vectors:
        print("   ", item)
    # Preserve line numbers. A color literal inside quotes is not a comment.
    source = re.sub(r'"(?:\\.|[^"\\])*"|#[^\n]*',
                    lambda m: "" if m[0].startswith("#") else m[0], source)
    funcs = list(re.finditer(r'^\s*(?:static )?func (\w+)\(', source, re.M))
    for i, f in enumerate(funcs):
        body = source[f.end():funcs[i+1].start() if i+1 < len(funcs) else len(source)]
        findings = []
        for m in re.finditer(r'\b(draw_\w+|_beam|_rope)\s*\(', body):
            name = m[1]
            if name in ("_beam", "_rope"):
                kind = "通用件拼装"
            elif name.startswith(("draw_set_", "draw_string")) or name == "draw_bank":
                continue
            elif name.startswith("draw_texture"):
                kind = "贴图"
            elif name in ("draw_polygon", "draw_colored_polygon"):
                args = arguments(body, m.end())
                kind = "贴图" if len(args) >= 4 and args[3] != "null" else "程序形状"
            else:
                kind = "程序形状"
            line = source.count("\n", 0, f.end()+m.start()) + 1
            findings.append((kind, line, name))
        if findings:
            counts = Counter(k for k, _, _ in findings)
            label = LABELS.get(f[1], f[1])
            print(f"  {path.name}:{findings[0][1]} {label} ({f[1]})  " +
                  " / ".join(f"{k}×{n}" for k, n in counts.items()))
            if details:
                for kind, number, call in findings:
                    print(f"    {number:4}  {kind}  {call}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--details", action="store_true", help="逐行列出绘制调用")
    args = parser.parse_args()
    start = time.perf_counter()
    visited = set()
    valid = False
    for filename in ("listening_entry.tscn", "river_lock.tscn"):
        refs, nodes = scripts_and_nodes(SCENES / filename)
        print("\n" + ("听音亭至桥东" if filename.startswith("listening") else
                       "相邻锁江门（共享一个脚本，报告含西岸以东）"))
        if filename.startswith("listening"):
            lever = nodes.get("TroughPivot/TroughLever", {})
            valid = (lever.get("type") == "Sprite2D" and lever.get("texture") == HANDLE
                     and resource(HANDLE).is_file() and all(nodes.get(key, {}).get("visible") != "false"
                     for key in ("ListeningEntry", "TroughPivot", "TroughPivot/TroughLever")))
            print("  水槽把手独立贴图及场景挂接：" + ("通过" if valid else "缺失或隐藏"))
            missing = check_mechanism(refs, {
                "entry": {"TROUGH": "pivot_trough.png", "BELL": "canal_bell.png"},
                "rig": {"WHEEL": "scoop_wheel.png", "DRUM": "rope_drum.png",
                        "BLOCK": "sheave_block.png", "EYE": "lashed_eye.png",
                        "HEMP": "hoist_hemp.png", "BOARDS": "drawbridge_boards.webp"},
            })
            print("  水槽、钟、槽轮、卷筒、滑轮、吊耳、绳股、桥板的贴图与绘制引用：" +
                  ("缺少 " + "、".join(missing) if missing else "齐全"))
            valid = valid and not missing
            fittings = ("hoist_trestle", "sheave_bracket", "wheel_stand", "trough_stand",
                       "clapper_hanger", "bell_pushrod", "bell_crank", "clapper_arm",
                       "bridge_fascia", "bridge_strap", "hinge_pin", "sling_shackle")
            parts = {name.upper(): name + ".png" for name in fittings}
            parts.update(BEARING="quay_bearing.png", STRIKER="bell_striker.png")
            missing = check_mechanism(refs, {
                "scenery": {"FEEDER": "feeder_flume.png", "POST": "flume_post.png"},
                "rig": parts,
            })
            print("  供水木槽与立柱、支架、吊环、桥端、箍带、轴销和钟槌传动：" +
                  ("缺少 " + "、".join(missing) if missing else "齐全"))
        else:
            missing = check_mechanism(refs, {"lock": {"SALT_CART": "salt_cart_wreck.png",
                                                       "CART_RUTS": "cart_ruts.png"}})
            print("  西岸运盐残车与车辙绘制引用：" + ("缺失" if missing else "通过"))
            valid = valid and not missing
            pieces = ("iron_leaf", "rust_bolt", "lintel", "pennant", "chain_link",
                      "anchor_eye", "scorched_cloth", "tidal_water", "gatehouse")
            parts = {name.upper(): name + ".png" for name in pieces}
            parts.update(QUAY="quay_lockwork.webp", SEATED_RIG="quay_seated_rig.webp",
                         TIMBER="quay_gate_timber.png",
                         HATCH="quay_hatch.png", HULL="quay_hull.png",
                         UPPER_STAY="quay_upper_stay.png", LOWER_STAY="quay_lower_stay.png",
                         KEY_TIP="quay_key_tip.png", KEY_HEEL="quay_key_heel.png")
            missing = check_mechanism(refs, {"lock": parts})
            print("  检修井、横栓两态、船与锚链、闸门三闩及闸后遗物：" +
                  ("缺少 " + "、".join(missing) if missing else "齐全"))
        valid = valid and not missing
        for name, node in nodes.items():
            if name.startswith("BackstageBay/"):
                continue  # The theatre begins well beyond the first lock.
            if node["type"] in GEOMETRY:
                print(f"  {filename}:{node['line']} {name}  " +
                      ("带材质/贴图，核对来源" if "texture" in node or "material" in node else "场景基本形"))
        for uri in refs.values():
            if uri.endswith(".gd") and uri not in visited:
                visited.add(uri)
                scan_script(resource(uri), args.details)
    print(f"\n用时 {time.perf_counter()-start:.2f} 秒。数字是源码调用点数。"
          "水花、投影也会命中。已烘焙图像的制作来源与实机遮挡需另核。")
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
