"""Add pose-following cat ears and tail to the 16-frame run palette base."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
IN = ROOT / "PendingArt" / "character" / ("\u4e3b\u89d2-\u5c9a") / "palette-bases" / "run" / "sprite sheets" / "run.png"
ORIGINAL = ROOT / "PendingArt" / "character" / ("\u4e3b\u89d2-\u5c9a") / "run" / "sprite sheets" / "run.png"
OUT = IN.parent
FRAME_W, FRAME_H, COLUMNS, ROWS = 65, 60, 4, 4

# Existing base colors, selected from the palette output.
HAIR_LIGHT = (254, 230, 165, 255)
HAIR_MID = (245, 196, 119, 255)
HAIR_SHADE = (218, 154, 81, 255)
HAIR_DARK = (171, 112, 60, 255)

def checker(image: Image.Image) -> Image.Image:
    out = Image.new("RGBA", image.size)
    for y in range(image.height):
        for x in range(image.width):
            c = 95 if (x // 4 + y // 4) % 2 else 112
            out.putpixel((x, y), (c, c, c, 255))
    out.alpha_composite(image)
    return out

def contact(frames: list[Image.Image], path: Path) -> None:
    scale = 7
    sheet = Image.new("RGB", (COLUMNS * FRAME_W * scale, ROWS * FRAME_H * scale), "#2F3036")
    for i, frame in enumerate(frames):
        display = checker(frame).convert("RGB").resize((FRAME_W * scale, FRAME_H * scale), Image.Resampling.NEAREST)
        sheet.paste(display, ((i % COLUMNS) * FRAME_W * scale, (i // COLUMNS) * FRAME_H * scale))
    sheet.save(path)

base = Image.open(IN).convert("RGBA")
assert base.size == (FRAME_W * COLUMNS, FRAME_H * ROWS)
frames = [base.crop(((i % COLUMNS) * FRAME_W, (i // COLUMNS) * FRAME_H, (i % COLUMNS + 1) * FRAME_W, (i // COLUMNS + 1) * FRAME_H)) for i in range(16)]
original_sheet = Image.open(ORIGINAL).convert("RGBA")
original_frames = [original_sheet.crop(((i % COLUMNS) * FRAME_W, (i // COLUMNS) * FRAME_H, (i % COLUMNS + 1) * FRAME_W, (i // COLUMNS + 1) * FRAME_H)) for i in range(16)]
contact(frames, OUT / "run-palette-base-7x.png")

# Measured from the run's face/crown positions. Frames 1–4 descend; 5–8 are
# an upper stride; 9–16 return through the opposite leg. Small changes keep
# the ear tips from flickering while retaining the template's head bob.
head_y = [4, 4, 5, 5, -6, -6, -5, -6, 0, 0, 0, 0, 0, 0, 1, 1]
head_x = [0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0]
root_y = [35, 35, 36, 36, 27, 27, 28, 27, 31, 31, 31, 32, 35, 35, 36, 36]
root_x = [36, 36, 36, 36, 37, 37, 38, 38, 35, 35, 35, 35, 34, 34, 34, 34]

# Small side-view ears, placed over the hair crown. ``f`` is inner-ear pink
# and ``.`` is transparent. The foremost ear is higher; the rear ear stays
# partly hidden by hair, which reads better at 65×60 than two equal triangles.
front_ear = ["...d..", "..dmd.", ".dmmd.", "dmmfd.", "dmffd.", ".dffd.", "..ddd."]
rear_ear = ["..d..", ".dmd.", ".dmmd", "dmmfd", ".dddd"]
ear_colors = {"d": HAIR_DARK, "m": HAIR_MID, "f": (224, 192, 156, 255)}

results: list[Image.Image] = []
for i, frame in enumerate(frames):
    character = frame.copy()
    ears = Image.new("RGBA", frame.size)
    ear_pixels: set[tuple[int, int]] = set()
    horn_pixels: set[tuple[int, int]] = set()
    # Identify dark horn components from the unmodified template. The component
    # reaching the left canvas edge is the forward horn and is erased. The
    # crown component is filled back with hair before the cat ears are drawn.
    original = original_frames[i]
    candidates = {(x, y) for y in range(16) for x in range(26)
                  if original.getpixel((x, y))[:3] in {(77,47,30), (169,110,103), (81,55,63), (145,88,76)}
                  and original.getpixel((x, y))[3]}
    components = []
    while candidates:
        start = candidates.pop(); component = {start}; queue = [start]
        while queue:
            px, py = queue.pop()
            for neighbor in ((px-1,py),(px+1,py),(px,py-1),(px,py+1),(px-1,py-1),(px+1,py+1),(px-1,py+1),(px+1,py-1)):
                if neighbor in candidates:
                    candidates.remove(neighbor); component.add(neighbor); queue.append(neighbor)
        components.append(component)
    for component in components:
        exterior = any(x == 0 for x, _ in component)
        for pixel in component:
            character.putpixel(pixel, (0,0,0,0) if exterior else HAIR_LIGHT)
            horn_pixels.add(pixel)
    # Crown is x=14–20 in all left-facing run frames.
    for pattern, ox, oy in ((rear_ear, 11 + head_x[i], head_y[i] + 3), (front_ear, 17 + head_x[i], head_y[i])):
        for yy, row in enumerate(pattern):
            for xx, code in enumerate(row):
                if code != ".":
                    pixel = (ox + xx, oy + yy)
                    ears.putpixel(pixel, ear_colors[code])
                    character.putpixel(pixel, ear_colors[code])
                    ear_pixels.add(pixel)
    # Tail lives under the original character frame. A phase-shifted soft arc
    # provides secondary motion without changing any limb or weapon pixel.
    phase = 2 * 3.1415926535 * i / 16
    sway = round(2 * __import__("math").sin(phase))
    lift = round(2 * __import__("math").cos(phase))
    points = [
        (root_x[i], root_y[i]),
        (root_x[i] + 8, root_y[i] - 1),
        (min(root_x[i] + 19 + sway, 61), root_y[i] - 8 + lift),
        (min(root_x[i] + 17 + sway, 61), root_y[i] - 15 + lift),
    ]
    curve: list[tuple[int, int]] = []
    for step in range(41):
        t = step / 40; u = 1 - t
        x = round(u**3 * points[0][0] + 3*u*u*t * points[1][0] + 3*u*t*t * points[2][0] + t**3 * points[3][0])
        y = round(u**3 * points[0][1] + 3*u*u*t * points[1][1] + 3*u*t*t * points[2][1] + t**3 * points[3][1])
        if 0 <= x < FRAME_W and 0 <= y < FRAME_H and (not curve or curve[-1] != (x, y)):
            curve.append((x, y))
    tail = Image.new("RGBA", frame.size)
    draw = ImageDraw.Draw(tail)
    draw.line(curve, fill=HAIR_DARK, width=5)
    draw.line(curve, fill=HAIR_MID, width=3)
    draw.line(curve[-3:], fill=HAIR_LIGHT, width=2)
    result = tail.copy()
    # Directly restore every original foreground pixel so even semi-transparent
    # edge pixels retain their exact RGBA value over the tail layer.
    for y in range(FRAME_H):
        for x in range(FRAME_W):
            original_pixel = frame.getpixel((x, y))
            if original_pixel[3] and (x, y) not in ear_pixels and (x, y) not in horn_pixels:
                result.putpixel((x, y), original_pixel)
    for pixel in ear_pixels:
        result.putpixel(pixel, ears.getpixel(pixel))
    # Final foreground lock after all layer work. Ear edits are confined to the
    # crown; the rest of the source character, including semi-transparent
    # anti-aliased edges, is byte-for-byte retained.
    for y in range(FRAME_H):
        for x in range(FRAME_W):
            if frame.getpixel((x, y))[3] and (x, y) not in horn_pixels and not (0 <= y <= 13 and 10 <= x <= 25):
                result.putpixel((x, y), frame.getpixel((x, y)))
    results.append(result)
    result.save(OUT / f"run-frame{i+1:02}-cat.png")
    ears.save(OUT / f"run-frame{i+1:02}-ears.png")
    tail.save(OUT / f"run-frame{i+1:02}-tail.png")

output = Image.new("RGBA", base.size)
for i, frame in enumerate(results):
    output.paste(frame, ((i % COLUMNS) * FRAME_W, (i // COLUMNS) * FRAME_H))
output.save(OUT / "run-cat-ears-tail.png")
contact(results, OUT / "run-cat-ears-tail-7x.png")

preview = [checker(frame).convert("RGB").resize((FRAME_W * 7, FRAME_H * 7), Image.Resampling.NEAREST) for frame in results]
preview[0].save(OUT / "run-cat-ears-tail-preview.gif", save_all=True, append_images=preview[1:], duration=[60, 60, 60, 70] * 4, loop=0, disposal=2)

# Source pixels are composited as the foreground, so no original opaque pixel
# can be moved or recolored. Only ear/tail pixels occupy transparent regions.
for i, (original, result) in enumerate(zip(frames, results), 1):
    for y in range(FRAME_H):
        for x in range(FRAME_W):
            if original.getpixel((x, y))[3] and result.getpixel((x, y)) != original.getpixel((x, y)):
                # Ear pixels are deliberately allowed only in the crown zone.
                if not (0 <= y <= 15 and 0 <= x <= 25):
                    raise AssertionError(f"frame {i}: foreground changed at {x},{y}; source={original.getpixel((x,y))}; result={result.getpixel((x,y))}")
print("PASS: 16 frames; original run foreground preserved outside crown ear area; tail composited behind character.")
