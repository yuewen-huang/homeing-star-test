from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageEnhance


ROOT = Path(r"D:\homing-star-godot")
GEN = Path(r"D:\CodexData\.codex\generated_images\01a0b8c2-1e44-7253-afac-31bbab1ac303")
OUT = ROOT / "assets" / "sideview" / "environment" / "tutorial_city_gate"
PREVIEW = ROOT / "tmp" / "art_previews" / "tutorial-city-gate"
REFERENCE = ROOT / "PendingArt" / "environment" / "tutorial-city-gate" / "layers"
SIZE = (1280, 720)

INPUTS = {
    "01_far_city.png": GEN / "exec-5ae49bf9-e82d-4674-98a8-1591691a45b9.png",
    "02_gate_architecture.png": GEN / "exec-ea102b9c-acf1-4226-9b92-965ccee1f3dd.png",
    "03_combat_ground.png": GEN / "exec-06947c28-5044-43c7-9015-ae66087bf2a7.png",
}


def resize_layer(path: Path, opaque: bool) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    image = image.resize(SIZE, Image.Resampling.LANCZOS)
    if opaque:
        image.putalpha(255)
    return image


def extend_ground_to_bottom(layer: Image.Image) -> Image.Image:
    """Remove the transparent footer by continuing the retaining-wall masonry."""
    alpha = layer.getchannel("A")
    # Ignore one-pixel resampling ghosts below the real cutout edge.
    bbox = alpha.point(lambda value: 255 if value > 8 else 0).getbbox()
    if bbox is None or bbox[3] >= layer.height:
        return layer

    content_bottom = bbox[3]
    missing_height = layer.height - content_bottom
    # Sample above the antialiased cutout fringe so the continuation is solid.
    sample_bottom = max(missing_height, content_bottom - 8)
    sample_top = max(0, sample_bottom - missing_height)
    sample = layer.crop((0, sample_top, layer.width, sample_bottom))
    if sample.height != missing_height:
        sample = sample.resize((layer.width, missing_height), Image.Resampling.NEAREST)
    result = layer.copy()
    result.alpha_composite(sample, (0, content_bottom))
    return result


def build_mirrored_panorama(center: Image.Image) -> Image.Image:
    """Build three screens whose touching edge columns are mathematically identical."""
    flipped = center.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    panorama = Image.new("RGBA", (center.width * 3, center.height), (0, 0, 0, 0))
    panorama.alpha_composite(flipped, (0, 0))
    panorama.alpha_composite(center, (center.width, 0))
    panorama.alpha_composite(flipped, (center.width * 2, 0))
    return panorama


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    layers_by_name: dict[str, Image.Image] = {}
    report: list[str] = []
    for index, (name, source) in enumerate(INPUTS.items()):
        layer = resize_layer(source, opaque=index == 0)
        # Slightly restrain saturation/contrast so the player and hit feedback stay dominant.
        rgb = Image.merge("RGB", layer.split()[:3])
        rgb = ImageEnhance.Color(rgb).enhance(0.82 if index == 0 else 0.88)
        rgb = ImageEnhance.Contrast(rgb).enhance(0.94)
        graded = Image.merge("RGBA", (*rgb.split(), layer.getchannel("A")))
        if name == "03_combat_ground.png":
            graded = extend_ground_to_bottom(graded)
        graded.save(OUT / name)
        layers_by_name[name] = graded
        alpha = graded.getchannel("A")
        report.append(f"{name}: {graded.width}x{graded.height}, alpha_range={alpha.getextrema()}")

    far_wide = build_mirrored_panorama(layers_by_name["01_far_city.png"])
    far_wide.save(OUT / "01_far_city_wide_v2.png")
    ground_wide = build_mirrored_panorama(layers_by_name["03_combat_ground.png"])
    ground_wide.save(OUT / "03_combat_ground_wide_v2.png")
    report.append(f"01_far_city_wide_v2.png: {far_wide.width}x{far_wide.height}, mirrored_edge_match=true")
    report.append(f"03_combat_ground_wide_v2.png: {ground_wide.width}x{ground_wide.height}, mirrored_edge_match=true")

    wide_preview = far_wide.copy()
    wide_gate = layers_by_name["02_gate_architecture.png"].resize(
        (round(SIZE[0] * 0.78), round(SIZE[1] * 0.78)), Image.Resampling.LANCZOS
    )
    wide_preview.alpha_composite(wide_gate, (1920 - 499, 0))
    wide_preview.alpha_composite(ground_wide, (0, 35))
    wide_preview.convert("RGB").save(PREVIEW / "tutorial-city-gate-wide-v2-preview.png")

    composite = Image.new("RGBA", SIZE, (0, 0, 0, 255))
    composite.alpha_composite(layers_by_name["01_far_city.png"])
    gate = layers_by_name["02_gate_architecture.png"].resize(
        (round(SIZE[0] * 0.78), round(SIZE[1] * 0.78)), Image.Resampling.LANCZOS
    )
    composite.alpha_composite(gate, ((SIZE[0] - gate.width) // 2, 0))
    composite.alpha_composite(layers_by_name["03_combat_ground.png"], (0, 35))
    composite.convert("RGB").save(PREVIEW / "tutorial-city-gate-composite-preview.png")

    REFERENCE.mkdir(parents=True, exist_ok=True)
    (REFERENCE / "LAYER_REPORT.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report))


if __name__ == "__main__":
    main()
