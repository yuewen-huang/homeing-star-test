"""Export phase-two master body and effect layers on the same frame grid."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "PendingArt/character/师傅/最终成品/二阶段"
BODY_OUTPUT = ROOT / "assets/sideview/characters/master/boss/phase2"
FX_OUTPUT = ROOT / "assets/sideview/effects/master_wind/phase2"
COLUMNS = 4

SPECS = (
    ("轻击/atak1.aseprite", "attack_1", (256, 256), 16),
    ("重击/atak2.aseprite", "attack_2", (300, 350), 32),
    ("特殊/sp-atak.aseprite", "special_attack", (380, 300), 24),
    ("冲刺/chongci.aseprite", "dash", (384, 384), 16),
    ("上挑/shangtiao.aseprite", "uppercut", (350, 350), 16),
)


def read_layers(path: Path, expected_size: tuple[int, int], expected_count: int) -> dict[int, list[Image.Image]]:
    data = path.read_bytes()
    frame_count = struct.unpack_from("<H", data, 6)[0]
    frame_size = struct.unpack_from("<HH", data, 8)
    assert frame_size == expected_size, f"Unexpected canvas in {path}: {frame_size}"
    assert frame_count == expected_count, f"Unexpected frame count in {path}: {frame_count}"

    layers = {
        index: [Image.new("RGBA", frame_size) for _ in range(frame_count)]
        for index in (0, 1)
    }
    linked_cels: dict[tuple[int, int], Image.Image] = {}
    position = 128
    for frame_index in range(frame_count):
        frame_bytes, _, old_chunks = struct.unpack_from("<IHH", data, position)
        new_chunks = struct.unpack_from("<I", data, position + 12)[0]
        chunk_position = position + 16
        for _ in range(new_chunks or old_chunks):
            chunk_size, chunk_type = struct.unpack_from("<IH", data, chunk_position)
            if chunk_type == 0x2005:
                layer_index, x, y = struct.unpack_from("<Hhh", data, chunk_position + 6)
                opacity = data[chunk_position + 12]
                cel_type = struct.unpack_from("<H", data, chunk_position + 13)[0]
                cel = None
                if cel_type in (0, 2):
                    width, height = struct.unpack_from("<HH", data, chunk_position + 22)
                    pixel_data = data[chunk_position + 26 : chunk_position + chunk_size]
                    if cel_type == 2:
                        pixel_data = zlib.decompress(pixel_data)
                    cel = Image.frombytes("RGBA", (width, height), pixel_data)
                elif cel_type == 1:
                    linked_frame = struct.unpack_from("<H", data, chunk_position + 22)[0]
                    cel = linked_cels[(linked_frame, layer_index)]
                if cel is not None:
                    linked_cels[(frame_index, layer_index)] = cel
                    if layer_index in layers:
                        rendered = cel.copy()
                        if opacity != 255:
                            rendered.putalpha(
                                rendered.getchannel("A").point(lambda alpha: alpha * opacity // 255)
                            )
                        layers[layer_index][frame_index].alpha_composite(rendered, (x, y))
            chunk_position += chunk_size
        position += frame_bytes
    assert any(frame.getchannel("A").getbbox() for frame in layers[0]), f"Missing body layer: {path}"
    assert any(frame.getchannel("A").getbbox() for frame in layers[1]), f"Missing FX layer: {path}"
    return layers


def save_sheet(frames: list[Image.Image], path: Path) -> None:
    frame_width, frame_height = frames[0].size
    rows = (len(frames) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (frame_width * COLUMNS, frame_height * rows))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(
            frame,
            ((index % COLUMNS) * frame_width, (index // COLUMNS) * frame_height),
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def main() -> None:
    for source_name, action_name, frame_size, frame_count in SPECS:
        layers = read_layers(SOURCE / source_name, frame_size, frame_count)
        suffix = f"{frame_size[0]}x{frame_size[1]}_{frame_count}f.png"
        save_sheet(layers[0], BODY_OUTPUT / f"{action_name}_{suffix}")
        save_sheet(layers[1], FX_OUTPUT / f"{action_name}_fx_{suffix}")


if __name__ == "__main__":
    main()
