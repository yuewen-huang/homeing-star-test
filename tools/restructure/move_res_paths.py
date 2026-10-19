"""Moves or renames game files and folders and rewrites every reference to them.

Usage:
  python move_res_paths.py MAPPING [--root <workspace>] [--apply]
  python move_res_paths.py --pair OLD NEW [--pair OLD NEW ...] [--apply]

MAPPING is a text file with one `old -> new` per line (game-relative, no `res://`; folders
or files; `#` starts a comment). Without --apply nothing changes: the plan is printed.

With --apply, in this order:
  1. each file moves with its `.import` / `.uid` sidecars (`git mv` when tracked, so history
     follows; a plain move otherwise); a folder moves whole;
  2. `res://old` becomes `res://new` in game and test files, and bare `old` paths
     (`assets/…`) in test-repo tools, doc-repo Markdown and game-repo JSON manifests;
  3. a report lists what was rewritten, plus HINTS: other places that still mention an old
     file name (paths built in code from a folder and a name need a manual look).

Afterwards: run a Godot editor import (`--editor --import`) so class caches and imported
textures follow the move, then `check_res_paths.py`, then the stage's key tests.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import res_paths as rp  # noqa: E402

SIDECARS = (".import", ".uid")
# Characters that continue a path: a match must not be followed by one (`a.png` must not
# match inside `a.png2` or `a.png_old`), nor preceded by one (no match inside `xassets/`).
PATH_BODY = r"A-Za-z0-9_\-"


def parse_mapping(text: str) -> list[tuple[str, str]]:
    pairs = []
    for number, line in enumerate(text.splitlines(), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if "->" not in line:
            raise ValueError(f"mapping line {number}: expected `old -> new`, got {line!r}")
        old, new = (part.strip().strip("/") for part in line.split("->", 1))
        pairs.append((normal(old), normal(new)))
    return pairs


def normal(path: str) -> str:
    path = path.replace("\\", "/")
    if path.startswith("res://"):
        path = path[len("res://"):]
    return path.strip("/")


def validate(game: Path, pairs: list[tuple[str, str]]) -> list[str]:
    problems = []
    olds = [old for old, _ in pairs]
    for old, new in pairs:
        if not (game / old).exists():
            problems.append(f"source missing: {old}")
        if (game / new).exists():
            problems.append(f"target already exists: {new}")
        if new == old or new.startswith(old + "/"):
            problems.append(f"cannot move {old} into itself: {new}")
    if len(set(olds)) != len(olds):
        problems.append("a source appears twice in the mapping")
    return problems


def reference_pattern(old: str, is_dir: bool, res_only: bool) -> re.Pattern:
    """Matches `old` as a whole path (or, for a folder, as a path prefix): after `res://`,
    after `homeing-star-game/`, or (unless res_only) standing on its own."""
    starts = [r"(?<=res://)"]
    if not res_only:
        starts += [rf"(?<={rp.GAME}/)", rf"(?<![{PATH_BODY}./:])"]
    head = "(?:" + "|".join(starts) + ")"
    if is_dir:
        return re.compile(head + re.escape(old) + rf"(?=/|(?![{PATH_BODY}.]))")
    # A file: not followed by more name, nor by `.ext` (a sentence's full stop is fine).
    return re.compile(head + re.escape(old) + rf"(?![{PATH_BODY}/]|\.[A-Za-z0-9])")


def rewrite_text(text: str, pairs, kinds: dict[str, bool], res_only: bool) -> tuple[str, int]:
    """Rewrites references in one file; with res_only, only `res://` forms."""
    total = 0
    for old, new in pairs:
        text, count = reference_pattern(old, kinds[old], res_only).subn(new, text)
        total += count
    return text, total


def rewrite_scope(repo_name: str, path: Path) -> bool:
    """True when bare paths may be rewritten too (tools, docs, manifests), not only res://."""
    if repo_name == rp.DOC:
        return True
    if repo_name == rp.TEST:
        return path.suffix in {".py", ".ps1", ".md", ".json"}
    return path.suffix in {".json", ".md"}


