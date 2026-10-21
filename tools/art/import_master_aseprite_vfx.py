"""Import the user's edited compact master VFX Aseprite sequences into the game atlases."""
import json
import math
import subprocess
import struct
import sys
import zlib
from pathlib import Path

from PIL import Image

WORK = Path(__file__).resolve().parents[3]
ASE_DIR = WORK / "homeing-star-temp-assert/Art/master_painted_vfx/20261021/aseprite_pre_painted_compact_109"
GAME_ASSETS = WORK / "homeing-star-game/assets/generated/combat_vfx/master/heavy_skills"
SOURCE_MANIFEST = ASE_DIR / "manifest_source.json"


def _chunks(blob, start, count):
    offset = start
    for _ in range(count):
        size, kind = struct.unpack_from("<IH", blob, offset)
        if size < 6 or offset + size > len(blob):
            raise ValueError("Invalid Aseprite chunk bounds")
        yield kind, blob[offset + 6:offset + size]
        offset += size


def _decode_aseprite(path):
    blob = path.read_bytes()
    size, magic, frame_count, width, height, depth = struct.unpack_from("<IHHHHH", blob)
    if size != len(blob) or magic != 0xA5E0 or depth not in (8, 32):
        raise ValueError(f"Unsupported or invalid Aseprite file: {path.name}")
    transparent_index = blob[28]
    layers = []
    palette = {}
    frames = []
    offset = 128
    for frame_index in range(frame_count):
        frame_size, frame_magic, old_count, duration = struct.unpack_from("<IHHH", blob, offset)
        chunk_count = struct.unpack_from("<I", blob, offset + 12)[0] or old_count
        if frame_magic != 0xF1FA or offset + frame_size > len(blob):
            raise ValueError(f"Invalid frame {frame_index} in {path.name}")
        cels = []
        for kind, payload in _chunks(blob, offset + 16, chunk_count):
            if kind == 0x2004:  # layer
                flags, layer_type, child, default_w, default_h, blend = struct.unpack_from("<HHHHHH", payload)
                opacity = payload[12]
                name_length = struct.unpack_from("<H", payload, 16)[0]
                name = payload[18:18 + name_length].decode("utf-8", "replace")
                layers.append({"flags": flags, "type": layer_type, "opacity": opacity, "blend": blend, "name": name})
            elif kind == 0x2019:  # indexed palette
                palette_size, first, last = struct.unpack_from("<III", payload)
                cursor = 20
                for index in range(first, last + 1):
                    flags = struct.unpack_from("<H", payload, cursor)[0]
                    palette[index] = tuple(payload[cursor + 2:cursor + 6])
                    cursor += 6
                    if flags & 1:
                        label_size = struct.unpack_from("<H", payload, cursor)[0]
                        cursor += 2 + label_size
            elif kind == 0x2005:  # cel
                layer_index, x, y, cel_opacity, cel_type = struct.unpack_from("<HhhBH", payload)
                if cel_type == 1:  # linked cel, resolved after parsing all frames
                    cels.append({"linked": struct.unpack_from("<H", payload, 16)[0], "layer": layer_index, "x": x, "y": y, "opacity": cel_opacity})
                    continue
                if cel_type not in (0, 2):
                    raise ValueError(f"Unsupported cel type {cel_type} in {path.name}")
                cel_w, cel_h = struct.unpack_from("<HH", payload, 16)
                pixels = payload[20:]
                if cel_type == 2:
                    pixels = zlib.decompress(pixels)
                if depth == 32:
                    image = Image.frombytes("RGBA", (cel_w, cel_h), pixels)
                else:
                    rgba = []
                    for color_index in pixels:
                        color = palette.get(color_index, (0, 0, 0, 0))
                        if color_index == transparent_index:
                            color = (color[0], color[1], color[2], 0)
                        rgba.append(color)
                    image = Image.new("RGBA", (cel_w, cel_h))
                    image.putdata(rgba)
                cels.append({"image": image, "layer": layer_index, "x": x, "y": y, "opacity": cel_opacity})
        frames.append({"duration_ms": duration, "cels": cels})
        offset += frame_size
    if offset != len(blob):
        raise ValueError(f"Trailing bytes in {path.name}")

    # Preserve linked cels if the artist used them.
    for frame_index, frame in enumerate(frames):
        resolved = []
        for cel in frame["cels"]:
            if "linked" in cel:
                linked = next((entry for entry in frames[cel["linked"]]["cels"] if entry.get("layer") == cel["layer"] and "image" in entry), None)
                if linked is None:
                    raise ValueError(f"Unresolved linked cel in {path.name}")
                cel = {**cel, "image": linked["image"]}
            resolved.append(cel)
        frame["cels"] = resolved

    # Honor visibility when several layers contribute to a frame. These VFX
    # documents have one artwork layer each; keep its pixels if it was hidden
    # in the editor so that a saved editor toggle cannot erase a whole game
    # direction (notably lunge_combo/cut_1_left).
    visible_layers = {index for index, layer in enumerate(layers) if layer["flags"] & 1}
    if not visible_layers and len(layers) == 1:
        visible_layers = {0}
    for layer in layers:
        if layer["type"] != 0 or layer["blend"] != 0:
            raise ValueError(f"Unsupported layer type/blend in {path.name}: {layer}")

    images = []
    for frame in frames:
        canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        for cel in sorted(frame["cels"], key=lambda entry: entry["layer"]):
            layer_index = cel["layer"]
            if layer_index not in visible_layers:
                continue
            image = cel["image"]
            opacity = cel["opacity"] * layers[layer_index]["opacity"] // 255
            if opacity != 255:
                alpha = image.getchannel("A").point(lambda value: value * opacity // 255)
                image = image.copy()
                image.putalpha(alpha)
            x, y = cel["x"], cel["y"]
            left, top = max(0, x), max(0, y)
            right, bottom = min(width, x + image.width), min(height, y + image.height)
            if right > left and bottom > top:
                canvas.alpha_composite(image.crop((left - x, top - y, right - x, bottom - y)), (left, top))
        images.append(canvas)
    return (width, height), images, [frame["duration_ms"] for frame in frames]


def main():
    manifest = json.loads((GAME_ASSETS / "manifest.json").read_text(encoding="utf-8"))
    original = json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))
    total_frames = 0
    for name, clip in manifest["clips"].items():
        source_clip = original["clips"][name]
        ase_path = ASE_DIR / (name.replace("/", "__") + ".aseprite")
        if not ase_path.is_file():
            raise FileNotFoundError(ase_path)
        (new_w, new_h), frames, _durations_ms = _decode_aseprite(ase_path)
        old_w, old_h = source_clip["cell"]
        if len(frames) != clip["frames"]:
            raise ValueError(f"Frame count changed for {name}: expected {clip['frames']}, got {len(frames)}")
        if new_w < old_w or new_h < old_h:
            raise ValueError(f"Aseprite canvas shrank for {name}; refusing to crop edited art")

        # Canvas growth in these files is centered. Move the game pivot by the
        # same top/left padding so the edited art stays anchored to the old pose.
        pad_x, pad_y = (new_w - old_w) // 2, (new_h - old_h) // 2
        clip["pivot"] = [float(source_clip["pivot"][0]) + pad_x, float(source_clip["pivot"][1]) + pad_y]
        clip["cell"] = [new_w, new_h]
        # The source folder documents that Aseprite frames preserve the old
        # atlas slots. Its final frame duration is a trailing cel duration,
        # not extra clip time; use the source timeline verbatim.
        clip["times"] = source_clip["times"]
        clip["duration"] = source_clip["duration"]
        if "protected" in source_clip:
            clip["protected"] = source_clip["protected"]
        clip["art"] = "user_edited_pre_painted_vfx"
        clip["source_aseprite"] = ase_path.name
        clip.pop("source_strip", None)
        # Always export each source under its own filename before the runtime
        # facing correction below; rerunning the importer must be idempotent.
        clip["pages"] = [name + "_00.png"]
        columns = int(clip["columns"])
        page = Image.new("RGBA", (new_w * columns, new_h * math.ceil(len(frames) / columns)), (0, 0, 0, 0))
        for index, frame in enumerate(frames):
            page.alpha_composite(frame, ((index % columns) * new_w, (index // columns) * new_h))
        page.save(GAME_ASSETS / clip["pages"][0], optimize=True)
        total_frames += len(frames)
        print(f"{name}: {len(frames)} frames, {new_w}x{new_h}, source duration {clip['duration']:.3f}s, pivot {clip['pivot']}")

    # The artist's first lunge-cut files are labelled in the opposite facing.
    # Swap their artwork and canvas pivots together, keeping the motion's hilt
    # anchors and timing attached to the intended gameplay direction.
    left = manifest["clips"]["lunge_combo/cut_1_left"]
    right = manifest["clips"]["lunge_combo/cut_1_right"]
    for field in ("pages", "pivot", "source_aseprite"):
        left[field], right[field] = right[field], left[field]

    manifest["art_pipeline"] = "aseprite_manual_edit/pre_painted_compact_109"
    (GAME_ASSETS / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Imported {len(manifest['clips'])} clips, {total_frames} frames from Aseprite.")
    subprocess.run(
        [sys.executable, str(Path(__file__).with_name("compile_master_heavy_skills_library.py"))],
        check=True,
    )


if __name__ == "__main__":
    main()
