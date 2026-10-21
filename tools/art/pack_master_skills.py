"""Trim and adaptively reduce the 120 Hz production captures; preserve event times."""
import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image


def select_frames(frames, times, protected, budget):
    """Spend a small art-frame budget on the largest held-image errors first."""
    # Low-resolution descriptors measure selection error only; shipped pixels are
    # copied unchanged from the full-resolution mother frames.
    features = []
    for frame in frames:
        a = np.asarray(frame.resize((64,32),Image.Resampling.BOX),dtype=np.float32)/255
        a[:,:,:3] *= a[:,:,3:]
        features.append(a.reshape(-1))
    features = np.stack(features)
    errors = np.stack([np.abs(features-f).mean(axis=1) for f in features])
    weights = np.diff(times)
    def cost(left,right):
        error = float((errors[left,left:right]*weights[left:right]).sum())
        # Even a quiet fade gets intermediate images rather than a long freeze.
        gap = times[right]-times[left]
        return error+max(0,gap-.075)**2*.2
    kept = sorted(protected)
    assert len(kept) <= budget, (len(kept),budget)
    while len(kept) < min(budget,len(frames)):
        best = None
        for left,right in zip(kept,kept[1:]):
            for candidate in range(left+1,right):
                gain = cost(left,right)-cost(left,candidate)-cost(candidate,right)
                if best is None or gain > best[0]: best = (gain,candidate)
        if best is None: break
        kept.append(best[1]); kept.sort()
    return kept


