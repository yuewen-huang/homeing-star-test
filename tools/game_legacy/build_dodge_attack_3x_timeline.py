from __future__ import annotations

import struct
import zlib
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "PendingArt/character/主角-岚/完全没改过的原稿/platformer character pack_v1/dodge atk/dodge atk 3x(vertical atk)"
SHEETS = SOURCE / "sprite sheets"
OUTPUT = ROOT / "assets/sideview/characters/lan/attack/dodge_attack_3x_timeline"
PREVIEW = ROOT / "tmp/art_previews/dodge-attack-3x-timeline"
FRAME_SIZE = (203, 269)
GRID = (6, 7)
FRAME_COUNT = 37
ASE_CANVAS = (224, 288)
ASE_CROP = (12, 13, 215, 282)


def frames_from_sheet(path: Path, size: tuple[int, int], count: int) -> list[Image.Image]:
    image = Image.open(path).convert("RGBA")
    columns = image.width // size[0]
    return [
        image.crop(((index % columns) * size[0], (index // columns) * size[1],
                    (index % columns + 1) * size[0], (index // columns + 1) * size[1]))
        for index in range(count)
    ]


def save_sheet(frames: list[Image.Image], path: Path) -> None:
    sheet = Image.new("RGBA", (FRAME_SIZE[0] * GRID[0], FRAME_SIZE[1] * GRID[1]))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, ((index % GRID[0]) * FRAME_SIZE[0], (index // GRID[0]) * FRAME_SIZE[1]))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def parse_aseprite_layers(path: Path, wanted: set[str]) -> dict[str, list[Image.Image]]:
    data = path.read_bytes()
    frame_count = struct.unpack_from("<H", data, 6)[0]
    canvas_width, canvas_height = struct.unpack_from("<HH", data, 8)
    assert frame_count == FRAME_COUNT and (canvas_width, canvas_height) == ASE_CANVAS
    layers: list[str] = []
    output = {name: [Image.new("RGBA", ASE_CANVAS) for _ in range(FRAME_COUNT)] for name in wanted}
    position = 128
    for frame_index in range(frame_count):
        frame_bytes, _, old_chunks = struct.unpack_from("<IHH", data, position)
        new_chunks = struct.unpack_from("<I", data, position + 12)[0]
        chunk_position = position + 16
        for _ in range(new_chunks or old_chunks):
            chunk_size, chunk_type = struct.unpack_from("<IH", data, chunk_position)
            if chunk_type == 0x2004:
                name_length = struct.unpack_from("<H", data, chunk_position + 22)[0]
                layers.append(data[chunk_position + 24:chunk_position + 24 + name_length].decode("utf-8"))
            elif chunk_type == 0x2005:
                layer_index, x, y = struct.unpack_from("<Hhh", data, chunk_position + 6)
                opacity = data[chunk_position + 12]
                cel_type = struct.unpack_from("<H", data, chunk_position + 13)[0]
                layer_name = layers[layer_index]
                if layer_name in wanted and cel_type == 2:
                    width, height = struct.unpack_from("<HH", data, chunk_position + 22)
                    pixels = zlib.decompress(data[chunk_position + 26:chunk_position + chunk_size])
                    cel = Image.frombytes("RGBA", (width, height), pixels)
                    if opacity != 255:
                        alpha = cel.getchannel("A").point(lambda value: value * opacity // 255)
                        cel.putalpha(alpha)
                    output[layer_name][frame_index].alpha_composite(cel, (x, y))
            chunk_position += chunk_size
        position += frame_bytes
    return {name: [frame.crop(ASE_CROP) for frame in frames] for name, frames in output.items()}


def build_character_track(middle_path: Path, middle_size: tuple[int, int], middle_position: tuple[int, int]) -> list[Image.Image]:
    character = frames_from_sheet(
        ROOT / "assets/sideview/characters/lan/attack/dodge_attack_3x_palette_base.png",
        (64, 128), 34,
    )
    middle = frames_from_sheet(middle_path, middle_size, 3)
    timeline = [Image.new("RGBA", FRAME_SIZE) for _ in range(FRAME_COUNT)]
    mapping: dict[int, int] = {}
    mapping.update({timeline_index: timeline_index for timeline_index in range(1, 11)})
    mapping.update({timeline_index: timeline_index - 2 for timeline_index in range(13, 19)})
    mapping.update({timeline_index: timeline_index - 3 for timeline_index in range(22, 38)})
    for timeline_index, character_index in mapping.items():
        timeline[timeline_index - 1].alpha_composite(character[character_index - 1], (68, 79))
    for offset, frame in enumerate(middle):
        timeline[18 + offset].alpha_composite(frame, middle_position)
    return timeline


def render_preview(character: list[Image.Image], fx01: list[Image.Image], fx02: list[Image.Image], path: Path) -> None:
    merged = []
    for index in range(FRAME_COUNT):
        frame = Image.new("RGBA", FRAME_SIZE)
        frame.alpha_composite(fx02[index])
        frame.alpha_composite(fx01[index])
        frame.alpha_composite(character[index])
        merged.append(frame)
    save_sheet(merged, path)


def main() -> None:
    layers = parse_aseprite_layers(SOURCE / "dodge atk 3x.aseprite", {"fx_upper", "smoke"})
    character_z = build_character_track(SHEETS / "dodge atk 3x_fall loop.png", (138, 241), (31, 1))
    character_z1 = build_character_track(SHEETS / "dodge atk 3x_fall loop1.png", (68, 241), (66, 1))
    save_sheet(character_z, OUTPUT / "dodge_attack_3x_character_z_203x269_37f.png")
    save_sheet(character_z1, OUTPUT / "dodge_attack_3x_character_z1_203x269_37f.png")
    save_sheet(layers["fx_upper"], OUTPUT / "dodge_attack_3x_fx01_203x269_37f.png")
    save_sheet(layers["smoke"], OUTPUT / "dodge_attack_3x_fx02_203x269_37f.png")
    render_preview(character_z, layers["fx_upper"], layers["smoke"], PREVIEW / "dodge_attack_3x_z_preview_37f.png")
    render_preview(character_z1, layers["fx_upper"], layers["smoke"], PREVIEW / "dodge_attack_3x_z1_preview_37f.png")
    print("Built two character variants and two FX tracks at 37 frames each.")


if __name__ == "__main__":
    main()
