"""Import painted mist layers and per-frame body translations without editing sources.
Requires Aseprite and Pillow. Source folder must contain the original capture manifest/raw.
Run with --source ART_FOLDER --project GODOT_FOLDER --aseprite ASEPRITE_EXE --work CACHE_FOLDER.
Only small runtime PNG atlases and timeline resource are copied to the game repository.
"""
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
from pathlib import Path
from PIL import Image, ImageChops
from split_deer_actions import migrate_painted

SPECS = {
    "light_stomp": ("01_轻跺脚.aseprite", "图层 1", "绘制_前景"),
    "heavy_stomp": ("02_人立践踏.aseprite", "图层 2", "图层 1"),
    "charge_uppercut": ("04_冲刺上挑.aseprite", "图层 1", "图层 2"),
}

def read_timing(source):
    data = source.read_bytes()
    _, magic, count, width, height, depth = struct.unpack_from("<I5H", data)
    if magic != 0xA5E0 or depth != 32:
        raise ValueError(f"Expected RGBA Aseprite file: {source}")
    result, position = [], 128
    for _ in range(count):
        length, frame_magic, _, duration = struct.unpack_from("<I3H", data, position)
        if frame_magic != 0xF1FA or not duration:
            raise ValueError(f"Invalid frame in {source}")
        result.append(duration)
        position += length
    return (width, height), result

def export_layer(executable, source, layer, stem):
    command = [str(executable), "-b", "--layer", layer, str(source), "--sheet", str(stem.with_suffix(".png")),
               "--sheet-type", "packed", "--sheet-width", "2048", "--trim", "--format", "json-array",
               "--data", str(stem.with_suffix(".json"))]
    subprocess.run(command, check=True, capture_output=True, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0), timeout=60)
    rows = json.loads(stem.with_suffix(".json").read_text(encoding="utf-8"))["frames"]
    # Aseprite omits empty frames from a trimmed layer. Recover original indices,
    # rather than collapsing gaps or playing the sparse atlas at the wrong time.
    frames = {}
    for row in rows:
        match = re.search(r" (\d+)\.aseprite$", row["filename"])
        if not match or row.get("rotated"):
            raise ValueError(f"Unexpected native export: {row}")
        frames[int(match.group(1))] = row
    return frames

def cel(row, anchor):
    if row is None:
        return None
    region, source = row["frame"], row["spriteSourceSize"]
    return {"region": [region[k] for k in ("x", "y", "w", "h")],
            "offset": [source["x"]-anchor[0], source["y"]-anchor[1]]}

