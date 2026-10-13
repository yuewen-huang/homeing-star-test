from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
LAN = ROOT / "assets/sideview/characters/lan"
OUTPUT = ROOT / "PendingArt/character/主角-岚/lan-ear-tail-audit.png"

ACTIONS = [
    ("idle", "idle.png", (46, 55), 10),
    ("walk", "walk.png", (45, 58), 24),
    ("run", "run/run.png", (65, 58), 20),
    ("jump", "jump/jump.png", (64, 80), 24),
    ("attack 1", "attack/ground_attack_1.png", (160, 64), 16),
    ("attack 2", "attack/ground_attack_2_palette_base.png", (192, 64), 25),
    ("attack 3", "attack/ground_attack_3_palette_base.png", (126, 62), 34),
    ("heavy 2-1", "attack/heavy_attack_2_1_palette_base.png", (112, 59), 6),
    ("heavy 2-2", "attack/heavy_attack_2_2_palette_base.png", (112, 59), 10),
    ("air attack 1", "attack/air_attack_1_palette_base.png", (82, 63), 9),
    ("air attack 2", "attack/air_attack_2_palette_base.png", (77, 75), 8),
    ("dodge attack 1", "attack/dodge_attack_1_palette_base.png", (87, 56), 19),
    ("dodge attack 2", "attack/dodge_attack_2_palette_base.png", (112, 128), 16),
    ("vertical", "attack/dodge_attack_3_palette_base.png", (64, 128), 34),
    ("back dodge", "dodge/back_dodge_palette_base.png", (96, 64), 24),
    ("crouch", "crouch/crouch_palette_base.png", (53, 50), 13),
    ("slide", "slide/slide_palette_base.png", (96, 64), 17),
    ("ultimate cast", "ultimate/ultimate_cast_47x64_18f.png", (47, 64), 18),
    ("wall jump", "wall/wall_jump_palette_base.png", (51, 58), 3),
    ("wall slide", "wall/wall_slide_palette_base.png", (44, 73), 3),
]


def sample_indices(count: int, amount: int = 6) -> list[int]:
    if count <= amount:
        return list(range(count))
    return sorted({round(index * (count - 1) / (amount - 1)) for index in range(amount)})


def main() -> None:
    cell_w, cell_h = 220, 180
    sheet = Image.new("RGBA", (cell_w * 6, cell_h * len(ACTIONS)), (25, 27, 34, 255))
    draw = ImageDraw.Draw(sheet)
    for row, (label, relative, frame_size, count) in enumerate(ACTIONS):
        source = Image.open(LAN / relative).convert("RGBA")
        width, height = frame_size
        columns = source.width // width
        for column, frame_index in enumerate(sample_indices(count)):
            x = (frame_index % columns) * width
            y = (frame_index // columns) * height
            frame = source.crop((x, y, x + width, y + height))
            scale = min(3, max(1, min(180 // width, 135 // height)))
            frame = frame.resize((width * scale, height * scale), Image.Resampling.NEAREST)
            left = column * cell_w + (cell_w - frame.width) // 2
            top = row * cell_h + 35 + (135 - frame.height) // 2
            sheet.alpha_composite(frame, (left, top))
            draw.text((column * cell_w + 6, row * cell_h + 18), f"{label}  F{frame_index + 1}", fill="white")
        draw.line((0, (row + 1) * cell_h - 1, sheet.width, (row + 1) * cell_h - 1), fill=(70, 74, 86, 255))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
