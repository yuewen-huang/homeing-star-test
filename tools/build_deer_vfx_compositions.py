"""Editable studio timelines for visual study, not production attacks or hitboxes."""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "artifacts/deer-vfx-compositions-20261104"
OLIVE = ["202719", "414e29", "87984f", "d1d8a3", "f2efd2"]
STYLE = {"palettes": {"normal": ["faf5dc", "d9e5ab", "8da456", "344a2b"]},
         "pixel": 1, "thickness": 1.15}


def leaves(name, base, changes):
    state = dict(t=0., do="swarm", id=name, material="leaf", count=220, size=.8,
                 ramp=OLIVE, leaf_curl=.7, leaf_sway=.5, turbulence=10., linger=4.)
    state.update(base)
    result = [state.copy()]
    for change in changes:
        state.update(change)
        result.append(state.copy())
    return result


def case(name, title, renderer, events, seconds=3.5):
    return dict(id=name, data=dict(name=title, events=sorted(events, key=lambda e: e["t"])),
                style=dict(STYLE, renderer=renderer), seconds=seconds,
                note="视觉编排草案 / 尚未接入角色与伤害")


def main():
    rush = leaves("rush_leaves", dict(form="cloud", at=[350,460], radius=120., height=150.), [
        dict(t=.68, form="stream", at=[920,470], time=.12, travel=.65, length=.65,
             width=65., path=[[260,390],[470,400],[720,465],[960,470]]),
        dict(t=1.28, form="burst", at=[930,470], time=.18, radius=260., height=170.),
        dict(t=1.55, form="fall", at=[810,470], time=.35, radius=350., height=130.),
        dict(t=2.3, form="gone", time=.4)])
    rush += [dict(t=.62, do="cast", element="wind", shape="beam", start=[350,470],
                  end=[930,470], path="straight", charge=.06, travel=.16, hold=.08, size=1.0, radius=45.),
             dict(t=.68, do="slash", stroke="cleave", angle=0., length=600., width=23.,
                  duration=.045, hold=.08, fade=.26, glow=.85, rays=0)]
    sweep = leaves("sweep_leaves", dict(form="cloud", at=[430,450], radius=90., height=130., count=180), [
        dict(t=.58, form="stream", at=[600,450], time=.1, travel=.4, length=.8, width=45.,
             path=[[370,340],[600,310],[660,470],[490,510]]),
        dict(t=.88, form="burst", at=[575,460], time=.18, radius=280., height=180.),
        dict(t=1.25, form="fall", time=.4, at=[610,430], radius=300., height=180.),
        dict(t=1.8, form="gone", time=.4)])
    sweep += [dict(t=.58, do="slash", radius=220., width=52., squash=.65,
                   **{"from":-125.,"to":80.}, tilt=-12., duration=.26, tail=.25)]
    drop = leaves("drop_leaves", dict(form="cloud", at=[840,410], radius=100., height=240., count=240), [
        dict(t=.82, form="stream", time=.1, at=[840,520], travel=.22, length=.9, width=90.,
             path=[[840,190],[815,300],[845,440],[840,520]]),
        dict(t=1.04, form="burst", at=[840,510], time=.1, radius=350., height=160.),
        dict(t=1.5, form="fall", time=.35, at=[840,450], radius=380., height=180.),
        dict(t=2.4, form="gone", time=.45)])
    drop += [dict(t=1.04, do="quake", x=840., y=520., unit="earth", form="slab", mode="radial",
                  width=310., travel=.18, strength=1.3, unit_size=.5, spacing=55., unit_time=.45,
                  dust_height=85., dust_spread=155., dust_density=1.5, dust_time=.65,
                  debris_height=145., debris_density=1.7, flash=0., shake=0., crack_time=.7),
             dict(t=.82, do="slash", stroke="cleave", angle=90., length=300., width=35.,
                  duration=.16, hold=.06, fade=.2, glow=.65, rays=0)]
    leaf = leaves("return_leaves", dict(form="halo", at=[360,450], radius=95., height=110., count=150), [
        dict(t=.76, form="stream", time=.12, at=[840,480], travel=1.12, length=.45, width=45.,
             path=[[360,450],[500,480],[680,480],[840,480]]),
        dict(t=1.88, form="stream", time=.14, at=[360,420], travel=1.12, length=.45, width=50.,
             path=[[840,480],[790,330],[530,370],[360,420]]),
        dict(t=3.0, form="burst", time=.13, at=[360,420], radius=200., height=160.),
        dict(t=3.3, form="gone", time=.4)])
    # Studio ring is an orbit around start_point, not a projectile. Use its
    # actual travelling skeleton here; production will mount the hero blade
    # on the game's authoritative return path instead of inheriting this path.
    leaf += [dict(t=0., do="cast", element="wind", shape="comet", start=[360,450], end=[840,480],
                  path="straight", charge=.76, travel=1.12, radius=42., size=.8),
             dict(t=1.88, do="cast", element="wind", shape="comet", start=[840,480], end=[360,420],
                  path="arc", arc=95., charge=0., travel=1.12, radius=42., size=.8)]
    studies = [case("rush", "横冲 / 贯穿刀光 + 风压 + 聚散", "magic", rush),
               case("sweep", "角扫 / 轨迹斩击 + 弧形叶浪", "ribbon", sweep),
               case("drop", "落击 / 下坠光痕 + 地震 + 爆散", "", drop),
               case("leaf", "往返叶刃 / 魔法凝聚 + 群体往返", "magic", leaf, 4.)]
    studies[2]["target"] = [840,520]
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "input.json"
    path.write_text(json.dumps(studies, ensure_ascii=False, indent=2), encoding="utf-8")
    print(path)


if __name__ == "__main__":
    main()
