"""Import the five saved Studio ice-cluster recipes into production (no demo dependency)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "combat-vfx-studio" / "combos"
TARGET = ROOT / "homeing-star-game/assets/bosses/crystal_crab/fx/ground_slam.json"


def main():
    profiles = {}
    common_style = None
    for key in ("normal", "burrow", "red", "gold", "aftershock"):
        folder = SOURCE / f"crystal_crab_slam_{key}"
        event, = json.loads((folder / "combo.json").read_text(encoding="utf-8"))["events"]
        style = json.loads((folder / "style.json").read_text(encoding="utf-8"))
        style.pop("title", None)
        assert event["do"] == "quake" and event["unit"] == "ice" and event["form"] == "cluster", key
        assert event["mode"] == "radial" and event["travel"] == 0.07 and event["shake"] == 0, key
        assert common_style is None or common_style == style, key
        common_style = style
        # The real boss supplies a locked world centre and the action clock.
        profiles[key] = event | {"t": 0.0, "x": 0.0, "y": 0.0}
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(json.dumps({"style": common_style, "profiles": profiles}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Imported {len(profiles)} Studio ice-cluster profiles: {TARGET}")


if __name__ == "__main__":
    main()
