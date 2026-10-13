"""Package transparent native Godot captures into editable Aseprite art handoffs.
File layout: https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md
Uses compressed RGBA cels, linked reference cels, frame durations, tags and pivot.
"""
from pathlib import Path
import argparse
import json
import struct
import zlib
from PIL import Image, ImageDraw, ImageFont

PACK = struct.pack
NAMES = {
    "light_stomp": "01_轻跺脚",
    "heavy_stomp": "02_人立践踏",
    "mist_combo": "03_雾阶段连击",
    "charge_uppercut": "04_冲刺上挑",
    "uppercut_only": "05_上挑单独",
    "mist_ultimate": "06_雾阶段大招",
    "vine_cage": "07_藤蔓牢笼",
}
LAYERS = [
    ("定位线_隐藏", None, False, False),
    ("概念_后景", "back", True, False),
    ("绘制_后景", None, True, True),
    ("动作参考_锁定", "body", True, False),
    ("概念_前景", "front", True, False),
    ("预警参考_可隐藏", "warning", True, False),
    ("绘制_前景", None, True, True),
]


def string(value):
    data = value.encode("utf-8")
    return PACK("<H", len(data)) + data


def chunk(kind, data):
    return PACK("<IH", len(data) + 6, kind) + data


def user_data(text):
    return chunk(0x2020, PACK("<I", 1) + string(text))


def tags_for(frames):
    tags = [{"name": "全动作", "from": 0, "to": len(frames) - 1}]
    start = 0
    for i in range(1, len(frames) + 1):
        if i == len(frames) or frames[i]["stage"] != frames[start]["stage"]:
            tags.append({"name": f"{len(tags):02d}_{frames[start]['stage']}", "from": start, "to": i - 1})
            start = i
    return tags


def write_aseprite(path, frames, raw_dir, canvas, anchor):
    width, height = canvas
    tags = tags_for(frames)
    initial = []
    for name, source, visible, editable in LAYERS:
        flags = int(visible) | (2 if editable else 0)
        initial.append(chunk(0x2004, PACK("<6HB3x", flags, 0, 0, 0, 0, 0, 255) + string(name)))
        purpose = "可自由画特效；空白帧互相独立。" if editable else "参考层可隐藏。动作与特效均以同一脚底原点定位。"
        initial.append(user_data(purpose))
    tag_data = PACK("<H8x", len(tags))
    for tag in tags:
        # Bytes 5-12 are reserved in 1.2; newer versions use two for repeat count.
        tag_data += PACK("<HHB8x3BB", tag["from"], tag["to"], 0, 130, 170, 110, 0) + string(tag["name"])
    initial.append(chunk(0x2018, tag_data))
    initial.append(chunk(0x2022, PACK("<III", 1, 2, 0) + string("boss_origin") + PACK("<IiiIIii", 0, 0, 0, width, height, *map(int, anchor))))
    initial.append(chunk(0x2007, PACK("<HHI8x", 1, 0, 0)))
    guide = Image.new("RGBA", canvas)
    draw = ImageDraw.Draw(guide)
    draw.line((16, anchor[1], width - 16, anchor[1]), fill=(95, 145, 173, 180))
    draw.line((anchor[0] - 7, anchor[1], anchor[0] + 7, anchor[1]), fill=(245, 192, 78, 255), width=2)
    draw.line((anchor[0], anchor[1] - 8, anchor[0], anchor[1] + 8), fill=(245, 192, 78, 255), width=2)
    cache = {}
    blocks = []
    for frame_index, frame in enumerate(frames):
        chunks = list(initial) if frame_index == 0 else []
        for layer_index, (name, source, visible, editable) in enumerate(LAYERS):
            if source:
                image = Image.open(raw_dir / f"{frame['index']:04d}_{source}.png").convert("RGBA")
                assert image.size == tuple(canvas), (path, image.size)
            elif layer_index == 0:
                image = guide
            else:
                image = Image.new("RGBA", (1, 1))
            bbox = image.getbbox()
            if bbox:
                x, y = bbox[:2]
                cropped = image.crop(bbox)
            else:
                x = y = 0
                cropped = Image.new("RGBA", (1, 1))
            raw = cropped.tobytes()
            key = (layer_index, x, y, cropped.size, raw)
            # Drawing layers never share linked cels, so painting one frame cannot
            # inadvertently edit every blank drawing frame in the file.
            if key in cache and not editable:
                cel = PACK("<HhhBHh5xH", layer_index, x, y, 255, 1, 0, cache[key])
            else:
                cel = PACK("<HhhBHh5xHH", layer_index, x, y, 255, 2, 0, *cropped.size) + zlib.compress(raw, 6)
                if not editable:
                    cache[key] = frame_index
            chunks.append(chunk(0x2005, cel))
        payload = b"".join(chunks)
        blocks.append(PACK("<IHHH2xI", len(payload) + 16, 0xF1FA, len(chunks), frame["duration_ms"], len(chunks)) + payload)
    header = bytearray(128)
    PACK_INTO = struct.pack_into
    PACK_INTO("<I5HIH", header, 0, 128 + sum(map(len, blocks)), 0xA5E0, len(frames), width, height, 32, 1, 50)
    header[34:36] = bytes((1, 1))
    PACK_INTO("<HH", header, 40, 16, 16)
    path.write_bytes(bytes(header) + b"".join(blocks))
    return tags


