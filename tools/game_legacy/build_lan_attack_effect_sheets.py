from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "PendingArt/character/主角-岚/完全没改过的原稿/platformer character pack_v1"
OUTPUT = ROOT / "assets/sideview/effects/lan_attacks"


@dataclass(frozen=True)
class EffectSpec:
    source: Path
    layers: frozenset[str]
    output: Path
    frame_count: int


SPECS = (
    EffectSpec(
        SOURCE / "atk/3x atk/3x atk.aseprite",
        frozenset(("3x atk_fx01", "3x atk_fx02", "3x atk_fx03")),
        OUTPUT / "attack_3x/attack_3x_fx_222x94_30f.png",
        30,
    ),
    EffectSpec(
        SOURCE / "dodge atk/dodge atk 1x/dodge atk 1x.aseprite",
        frozenset(("fx01", "fx02")),
        OUTPUT / "dodge_attack_1x/dodge_attack_1x_fx_272x64_19f.png",
        19,
    ),
    EffectSpec(
        SOURCE / "dodge atk/dodge atk 2x/dodge atk 2x.aseprite",
        frozenset(("fx",)),
        OUTPUT / "dodge_attack_2x/dodge_attack_2x_fx_112x128_16f.png",
        16,
    ),
    EffectSpec(
        SOURCE / "jump attack/jump atk 1x/jump attack 1x.aseprite",
        frozenset(("fx",)),
        OUTPUT / "jump_attack_1x/jump_attack_1x_fx_144x72_9f.png",
        9,
    ),
    EffectSpec(
        SOURCE / "jump attack/jump atk 2x/jump atk 2x.aseprite",
        frozenset(("fx",)),
        OUTPUT / "jump_attack_2x/jump_attack_2x_fx_100x112_8f.png",
        8,
    ),
)


def parse_layers(path: Path, wanted: frozenset[str]) -> list[Image.Image]:
    data = path.read_bytes()
    frame_count = struct.unpack_from("<H", data, 6)[0]
    canvas = struct.unpack_from("<HH", data, 8)
    layers: list[str] = []
    frames = [Image.new("RGBA", canvas) for _ in range(frame_count)]
    linked_cels: dict[tuple[int, int], Image.Image] = {}
    position = 128

    for frame_index in range(frame_count):
        frame_bytes, _, old_chunks = struct.unpack_from("<IHH", data, position)
        new_chunks = struct.unpack_from("<I", data, position + 12)[0]
        chunk_position = position + 16
        for _ in range(new_chunks or old_chunks):
            chunk_size, chunk_type = struct.unpack_from("<IH", data, chunk_position)
            if chunk_type == 0x2004:
                name_length = struct.unpack_from("<H", data, chunk_position + 22)[0]
                name = data[chunk_position + 24:chunk_position + 24 + name_length].decode("utf-8")
                layers.append(name)
            elif chunk_type == 0x2005:
                layer_index, x, y = struct.unpack_from("<Hhh", data, chunk_position + 6)
                opacity = data[chunk_position + 12]
                cel_type = struct.unpack_from("<H", data, chunk_position + 13)[0]
                layer_name = layers[layer_index]
                cel: Image.Image | None = None
                if cel_type == 0:
                    width, height = struct.unpack_from("<HH", data, chunk_position + 22)
                    pixels = data[chunk_position + 26:chunk_position + 26 + width * height * 4]
                    cel = Image.frombytes("RGBA", (width, height), pixels)
                elif cel_type == 1:
                    linked_frame = struct.unpack_from("<H", data, chunk_position + 22)[0]
                    cel = linked_cels.get((linked_frame, layer_index))
                elif cel_type == 2:
                    width, height = struct.unpack_from("<HH", data, chunk_position + 22)
                    pixels = zlib.decompress(data[chunk_position + 26:chunk_position + chunk_size])
                    cel = Image.frombytes("RGBA", (width, height), pixels)
                if cel is not None:
                    linked_cels[(frame_index, layer_index)] = cel
                    if layer_name in wanted:
                        rendered = cel.copy()
                        if opacity != 255:
                            alpha = rendered.getchannel("A").point(lambda value: value * opacity // 255)
                            rendered.putalpha(alpha)
                        frames[frame_index].alpha_composite(rendered, (x, y))
            chunk_position += chunk_size
        position += frame_bytes
    return frames


def save_sheet(frames: list[Image.Image], path: Path) -> None:
    width, height = frames[0].size
    sheet = Image.new("RGBA", (width * len(frames), height))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (index * width, 0))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def main() -> None:
    for spec in SPECS:
        frames = parse_layers(spec.source, spec.layers)[:spec.frame_count]
        save_sheet(frames, spec.output)
        print(f"Built {spec.output.relative_to(ROOT)} ({len(frames)} frames)")


if __name__ == "__main__":
    main()
