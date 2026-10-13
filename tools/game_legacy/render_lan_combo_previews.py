from pathlib import Path
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tmp" / "art_previews" / "lan-combos"
BASE = ROOT / "PendingArt" / "character" / "主角-岚" / "palette-bases"

CANVAS = (300, 190)
SCALE = 3
GROUND_Y = 150
START_X = 205
BACKGROUND = (34, 31, 40, 255)
GROUND = (70, 63, 76, 255)


def read_frames(relative_path, cell, count):
    sheet = Image.open(BASE / relative_path).convert("RGBA")
    cols = sheet.width // cell[0]
    frames = []
    for index in range(count):
        x = (index % cols) * cell[0]
        y = (index // cols) * cell[1]
        frames.append(sheet.crop((x, y, x + cell[0], y + cell[1])))
    return frames


def foot_anchor(frame):
    alpha = frame.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        return frame.width // 2, frame.height - 1
    left, top, right, bottom = bounds
    bottom_y = bottom - 1
    candidates = []
    for y in range(max(top, bottom_y - 2), bottom):
        for x in range(left, right):
            if alpha.getpixel((x, y)) > 0:
                candidates.append(x)
    if not candidates:
        return (left + right) // 2, bottom_y
    candidates.sort()
    return candidates[len(candidates) // 2], bottom_y


def render_combo(name, actions):
    rendered = []
    durations = []
    world_x = START_X

    for label, frames, frame_range, duration in actions:
        selected = frames[frame_range[0] : frame_range[1]]
        if not selected:
            continue
        start_foot = foot_anchor(selected[0])
        last_foot = foot_anchor(selected[-1])

        for frame in selected:
            canvas = Image.new("RGBA", CANVAS, BACKGROUND)
            draw = ImageDraw.Draw(canvas)
            draw.rectangle((0, GROUND_Y + 1, CANVAS[0], CANVAS[1]), fill=GROUND)
            draw.line((0, GROUND_Y, CANVAS[0], GROUND_Y), fill=(145, 131, 150, 255), width=1)
            draw.text((8, 8), label, fill=(240, 231, 188, 255))

            x = round(world_x - start_foot[0])
            y = GROUND_Y - start_foot[1]
            canvas.alpha_composite(frame, (x, y))
            rendered.append(canvas.resize(
                (CANVAS[0] * SCALE, CANVAS[1] * SCALE),
                Image.Resampling.NEAREST,
            ))
            durations.append(duration)

        world_x += last_foot[0] - start_foot[0]

    # Give the final pose a readable hold without adding a fake blank frame.
    durations[-1] += 450
    output = OUT / name
    output.parent.mkdir(parents=True, exist_ok=True)
    rendered[0].save(
        output,
        save_all=True,
        append_images=rendered[1:],
        duration=durations,
        loop=0,
        disposal=2,
        optimize=False,
    )
    return output


attack_1 = read_frames(
    Path("atk/1x atk/sprite sheets/1x atk_char.png"), (160, 64), 17
)
attack_2_short = read_frames(
    Path("atk/2x atk/sprite sheets/2x atk_char(short).png"), (192, 64), 19
)
attack_2_1 = read_frames(
    Path("atk/2x-1 atk/sprite sheets/2x-1 atk_char.png"), (112, 59), 6
)
attack_2_2 = read_frames(
    Path("atk/2x-2 atk/sprite sheets/2x-2 atk_char.png"), (112, 59), 10
)
attack_3 = read_frames(
    Path("atk/3x atk/sprite sheets/3x atk_char.png"), (126, 62), 34
)
vertical = read_frames(
    Path("dodge atk/dodge atk 3x(vertical atk)/sprite sheets/dodge atk 3x_char.png"),
    (64, 128),
    36,
)


basic = render_combo(
    "lan-basic-3-hit-preview.gif",
    [
        ("1x", attack_1, (0, 12), 40),
        ("2x", attack_2_short, (0, 19), 40),
        ("3x", attack_3, (0, 34), 35),
    ],
)

five_hit = render_combo(
    "lan-official-5-hit-preview.gif",
    [
        ("1x", attack_1, (0, 12), 40),
        ("2x-1", attack_2_1, (0, 6), 40),
        ("2x-2", attack_2_2, (0, 10), 40),
        ("3x", attack_3, (0, 24), 35),
        ("Vertical", vertical, (0, 36), 40),
    ],
)

print(basic)
print(five_hit)
