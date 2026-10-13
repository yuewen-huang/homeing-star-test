"""Verify handoff files with the user's actual Aseprite and native capture pixels."""
from pathlib import Path
import json
import struct
import subprocess
import sys
import zlib
from PIL import Image, ImageChops
from package_deer_vfx_aseprite import composite

out = Path(sys.argv[1])
metadata = json.loads((out / "时间轴.json").read_text(encoding="utf-8"))
manifest = json.loads((out / "capture_manifest.json").read_text(encoding="utf-8"))
raw_dirs = {c["id"]: Path(c["folder"]) for c in manifest["clips"]}
legacy_ids = ["light_stomp", "heavy_stomp", "mist_combo", "charge_uppercut", "uppercut_only", "mist_ultimate", "vine_cage"]
ids = [c["id"] if "id" in c else legacy_ids[i] for i, c in enumerate(metadata["clips"])]
verify = out / "校验"
verify.mkdir(exist_ok=True)
report = []
for clip, kind in zip(metadata["clips"], ids):
    path = out / clip["file"]
    canvas = tuple(clip.get("canvas", metadata.get("canvas", [512,384])))
    data = path.read_bytes()
    size, magic, count, width, height, depth = struct.unpack_from("<I5H", data)
    assert (size, magic, count, width, height, depth) == (len(data), 0xA5E0, clip["frame_count"], *canvas, 32)
    pos = 128
    layer_flags = []
    for index in range(count):
        frame_size, frame_magic, chunk_count, duration = struct.unpack_from("<I3H", data, pos)
        assert frame_magic == 0xF1FA and duration == clip["frames"][index]["duration_ms"]
        cursor = pos + 16
        draw_cels = 0
        for _ in range(chunk_count):
            length, chunk_type = struct.unpack_from("<IH", data, cursor)
            if chunk_type == 0x2004:
                layer_flags.append(struct.unpack_from("<H", data, cursor + 6)[0])
            elif chunk_type == 0x2005:
                layer, x, y, opacity, cel_type = struct.unpack_from("<HhhBH", data, cursor + 6)
                if layer in [2, 6]:
                    assert cel_type == 2, "Drawing cels must not be linked"
                    w, h = struct.unpack_from("<HH", data, cursor + 22)
                    assert (w, h) == (1, 1)
                    assert zlib.decompress(data[cursor+26:cursor+length]) == b"\0\0\0\0"
                    draw_cels += 1
            cursor += length
        assert cursor == pos + frame_size and draw_cels == 2
        pos += frame_size
    assert pos == len(data)
    assert layer_flags == [0, 1, 3, 1, 1, 1, 3], layer_flags
    stem = path.stem
    meta_path = verify / (stem + ".json")
    sheet_path = verify / (stem + "-sheet.png")
    r = subprocess.run(["D:/Aseprite/Aseprite.exe", "-b", "--list-layers", "--list-tags", str(path), "--trim",
        "--format", "json-array", "--data", str(meta_path), "--sheet", str(sheet_path),
        "--sheet-type", "rows", "--sheet-width", "4096"], capture_output=True,
        creationflags=subprocess.CREATE_NO_WINDOW, timeout=45)
    assert r.returncode == 0, r.stderr
    native = json.loads(meta_path.read_text(encoding="utf-8"))
    assert len(native["frames"]) == count
    assert all(f["duration"] == clip["frames"][i]["duration_ms"] and f["sourceSize"] == {"w":canvas[0], "h":canvas[1]} for i,f in enumerate(native["frames"]))
    assert [l["name"] for l in native["meta"]["layers"]] == metadata["layers"][1:]
    assert native["meta"]["frameTags"][0]["to"] == count - 1
    sheet = Image.open(sheet_path).convert("RGBA")
    raw = raw_dirs["charge_uppercut" if kind == "uppercut_only" else kind]
    chosen = {"light_nodule":18,"heavy_wave":40,"root_combo":72,"tracking_module":16,"root_ultimate":167,"decoy_counter":167}.get(kind, next((i for i,f in enumerate(clip["frames"]) if f.get("attack")), count//2))
    selected = sorted(set([0, chosen, min(chosen+3,count-1), count//2, count-1] + [min(tag["from"]+2,count-1) for tag in clip["tags"]]))
    maxima = []
    for i in selected:
        rect = native["frames"][i]["frame"]
        cropped = sheet.crop((rect["x"],rect["y"],rect["x"]+rect["w"],rect["y"]+rect["h"]))
        offset = native["frames"][i]["spriteSourceSize"]
        actual = Image.new("RGBA",canvas)
        actual.paste(cropped,(offset["x"],offset["y"]))
        expected = composite(raw, clip["frames"][i], canvas)
        diff = ImageChops.difference(actual.convert("RGBa"), expected.convert("RGBa"))
        maximum = max(high for low,high in diff.getextrema())
        assert maximum <= 8, (kind, i, maximum)
        maxima.append(maximum)
        if i == chosen:
            actual.save(verify / (stem + "-已由Aseprite打开.png"))
    report.append({"file":clip["file"], "frames":count, "layers":7, "sampled_frames":selected,
        "max_pixel_difference":max(maxima), "independent_drawing_cels":True, "native_aseprite":"1.2.15-x64"})
    print("VERIFIED", stem, count, "frames; pixel difference",max(maxima),flush=True)
(verify / "验证结果.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
print(f"ALL {len(report)} ASEPRITE FILES VERIFIED",flush=True)
