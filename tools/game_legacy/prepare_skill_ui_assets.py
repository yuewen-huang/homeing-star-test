from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE_FRAME = ROOT / "PendingArt" / "UI" / "homing-star-ui-library-2026-09-21" / "modules" / "skill_bar.png"
OUTPUT_DIR = ROOT / "assets" / "ui" / "skill-bar"
ICON_DIR = ROOT / "assets" / "ui" / "skill-icons"


def build_clean_frame() -> None:
    source = Image.open(SOURCE_FRAME).convert("RGBA")
    # Keep the square ornament, discard the key-cap extension, and repair the
    # short section of lower border that was interrupted by that extension.
    frame = source.crop((4, 0, 114, 110))
    pixels = frame.load()
    interior = (14, 22, 28, 255)
    for y in range(100, 110):
        for x in range(frame.width):
            pixels[x, y] = (0, 0, 0, 0)
    for y in range(87, 100):
        for x in range(38, 72):
            pixels[x, y] = interior
    draw = ImageDraw.Draw(frame)
    draw.line((13, 98, 96, 98), fill=(42, 39, 33, 255), width=4)
    draw.line((14, 96, 95, 96), fill=(144, 124, 84, 255), width=2)
    draw.line((16, 95, 93, 95), fill=(78, 72, 56, 255), width=1)
    frame.save(OUTPUT_DIR / "skill_slot_frame_clean.png", optimize=True)


def remove_black_background(source_name: str, output_name: str) -> None:
    image = Image.open(ICON_DIR / source_name).convert("RGBA")
    cleaned = Image.new("RGBA", image.size, (0, 0, 0, 0))
    source_pixels = image.load()
    output_pixels = cleaned.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = source_pixels[x, y]
            brightness = max(red, green, blue)
            if brightness <= 18:
                continue
            edge_alpha = min(alpha, round(255.0 * (brightness - 18) / 34.0)) if brightness < 52 else alpha
            output_pixels[x, y] = (red, green, blue, edge_alpha)
    cleaned.save(ICON_DIR / output_name, optimize=True)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    build_clean_frame()
    remove_black_background("jump-single.png", "jump-single-clean.png")
    remove_black_background("jump-double.png", "jump-double-clean.png")


if __name__ == "__main__":
    main()
