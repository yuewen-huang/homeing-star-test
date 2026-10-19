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
            if repo_name == rp.TEST and where.startswith(f"{rp.TEST}/tools/restructure/"):
                continue  # these tools and their tests hold example paths on purpose
            if repo_name == rp.DOC and path.name.startswith("restructure_") and path.name.endswith("_unused_assets.md"):
                continue  # archive records: they list paths that were moved out on purpose
            for match in rp.RES_RE.finditer(text):
                rel = rp.clean(match.group(0)[len("res://"):])
                if not rel or rel.startswith(".godot/") or rel in KNOWN_MISSING:
                    continue
                if rp.is_dynamic(rel):
                    prefix = rp.static_prefix(rel)
                    if prefix and not exists(game, prefix):
                        warnings[where].append(f"runtime path folder missing: res://{rel}")
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
