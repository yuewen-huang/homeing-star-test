"""Shared scanning for the restructure tools (check_res_paths.py, move_res_paths.py).

The four repos sit side by side under one workspace folder. Paths inside the game are
written three ways and all three are scanned:
  * `res://assets/...` in game scripts, scenes, resources, import files and test scripts;
  * bare game-relative paths (`assets/...`, `scenes/...`, `scripts/...`) in test-repo Python
    and PowerShell tools and in doc-repo Markdown;
  * `uid://...` in scenes and resources (resolved against .uid / .import / resource headers).
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

GAME = "homeing-star-game"
TEST = "homeing-star-test"
DOC = "homeing-star-doc"

# Text files that may hold paths, per repo.
GAME_SUFFIXES = {".gd", ".tscn", ".tres", ".gdshader", ".cfg", ".godot", ".json", ".import", ".md", ".uid"}
TEST_SUFFIXES = {".gd", ".py", ".ps1", ".json", ".jsonl", ".md", ".tscn", ".tres"}
DOC_SUFFIXES = {".md", ".json"}
SKIP_DIRS = {".git", ".godot", "artifacts", "game_legacy", "__pycache__", "node_modules"}

# Game paths are ASCII (snake_case); format marks are kept so runtime-built paths are seen.
PATH_CHARS = r"[A-Za-z0-9_./\-%{}$<>]"
RES_RE = re.compile(r"res://" + PATH_CHARS + "*")
UID_RE = re.compile(r"uid://[a-z0-9]+")
# Bare game-relative paths in tools and docs.
BARE_RE = re.compile(r"(?<![\w./\-:])((?:assets|scenes|scripts)/" + PATH_CHARS + "+)")
DYNAMIC_MARKS = ("%", "{", "<", "$")


@dataclass
class Workspace:
    root: Path

    @property
    def game(self) -> Path:
        override = os.environ.get("HOMING_STAR_GAME_PROJECT")
        return Path(override) if override else self.root / GAME

    @property
    def test(self) -> Path:
        return self.root / TEST

    @property
    def doc(self) -> Path:
        return self.root / DOC

    def repos(self):
        """(repo name, repo path, suffixes) for every repo that exists."""
        for name, path, suffixes in ((GAME, self.game, GAME_SUFFIXES), (TEST, self.test, TEST_SUFFIXES), (DOC, self.doc, DOC_SUFFIXES)):
            if path.is_dir():
                yield name, path, suffixes


def default_root() -> Path:
    # tools/restructure/<this file> → homeing-star-test → workspace
    return Path(__file__).resolve().parents[3]


def text_files(repo: Path, suffixes: set[str]):
    for folder, dirs, files in os.walk(repo):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            path = Path(folder) / name
            if path.suffix in suffixes or name == "project.godot":
                yield path


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return None


def clean(path: str) -> str:
    """Trims punctuation a regex may have swallowed at the end of a path."""
    return path.rstrip(".:'\"")


def is_dynamic(path: str) -> bool:
    return any(mark in path for mark in DYNAMIC_MARKS)


def static_prefix(path: str) -> str:
    """The folder part of a path that is built at runtime (before its first format mark)."""
    cut = min((path.index(m) for m in DYNAMIC_MARKS if m in path), default=len(path))
    return path[:cut].rsplit("/", 1)[0]


def is_restructure_record(repo_name: str, repo: Path, path: Path) -> bool:
    """The restructure tools, their tests and move tables, and archive lists: they hold old
    and example paths on purpose and are never rewritten or checked."""
    rel = path.relative_to(repo).as_posix()
    if repo_name == TEST and rel.startswith("tools/restructure/"):
        return True
    return repo_name == DOC and path.name.startswith("restructure_") and path.name.endswith("_unused_assets.md")


def collect_uids(game: Path) -> set[str]:
    uids: set[str] = set()
    header = re.compile(r"uid=\"(uid://[a-z0-9]+)\"")
    for path in text_files(game, {".uid", ".import", ".tscn", ".tres"}):
        text = read_text(path)
        if text is None:
            continue
        if path.suffix == ".uid":
            uids.add(text.strip())
        elif path.suffix == ".import":
            found = re.search(r"^uid=\"(uid://[a-z0-9]+)\"", text, re.M)
            if found:
                uids.add(found.group(1))
        else:
            # Only the resource's own uid, on the header line of a .tscn/.tres.
            found = header.search(text.split("\n", 1)[0])
            if found:
                uids.add(found.group(1))
    return uids