def body_shift(row, atlas, original):
    bounds = original.getchannel("A").getbbox()
    if row is None:
        if bounds:
            raise ValueError("Body layer is missing an original nonempty frame")
        return [0, 0]
    r, pos = row["frame"], row["spriteSourceSize"]
    actual = atlas.crop((r["x"], r["y"], r["x"]+r["w"], r["y"]+r["h"]))
    expected = original.crop(bounds)
    if actual.size != expected.size or max(v[1] for v in ImageChops.difference(actual, expected).getextrema()) > 1:
        raise ValueError("Body artwork changed beyond a translation; import the new body animation separately")
    return [pos["x"]-bounds[0], pos["y"]-bounds[1]]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source", "project", "aseprite", "work"):
        parser.add_argument("--"+name, type=Path, required=True)
    parser.add_argument("--vine-source", type=Path, help="Finished short cage folder containing 07 and its capture manifest/raw")
    parser.add_argument("--dash-source", type=Path, help="Finished short mist dash folder containing 06 and its capture manifest/raw")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((args.source/"capture_manifest.json").read_text(encoding="utf-8"))
    refs = {clip["id"]: clip for clip in manifest["clips"]}
    anchor = manifest["anchor"]
    destination = args.project/"assets/sideview/effects/deer_painted"
    timeline_path = destination/"timelines.tres"
    preserved = {}
    if timeline_path.exists():
        encoded = timeline_path.read_text(encoding="utf-8").split("metadata/timelines = ",1)[1].strip()
        preserved = json.loads(json.loads(encoded))["clips"]
    output = {"world_scale": manifest["world_units_per_pixel"], "clips": preserved}
    for kind, (filename, back_name, front_name) in SPECS.items():
        source = args.source/filename
        canvas, timing = read_timing(source)
        reference = refs[kind]
        if list(canvas) != manifest["canvas"] or len(timing) != len(reference["frames"]):
            raise ValueError(f"Canvas/frame-count differs from original capture: {filename}")
        layers = {depth: export_layer(args.aseprite, source, layer, args.work/(kind+"_"+depth))
                  for depth, layer in (("back",back_name),("front",front_name),("body","动作参考_锁定"))}
        clip = {"canvas": list(canvas), "anchor": anchor, "canonical_direction": -1,
                "duration_ms": sum(timing), "frames": [], "body_offsets": [],
                "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
        source_time = 0
        with Image.open(args.work/(kind+"_body.png")) as body_file:
            body_atlas = body_file.convert("RGBA")
            for index, duration in enumerate(timing):
                clip["frames"].append({"duration_ms": duration, **{depth: cel(layers[depth].get(index), anchor) for depth in ("back","front")}})
                ref = reference["frames"][index]
                with Image.open(args.source/"raw"/kind/(f"{index:04d}_body.png")) as original:
                    shift = body_shift(layers["body"].get(index), body_atlas, original.convert("RGBA"))
                clip["body_offsets"].append({"time_ms": source_time, "animation": ref["animation"], "body_frame": ref["body_frame"], "offset": shift})
                if kind == "charge_uppercut" and ref["animation"] == "charge" and ref["body_frame"] == 18 and "uppercut_source_ms" not in clip:
                    clip["uppercut_source_ms"] = source_time
                source_time += duration
        if kind == "charge_uppercut":
            clip["loop_end_ms"] = clip["uppercut_source_ms"]
        output["clips"][kind] = clip
        print(f"{filename}: {len(timing)} timeline frames, back={len(layers['back'])}, front={len(layers['front'])}")
    if args.vine_source:
        source = args.vine_source/"07_藤蔓囚笼_出土合拢.aseprite"
        vine_manifest = json.loads((args.vine_source/"capture_manifest.json").read_text(encoding="utf-8"))
        reference = next(clip for clip in vine_manifest["clips"] if clip["id"] == "vine_growth")
        canvas, timing = read_timing(source)
        if list(canvas) != vine_manifest["canvas"] or len(timing) != len(reference["frames"]):
            raise ValueError("Cage canvas/frame-count differs from original capture")
        anchor = vine_manifest["anchor"]
        front = export_layer(args.aseprite, source, "图层 1", args.work/"vine_cage_front")
        bodies = export_layer(args.aseprite, source, "动作参考_锁定", args.work/"vine_cage_body")
        if len(front) != len(timing):
            raise ValueError("Expected a painted cage cel on each growth frame")
        clip = {"canvas": list(canvas), "anchor": anchor, "canonical_direction": -1,
                "duration_ms": sum(timing), "frames": [], "body_offsets": [],
                "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
        source_time = 0
        with Image.open(args.work/"vine_cage_body.png") as body_file:
            body_atlas = body_file.convert("RGBA")
            for index, duration in enumerate(timing):
                clip["frames"].append({"duration_ms": duration, "back": None, "front": cel(front.get(index), anchor)})
                ref = reference["frames"][index]
                with Image.open(args.vine_source/"raw/vine_growth"/(f"{index:04d}_body.png")) as original:
                    shift = body_shift(bodies.get(index), body_atlas, original.convert("RGBA"))
                clip["body_offsets"].append({"time_ms": source_time, "animation": ref["animation"], "body_frame": ref["body_frame"], "offset": shift})
                source_time += duration
        output["clips"]["vine_cage"] = clip
        print(f"Painted cage: {len(timing)} frames, {sum(timing)} ms, with body translations")
    if args.dash_source:
        source = args.dash_source/"06_雾大招_冲刺循环.aseprite"
        dash_manifest = json.loads((args.dash_source/"capture_manifest.json").read_text(encoding="utf-8"))
        reference = next(clip for clip in dash_manifest["clips"] if clip["id"] == "mist_dash_loop")
        canvas, timing = read_timing(source)
        if list(canvas) != dash_manifest["canvas"] or len(timing) != len(reference["frames"]):
            raise ValueError("Mist dash canvas/frame-count differs from original capture")
        anchor = dash_manifest["anchor"]
        layers = {depth: export_layer(args.aseprite, source, layer, args.work/("mist_dash_"+depth))
                  for depth, layer in (("back","图层 2"),("front","图层 3"),("body","动作参考_锁定"))}
        clip = {"canvas": list(canvas), "anchor": anchor, "canonical_direction": -1,
                "duration_ms": sum(timing), "frames": [], "body_offsets": [],
                "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
        source_time = 0
        with Image.open(args.work/"mist_dash_body.png") as body_file:
            body_atlas = body_file.convert("RGBA")
            for index, duration in enumerate(timing):
                ref = reference["frames"][index]
                clip["frames"].append({"duration_ms": duration, "body_frame": ref["body_frame"],
                    **{depth: cel(layers[depth].get(index), anchor) for depth in ("back","front")}})
                with Image.open(args.dash_source/"raw/mist_dash_loop"/(f"{index:04d}_body.png")) as original:
                    shift = body_shift(layers["body"].get(index), body_atlas, original.convert("RGBA"))
                clip["body_offsets"].append({"time_ms": source_time, "animation": ref["animation"], "body_frame": ref["body_frame"], "offset": shift})
                source_time += duration
        output["clips"]["mist_dash"] = clip
        print(f"Painted mist dash: {len(timing)} frames, {sum(timing)} ms, back={len(layers['back'])}, front={len(layers['front'])}")
    # Validate all inputs before replacing any runtime file. Sources stay untouched.
    destination = args.project/"assets/sideview/effects/deer_painted"
    destination.mkdir(parents=True, exist_ok=True)
    for kind in SPECS:
        for depth in ("back", "front"):
            filename = kind+"_"+depth+".png"
            shutil.copy2(args.work/filename, destination/filename)
    if args.vine_source:
        shutil.copy2(args.work/"vine_cage_front.png", destination/"vine_cage_front.png")
    if args.dash_source:
        for depth in ("back", "front"):
            shutil.copy2(args.work/("mist_dash_"+depth+".png"), destination/("mist_dash_"+depth+".png"))
    serialized = json.dumps(output, ensure_ascii=False, separators=(",",":"))
    # Use an imported resource, as the existing body/core data does, so game
    # exports include the timeline without a custom non-resource include filter.
    resource = '[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/timelines = ' + json.dumps(serialized, ensure_ascii=False) + "\n"
    (destination/"timelines.tres").write_text(resource,encoding="utf-8")
    migrate_painted(args.project)
    print(f"Imported authored layers and alignment: {destination}")

if __name__ == "__main__":
    main()
