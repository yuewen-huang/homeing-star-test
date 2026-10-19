"""Tests for check_res_paths.py and move_res_paths.py on a throwaway workspace.

Run: python -m unittest tools/restructure/test_restructure_tools.py (from homeing-star-test),
or run this file directly. Builds fake game/test/doc repos in a temp folder; the real repos
are never touched.
"""
from __future__ import annotations

import contextlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_res_paths  # noqa: E402
import move_res_paths  # noqa: E402
import res_paths as rp  # noqa: E402


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class Workspace:
    """game: a script, a scene, an art folder with import sidecars, a JSON manifest and a
    runtime-built path; test: a GDScript test and a Python tool; doc: a design note."""

    def __init__(self, root: Path):
        self.root = root
        game = root / rp.GAME
        write(game / "project.godot", "config_version=5\n")
        write(game / "assets/old_fx/wave_186x81_4f.png", "PNG")
        write(game / "assets/old_fx/wave_186x81_4f.png.import",
              '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\nuid="uid://wave1"\n'
              'path="res://.godot/imported/wave.ctex"\n\n[deps]\n\nsource_file="res://assets/old_fx/wave_186x81_4f.png"\n')
        write(game / "assets/old_fx/glow.png", "PNG")
        write(game / "assets/old_fx_extra/keep.png", "PNG")
        write(game / "assets/old_fx/manifest.json", '{"page": "assets/old_fx/glow.png"}\n')
        write(game / "scripts/wave.gd",
              'const TEXTURE := preload("res://assets/old_fx/wave_186x81_4f.png")\n'
              'const KEEP := preload("res://assets/old_fx_extra/keep.png")\n'
              'const DIR := "res://assets/old_fx/"\n'
              'func frame(i): return load("res://assets/old_fx/frame_%02d.png" % i)\n')
        write(game / "scripts/wave.gd.uid", "uid://script1\n")
        write(game / "scenes/wave.tscn",
              '[gd_scene format=3 uid="uid://scene1"]\n\n'
              '[ext_resource type="Script" uid="uid://script1" path="res://scripts/wave.gd" id="1"]\n'
              '[ext_resource type="Texture2D" uid="uid://wave1" path="res://assets/old_fx/wave_186x81_4f.png" id="2"]\n')
        test = root / rp.TEST
        write(test / "tools/test_wave.gd", 'var scene := load("res://scenes/wave.tscn")\n')
        write(test / "tools/import_wave.py",
              "GAME = ROOT / 'homeing-star-game'\nTARGET = GAME / 'assets/old_fx/wave_186x81_4f.png'\n"
              "OTHER = ROOT / 'homeing-star-game/assets/old_fx/glow.png'\n")
        write(root / rp.DOC / "docs/wave.md", "The wave lives in `assets/old_fx/wave_186x81_4f.png`.\n")

    def game(self, rel: str) -> Path:
        return self.root / rp.GAME / rel

    def text(self, repo: str, rel: str) -> str:
        return (self.root / repo / rel).read_text(encoding="utf-8")


