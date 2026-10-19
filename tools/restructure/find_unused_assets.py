"""Lists game assets that nothing in the game refers to, and byte-identical duplicates.

Usage: python find_unused_assets.py [--root <workspace>] [--markdown <out.md>]

An asset under `assets/` counts as used when the game (scripts, scenes, resources, project
settings, shaders, JSON manifests) mentions it by `res://` path, by its uid, by a `res://`
folder that code joins file names onto, or — for files listed in a manifest — by its bare
file name. Its own `.import` file does not count. The test repo does not count: a file only
tests or tools touch is still unused by the game. Treat the result as a candidate list for
the user to confirm.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import res_paths as rp  # noqa: E402

ASSET_SKIP = {".import", ".uid", ".md"}
USER_SUFFIXES = {".gd", ".tscn", ".tres", ".gdshader", ".godot", ".json", ".cfg"}


def references(text: str):
    """(res paths, res folders) mentioned in one file."""
    paths, folders = set(), set()
    for match in rp.RES_RE.finditer(text):
        rel = rp.clean(match.group(0)[len("res://"):])
        if rp.is_dynamic(rel):
            folders.add(rp.static_prefix(rel) + "/")
        elif rel.endswith("/"):
            folders.add(rel)
        else:
            paths.add(rel)
    return paths, folders


def own_uid(game: Path, rel: str) -> str | None:
    for sidecar in (rel + ".import", rel + ".uid"):
        text = rp.read_text(game / sidecar) if (game / sidecar).exists() else None
        if text:
            found = re.search(r"uid://[a-z0-9]+", text)
            if found:
                return found.group(0)
    return None


def classify(game: Path):
    """Marks assets used, starting from everything outside assets/ (code, scenes, project
    settings) and following references out of each used asset in turn, so a resource that
    only a dead resource refers to stays unused."""
    texts: dict[str, str] = {}
    for path in rp.text_files(game, USER_SUFFIXES):
        text = rp.read_text(path)
        if text is not None:
            texts[path.relative_to(game).as_posix()] = text
    assets = [p for p in sorted((game / "assets").rglob("*")) if p.is_file() and p.suffix not in ASSET_SKIP]
    rels = {p.relative_to(game).as_posix(): p for p in assets}
    uid_of = {rel: own_uid(game, rel) for rel in rels}
    kind: dict[str, str] = {}
    queue = [rel for rel in texts if not rel.startswith("assets/")]
    seen = set(queue)
    while queue:
        source = queue.pop()
        text = texts.get(source, "")
        paths, folders = references(text)
        found_uids = set(rp.UID_RE.findall(text))
        for rel in rels:
            if rel in kind:
                continue
            if rel in paths or (uid_of[rel] and uid_of[rel] in found_uids):
                kind[rel] = "path"
            elif any(rel.startswith(f) for f in folders):  # code joins names (and subfolders) onto it
                kind[rel] = "folder"
            elif source.endswith((".json", ".tres")) and re.search(
                    r"(?<![\w.\-])" + re.escape(rels[rel].name) + r"(?![\w\-])", text):
                kind[rel] = "name"
            else:
                continue
            if rel in texts and rel not in seen:
                seen.add(rel)
                queue.append(rel)
    result = defaultdict(list)
    for rel, path in rels.items():
        result[kind.get(rel, "unused")].append((rel, path.stat().st_size))
    return result


def duplicates(game: Path):
    by_hash = defaultdict(list)
    for path in (game / "assets").rglob("*"):
        if path.is_file() and path.suffix not in ASSET_SKIP:
            by_hash[hashlib.sha256(path.read_bytes()).hexdigest()].append(path.relative_to(game).as_posix())
    return [sorted(group) for group in by_hash.values() if len(group) > 1]


def mb(size: int) -> str:
    return f"{size / 1048576:.2f} MB" if size >= 104858 else f"{size / 1024:.0f} KB"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--root", type=Path, default=rp.default_root())
    parser.add_argument("--markdown", type=Path, help="also write the lists as a Markdown table")
    args = parser.parse_args(argv)
    game = rp.Workspace(args.root).game
    result = classify(game)
    for kind in ("path", "folder", "name", "unused"):
        files = result[kind]
        print(f"{kind}: {len(files)} files, {mb(sum(s for _, s in files))}")
    unused = result["unused"]
    dups = duplicates(game)
    for rel, size in unused:
        print(f"  UNUSED {mb(size):>9}  {rel}")
    for group in dups:
        print("  SAME   " + "  =  ".join(group))
    if args.markdown:
        lines = ["| 确认 | 大小 | 文件 |", "|---|---|---|"]
        lines += [f"| [ ] | {mb(size)} | `{rel}` |" for rel, size in sorted(unused, key=lambda item: -item[1])]
        lines += ["", "完全相同的文件（同一行内容一致）：", ""]
        lines += ["- " + " = ".join(f"`{rel}`" for rel in group) for group in dups]
        args.markdown.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
