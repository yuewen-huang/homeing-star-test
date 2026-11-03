"""Author editable Studio quake presets and export the exact events for production."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PALETTES = [
    (["1d2927", "3b5049", "6b8374", "aab8a1", "d6dfc0"], "80958a", "雾"),
    (["29251d", "574730", "88704a", "bda77a", "ded0a1"], "998569", "根"),
    (["202d31", "3c5960", "6e9295", "a7c7bf", "d5e2ce"], "86a5a5", "风"),
    (["202a20", "42583a", "788c52", "b4c586", "dae2ae"], "8b9d74", "藤"),
]

def main():
    profiles = {}
    for phase, (ramp, dust, title) in enumerate(PALETTES, 1):
        for heavy in (False, True):
            key = f"{phase}_{'heavy' if heavy else 'light'}"
            name = f"deer_stomp_{key}"
            event = dict(t=0, do="quake", x=640, y=520, unit="sword", form="crescent",
                         trail="flame", reverse=False, sink=.18,
                         mode="radial", width=480 if heavy else 300, perspective=.20,
                         travel=.30 if heavy else .18, ease=.85, spacing=80 if heavy else 70,
                         strength=1.10 if heavy else .72, unit_size=.80 if heavy else .50,
                         unit_time=.48 if heavy else .28, ramp=ramp,
                         cracks=True, crack_amount=.65 if heavy else .35,
                         crack_time=.42 if heavy else .24, crack_glow=.08,
                         wave=False, wave_height=.24, flash=.12 if heavy else .06, shake=0,
                         debris="auto", debris_density=.35 if heavy else .20,
                         debris_height=48 if heavy else 24,
                         dust=True, dust_density=.35 if heavy else .20,
                         dust_height=35 if heavy else 20, dust_spread=65 if heavy else 40,
                         dust_time=.55 if heavy else .35, dust_color=dust,
                         seed=71 if heavy else 37)
            style = dict(language="zh", renderer="quake", quake_style="cel",
                         quake_detail="balanced", pixel=2, title=f"鹿·{title}·{'重踏' if heavy else '轻踏'}")
            folder = ROOT / "combat-vfx-studio/combos" / name
            folder.mkdir(parents=True, exist_ok=True)
            write(folder/"combo.json", {"name":style["title"], "events":[event]})
            write(folder/"style.json", style)
            (folder/"prompt.md").write_text("用户指定：剑气材质、圆心向外扩散、月牙剑气、烈焰拖尾。其余参数由 Codex 调整：轻踏短促、重踏更宽厚，阶段换色、适度入地与短尾，不额外叠加震波圈及命中闪屏。\n",encoding="utf-8")
            profiles[key] = event | {"x":0,"y":0,"quake_style":"cel","quake_detail":"balanced"}
    target=ROOT/"homeing-star-game/assets/bosses/deer/fx/stomp_profiles.json"
    write(target,{"profiles":profiles})
    print(f"Saved 8 editable Studio presets and exported {target}")

def write(path, data):
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

if __name__=="__main__": main()
