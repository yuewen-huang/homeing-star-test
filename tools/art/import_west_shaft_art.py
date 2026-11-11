"""Prepare A22's small transparent sprites from the source atlas."""

from pathlib import Path

from PIL import Image


WORKSPACE = Path(__file__).resolve().parents[3]
SOURCE = WORKSPACE / "homeing-star-temp-assert/ProductionArt/chapter_2_underwater_cavern/20261111/west_shaft/a22_parts.png"
DEST = WORKSPACE / "homeing-star-game/assets/levels/chapter_2_underwater/cavern/environment/props/west_shaft"
PARTS = {
    "spear_head": ((215, 70, 680, 295), (48, 20)),
    "spear_shaft": ((740, 95, 1515, 260), (176, 20)),
    "wall_socket": ((205, 330, 570, 722), (32, 41)),
    "hanger_rail": ((1050, 326, 1200, 719), (18, 78)),
    "spring_plate": ((47, 816, 722, 916), (96, 15)),
    "spring_coils": ((770, 831, 1489, 981), (96, 17)),
    "strike_plate": ((217, 820, 553, 847), (60, 5)),
}


def harden_alpha(sprite, threshold):
    sprite.putalpha(sprite.getchannel("A").point(lambda value: 255 if value >= threshold else 0))


def prepare(source, crop, limit):
    sprite = source.crop(crop)
    harden_alpha(sprite, 115)
    sprite = sprite.crop(sprite.getbbox())
    sprite.thumbnail(limit, Image.Resampling.LANCZOS)
    harden_alpha(sprite, 115)
    return sprite.crop(sprite.getbbox())


def prepare_spring_plate(source):
    crop, limit = PARTS["spring_plate"]
    plate = source.crop(crop)
    mask = Image.new("L", plate.size)
    for y in range(44, 55):
        for x in range(157, 524):
            red, green, blue, alpha = plate.getpixel((x, y))
            if alpha >= 115 and green >= 85 and green - red > 18:
                mask.putpixel((x, y), 255)
                plate.putpixel((x, y), (red // 3, green // 4, blue // 4, alpha))
    sprite = prepare(plate, (0, 0, *plate.size), limit)
    mask = mask.resize(sprite.size, Image.Resampling.BOX)
    mask = mask.point(lambda value: 255 if value >= 58 else 0)
    lamp_box = mask.getbbox()
    light = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    light.putalpha(mask)
    return sprite, light.crop(lamp_box), lamp_box


def save_palette_sprites(sprites):
    samples = [pixel[:3] for sprite in sprites.values() for pixel in sprite.getdata() if pixel[3]]
    palette_sample = Image.new("RGB", (len(samples), 1))
    palette_sample.putdata(samples)
    palette = palette_sample.quantize(colors=36, method=Image.Quantize.MEDIANCUT)
    DEST.mkdir(parents=True, exist_ok=True)
    for name, sprite in sprites.items():
        alpha = sprite.getchannel("A")
        skin = sprite.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGBA")
        skin.putalpha(alpha)
        skin.save(DEST / f"{name}.png", optimize=True)
        print(f"{name}: {skin.width}x{skin.height}")


def main():
    source = Image.open(SOURCE).convert("RGBA")
    sprites = {name: prepare(source, *recipe) for name, recipe in PARTS.items() if name != "spring_plate"}
    sprites["spring_plate"], light, lamp_box = prepare_spring_plate(source)
    save_palette_sprites(sprites)
    light.save(DEST / "spring_light.png", optimize=True)
    print(f"spring_light: {light.width}x{light.height}, plate pixel bounds {lamp_box}")


if __name__ == "__main__":
    main()