def tracked(repo: Path, rel: str) -> bool:
    result = subprocess.run(["git", "-C", str(repo), "ls-files", "--error-unmatch", rel],
                            capture_output=True, text=True)
    return result.returncode == 0


def move_one(game: Path, old: str, new: str, log: list[str]) -> None:
    source = game / old
    target = game / new
    target.parent.mkdir(parents=True, exist_ok=True)
    items = [(old, new)]
    if source.is_file():
        items += [(old + s, new + s) for s in SIDECARS if (game / (old + s)).exists()]
    for a, b in items:
        if tracked(game, a):
            subprocess.run(["git", "-C", str(game), "mv", a, b], check=True, capture_output=True)
            log.append(f"git mv {a} -> {b}")
        else:
            shutil.move(str(game / a), str(game / b))
            log.append(f"mv {a} -> {b}")
    # Leave no empty folders behind.
    parent = source.parent
    while parent != game and parent.is_dir() and not any(parent.iterdir()):
        parent.rmdir()
        parent = parent.parent


def plan_or_apply(ws: rp.Workspace, pairs, apply: bool) -> int:
    game = ws.game
    problems = validate(game, pairs)
    if problems:
        print("REFUSED:")
        for p in problems:
            print("  " + p)
        return 2
    kinds = {old: (game / old).is_dir() for old, _ in pairs}
    # Longest sources first, so a file mapping wins over its parent folder's.
    pairs = sorted(pairs, key=lambda pair: -len(pair[0]))
    edits: dict[str, int] = {}
    hints: dict[str, list[str]] = defaultdict(list)
    names = {Path(old).name: (old, new) for old, new in pairs if not kinds[old]}
    for repo_name, repo, suffixes in ws.repos():
        for path in rp.text_files(repo, suffixes):
            text = rp.read_text(path)
            if text is None:
                continue
            res_only = not rewrite_scope(repo_name, path)
            updated, count = rewrite_text(text, pairs, kinds, res_only)
            where = f"{repo_name}/{path.relative_to(repo).as_posix()}"
            if count:
                edits[where] = count
                if apply:
                    path.write_text(updated, encoding="utf-8", newline="")
            if path.suffix in SIDECARS:
                continue
            for name, (old, new) in names.items():
                if name in updated and new not in updated:
                    hints[where].append(f"mentions {name} but not its new path (moved from {old})")
    log: list[str] = []
    if apply:
        for old, new in pairs:
            move_one(game, old, new, log)
    print(("APPLIED" if apply else "DRY RUN (nothing changed; add --apply)") + f": {len(pairs)} moves")
    for old, new in sorted(pairs):
        print(f"  {old} -> {new}{'/' if kinds[old] else ''}")
    for line in log:
        print("  " + line)
    print(f"REFERENCES: {sum(edits.values())} in {len(edits)} files")
    for where in sorted(edits):
        print(f"  {where}: {edits[where]}")
    print(f"HINTS: {sum(len(v) for v in hints.values())} (check these by hand)")
    for where in sorted(hints):
        for item in hints[where]:
            print(f"  {where}: {item}")
    if apply:
        print("NEXT: Godot `--editor --import`, then check_res_paths.py, then the stage's key tests.")
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("mapping", nargs="?", type=Path, help="file of `old -> new` lines")
    parser.add_argument("--pair", nargs=2, action="append", metavar=("OLD", "NEW"), default=[])
    parser.add_argument("--root", type=Path, default=rp.default_root(), help="folder holding the four repos")
    parser.add_argument("--apply", action="store_true", help="really move and rewrite")
    args = parser.parse_args(argv)
    pairs = [(normal(a), normal(b)) for a, b in args.pair]
    if args.mapping:
        pairs += parse_mapping(args.mapping.read_text(encoding="utf-8"))
    if not pairs:
        parser.error("give a mapping file or --pair OLD NEW")
    return plan_or_apply(rp.Workspace(args.root), pairs, args.apply)


if __name__ == "__main__":
    sys.exit(main())
