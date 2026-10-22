"""Export reviewed smear combos into self-contained production data (no demo runtime)."""
from pathlib import Path
import hashlib
import json
import math
import sys

ROOT = Path(__file__).resolve().parents[3]
DEMO = ROOT / "smear-combo-demo"
sys.path.insert(0, str(DEMO / "tools"))
from smear_tools import Character, check_combo

BASE_SCALE = 675 / 472  # Keep the production master's existing standing height.
CHAR = Character(DEMO, "master_phase1")
FACTOR = BASE_SCALE / CHAR.scale
NAMES = {"inertia_combo": ("pressure_five", "断空·压身五连"),
         "lunge_combo": ("flow_six", "断空·回流六连"),
         "air_qi_combo": ("sky_eight", "断空·跃空八连")}


def smooth(u):
    u = max(0, min(1, u))
    return u * u * (3 - 2 * u)


def burst(u):
    return 1 - (1 - u * u) ** 3


def inverse(u):
    return math.sqrt(1 - (1 - u) ** (1 / 3))


def export(name, label):
    path = DEMO / "combos" / ("master_phase1_rework_" + name) / "combo.json"
    raw = json.loads(path.read_text(encoding="utf-8"))
    errors, contacts = check_combo(raw, CHAR)
    assert not errors, errors
    timeline, cuts = [], []
    at = 0.0
    for n, original in enumerate(raw["cuts"]):
        cut = {k: v for k, v in original.items() if k != "hit"}
        action = cut["action"]
        # No unannotated art is allowed into either the body or a recovery silhouette.
        for field in ["lead", "swing_frames", "follow", "recover"]:
            for f in cut.get(field, []):
                assert CHAR.role(action, f), (action, f)
        for f in [cut["wind"], cut["finish"]]:
            assert CHAR.role(action, f) and CHAR.pose(action, f), (action, f)
        spec = CHAR.actions[action]
        base = next(b for b in ["air_spin_slam", "attack_1", "attack_2", "attack_3", "dash"] if action.endswith(b + "_" + b))
        cut.update(base=base, feet=spec["feet"], cell=spec["cell"],
                   scale=spec["scale"] * BASE_SCALE, facing=spec["facing"], start=at)
        def show(t, f):
            timeline.append([t, base, f, n])
        for k, f in enumerate(cut.get("lead", [])):
            show(at + k / raw.get("lead_fps", 24), f)
        show(at + len(cut.get("lead", [])) / raw.get("lead_fps", 24), cut["wind"])
        at += cut["wind_time"]
        cut["release"] = at
        frames = [cut["wind"], *cut.get("swing_frames", []), cut["finish"]]
        if len(frames) == 2:
            show(at, frames[-1])
        else:
            for k, f in enumerate(frames[1:], 1):
                show(at + cut["swing"] * inverse((k - .5) / (len(frames) - 1)), f)
        cut["contact_at"] = contacts[n]
        at += cut["swing"]
        cut["end"] = at
        for k, f in enumerate(cut.get("follow", [])):
            show(at + cut["hold"] * (k + 1) / (len(cut["follow"]) + 1), f)
        at += cut["hold"]
        cut["hold_end"] = at
        schedule = []
        t = at
        for f in cut.get("recover", []):
            schedule.append([t, f])
            t += CHAR.duration_ms(action, f) / 1000 * cut.get("recover_pace", 1)
        next_at = t if n == len(raw["cuts"]) - 1 else at + cut.get("cancel", 0)
        for t0, f in schedule:
            if n == len(raw["cuts"]) - 1 or t0 < next_at - .0001:
                show(t0, f)
        cut["recovery_schedule"] = schedule
        cut["recovery_end"] = t
        at = next_at
        # Small extension of disappearance only. Swing/contact/body timing is unchanged.
        cut["tail"] = max(.18 if n == len(raw["cuts"]) - 1 else .09, cut["tail"] + .035)
        cut["look"] = "trail"
        cut["lunge"] *= FACTOR
        measured = []
        turn = cut["turn"]
        for k, f in enumerate(frames):
            pose = CHAR.pose(action, f)
            if not pose:
                continue  # e.g. dash F7: body plays; sword interpolates F6 -> F8.
            h, tip = pose["hilt"], pose["tip"]
            a = math.atan2(tip[1] - h[1], tip[0] - h[0])
            if measured:
                last = measured[-1][2]
                a = last + (turn * ((turn * (a - last)) % math.tau) if turn else (a - last + math.pi) % math.tau - math.pi)
            measured.append([k / (len(frames) - 1), h, a, math.dist(h, tip)])
        cut["measured"] = measured
        cuts.append(cut)
    def lunge(t):
        return sum(c["lunge"] * smooth((t - c["release"]) / c["swing"]) for c in cuts)
    for cut in cuts:
        poses = []
        prev = None
        swords = cut.pop("measured")
        for i in range(33):
            u = i / 32
            progress = burst(u)
            j = 0
            while j < len(swords) - 2 and progress > swords[j + 1][0]:
                j += 1
            a, b = swords[j:j+2]
            s = max(0, min(1, (progress - a[0]) / max(.0001, b[0] - a[0])))
            h = [a[1][k] + (b[1][k] - a[1][k]) * s for k in range(2)]
            angle, length = a[2] + (b[2] - a[2]) * s, a[3] + (b[3] - a[3]) * s
            tip = [h[0] + math.cos(angle) * length, h[1] + math.sin(angle) * length]
            drift = lunge(cut["release"] + cut["swing"] * u) - lunge(cut["release"])
            def local(p):
                return [(p[0] - cut["feet"][0]) * cut["facing"] * cut["scale"] + drift,
                        (p[1] - cut["feet"][1]) * cut["scale"]]
            h, tip = local(h), local(tip)
            angle = math.atan2(tip[1] - h[1], tip[0] - h[0])
            if prev is not None:
                angle = prev + (angle - prev + math.pi) % math.tau - math.pi
            prev = angle
            poses.append({"u": u, "hilt": h, "tip": tip, "angle": angle})
        widest = max(math.dist(p["hilt"], p["tip"]) for p in poses)
        cut["poses"] = poses
        cut["ribbon_width"] = cut["band_width"] * FACTOR if "band_width" in cut else widest * cut["width"] * (.4 if cut["turn"] == 0 else 1)
        cut["reference_blade_length"] = widest if cut.get("preserve_band_width") else 0
    sources = [path, CHAR.folder / "character.json", CHAR.folder / "presentation.json"]
    return {"label": label, "look": "trail", "duration": at, "cuts": cuts, "timeline": timeline,
            "source_sha256": {p.name if p.name != "combo.json" else name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}


if __name__ == "__main__":
    result = {key: export(*value) for key, value in NAMES.items()}
    dest = ROOT / "homeing-star-game/assets/bosses/master/body/phase1_annotated_combos.json"
    dest.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for key, combo in result.items():
        print(f"{key}: {len(combo['cuts'])} cuts, {combo['duration']:.3f}s, trail tails {[round(c['tail'],3) for c in combo['cuts']]}")
