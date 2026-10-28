"""Reports game paths that point at nothing, across the game, test and doc repos.

Usage: python check_res_paths.py [--root <workspace>] [--quiet]

Errors (exit code 1): a `res://` path in the game or test repo, or a `uid://` reference in
the game, that does not exist.
Warnings (never fail): bare `assets/…` paths in test tools (some are outputs not made yet)
and in docs (older design notes), and runtime-built paths whose folder is missing.
Runtime-built paths (`%s`, `{}`) are checked by their fixed folder prefix only.
"""
from __future__ import annotations

import argparse
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import res_paths as rp  # noqa: E402


# Game files whose dictionary keys are old paths on purpose (`"res://old": "res://new"`);
# their values are still checked.
LEGACY_KEY_FILES = {"scripts/autoload/save_path_migration.gd"}
# Test files that use old paths on purpose (to prove they are migrated).
LEGACY_TEST_FILES = {"tests/autoload/test_save_path_migration.gd"}
# Importers contain literal paths belonging to their source Godot project.
# Resolve only these exact references there; all production paths still use the game.
STUDIO_REFERENCES = {
    "tools/art/import_master_phase2_arrangements.py": {"combos/", "vfx/combo_player.gd"},
    "tools/art/import_master_phase2_studio.py": {"tools/export_master_runtime.gd", "vfx/"},
    "tools/art/import_parry_wave.py": {"vfx/"},
}
DEMO_REFERENCES = {
    "tools/art/import_deer_phase3_arrangements.py": {"vfx/", "vfx/vendor_studio/magic/shaders/"},
}
# This historical generator describes its own output, retired from the runtime.
# Keep reporting it as a warning rather than treating it as a production dependency.
RETIRED_OUTPUTS = {
    "tools/art/integrate_master_painted_vfx.py": {"assets/generated/combat_vfx/master/heavy_skills/{page}"},
}

# Paths that are missing on purpose: path → why.
KNOWN_MISSING = {
    "missing_scene.tscn": "test_town_travel checks that a checkpoint to a missing scene is refused",
}


def exists(game: Path, rel: str) -> bool:
    return (game / rel).exists()


def check(ws: rp.Workspace):
    errors: dict[str, list[str]] = defaultdict(list)
    warnings: dict[str, list[str]] = defaultdict(list)
    game = ws.game
    uids = rp.collect_uids(game)
    for repo_name, repo, suffixes in ws.repos():
        for path in rp.text_files(repo, suffixes):
            text = rp.read_text(path)
            if text is None:
                continue
            where = f"{repo_name}/{path.relative_to(repo).as_posix()}"
            if rp.is_restructure_record(repo_name, repo, path):
                continue
            for match in rp.RES_RE.finditer(text):
                rel = rp.clean(match.group(0)[len("res://"):])
                if not rel or rel.startswith(".godot/") or rel in KNOWN_MISSING:
                    continue
                if repo_name == rp.TEST and rel in STUDIO_REFERENCES.get(path.relative_to(repo).as_posix(), set()):
                    if not exists(ws.root / "combat-vfx-studio", rel):
                        errors[where].append(f"Studio source missing: {rel}")
                    continue
                if repo_name == rp.TEST and rel in DEMO_REFERENCES.get(path.relative_to(repo).as_posix(), set()):
                    if not exists(ws.root / "smear-combo-demo", rel):
                        errors[where].append(f"Smear demo source missing: {rel}")
                    continue
                if repo_name == rp.TEST and rel in RETIRED_OUTPUTS.get(path.relative_to(repo).as_posix(), set()):
                    warnings[where].append(f"retired generator output: res://{rel}")
                    continue
                if rp.is_dynamic(rel):
                    prefix = rp.static_prefix(rel)
                    if prefix and not exists(game, prefix):
                        target = warnings if repo_name == rp.DOC else errors
                        target[where].append(f"runtime path folder missing: res://{rel}")
                    continue
                legacy_key = text[match.end():match.end() + 2] == '":'
                if legacy_key and repo_name == rp.GAME and path.relative_to(repo).as_posix() in LEGACY_KEY_FILES:
                    continue
                if repo_name == rp.TEST and path.relative_to(repo).as_posix() in LEGACY_TEST_FILES:
                    continue
                if not exists(game, rel):
                    target = warnings if repo_name == rp.DOC else errors
                    target[where].append(f"missing: res://{rel}")
            if repo_name == rp.GAME and path.suffix in {".tscn", ".tres", ".gd"}:
                for match in rp.UID_RE.finditer(text):
                    if match.group(0) not in uids:
                        errors[where].append(f"unknown {match.group(0)}")
            if repo_name in (rp.TEST, rp.DOC) and path.suffix in {".py", ".ps1", ".md", ".jsonl"}:
                if path.suffix == ".jsonl":
                    continue  # recipe asset paths are relative to the baked atlas root
                for match in rp.BARE_RE.finditer(text):
                    rel = rp.clean(match.group(1))
                    if rp.is_dynamic(rel):
                        rel = rp.static_prefix(rel)
                    if rel and "/" in rel and not exists(game, rel):
                        warnings[where].append(f"bare path missing: {rel}")
    return errors, warnings


def report(title: str, found: dict[str, list[str]]) -> int:
    count = sum(len(v) for v in found.values())
    print(f"{title}: {count}")
    for where in sorted(found):
        for item in sorted(set(found[where])):
            print(f"  {where}: {item}")
    return count


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--root", type=Path, default=rp.default_root(), help="folder holding the four repos")
    parser.add_argument("--quiet", action="store_true", help="print warnings as a count only")
    args = parser.parse_args(argv)
    errors, warnings = check(rp.Workspace(args.root))
    error_count = report("ERRORS", errors)
    if args.quiet:
        print(f"WARNINGS: {sum(len(v) for v in warnings.values())} (run without --quiet to list)")
    else:
        report("WARNINGS", warnings)
    return 1 if error_count else 0


if __name__ == "__main__":
    sys.exit(main())
