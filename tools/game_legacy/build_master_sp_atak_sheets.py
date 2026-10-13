from __future__ import annotations

import struct
import zlib
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "PendingArt/character/师傅/最终成品/一阶段画风优化版/SP-ATAK.aseprite"
BODY_OUTPUT = ROOT / "assets/sideview/characters/master/boss/phase1_optimized_sp_atak_body_500x500_16f.png"
FX_OUTPUT = ROOT / "assets/sideview/effects/master_wind/phase1_optimized_sp_atak_fx_500x500_16f.png"
FRAME_SIZE = (500, 500)
FRAME_COUNT = 16
FRAME_COLUMNS = 4


def read_layers(path: Path) -> dict[int, list[Image.Image]]:
    data = path.read_bytes()
    frame_count = struct.unpack_from("<H", data, 6)[0]
    canvas_size = struct.unpack_from("<HH", data, 8)
    assert canvas_size == FRAME_SIZE, f"Unexpected Aseprite canvas: {canvas_size}"
    assert frame_count == FRAME_COUNT, f"Unexpected Aseprite frame count: {frame_count}"
    layers = {index: [Image.new("RGBA", FRAME_SIZE) for _ in range(frame_count)] for index in (0, 1)}

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
                if cel_type == 2 and layer_index in layers:
                    width, height = struct.unpack_from("<HH", data, chunk_position + 22)
                    pixels = zlib.decompress(data[chunk_position + 26 : chunk_position + chunk_size])
                    cel = Image.frombytes("RGBA", (width, height), pixels)
                    if opacity != 255:
                        cel.putalpha(cel.getchannel("A").point(lambda alpha: alpha * opacity // 255))
                    layers[layer_index][frame_index].alpha_composite(cel, (x, y))
            chunk_position += chunk_size
        position += frame_bytes
    return layers


def save_sheet(frames: list[Image.Image], path: Path) -> None:
    rows = (len(frames) + FRAME_COLUMNS - 1) // FRAME_COLUMNS
    sheet = Image.new("RGBA", (FRAME_SIZE[0] * FRAME_COLUMNS, FRAME_SIZE[1] * rows))
    for frame_index, frame in enumerate(frames):
        sheet.alpha_composite(
            frame,
            ((frame_index % FRAME_COLUMNS) * FRAME_SIZE[0], (frame_index // FRAME_COLUMNS) * FRAME_SIZE[1]),
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def main() -> None:
    layers = read_layers(SOURCE)
    save_sheet(layers[0], BODY_OUTPUT)
    save_sheet(layers[1], FX_OUTPUT)
    fx_frames = [index + 1 for index, frame in enumerate(layers[1]) if frame.getchannel("A").getbbox()]
    print(f"FX layer has pixels in Aseprite frames: {fx_frames}")
    for frame_index in (12, 13, 14):
        print(f"Aseprite frame {frame_index + 1} effect bounds={layers[1][frame_index].getchannel('A').getbbox()}")
    print(f"Built {BODY_OUTPUT.relative_to(ROOT)}")
    print(f"Built {FX_OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
