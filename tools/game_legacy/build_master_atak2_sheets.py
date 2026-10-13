from __future__ import annotations

import struct
import zlib
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "PendingArt/character/师傅/最终成品/一阶段画风优化版/atak2.aseprite"
BODY_OUTPUT = ROOT / "assets/sideview/characters/master/boss/phase1_optimized_atak2_body_750x384_25f.png"
FX_OUTPUT = ROOT / "assets/sideview/effects/master_wind/phase1_optimized_atak2_fx_750x384_25f.png"
FRAME_SIZE = (750, 384)
FRAME_COUNT = 25
FRAME_COLUMNS = 5
RECOLORED_FX_FRAMES = range(15, 23)  # Aseprite frames 16-23.


def recolor_new_fx_to_original_wind(effect: Image.Image) -> Image.Image:
    # The replacement cels are cyan. Shift them to the original attack-2 ice-blue
    # palette while preserving their value contrast and exact alpha silhouette.
    alpha = effect.getchannel("A")
    hue, saturation, value = effect.convert("RGB").convert("HSV").split()
    hue = hue.point(lambda channel: (channel + 11) % 256)
    saturation = saturation.point(lambda channel: round(channel * 0.58))
    value = value.point(lambda channel: min(255, round(channel * 1.07)))
    recolored = Image.merge("HSV", (hue, saturation, value)).convert("RGB").convert("RGBA")
    recolored.putalpha(alpha)
    return recolored


def _cel_image(data: bytes, offset: int, size: int) -> Image.Image | None:
    cel_type = struct.unpack_from("<H", data, offset + 13)[0]
    if cel_type == 1:
        return None  # This source does not use linked cels.
    width, height = struct.unpack_from("<HH", data, offset + 22)
    if cel_type == 0:
        pixels = data[offset + 26 : offset + 26 + width * height * 4]
    elif cel_type == 2:
        pixels = zlib.decompress(data[offset + 26 : offset + size])
    else:
        return None
    return Image.frombytes("RGBA", (width, height), pixels)


def read_layers(path: Path) -> dict[int, list[Image.Image]]:
    data = path.read_bytes()
    frame_count = struct.unpack_from("<H", data, 6)[0]
    canvas_size = struct.unpack_from("<HH", data, 8)
    assert canvas_size == FRAME_SIZE, f"Unexpected Aseprite canvas: {canvas_size}"
    assert frame_count == FRAME_COUNT, f"Unexpected Aseprite frame count: {frame_count}"
    layers = {index: [Image.new("RGBA", FRAME_SIZE) for _ in range(frame_count)] for index in (0, 1, 2)}

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
                image = _cel_image(data, chunk_position, chunk_size)
                if layer_index in layers and image is not None:
                    if opacity != 255:
                        image.putalpha(image.getchannel("A").point(lambda alpha: alpha * opacity // 255))
                    layers[layer_index][frame_index].alpha_composite(image, (x, y))
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
    body_frames = layers[1]
    effect_frames = []
    for frame_index in range(FRAME_COUNT):
        effect = layers[0][frame_index].copy()
        effect.alpha_composite(layers[2][frame_index])
        if frame_index in RECOLORED_FX_FRAMES:
            effect = recolor_new_fx_to_original_wind(effect)
        effect_frames.append(effect)

    hit_frame_indices = (8, 9, 10, 15, 16, 17, 20, 21, 22)
    for frame_index in hit_frame_indices:
        bbox = effect_frames[frame_index].getchannel("A").getbbox()
        print(f"Aseprite frame {frame_index + 1}: effect bounds={bbox}")

    save_sheet(body_frames, BODY_OUTPUT)
    save_sheet(effect_frames, FX_OUTPUT)
    print(f"Built {BODY_OUTPUT.relative_to(ROOT)}")
    print(f"Built {FX_OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
