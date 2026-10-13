from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "PendingArt/character/师傅/无毛边"
OUTPUT = ROOT / "assets/sideview/characters/master/boss/final"
@dataclass(frozen=True)
class Spec:
    source: Path
    output: Path
    frame_count: int
    output_frame_size: tuple[int, int]
    output_columns: int
    source_frame_size: tuple[int, int] | None = None
    scale: float = 0.75


SPECS = (
    Spec(SOURCE / "atak1.aseprite", OUTPUT / "attack_1_576x256_11f.png", 11, (576, 256), 4, scale=0.60),
    Spec(SOURCE / "atak2.aseprite", OUTPUT / "attack_2_576x256_19f.png", 19, (576, 256), 4, scale=0.60),
    Spec(SOURCE / "atak3.aseprite", OUTPUT / "attack_3_576x256_28f.png", 28, (576, 256), 4, scale=0.60),
    Spec(SOURCE / "sp-atak.aseprite", OUTPUT / "special_attack_576x256_18f.png", 18, (576, 256), 3),
    Spec(
        SOURCE / "待机/image-2/textures/image-2_spritesheet.png",
        OUTPUT / "idle_152x152_16f.png",
        16,
        (152, 152),
        4,
        (256, 256),
    ),
    Spec(
        SOURCE / "走路new/image-2/textures/image-2_spritesheet.png",
        OUTPUT / "walk_152x152_16f.png",
        16,
        (152, 152),
        4,
        source_frame_size=(256, 256),
    ),
)


def parse_flattened_aseprite(path: Path) -> list[Image.Image]:
    data = path.read_bytes()
    frame_count = struct.unpack_from("<H", data, 6)[0]
    canvas = struct.unpack_from("<HH", data, 8)
    frames = [Image.new("RGBA", canvas) for _ in range(frame_count)]
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
                cel: Image.Image | None = None
                if cel_type == 0:
                    width, height = struct.unpack_from("<HH", data, chunk_position + 22)
                    end = chunk_position + 26 + width * height * 4
                    cel = Image.frombytes("RGBA", (width, height), data[chunk_position + 26:end])
                elif cel_type == 1:
                    linked_frame = struct.unpack_from("<H", data, chunk_position + 22)[0]
                    cel = linked_cels.get((linked_frame, layer_index))
                elif cel_type == 2:
                    width, height = struct.unpack_from("<HH", data, chunk_position + 22)
                    pixels = zlib.decompress(data[chunk_position + 26:chunk_position + chunk_size])
                    cel = Image.frombytes("RGBA", (width, height), pixels)
                if cel is not None:
                    linked_cels[(frame_index, layer_index)] = cel
                    rendered = cel.copy()
                    if opacity != 255:
                        alpha = rendered.getchannel("A").point(lambda value: value * opacity // 255)
                        rendered.putalpha(alpha)
                    frames[frame_index].alpha_composite(rendered, (x, y))
            chunk_position += chunk_size
        position += frame_bytes
    return frames


def frames_from_sheet(path: Path, frame_size: tuple[int, int], count: int) -> list[Image.Image]:
    image = Image.open(path).convert("RGBA")
    columns = image.width // frame_size[0]
    return [
        image.crop((
            index % columns * frame_size[0],
            index // columns * frame_size[1],
            (index % columns + 1) * frame_size[0],
            (index // columns + 1) * frame_size[1],
        ))
        for index in range(count)
    ]


def scale_frame(source: Image.Image, scale: float) -> Image.Image:
    return source.resize(
        (round(source.width * scale), round(source.height * scale)),
        Image.Resampling.NEAREST,
    )


def calculate_shared_offset(scaled_seed: Image.Image, old_seed: Image.Image) -> tuple[int, int]:
    source_box = scaled_seed.getchannel("A").getbbox()
    old_box = old_seed.getchannel("A").getbbox()
    assert source_box is not None and old_box is not None, "Animation frames must not be blank"
    source_center_x = (source_box[0] + source_box[2]) * 0.5
    old_center_x = (old_box[0] + old_box[2]) * 0.5
    return (
        round(old_center_x - source_center_x),
        old_box[3] - source_box[3],
    )


def normalize_frame(
    scaled: Image.Image,
    output_size: tuple[int, int],
    shared_offset: tuple[int, int],
) -> Image.Image:
    output = Image.new("RGBA", output_size)
    output.alpha_composite(scaled, shared_offset)
    return output


def save_sheet(frames: list[Image.Image], path: Path, columns: int) -> None:
    frame_width, frame_height = frames[0].size
    rows = (len(frames) + columns - 1) // columns
    sheet = Image.new("RGBA", (frame_width * columns, frame_height * rows))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (index % columns * frame_width, index // columns * frame_height))
    sheet.save(path)


def main() -> None:
    for spec in SPECS:
        old_frames = frames_from_sheet(spec.output, spec.output_frame_size, spec.frame_count)
        if spec.source.suffix == ".aseprite":
            source_frames = parse_flattened_aseprite(spec.source)
        else:
            assert spec.source_frame_size is not None
            source_frames = frames_from_sheet(spec.source, spec.source_frame_size, spec.frame_count)
        assert len(source_frames) == spec.frame_count
        # One transform per animation is essential. Per-frame silhouette alignment
        # turns harmless changes to the sword, coat, or tail bounds into visible
        # one-pixel shaking and destroys the artist-authored canvas anchors.
        scaled_frames = [scale_frame(frame, spec.scale) for frame in source_frames]
        shared_offset = calculate_shared_offset(scaled_frames[0], old_frames[0])
        normalized = [
            normalize_frame(frame, spec.output_frame_size, shared_offset)
            for frame in scaled_frames
        ]
        save_sheet(normalized, spec.output, spec.output_columns)
        print(f"Built {spec.output.relative_to(ROOT)} ({spec.frame_count} nonblank frames)")


if __name__ == "__main__":
    main()
