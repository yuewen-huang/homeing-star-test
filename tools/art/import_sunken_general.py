"""Cut the two user-edited sheets and register the five combat clips at the feet."""

import argparse
import hashlib
import json
from pathlib import Path
import sys

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from aseprite_rgba_reader import layer_frame, read

ROOT = Path(__file__).resolve().parents[3]
STANCES = ROOT / "homeing-star-temp-assert/PendingArt/sunken_general/20261112/stance"
MANUAL = STANCES.parent / "manual"
DEST = ROOT / "homeing-star-game/assets/bosses/sunken_general/body"
FRAME_SIZE = (520, 350)
PIVOT = (260, 287)
COLUMNS = 4

# The user placed some atak1 blades beyond the nominal column lines.
SWEEP_ROWS = (
    (0, 331, 665, 989, 1660), (0, 300, 668, 1020, 1660),
    (0, 340, 690, 1050, 1660), (0, 386, 722, 1082, 1660), (0, 386),
)

# Source-cell coordinates. Each tuple is (body x, shaft butt x/y, blade tip x/y).
# The weapon track is for runtime VFX registration and uppercut sweep sampling.
MARKS = {
    "atak1": [
        (154,197,236,196,5), (166,229,213,192,16), (189,253,198,101,48),
        (203,270,174,67,139), (166,237,162,8,160), (216,269,157,82,157),
        (163,236,157,100,158), (177,214,157,123,157), (167,206,156,126,165),
        (175,156,129,252,173), (174,105,135,284,172), (151,84,132,279,176),
        (180,112,140,334,190), (144,55,160,281,151), (135,58,162,287,110),
        (111,152,236,163,13), (167,210,237,209,5),
    ],
    "atak2": [
        (124,217,70,6,120), (131,189,68,30,124), (130,202,54,61,121),
        (130,184,12,122,134), (142,114,25,223,142), (145,71,55,289,112),
        (154,95,78,283,77), (164,107,73,292,70), (206,146,74,319,73),
        (215,159,73,325,72), (225,165,55,349,54), (280,206,51,405,83),
        (277,214,40,410,91), (292,221,53,413,106), (302,217,53,405,100),
        (310,204,45,403,102),
    ],
    "uppercut": [
        (239,124,147,341,207), (234,151,149,338,229), (228,152,128,332,244),
        (219,258,120,190,282), (225,281,130,151,269), (222,300,128,129,256),
        (234,333,126,111,255), (239,327,123,118,250), (242,311,125,123,248),
        (226,275,118,198,284), (219,257,100,217,277), (229,270,94,253,282),
        (245,205,100,391,238), (290,265,124,423,205), (299,234,219,441,154),
        (307,233,218,430,130), (314,245,220,431,117), (323,250,221,439,118),
        (321,248,220,435,121), (317,236,227,462,126),
    ],
    "three_chops": [
        (235,160,184,368,263), (235,266,71,134,247), (254,308,55,159,200),
        (281,342,63,157,119), (267,351,110,148,94), (279,352,150,202,56),
        (280,342,209,255,49), (286,323,245,332,59), (310,252,194,409,70),
        (282,233,209,411,117), (262,200,209,403,209), (235,161,189,378,255),
        (235,198,187,142,267), (257,279,102,155,252), (291,302,80,151,223),
        (306,358,93,194,132), (303,384,111,183,101), (308,384,167,229,76),
        (308,364,185,259,54), (314,344,211,357,58), (324,280,222,416,88),
        (272,195,199,419,182), (254,180,186,365,259), (258,326,116,187,255),
        (292,321,93,207,256), (326,373,96,224,147), (318,407,109,203,95),
        (313,368,161,218,55), (323,386,207,280,38), (334,370,185,352,32),
        (343,307,219,443,87), (288,232,198,443,222), (259,185,184,386,252),
    ],
    "kindle": [
        (282,332,282,330,51), (282,335,271,326,46), (282,311,247,320,48),
        (282,292,241,312,46), (282,270,254,308,45), (282,257,248,263,48),
        (282,281,231,194,54), (282,283,239,175,59), (282,200,179,116,66),
        (282,172,175,63,58), (282,246,208,141,86), (282,294,259,200,59),
        (282,304,263,322,64), (282,319,276,337,55), (282,330,279,329,55),
        (282,332,282,330,51),
    ],
}


def cells(atlas, size, count):
    width, height = size
    for index in range(count):
        row, column = divmod(index, COLUMNS)
        x, y = column * width, row * height
        yield atlas.crop((x, y, x + width, y + height))


def read_manual(path):
    document = read(path)
    assert len(document["frames"]) == len(document["layers"]) == 1, path
    canvas, opacity = layer_frame(document, 0, 0)
    assert opacity == 1.0, path
    if path.stem == "atak1":
        assert canvas.size == (1660, 1220)
        for row, bounds in enumerate(SWEEP_ROWS):
            for left, right in zip(bounds, bounds[1:]):
                yield canvas.crop((left, row * 244, right, (row + 1) * 244))
    else:
        assert canvas.size == (1660, 704)
        yield from cells(canvas, (415, 176), 16)


def export_clip(name, frames, source):
    marks = MARKS[name]
    width, height = FRAME_SIZE
    atlas = Image.new("RGBA", (width * COLUMNS, height * ((len(marks) + 3) // 4)))
    weapons = []
    for index, (frame, mark) in enumerate(zip(frames, marks, strict=True)):
        left, top, right, sole = frame.getbbox()
        origin_x, butt_x, butt_y, tip_x, tip_y = mark
        dx, dy = PIVOT[0] - origin_x, PIVOT[1] - sole
        assert 0 < left + dx < right + dx < width, (name, index, frame.getbbox())
        assert 0 < top + dy < sole + dy < height, (name, index)
        row, column = divmod(index, COLUMNS)
        tile = Image.new("RGBA", FRAME_SIZE)
        tile.paste(frame.crop((left, top, right, sole)), (left + dx, top + dy))
        atlas.paste(tile, (column * width, row * height))
        weapons.append([[butt_x - origin_x, butt_y - sole], [tip_x - origin_x, tip_y - sole]])
    texture = f"{name}_{width}x{height}_{len(marks)}f.png"
    atlas.save(DEST / texture)
    print(name, len(marks), source.name)
    return {"texture": texture, "weapon": weapons, "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manual_dir", type=Path, nargs="?", default=MANUAL)
    args = parser.parse_args()
    DEST.mkdir(parents=True, exist_ok=True)
    manifest = {"clips": {}, "frame_size": FRAME_SIZE, "pivot": PIVOT, "columns": COLUMNS}
    for name in ("atak1", "atak2"):
        source = args.manual_dir / f"{name}.aseprite"
        manifest["clips"][name] = export_clip(name, read_manual(source), source)
    for name, rel in (
        ("uppercut", "low_stance_uppercut/turning/motion/turning_uppercut_520x350_20f.png"),
        ("three_chops", "triple_jump_slash/motion/triple_jump_slash_520x350_33f.png"),
        ("kindle", "front_guandao_stand/raise_and_return/motion/raise_and_return_520x350_16f.png"),
    ):
        source = STANCES / rel
        with Image.open(source) as atlas:
            manifest["clips"][name] = export_clip(name, cells(atlas.convert("RGBA"), FRAME_SIZE, len(MARKS[name])), source)
    (DEST / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    main()
