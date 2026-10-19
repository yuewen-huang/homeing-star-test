"""Moves test-repo GDScript files and rewrites every reference to them.

Usage:
  python move_test_files.py MAPPING [--root <workspace>] [--apply]
  python move_test_files.py --pair OLD NEW [--pair OLD NEW ...] [--apply]

Paths are relative to homeing-star-test (`tools/test_x.gd -> tests/combat/test_x.gd`);
MAPPING has one `old -> new` per line, `#` starts a comment. Without --apply nothing changes.

With --apply:
  1. relative script paths in test-repo GDScript (`extends "test_a.gd"`,
     `preload("./b.gd")`, `load("../x.gd")`) are recomputed for every file that moved or
     whose target moved;
  2. mentions of `tools/test_x.gd` (alone or after `homeing-star-test/`) in the test, doc
     and game repos are rewritten;
  3. each file moves with its `.uid` (`git mv` when tracked).
run-tests.ps1 finds tests by base name anywhere under tools/ and tests/, so names stay.
"""
from __future__ import annotations

import argparse
import posixpath
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import move_res_paths as mover  # noqa: E402
import res_paths as rp  # noqa: E402

REL_REF = re.compile(r"""((?:extends|preload|load)\s*\(?\s*")([^"]+\.gd)(")""")
MENTION_SUFFIXES = {".md", ".py", ".ps1", ".json", ".gd", ".txt"}


def relative_refs_rewrite(text: str, file_old: str, file_new: str, moves: dict[str, str]) -> tuple[str, int]:
    """Recomputes relative .gd paths in one file (repo-relative posix paths)."""
    count = 0

    def fix(match: re.Match) -> str:
        nonlocal count
        target = match.group(2)
        if target.startswith(("res://", "user://", "/")) or re.match(r"^[A-Za-z]:", target):
            return match.group(0)
        resolved = posixpath.normpath(posixpath.join(posixpath.dirname(file_old), target))
        new_target = moves.get(resolved, resolved)
        if new_target == resolved and file_new == file_old:
            return match.group(0)
        rel = posixpath.relpath(new_target, posixpath.dirname(file_new) or ".")
        if rel == target:
            return match.group(0)
        count += 1
        return match.group(1) + rel + match.group(3)

    return REL_REF.sub(fix, text), count


def mention_pattern(old: str) -> re.Pattern:
    head = rf"(?:(?<={rp.TEST}/)|(?<![{mover.PATH_BODY}./:]))"
    return re.compile(head + re.escape(old) + rf"(?![{mover.PATH_BODY}/]|\.[A-Za-z0-9])")


def plan_or_apply(ws: rp.Workspace, pairs, apply: bool) -> int:
    test = ws.test
    problems = []
    for old, new in pairs:
        if not (test / old).is_file():
            problems.append(f"source missing: {old}")
        if (test / new).exists():
            problems.append(f"target already exists: {new}")
        if not old.endswith(".gd") or not new.endswith(".gd"):
            problems.append(f"only .gd files: {old} -> {new}")
    if problems:
        print("REFUSED:")
        for p in problems:
            print("  " + p)
        return 2
    moves = dict(pairs)
    edits: dict[str, int] = {}
    pending: dict[Path, str] = {}
    # 1. relative script references inside the test repo
    for path in rp.text_files(test, {".gd"}):
        rel = path.relative_to(test).as_posix()
        text = rp.read_text(path)
        if text is None:
            continue
        updated, count = relative_refs_rewrite(text, rel, moves.get(rel, rel), moves)
        if count:
            pending[path] = updated
            edits[f"{rp.TEST}/{rel}"] = count
    # 2. mentions of the old repo-relative paths in all repos
    patterns = [(mention_pattern(old), new) for old, new in sorted(pairs, key=lambda p: -len(p[0]))]
    for repo_name, repo, _ in ws.repos():
        for path in rp.text_files(repo, MENTION_SUFFIXES):
            if rp.is_restructure_record(repo_name, repo, path):
                continue
            text = pending.get(path) or rp.read_text(path)
            if text is None:
                continue
            total = 0
            for pattern, new in patterns:
                text, count = pattern.subn(new, text)
                total += count
            if total:
                pending[path] = text
                where = f"{repo_name}/{path.relative_to(repo).as_posix()}"
                edits[where] = edits.get(where, 0) + total
    log = []
    if apply:
        for path, text in pending.items():
            path.write_text(text, encoding="utf-8", newline="")
        for old, new in pairs:
            (test / new).parent.mkdir(parents=True, exist_ok=True)
            for a, b in [(old, new)] + [(old + ".uid", new + ".uid")] * (test / (old + ".uid")).exists():
                if mover.tracked(test, a):
                    subprocess.run(["git", "-C", str(test), "mv", a, b], check=True, capture_output=True)
                    log.append(f"git mv {a} -> {b}")
                else:
                    shutil.move(str(test / a), str(test / b))
                    log.append(f"mv {a} -> {b}")
    print(("APPLIED" if apply else "DRY RUN (nothing changed; add --apply)") + f": {len(pairs)} moves")
    for line in log:
        print("  " + line)
    print(f"REFERENCES: {sum(edits.values())} in {len(edits)} files")
    for where in sorted(edits):
        print(f"  {where}: {edits[where]}")
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("mapping", nargs="?", type=Path)
    parser.add_argument("--pair", nargs=2, action="append", metavar=("OLD", "NEW"), default=[])
    parser.add_argument("--root", type=Path, default=rp.default_root())
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args(argv)
    pairs = [(mover.normal(a), mover.normal(b)) for a, b in args.pair]
    if args.mapping:
        pairs += mover.parse_mapping(args.mapping.read_text(encoding="utf-8"))
    if not pairs:
        parser.error("give a mapping file or --pair OLD NEW")
    return plan_or_apply(rp.Workspace(args.root), pairs, args.apply)


if __name__ == "__main__":
    sys.exit(main())
