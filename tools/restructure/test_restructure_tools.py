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
import find_unused_assets  # noqa: E402
import move_res_paths  # noqa: E402
import move_test_files  # noqa: E402
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

    def test_runtime_built_path_into_missing_folder_is_an_error(self):
        write(self.ws.root / rp.TEST / "tests/test_rooms.gd", 'var p := "res://scenes/gone/room_%s.tscn" % id\n')
        code, out = quietly(check_res_paths.main, ["--root", str(self.ws.root)])
        self.assertEqual(code, 1, out)
        self.assertIn("runtime path folder missing: res://scenes/gone/room_%s.tscn", out.split("WARNINGS")[0])

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


class FindUnusedAssetsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.ws = Workspace(Path(self.temp.name))
        game = self.ws.root / rp.GAME
        # A resource only a dead resource uses, a nested file under a code-built folder,
        # and a file named only in a used manifest.
        write(game / "assets/dead/old.tres", '[gd_resource format=3]\n[ext_resource path="res://assets/dead/old.png" id="1"]\n')
        write(game / "assets/dead/old.png", "PNG")
        write(game / "assets/npc/ali/normal.png", "PNG")
        write(game / "scripts/npc.gd", 'func face(id, e): return load("res://assets/npc/%s/%s.png" % [id, e])\n')
        write(game / "assets/listed_only/listed.png", "PNG")
        write(game / "scripts/manifest_user.gd", 'const M := preload("res://assets/listed_only/manifest.json")\n')
        write(game / "assets/listed_only/manifest.json", '{"extra": "listed.png"}\n')
        write(game / "assets/twin_a.png", "SAME")
        write(game / "assets/twin_b.png", "SAME")

    def tearDown(self):
        self.temp.cleanup()

    def test_classifies_by_reference_kind(self):
        result = find_unused_assets.classify(self.ws.root / rp.GAME)
        kinds = {rel: kind for kind, rows in result.items() for rel, _ in rows}
        self.assertEqual(kinds["assets/old_fx/wave_186x81_4f.png"], "path")
        self.assertEqual(kinds["assets/npc/ali/normal.png"], "folder")
        self.assertEqual(kinds["assets/listed_only/listed.png"], "name")
        self.assertEqual(kinds["assets/dead/old.tres"], "unused")
        self.assertEqual(kinds["assets/dead/old.png"], "unused", "only a dead resource refers to it")
        self.assertNotIn("assets/old_fx/wave_186x81_4f.png.import", kinds)

    def test_finds_duplicates(self):
        groups = find_unused_assets.duplicates(self.ws.root / rp.GAME)
        self.assertIn(["assets/twin_a.png", "assets/twin_b.png"], groups)


class MoveTestFilesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.ws = Workspace(Path(self.temp.name))
        test = self.ws.root / rp.TEST
        write(test / "tests/support/test_harness.gd", "extends SceneTree\n")
        write(test / "tools/test_base.gd", 'extends "../tests/support/test_harness.gd"\n')
        write(test / "tools/test_child.gd", 'extends "test_base.gd"\nconst H := preload("./helper.gd")\n')
        write(test / "tools/test_base.gd.uid", "uid://base1\n")
        write(test / "tools/helper.gd", "extends RefCounted\n")
        write(test / "docs/notes.md", "Run `tools/test_base.gd`; see homeing-star-test/tools/test_child.gd.\n")
        write(self.ws.root / rp.DOC / "docs/testing.md", "`tools/test_base.gd` and `tools/test_base.gd.uid`\n")

    def tearDown(self):
        self.temp.cleanup()

    def text(self, rel):
        return (self.ws.root / rp.TEST / rel).read_text(encoding="utf-8")

    def test_moves_and_relinks(self):
        args = ["--root", str(self.ws.root), "--apply",
                "--pair", "tools/test_base.gd", "tests/combat/test_base.gd",
                "--pair", "tools/test_child.gd", "tests/player/lan/test_child.gd"]
        code, out = quietly(move_test_files.main, args)
        self.assertEqual(code, 0, out)
        self.assertEqual(self.text("tests/combat/test_base.gd"), 'extends "../support/test_harness.gd"\n')
        child = self.text("tests/player/lan/test_child.gd")
        self.assertIn('extends "../../combat/test_base.gd"', child)
        self.assertIn('preload("../../../tools/helper.gd")', child)
        self.assertTrue((self.ws.root / rp.TEST / "tests/combat/test_base.gd.uid").exists())
        notes = self.text("docs/notes.md")
        self.assertIn("`tests/combat/test_base.gd`", notes)
        self.assertIn("homeing-star-test/tests/player/lan/test_child.gd", notes)
        doc = (self.ws.root / rp.DOC / "docs/testing.md").read_text(encoding="utf-8")
        self.assertIn("`tests/combat/test_base.gd`", doc)
        self.assertIn("`tools/test_base.gd.uid`", doc, "a longer name is not a mention")

    def test_dry_run_and_refusals(self):
        code, out = quietly(move_test_files.main, ["--root", str(self.ws.root), "--pair", "tools/test_base.gd", "tests/x/test_base.gd"])
        self.assertEqual(code, 0)
        self.assertTrue((self.ws.root / rp.TEST / "tools/test_base.gd").exists())
        code, out = quietly(move_test_files.main, ["--root", str(self.ws.root), "--pair", "tools/nothing.gd", "tests/x/nothing.gd"])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