def quietly(function, *args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        result = function(*args)
    return result, out.getvalue()


class CheckResPathsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.ws = Workspace(Path(self.temp.name))

    def tearDown(self):
        self.temp.cleanup()

    def test_clean_workspace_has_no_errors(self):
        code, out = quietly(check_res_paths.main, ["--root", str(self.ws.root)])
        self.assertEqual(code, 0, out)
        self.assertIn("ERRORS: 0", out)
        # The runtime-built frame path is checked by its folder only.
        self.assertNotIn("frame_", out)

    def test_missing_res_path_and_uid_are_errors(self):
        self.ws.game("assets/old_fx/glow.png").unlink()
        write(self.ws.game("scenes/broken.tscn"),
              '[gd_scene format=3]\n[ext_resource type="Texture2D" uid="uid://nothing" path="res://assets/none.png" id="1"]\n')
        code, out = quietly(check_res_paths.main, ["--root", str(self.ws.root)])
        self.assertEqual(code, 1)
        self.assertIn("missing: res://assets/none.png", out)
        self.assertIn("unknown uid://nothing", out)

    def test_doc_and_tool_paths_only_warn(self):
        write(self.ws.root / rp.DOC / "docs/old.md", "See `res://assets/gone.png` and `assets/gone_too.png`.\n")
        code, out = quietly(check_res_paths.main, ["--root", str(self.ws.root)])
        self.assertEqual(code, 0, out)
        self.assertIn("missing: res://assets/gone.png", out.split("WARNINGS")[1])
        self.assertIn("bare path missing: assets/gone_too.png", out)


class MoveResPathsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.ws = Workspace(Path(self.temp.name))

    def tearDown(self):
        self.temp.cleanup()

    def move(self, *pairs, apply=True):
        args = ["--root", str(self.ws.root)]
        for old, new in pairs:
            args += ["--pair", old, new]
        if apply:
            args.append("--apply")
        return quietly(move_res_paths.main, args)

    def test_dry_run_changes_nothing(self):
        before = self.ws.text(rp.GAME, "scripts/wave.gd")
        code, out = self.move(("assets/old_fx", "assets/shared/fx"), apply=False)
        self.assertEqual(code, 0, out)
        self.assertIn("DRY RUN", out)
        self.assertTrue(self.ws.game("assets/old_fx/glow.png").exists())
        self.assertEqual(self.ws.text(rp.GAME, "scripts/wave.gd"), before)

    def test_folder_move_rewrites_every_form(self):
        code, out = self.move(("assets/old_fx", "assets/shared/fx"))
        self.assertEqual(code, 0, out)
        self.assertTrue(self.ws.game("assets/shared/fx/wave_186x81_4f.png.import").exists())
        self.assertFalse(self.ws.game("assets/old_fx").exists())
        script = self.ws.text(rp.GAME, "scripts/wave.gd")
        self.assertIn('preload("res://assets/shared/fx/wave_186x81_4f.png")', script)
        self.assertIn('"res://assets/shared/fx/"', script)
        self.assertIn('"res://assets/shared/fx/frame_%02d.png"', script)
        # A sibling folder whose name starts the same is left alone.
        self.assertIn("res://assets/old_fx_extra/keep.png", script)
        self.assertIn('path="res://assets/shared/fx/wave_186x81_4f.png"', self.ws.text(rp.GAME, "scenes/wave.tscn"))
        self.assertIn('source_file="res://assets/shared/fx/wave_186x81_4f.png"',
                      self.ws.text(rp.GAME, "assets/shared/fx/wave_186x81_4f.png.import"))
        self.assertIn('"assets/shared/fx/glow.png"', self.ws.text(rp.GAME, "assets/shared/fx/manifest.json"))
        tool = self.ws.text(rp.TEST, "tools/import_wave.py")
        self.assertIn("GAME / 'assets/shared/fx/wave_186x81_4f.png'", tool)
        self.assertIn("'homeing-star-game/assets/shared/fx/glow.png'", tool)
        self.assertIn("`assets/shared/fx/wave_186x81_4f.png`", self.ws.text(rp.DOC, "docs/wave.md"))
        code, out = quietly(check_res_paths.main, ["--root", str(self.ws.root)])
        self.assertEqual(code, 0, out)

    def test_file_move_takes_sidecars_and_hints_at_built_paths(self):
        code, out = self.move(("assets/old_fx/wave_186x81_4f.png", "assets/lan/fx/sword_wave_186x81_4f.png"))
        self.assertEqual(code, 0, out)
        self.assertTrue(self.ws.game("assets/lan/fx/sword_wave_186x81_4f.png.import").exists())
        self.assertFalse(self.ws.game("assets/old_fx/wave_186x81_4f.png.import").exists())
        self.assertIn("res://assets/lan/fx/sword_wave_186x81_4f.png", self.ws.text(rp.GAME, "scripts/wave.gd"))
        # The folder constant stays: other files still live there.
        self.assertIn('"res://assets/old_fx/"', self.ws.text(rp.GAME, "scripts/wave.gd"))

    def test_moving_a_script_keeps_its_uid_file(self):
        code, out = self.move(("scripts/wave.gd", "scripts/vfx/wave.gd"))
        self.assertEqual(code, 0, out)
        self.assertTrue(self.ws.game("scripts/vfx/wave.gd.uid").exists())
        self.assertIn('path="res://scripts/vfx/wave.gd"', self.ws.text(rp.GAME, "scenes/wave.tscn"))
        code, out = quietly(check_res_paths.main, ["--root", str(self.ws.root)])
        self.assertEqual(code, 0, out)

    def test_refuses_missing_source_or_existing_target(self):
        code, out = self.move(("assets/nothing", "assets/x"))
        self.assertEqual(code, 2)
        self.assertIn("source missing", out)
        code, out = self.move(("assets/old_fx/glow.png", "assets/old_fx_extra/keep.png"))
        self.assertEqual(code, 2)
        self.assertIn("target already exists", out)

    def test_git_tracked_files_move_with_history(self):
        game = self.ws.root / rp.GAME
        run = lambda *a: subprocess.run(["git", "-C", str(game), *a], check=True, capture_output=True)
        run("init", "-q")
        run("add", "-A")
        run("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
        code, out = self.move(("assets/old_fx/glow.png", "assets/shared/glow.png"))
        self.assertEqual(code, 0, out)
        self.assertIn("git mv assets/old_fx/glow.png -> assets/shared/glow.png", out)
        status = subprocess.run(["git", "-C", str(game), "status", "--short"], capture_output=True, text=True).stdout
        self.assertIn("R  assets/old_fx/glow.png -> assets/shared/glow.png", status)

    def test_mapping_file_format(self):
        pairs = move_res_paths.parse_mapping("# comment\nres://assets/a/ -> assets/b  # why\n\n")
        self.assertEqual(pairs, [("assets/a", "assets/b")])
        with self.assertRaises(ValueError):
            move_res_paths.parse_mapping("assets/a assets/b\n")


if __name__ == "__main__":
    unittest.main()