def pack(raw: Path, output: Path):
    source = json.loads((raw / "raw_manifest.json").read_text(encoding="utf-8"))
    result = {"version": 1, "source_fps": source["fps"], "clips": {}}
    total_raw = total_kept = 0
    for name, spec in source["clips"].items():
        frames = [Image.open(raw/name/f"{i:04d}.png").convert("RGBA") for i in range(len(spec["times"]))]
        override = raw.parent/"rising_override"
        corrected = name.startswith("inertia_combo/cut_3_") and (override/"locked_manifest.json").exists()
        if corrected:
            index = min(range(len(spec["times"])),key=lambda i: abs(spec["times"][i]-1/3))
            image = Image.open(override/("left.png" if name.endswith("left") else "right.png")).convert("RGBA")
            assert image.size == frames[index].size, "Single-frame correction must keep the mother canvas"
            frames[index] = image
        if not spec["hilt"]:
            # A transparent viewport readback is premultiplied. Ground accents
            # previously drew straight onto the scene, so restore straight RGBA
            # before Sprite2D applies alpha. Ribbons retain their original two-pass look.
            straight = []
            for frame in frames:
                pixels = np.array(frame, dtype=np.float32)
                alpha = pixels[:, :, 3:]
                pixels[:, :, :3] = np.where(alpha > 0, pixels[:, :, :3]*255/np.maximum(alpha,1),0)
                straight.append(Image.fromarray(np.clip(np.rint(pixels),0,255).astype(np.uint8)))
            frames = straight
        assert len(frames) == len(spec["times"]), name
        boxes = [f.getchannel("A").getbbox() for f in frames]
        boxes = [b for b in boxes if b]
        assert boxes, f"Empty clip: {name}"
        bounds = (max(0, min(b[0] for b in boxes)-1), max(0, min(b[1] for b in boxes)-1),
                  min(frames[0].width, max(b[2] for b in boxes)+1),
                  min(frames[0].height, max(b[3] for b in boxes)+1))
        cropped = [f.crop(bounds) for f in frames]
        protected = {min(range(len(frames)), key=lambda i: abs(spec["times"][i]-t))
                     for t in spec["protected"]}
        protected.update((0, len(frames)-1))
        if "/cut_" in name:
            move,cut = name.split("/cut_")
            budget = {"inertia_combo":[7,8,8],"lunge_combo":[7,8],"air_qi_combo":[8]}[move][int(cut.split("_")[0])-1]
        else:
            budget = {"takeoff_halo":5,"landing_gold":9,"release_glint":3}[name.split("/")[-1]]
        kept = select_frames(cropped,spec["times"],protected,budget)
        if corrected:
            locked = json.loads((override/"locked_manifest.json").read_text(encoding="utf-8"))["clips"][name]
            kept = [min(range(len(spec["times"])),key=lambda i: abs(spec["times"][i]-t)) for t in locked["times"]]
        cell = cropped[0].size
        columns = max(1, min(8, 2048//cell[0]))
        rows = max(1, min(8, 2048//cell[1]))
        capacity = columns*rows
        pages = []
        for first in range(0, len(kept), capacity):
            batch = kept[first:first+capacity]
            sheet = Image.new("RGBA", (cell[0]*columns, cell[1]*math.ceil(len(batch)/columns)))
            for j, index in enumerate(batch):
                sheet.paste(cropped[index], ((j%columns)*cell[0], (j//columns)*cell[1]))
            path = f"{name}_{len(pages):02d}.png"
            (output/path).parent.mkdir(parents=True, exist_ok=True)
            sheet.save(output/path)
            pages.append(path)
        # Remove only obsolete pages generated by this tool for this exact clip.
        for stale in (output/name).parent.glob(Path(name).name+"_[0-9][0-9].png"):
            if stale.relative_to(output).as_posix() not in pages:
                stale.unlink()
                sidecar = stale.with_suffix(stale.suffix+".import")
                if sidecar.exists(): sidecar.unlink()
        clip = dict(spec)
        clip.update(pages=pages, cell=list(cell), columns=columns, capacity=capacity,
                    pivot=[spec["pivot"][0]-bounds[0],spec["pivot"][1]-bounds[1]],
                    times=[spec["times"][i] for i in kept], frames=len(kept), raw_frames=len(frames))
        result["clips"][name] = clip
        total_raw += len(frames)
        total_kept += len(kept)
        # Same-speed raw/reduced previews stay in ignored diagnostic artifacts.
        previews = []
        for label, indices in (("raw",list(range(len(frames)))), ("reduced",kept)):
            # GIF has a 10ms tick, so 120Hz native durations would stretch time.
            # Sample both playbacks at identical 50Hz timestamps for a fair loop.
            selected = []
            cursor = 0
            for time in np.arange(0,spec["duration"],.02):
                while cursor+1 < len(indices) and spec["times"][indices[cursor+1]] <= time+1e-6:
                    cursor += 1
                selected.append(cropped[indices[cursor]])
            backdrop = []
            for image in selected:
                bg = Image.new("RGBA", image.size, (35,40,42,255))
                bg.alpha_composite(image)
                backdrop.append(bg.convert("RGB"))
            if backdrop:
                backdrop[0].save(raw/name/f"{label}.gif",save_all=True,append_images=backdrop[1:],duration=20,loop=0,disposal=2)
            previews.append(backdrop)
        comparison = []
        for a,b in zip(*previews):
            pair = Image.new("RGB",(a.width*2,a.height+18),(35,40,42))
            pair.paste(a,(0,18)); pair.paste(b,(a.width,18))
            from PIL import ImageDraw
            draw = ImageDraw.Draw(pair)
            draw.text((3,2),"120 Hz source",fill="white")
            draw.text((a.width+3,2),"Baked frames",fill="white")
            comparison.append(pair)
        if comparison:
            comparison[0].save(raw/name/"comparison.gif",save_all=True,append_images=comparison[1:],duration=20,loop=0,disposal=2)
        print(f"{name}: {len(frames)} -> {len(kept)}, cell {cell}")
    result["raw_frames"] = total_raw
    result["frames"] = total_kept
    output.mkdir(parents=True, exist_ok=True)
    (output/"manifest.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    # Explicit texture dependencies and a preloaded Resource survive PCK exports;
    # runtime never depends on loose JSON files or filename-only load discovery.
    pages = [p for clip in result["clips"].values() for p in clip["pages"]]
    lines = [f'[gd_resource type="Resource" load_steps={len(pages)+1} format=3]', ""]
    for index, page in enumerate(pages):
        lines.append(f'[ext_resource type="Texture2D" path="res://assets/generated/combat_vfx/master/heavy_skills/{page}" id="{index+1}"]')
    lines.extend(["", "[resource]", "metadata/manifest = "+json.dumps(json.dumps(result,separators=(",",":"))),
                  "metadata/textures = {"])
    lines.extend(json.dumps(page)+f': ExtResource("{index+1}")'+("," if index+1<len(pages) else "") for index,page in enumerate(pages))
    lines.extend(["}", ""])
    (output/"library.tres").write_text("\n".join(lines),encoding="utf-8")
    print(f"TOTAL {total_raw} -> {total_kept}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("raw",type=Path)
    parser.add_argument("output",type=Path)
    args = parser.parse_args()
    pack(args.raw,args.output)
