"""Pack the twins' shared painted-motion library and reviewed spine guides.

These are artwork guides, not inferred physical bones. Key poses were read from
the original 256-pixel cells; intermediate guides are interpolated, then pulled
onto the opaque blue body locally. Original pixels and black/white alpha remain
unchanged. --review writes every frame with its five guide points for inspection.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "homeing-star-temp-assert/PendingArt/character/双子"
DEST = ROOT / "homeing-star-game/assets/bosses/twin_fish/body"
CELL, COLUMNS = 256, 8
STANDARD = [(64,122),(88,131),(117,139),(148,134),(188,139)]
SOURCES = [
    ("low_curl", "低头回旋", "image-1792208184734-8e7vfbne8xp.png"),
    ("fin_sweep", "展鳍扫摆", "image-1792209131521-t8cjz68p8vd.png"),
    ("rise_dive", "仰头压潜", "image-1792209328987-7260hexa2su.png"),
    ("double_curl", "连续两次回旋", "image-1792209421976-vk471fv3h4.png"),
    ("coil_probe", "蜷身蓄势前探", "image-1792209609280-pdzi3qau20d.png"),
    ("high_curl", "抬头回旋", "image-1792209705421-c70dagysy8.png"),
    ("tail_sway", "水平摆尾", "image-1792399997238-2510rku6g1r.png"),
]

# One-based source frames. Same anatomical order in every pose and color:
# skull centre, anterior trunk, posterior trunk, tail root, main tail axis.
# These guides deliberately follow the body tube, not its enclosing box.
GUIDES = {
 "low_curl": {
  1: STANDARD, 5:[(64,125),(82,126),(112,145),(137,153),(183,161)],
  9:[(68,138),(61,115),(77,92),(103,94),(138,119)],
  13:[(108,143),(85,146),(62,132),(49,109),(66,82)],
  17:[(128,119),(118,145),(99,162),(74,169),(48,154)],
  21:[(112,121),(135,135),(151,155),(150,179),(130,199)],
  25:[(84,126),(113,127),(142,124),(171,130),(180,168)],
  29:[(67,124),(93,130),(123,135),(153,123),(181,126)],32:STANDARD,
 },
 "fin_sweep": {
  1:STANDARD,5:STANDARD,
  9:[(67,122),(96,116),(124,108),(145,122),(160,157)],
  13:[(64,122),(96,122),(128,120),(150,104),(176,121)],
  15:[(64,122),(88,117),(112,135),(119,162),(145,178)],
  16:[(64,122),(92,115),(122,104),(142,130),(134,161)],
  17:[(66,120),(95,120),(125,111),(151,97),(175,107)],
  18:[(64,122),(94,123),(124,121),(146,106),(148,80)],
  19:[(80,122),(105,126),(132,129),(153,126),(167,99)],
  21:[(87,119),(111,121),(140,130),(168,137),(198,126)],
  25:[(84,117),(113,116),(145,115),(168,126),(197,155)],
  29:[(67,120),(94,123),(124,128),(151,124),(187,127)],32:STANDARD,
 },
 "rise_dive": {
  1:STANDARD,
  5:[(78,107),(85,128),(106,147),(132,150),(170,133)],
  9:[(82,96),(90,122),(93,150),(112,166),(155,159)],
  13:[(78,96),(101,84),(122,98),(121,128),(125,159)],
  17:[(84,114),(96,100),(111,81),(135,81),(159,104)],
  21:[(78,150),(106,146),(129,127),(137,101),(126,73)],
  25:[(78,133),(105,139),(119,157),(146,170),(182,157)],
  29:[(65,125),(92,126),(122,122),(151,126),(175,153)],32:STANDARD,
 },
 "double_curl": {
  1:STANDARD,
  5:[(68,125),(91,130),(111,148),(139,156),(181,145)],
  7:[(75,136),(75,111),(99,102),(125,119),(155,153)],
  9:[(122,150),(98,155),(79,143),(73,115),(95,93)],
  13:[(124,105),(129,131),(119,152),(97,165),(67,162)],
  17:[(87,140),(114,119),(140,105),(168,106),(185,130)],
  21:[(139,149),(112,155),(82,145),(65,122),(78,81)],
  25:[(117,111),(129,134),(122,157),(102,174),(66,172)],
  29:[(68,119),(93,126),(124,135),(151,138),(165,165)],32:STANDARD,
 },
 "coil_probe": {
  1:STANDARD,
  5:[(69,115),(95,128),(117,144),(146,142),(177,126)],
  9:[(78,117),(98,106),(113,116),(109,143),(116,169)],
  12:[(81,118),(97,101),(113,111),(102,139),(107,173)],
  13:[(82,119),(105,102),(130,109),(134,137),(116,161)],
  17:[(67,126),(96,122),(124,115),(146,93),(174,86)],
  21:[(69,112),(94,121),(117,138),(143,145),(177,124)],
  25:[(65,120),(94,122),(124,123),(151,139),(180,155)],
  29:[(66,120),(94,123),(123,129),(151,137),(179,155)],32:STANDARD,
 },
 "high_curl": {
  1:STANDARD,
  5:[(77,79),(82,96),(88,124),(107,148),(142,161)],
  6:[(105,58),(93,76),(79,99),(80,128),(101,156)],
  7:[(114,53),(97,70),(73,88),(69,117),(86,148)],
  8:[(126,60),(104,65),(83,78),(64,97),(53,130)],
  9:[(129,64),(106,68),(82,83),(65,99),(50,129)],
  10:[(139,83),(115,77),(92,76),(73,79),(57,105)],
  11:[(141,98),(123,89),(109,73),(86,71),(61,100)],
  12:[(124,117),(123,98),(116,78),(94,70),(66,93)],
  13:[(120,134),(133,113),(131,84),(112,70),(84,78)],
  17:[(88,144),(111,147),(132,137),(143,115),(130,85)],
  21:[(67,128),(95,137),(127,134),(147,115),(144,86)],
  25:[(64,122),(94,132),(125,139),(154,132),(185,132)],
  29:STANDARD,32:STANDARD,
 },
 "tail_sway": {
  1:STANDARD,
  5:[(64,122),(88,122),(115,135),(140,149),(180,152)],
  9:[(66,124),(94,113),(122,113),(143,134),(166,153)],
  13:[(67,124),(94,124),(121,119),(150,115),(165,145)],
  17:[(64,122),(92,121),(122,119),(153,127),(189,127)],
  21:[(64,122),(91,118),(116,126),(143,145),(183,144)],
  25:[(64,122),(91,115),(119,123),(140,143),(172,154)],
  29:STANDARD,32:STANDARD,
 },
}

LOW_HEADS = [
 (64,122,180),(64,122,180),(64,123,180),(64,124,176),
 (64,125,173),(63,128,165),(62,134,145),(65,137,120),
 (68,138,85),(71,145,45),(93,148,10),(101,148,0),
 (108,143,-5),(119,135,-30),(126,129,-50),(124,123,-75),
 (128,119,-105),(133,112,-130),(125,117,-150),(117,122,-165),
 (112,121,-175),(101,123,-180),(99,123,-180),(92,126,-180),
 (84,126,-180),(80,126,-180),(74,124,-180),(69,122,-180),
 (67,124,-180),(66,122,-180),(64,122,-180),(64,122,-180),
]
HIGH_HEADS = [
 (64,122,180),(64,122,180),(65,104,210),(68,94,230),
 (77,79,255),(105,58,290),(114,53,310),(126,60,330),
 (129,64,355),(139,83,375),(141,98,400),(124,117,450),
 (120,134,475),(117,140,490),(110,143,510),(107,146,525),
 (88,144,540),(85,141,540),(72,136,540),(70,135,540),
 (67,128,540),(64,130,540),(65,127,540),(64,124,540),
 (64,122,540),(64,122,540),(64,122,540),(64,122,540),
 (64,122,540),(64,122,540),(64,122,540),(64,122,540),
]


def cell(sheet: Image.Image, index: int, columns: int = 6) -> Image.Image:
    x, y = index % columns * CELL, index // columns * CELL
    return sheet.crop((x, y, x + CELL, y + CELL))


def interpolate_guides(name: str, count: int) -> np.ndarray:
    keys = GUIDES[name]
    times = sorted(keys)
    values = np.array([keys[t] for t in times], dtype=float)
    result = np.empty((count, 5, 2), dtype=float)
    for joint in range(5):
        for axis in range(2):
            result[:, joint, axis] = np.interp(np.arange(1, count + 1), times, values[:, joint, axis])
    if name in ("low_curl", "high_curl"):
        result[:, 0, :] = np.array(LOW_HEADS if name == "low_curl" else HIGH_HEADS)[:, :2]
    return result


def body_thickness(image: Image.Image) -> np.ndarray:
    a = np.asarray(image)
    # Exclude transparent antialias and thin dark outlines from the body ridge.
    mask = (a[:, :, 3] > 160) & (a[:, :, 2] > 56) & (a[:, :, 1] > 25)
    mask = np.asarray(Image.fromarray(mask).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3)))
    distances = np.zeros(mask.shape, dtype=np.float32)
    inside = mask.copy()
    for _ in range(20):
        if not inside.any():
            break
        distances += inside
        pad = np.pad(inside, 1)
        inside = pad[1:-1, 1:-1] & pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]
    return distances


def refine(image: Image.Image, guides: np.ndarray) -> tuple[list[list[float]], float]:
    thickness = body_thickness(image)
    alpha = np.asarray(image)[:, :, 3]
    result = []
    supported = 0
    for joint, guide in enumerate(guides):
        x, y = guide
        # Keep the reviewed head anchor; refining it onto the thick neck would
        # move the visible skull and destroy the source's direction track.
        radius = 0 if joint == 0 else (8 if joint < 4 else 10)
        left, top = max(0, round(x) - radius), max(0, round(y) - radius)
        right, bottom = min(CELL, round(x) + radius + 1), min(CELL, round(y) + radius + 1)
        yy, xx = np.mgrid[top:bottom, left:right]
        cost = thickness[top:bottom, left:right] * 1.1 - np.hypot(xx - x, yy - y) * 1.05
        cost[alpha[top:bottom, left:right] < 180] -= 30
        py, px = np.unravel_index(cost.argmax(), cost.shape)
        point = [float(left + px), float(top + py)]
        result.append(point)
        supported += int(alpha[int(point[1]), int(point[0])] >= 180)
    return result, supported / 5


def frame_headings(name: str, joints: list[list[list[float]]]) -> list[float]:
    if name == "low_curl":
        return [float(x[2]) for x in LOW_HEADS]
    if name == "high_curl":
        return [float(x[2]) for x in HIGH_HEADS]
    if name == "double_curl":
        # Two authored counter-clockwise turns; raw atan2 across sparse guides
        # would unwrap the first crossing backwards around the spine's overlap.
        values = {1:180,5:175,6:160,7:95,8:35,9:0,10:-10,11:-40,
                  12:-80,13:-115,14:-140,15:-170,16:-180,17:-200,
                  18:-225,19:-270,20:-315,21:-350,22:-375,23:-405,
                  24:-445,25:-475,26:-505,27:-530,28:-540,29:-540,32:-540}
        return np.interp(np.arange(1,33), list(values), list(values.values())).tolist()
    if name in ("fin_sweep", "tail_sway", "coil_probe", "rise_dive"):
        # Skull/nose direction read separately from the curved neck. A line
        # from skull to trunk is not a reliable forward axis on these poses.
        tracks = {
            "fin_sweep": {1:180,5:180,9:170,13:180,15:185,16:185,17:175,21:180,25:180,29:180,32:180},
            "tail_sway": {1:180,5:175,9:155,13:175,17:180,21:170,25:155,29:180,32:180},
            "coil_probe": {1:180,5:190,9:150,13:150,17:180,21:190,25:180,29:180,32:180},
            "rise_dive": {1:180,5:240,9:260,13:150,17:100,21:170,25:180,29:180,32:180},
        }
        values = tracks[name]
        return np.interp(np.arange(1,33), list(values), list(values.values())).tolist()
    # For non-curl clips use the reviewed head-to-trunk guides, not noisy
    # per-pixel refinement, then unwrap to preserve authored turn direction.
    guides = interpolate_guides(name, len(joints)) if name != "swim" else np.repeat(np.array(STANDARD)[None, ...], len(joints), axis=0)
    direction = guides[:, 0] - guides[:, 1]
    angles = np.unwrap(np.arctan2(direction[:, 1], direction[:, 0]))
    # Horizontal source starts at a leftward pose. Remove the resting neck
    # slope while preserving all relative changes measured in the other poses.
    return np.round(np.degrees(angles - angles[0]) + 180.0, 3).tolist()


def write_review(folder: Path, clips: dict, frames: list, black_frames: list) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    for name, clip in clips.items():
        count, first = clip["count"], clip["first"]
        sheet = Image.new("RGB", (CELL * 8, ((count + 7) // 8) * (CELL + 24)), (92, 103, 108))
        draw = ImageDraw.Draw(sheet)
        for i in range(count):
            x, y = i % 8 * CELL, i // 8 * (CELL + 24) + 24
            image = black_frames[first + i]
            sheet.paste(image, (x, y), image)
            points = [(x + p[0], y + p[1]) for p in frames[first + i]["joints"]]
            draw.line(points, fill=(255, 197, 59), width=2)
            for j, (px, py) in enumerate(points):
                color = (255, 104, 114) if j == 0 else (107, 255, 166)
                draw.ellipse((px - 3, py - 3, px + 3, py + 3), fill=color)
                draw.text((px + 4, py - 7), str(j), fill=(255,255,255))
            draw.text((x + 5, y - 19), f"{name} F{i + 1:02} / {frames[first+i]['heading_deg']:.0f}deg", fill=(255,255,255))
        sheet.save(folder / f"{name}_bones.png")


def build(review: Path | None) -> None:
    packed = {"black": [], "white": []}
    clips, frames = {}, []
    for name, label, source in [("swim", "原生横游", "native_walk")] + SOURCES:
        native = name == "swim"
        count = 16 if native else 32
        first = len(frames)
        sources = {
            color: Image.open(DEST / f"twin_{color}_walk.png" if native else ART / folder / source).convert("RGBA")
            for color, folder in (("black", "黑鱼"), ("white", "白鱼"))
        }
        guides = np.repeat(np.array(STANDARD, dtype=float)[None, ...], count, axis=0) if native else interpolate_guides(name, count)
        clip_frames = []
        for i in range(count):
            pair = {color: cell(sheet, i, 4 if native else 6) for color, sheet in sources.items()}
            assert np.array_equal(np.asarray(pair["black"])[:, :, 3], np.asarray(pair["white"])[:, :, 3]), (name, i, "alpha mismatch")
            for color in packed:
                packed[color].append(pair[color])
            joints, confidence = refine(pair["black"], guides[i])
            row = {"joints": joints, "confidence": confidence, "source_frame": i,
                   "rig_basis": "reviewed_keypose" if native or i + 1 in GUIDES[name] else "interpolated_guide_pixel_refined"}
            clip_frames.append(row)
        headings = frame_headings(name, [row["joints"] for row in clip_frames])
        for row, heading in zip(clip_frames, headings):
            row["heading_deg"] = heading
        frames.extend(clip_frames)
        clips[name] = {"first": first, "count": count, "duration": 1.6 if native else 3.2,
                       "loop": name in ("swim", "tail_sway"), "label": label,
                       "source": source, "heading_change": headings[-1] - headings[0]}
    assert len(frames) == 240 and all(len(f["joints"]) == 5 for f in frames)
    for color, images in packed.items():
        atlas = Image.new("RGBA", (CELL * COLUMNS, ((len(images) + COLUMNS - 1) // COLUMNS) * CELL))
        for index, im in enumerate(images):
            atlas.paste(im, (index % COLUMNS * CELL, index // COLUMNS * CELL))
        atlas.save(DEST / f"twin_{color}_motion_{CELL}x{CELL}_{len(images)}f.png")
    data = {"canvas": [CELL, CELL], "columns": COLUMNS, "joint_names": ["head", "front_body", "rear_body", "tail_root", "tail_axis"],
            "rig_method": "shared reviewed keypose guides, local body-pixel refinement; not automatic anatomical reconstruction",
            "confidence_meaning": "fraction of the five guide points supported by alpha >= 180; not an anatomical accuracy probability",
            "clips": clips, "frames": frames}
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    (DEST / "twin_fish_motion.tres").write_text('[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/animation = ' + json.dumps(payload, ensure_ascii=False) + '\n', encoding="utf-8")
    if review:
        write_review(review, clips, frames, packed["black"])
        (review / "motion.json").write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Packed {len(frames)} shared poses, {len(clips)} clips; supported joints: {sum(f['confidence'] for f in frames)/len(frames):.3f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", type=Path)
    build(parser.parse_args().review)
