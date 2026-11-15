"""Bake the spear wind and arrow used by the Zhenxi Gate formations."""

from pathlib import Path

from PIL import Image, ImageDraw


FX = Path(__file__).resolve().parents[3] / "homeing-star-game/assets/bosses/sunken_general/fx"


def bake(name, size, polygons):
    image = Image.new("RGBA", size)
    for points, color in polygons:
        layer = Image.new("RGBA", size)
        ImageDraw.Draw(layer).polygon(points, fill=color)
        image.alpha_composite(layer)
    data = ", ".join(map(str, image.tobytes()))
    (FX / f"{name}.tres").write_text(
        '[gd_resource type="ImageTexture" load_steps=2 format=3]\n\n'
        '[sub_resource type="Image" id="Image_pixels"]\n'
        f'data = {{"data": PackedByteArray({data}), "format": "RGBA8", '
        f'"height": {size[1]}, "mipmaps": false, "width": {size[0]}}}\n\n'
        '[resource]\nimage = SubResource("Image_pixels")\n', encoding="utf-8"
    )


def main():
    bake("infantry_spear_wind", (124, 24), [
        ([(0, 16), (38, 12), (66, 8), (103, 3), (121, 9), (123, 12),
          (107, 20), (77, 22), (47, 19), (20, 20), (63, 15)], (72, 96, 106, 96)),
        ([(17, 13), (51, 10), (90, 5), (108, 5), (123, 12), (106, 18),
          (78, 18), (42, 20), (77, 13)], (174, 202, 209, 120)),
        ([(31, 14), (84, 9), (108, 7), (123, 12), (109, 15),
          (82, 14), (65, 17), (72, 13)], (232, 241, 234, 203)),
        ([(87, 11), (109, 9), (123, 12), (108, 13)], (255, 250, 223, 255)),
        ([(5, 22), (34, 20), (55, 20), (30, 22)], (182, 210, 216, 87)),
    ])
    bake("reinforcement_arrow", (53, 12), [
        ([(0, 5), (17, 4), (45, 5), (45, 7), (14, 7)], (177, 207, 215, 110)),
        ([(10, 4), (21, 5), (47, 5), (47, 7), (16, 7)], (48, 36, 37, 225)),
        ([(15, 5), (48, 5), (48, 6), (18, 6)], (186, 152, 113, 255)),
        ([(7, 1), (15, 2), (22, 6), (12, 6)], (201, 213, 205, 226)),
        ([(9, 10), (16, 9), (22, 6), (12, 6)], (110, 139, 147, 220)),
        ([(43, 2), (52, 6), (43, 10), (45, 6)], (249, 241, 208, 255)),
    ])


if __name__ == "__main__":
    main()
