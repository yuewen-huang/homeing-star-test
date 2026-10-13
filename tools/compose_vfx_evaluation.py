import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat


ROOT = Path(r"C:\Users\P6063166\.codex\visualizations\2026\10\10\01a123df-d0fc-7331-96ec-48167310c626\opensource_vfx")
FONT = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 20)
SMALL = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 16)
CASES = ["smoke_raw", "smoke_adapted", "wave_baseline", "fog_raw", "fog_baseline", "rope_raw", "rope_adapted", "rope_stress", "grass"]


def load_case(name):
    paths = sorted((ROOT / name).glob("[0-9][0-9][0-9].png"))
    assert len(paths) == 48, (name, len(paths))
    frames = []
    for path in paths:
        with Image.open(path) as source:
            assert source.size == (960, 540), (path, source.size)
            frames.append(source.convert("RGB"))
    return frames


def save_animation(name, frames):
    # One shared palette avoids color flicker between independently indexed frames.
    samples = Image.new("RGB", (256 * 12, 144))
    for i in range(12):
        sample = frames[round(i * (len(frames) - 1) / 11)]
        samples.paste(sample.resize((256, 144)), (i * 256, 0))
    palette = samples.quantize(colors=256)
    indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    durations = [80 if i % 3 < 2 else 90 for i in range(len(frames))]
    path = ROOT / f"{name}.gif"
    indexed[0].save(path, save_all=True, append_images=indexed[1:], duration=durations,
                    loop=0, disposal=1, optimize=True)
    frames[0].save(ROOT / f"{name}.webp", save_all=True, append_images=frames[1:],
                   duration=83, loop=0, quality=88, method=4)
    with Image.open(path) as result:
        assert result.n_frames == len(frames), (name, result.n_frames)
        duration = sum(result.seek(i) or result.info["duration"] for i in range(result.n_frames))
    return {"frames": len(frames), "gif_bytes": path.stat().st_size, "duration_ms": duration}


def side_by_side(left, right, labels, crop):
    width, height = crop[2] - crop[0], crop[3] - crop[1]
    frames = []
    for i in range(48):
        frame = Image.new("RGB", (width * 2, height + 48), "#17221c")
        draw = ImageDraw.Draw(frame)
        for column, source in enumerate([left[i], right[i]]):
            frame.paste(source.crop(crop), (column * width, 48))
            draw.text((column * width + 12, 12), labels[column], font=FONT, fill="#edf2df")
        frames.append(frame)
    return frames


def main():
    captures = {name: load_case(name) for name in CASES}
    checks = {}
    for name, frames in captures.items():
        combat = [frame.crop((0, 72, 960, 470)) for frame in frames]
        motion = max(sum(ImageStat.Stat(ImageChops.difference(combat[0], image)).mean) / 3
                     for image in combat[1:])
        assert motion > 0.05, (name, "blank or static animation")
        metrics = json.loads((ROOT / name / "metrics.json").read_text())
        assert metrics["capture_failures"] == 0 and metrics["nonfinite_points"] == 0, metrics
        checks[name] = {"pixel_motion_mean": round(motion, 4), "native_metrics": metrics}

    outputs = {}
    outputs["smoke_compare"] = save_animation("smoke_compare", captures["smoke_raw"] + captures["smoke_adapted"] + captures["wave_baseline"])
    rope = side_by_side(captures["rope_raw"], captures["rope_adapted"],
                        ["A  Upstream physics / plain line", "B  Same physics / procedural vine"],
                        (300, 160, 820, 450))
    outputs["rope_compare"] = save_animation("rope_compare", rope)
    fog = side_by_side(captures["fog_raw"], captures["fog_baseline"],
                       ["A  Upstream scrolling noise", "B  Current mist / clear sight area"],
                       (230, 140, 730, 440))
    outputs["fog_compare"] = save_animation("fog_compare", fog)
    outputs["rope_stress"] = save_animation("rope_stress", captures["rope_stress"])
    outputs["vegetation"] = save_animation("vegetation", captures["grass"])

    sheet = Image.new("RGB", (960, 9 * 168), "#17221c")
    draw = ImageDraw.Draw(sheet)
    for row, name in enumerate(CASES):
        y = row * 168
        draw.text((12, y + 4), name, font=SMALL, fill="white")
        for column, index in enumerate([0, 18, 24, 47]):
            shot = captures[name][index].crop((0, 90, 960, 470)).resize((240, 132), Image.Resampling.NEAREST)
            sheet.paste(shot, (column * 240, y + 28))
    sheet.save(ROOT / "contact_sheet.png")
    report = {"checks": checks, "outputs": outputs,
              "note": "Motion checks detect static/blank capture, not VFX quality or combat correctness. Fixed simulation is not a real-time FPS benchmark."}
    (ROOT / "capture_validation.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