def composite(raw_dir, frame, canvas):
    result = Image.new("RGBA", canvas)
    for layer in ["back", "body", "front", "warning"]:
        result = Image.alpha_composite(result, Image.open(raw_dir / f"{frame['index']:04d}_{layer}.png").convert("RGBA"))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    out = args.output
    manifest = json.loads((out / "capture_manifest.json").read_text(encoding="utf-8"))
    clips = manifest["clips"]
    charge = next(c for c in clips if c["id"] == "charge_uppercut")
    start = next(i for i, f in enumerate(charge["frames"]) if f["state"] == "CHARGE" and f["segment"] >= 1)
    upper = {"id": "uppercut_only", "folder": charge["folder"], "frames": charge["frames"][start:]}
    clips.insert(4, upper)
    (out / "预览").mkdir(exist_ok=True)
    notes = []
    overview = Image.new("RGB", (512 * 3, 310 * 3), (32, 36, 39))
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18)
    text = ImageDraw.Draw(overview)
    for i, clip in enumerate(clips):
        name = NAMES[clip["id"]]
        raw_dir = Path(clip["folder"])
        tags = write_aseprite(out / (name + ".aseprite"), clip["frames"], raw_dir, manifest["canvas"], manifest["anchor"])
        notes.append({"file": name + ".aseprite", "frame_count": len(clip["frames"]), "duration_ms": sum(f["duration_ms"] for f in clip["frames"]), "tags": tags, "frames": clip["frames"]})
        preview = []
        # A static neutral background is only for GIF preview, not in the .aseprite.
        for frame in clip["frames"]:
            bg = Image.new("RGBA", manifest["canvas"], (32, 36, 39, 255))
            bg.alpha_composite(composite(raw_dir, frame, manifest["canvas"]))
            preview.append(bg.convert("RGB"))
        preview[0].save(out / "预览" / (name + ".gif"), save_all=True, append_images=preview[1:], duration=[f["duration_ms"] for f in clip["frames"]], loop=0, disposal=2)
        if clip["id"] == "vine_cage":
            chosen = next(j for j, f in enumerate(clip["frames"]) if f["snare_growth"] == 1)
        elif clip["id"] in ["charge_uppercut", "uppercut_only"]:
            chosen = next(j for j, f in enumerate(clip["frames"]) if f["stage"] == "上挑爆发")
        else:
            chosen = next((j + 2 for j, f in enumerate(clip["frames"]) if f["attack"]), min(12, len(preview)-1))
        chosen = min(chosen, len(preview) - 1)
        thumb = preview[chosen].resize((384, 288), Image.Resampling.NEAREST)
        x, y = i % 3 * 512 + 64, i // 3 * 310
        overview.paste(thumb, (x, y + 20))
        text.text((x, y + 3), name, font=font, fill=(230, 232, 234))
        print(name, len(clip["frames"]), "frames", (out / (name + ".aseprite")).stat().st_size)
    overview.save(out / "预览" / "总览.png")
    (out / "时间轴.json").write_text(json.dumps({"canvas":manifest["canvas"], "anchor":manifest["anchor"], "layers": [l[0] for l in LAYERS], "clips": notes}, ensure_ascii=False, indent=2), encoding="utf-8")
    (out / "开始画特效.md").write_text("""# 鹿 BOSS 特效绘制工程

直接打开本目录的 `.aseprite` 文件。已按游戏当前的动作节奏对齐，不必自己拼动作。

- 在 `绘制_前景`、`绘制_后景` 两层画正式特效。它们的空白帧独立，画一帧不会修改其他帧。
- `概念_前景`、`概念_后景` 是程序特效截图，只用来看走向、范围和爆发节奏；可以随时隐藏。
- `动作参考_锁定` 带鹿的真实动作，不需要重画。`预警参考_可隐藏` 单独放置红/金预警。
- `定位线_隐藏` 默认关闭，打开可以看脚底原点和地面线。前后景分别在鹿前、鹿后。
- 时间轴标签标明蓄势、冲刺、上挑、重踩，以及牢笼出土、合拢、保持、退回地下。

## 文件

01 轻跺脚；02 人立践踏；03 雾阶段快→慢连击；04 完整冲刺上挑；05 单独上挑；06 雾阶段完整大招；07 藤蔓牢笼破解及失衡动作。

04 和 05 的上挑是同一段，可以主要画 05；03 的跺脚也复用 01/02 的特效，不用重复设计。
06 包含目前已实现的鹿鸣起手、四轮金色预警/冲撞残影、最后重踩。环境雾是独立的全屏 shader，未混进角色特效画布。
07 先出土攀升再顶部合拢，牢笼保持到 4.5 秒失衡结束，随后退回地下。保持段可以复用少量帧。

## 尺寸与交付

- 统一透明画布 **512×384**，脚底原点 **(256,332)**；Aseprite 的 `boss_origin` 切片带这个 pivot。
- 保留原动作的 256×256 像素尺度。1 个画布像素对应游戏 1.4 个世界单位；移动的动作以鹿为中心跟随，世界位移在 JSON 里。
- 参考采样 **20 FPS，每帧 50 ms**。原动作和特效来自 60 Hz 的真实逻辑，不是每帧都必须重画；可以重复或删减绘制帧并调整时长。
- `预览/` 的 GIF 方便先看节奏；深色背景只用于预览，工程内仍透明。
- 画好后把 `.aseprite` 给我。默认只导出你的两个绘制层；动作、概念、预警与定位线不会进入正式特效。
- 正式形状、覆盖范围以你画的为准，程序判定随后配合调整。尽量保留画布与原点，便于替换。

`时间轴.json` 保存每个参考帧的动作名、原动作帧号（从 0 开始）、实际世界位置、方向、阶段与伤害段，便于后续接回游戏。

导出脚本放在测试仓库 `tools/export_deer_vfx_reference.gd` 和 `tools/package_deer_vfx_aseprite.py`。素材工程放在游戏仓库外，未增加 Gitee 游戏仓库体积。
Aseprite 文件结构按官方规范生成，并使用本机 Aseprite 批处理校验：https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md
""", encoding="utf-8")


if __name__ == "__main__":
    main()
