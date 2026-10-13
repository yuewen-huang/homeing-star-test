"""Draft run frames 09 and 13 from the user's hand-edited frame 01.

This deliberately creates separate files.  ``run.png`` is never modified:
the artist can compare or paste these two key poses, then adjust them in
Aseprite before the remaining in-betweens are propagated.
"""
from __future__ import annotations

import ast
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SHEETS = ROOT / "PendingArt" / "character" / ("\u4e3b\u89d2-\u5c9a") / "palette-bases" / "run" / "sprite sheets"
USER_SHEET = SHEETS / "run.png"
TEMPLATE = ROOT / "PendingArt" / "character" / ("\u4e3b\u89d2-\u5c9a") / "run" / "sprite sheets" / "run.png"
# The run sheet is 260x240: four columns by five rows, hence 20 frames.
FRAME_W, FRAME_H = 65, 48


def palette_base(image: Image.Image) -> Image.Image:
    """Rebuild the untouched palette conversion from the source template."""
    tree = ast.parse((ROOT / "tools" / "aseprite" / "lan_batch_palette_bases.py").read_text(encoding="utf-8"))
    palette = next(
        ast.literal_eval(node.value)
        for node in tree.body
        if isinstance(node, ast.Assign)
        and any(isinstance(target, ast.Name) and target.id == "PALETTE" for target in node.targets)
    )
    result = image.convert("RGBA").copy()
    for y in range(result.height):
        for x in range(result.width):
            r, g, b, a = result.getpixel((x, y))
            replacement = palette.get(f"{r:02X}{g:02X}{b:02X}") if a else None
            if replacement:
                result.putpixel((x, y), tuple(bytes.fromhex(replacement)) + (a,))
    return result


def frame(image: Image.Image, number: int) -> Image.Image:
    index = number - 1
    left, top = (index % 4) * FRAME_W, (index // 4) * FRAME_H
    return image.crop((left, top, left + FRAME_W, top + FRAME_H))


def checker(image: Image.Image, scale: int = 10) -> Image.Image:
    background = Image.new("RGBA", image.size)
    for y in range(image.height):
        for x in range(image.width):
            c = 95 if (x // 4 + y // 4) % 2 else 115
            background.putpixel((x, y), (c, c, c, 255))
    background.alpha_composite(image)
    return background.convert("RGB").resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)


template = Image.open(TEMPLATE).convert("RGBA")
clean = palette_base(template)
user = Image.open(USER_SHEET).convert("RGBA")

# Everything the artist changed in frame 01 is the style sample.  It includes
# both newly drawn pixels and pixels deliberately erased/repainted over the
# old horn, so it must be copied as exact RGBA pixels rather than composited.
sample = frame(user, 1)
clean_one = frame(clean, 1)
edits = [(x, y, sample.getpixel((x, y))) for y in range(FRAME_H) for x in range(FRAME_W)
         if sample.getpixel((x, y)) != clean_one.getpixel((x, y))]

# Measured from the template's crown and tail-root displacement.  09 is the
# lower run pose; 13 returns the tail root left while the crown remains level.
# The ear patch stays fixed to the crown; only the tail-region edit shifts.
specs = {
    9: {"ear": (0, 0), "tail": (-1, -4)},
    13: {"ear": (0, 0), "tail": (-2, 0)},
}

outputs: list[Image.Image] = []
for number, offsets in specs.items():
    result = frame(clean, number)
    for x, y, color in edits:
        # The hand-drawn ear/horn replacement occupies the crown through y=14;
        # the tail and its root begin farther right/lower.  Moving them
        # separately keeps both attached to their corresponding pose anchors.
        dx, dy = offsets["ear"] if y <= 14 else offsets["tail"]
        tx, ty = x + dx, y + dy
        if 0 <= tx < FRAME_W and 0 <= ty < FRAME_H:
            result.putpixel((tx, ty), color)
    result.save(SHEETS / f"run-frame{number:02}-draft.png")
    outputs.append(result)

contact = Image.new("RGBA", (FRAME_W * len(outputs), FRAME_H))
for i, output in enumerate(outputs):
    contact.paste(output, (i * FRAME_W, 0))
contact.save(SHEETS / "run-keyframes-09-13-draft.png")

# A convenient full-size sheet for the next manual pass.  It begins with the
# artist's current ``run.png`` unchanged and replaces only cells 09 and 13.
sheet_draft = user.copy()
for number, output in zip(specs, outputs):
    index = number - 1
    sheet_draft.paste(output, ((index % 4) * FRAME_W, (index // 4) * FRAME_H))
sheet_draft.save(SHEETS / "run-with-09-13-draft.png")

preview = Image.new("RGB", (FRAME_W * len(outputs) * 10, FRAME_H * 10), "#2f3036")
for i, output in enumerate(outputs):
    preview.paste(checker(output), (i * FRAME_W * 10, 0))
preview.save(SHEETS / "run-keyframes-09-13-draft-10x.png")

print(f"PASS: transferred {len(edits)} hand-edited sample pixels to frames 09 and 13")
