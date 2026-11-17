"""Pack the painted half-turns and entrance loops for the twin fish preview."""

import json
from pathlib import Path
from shutil import copyfile

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "homeing-star-temp-assert/PendingArt/character/双子"
DEST = ROOT / "homeing-star-game/assets/bosses/twin_fish/body"
LOW = "image-1792208184734-8e7vfbne8xp.png"
HIGH = "image-1792209705421-c70dagysy8.png"
CELL = 256
COLUMNS = 8

# Fish-head pivots measured in the original cells. The runtime supplies movement.
LOW_HEADS = {
    1: (64, 122), 2: (64, 122), 3: (64, 123), 4: (64, 124), 5: (64, 125),
    6: (63, 128), 7: (62, 134), 8: (65, 137), 9: (68, 138), 10: (71, 145),
    16: (124, 123), 17: (128, 119), 18: (133, 112), 19: (125, 117),
    20: (117, 122), 21: (112, 121), 22: (101, 123), 23: (99, 123),
    24: (92, 126), 25: (84, 126), 26: (80, 126), 27: (74, 124),
    28: (69, 122), 29: (67, 124), 30: (66, 122), 31: (64, 122), 32: (64, 122),
}
HIGH_HEADS = {
    1: (64, 122), 2: (64, 122), 3: (65, 104), 4: (68, 94), 5: (77, 79),
    13: (120, 134), 14: (117, 140), 15: (110, 143), 16: (107, 146),
    17: (88, 144), 18: (85, 141), 19: (72, 136), 20: (70, 135),
    21: (67, 128), 22: (64, 130), 23: (65, 127), 24: (64, 124),
    25: (64, 122), 26: (64, 122), 27: (64, 122), 28: (64, 122),
    29: (64, 122), 30: (64, 122), 31: (64, 122), 32: (64, 122),
}
CLIPS = {
    "up": (HIGH, HIGH_HEADS, range(2, 6), LOW, LOW_HEADS, range(17, 32)),
    "down": (LOW, LOW_HEADS, range(2, 11), HIGH, HIGH_HEADS, range(13, 32)),
}


def cell(sheet, frame, columns=6):
    row, column = divmod(frame - 1, columns)
    x, y = column * CELL, row * CELL
    return sheet.crop((x, y, x + CELL, y + CELL))


def pack_color(color, source_folder):
    source = {
        name: Image.open(SOURCE / source_folder / name).convert("RGBA") for name in (LOW, HIGH)
    }
    walk = cell(Image.open(DEST / f"twin_{color}_walk.png").convert("RGBA"), 1, 4)
    frames = []
    clips = {}
    for name, (start, start_heads, start_frames, end, end_heads, end_frames) in CLIPS.items():
        first = len(frames)
        frames.append((walk, (64, 122)))
        frames.extend((cell(source[start], i), start_heads[i]) for i in start_frames)
        join = len(frames) - first
        for i in end_frames:
            x, y = end_heads[i]
            frames.append((ImageOps.mirror(cell(source[end], i)), (CELL - x, y)))
        frames.append((ImageOps.mirror(walk), (192, 122)))
        clips[name] = {"first": first, "join": join, "count": len(frames) - first}

    rows = (len(frames) + COLUMNS - 1) // COLUMNS
    atlas = Image.new("RGBA", (CELL * COLUMNS, CELL * rows))
    for i, (frame, _) in enumerate(frames):
        row, column = divmod(i, COLUMNS)
        atlas.paste(frame, (column * CELL, row * CELL))
    atlas.save(DEST / f"twin_{color}_turns_{CELL}x{CELL}_{len(frames)}f.png")
    return {
        "columns": COLUMNS,
        "clips": clips,
        "anchors": [anchor for _, anchor in frames],
    }


if __name__ == "__main__":
    black = pack_color("black", "黑鱼")
    white = pack_color("white", "白鱼")
    assert black == white
    payload = json.dumps(black, separators=(",", ":"))
    (DEST / "twin_idle_turns.tres").write_text(
        '[gd_resource type="Resource" format=3]\n\n[resource]\n'
        + "metadata/animation = " + json.dumps(payload) + "\n",
        encoding="utf-8",
    )
    copyfile(SOURCE / "黑鱼" / LOW, DEST / "twin_black_arrival_roll_256x256_32f.png")
    copyfile(SOURCE / "白鱼" / HIGH, DEST / "twin_white_arrival_roll_256x256_32f.png")
    print(f"Packed {len(black['anchors'])} poses per color")
